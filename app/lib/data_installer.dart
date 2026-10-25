import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'data_packages.dart';

const String kCatalogAsset = 'assets/database-manifest.json';
const String kCompiledDataBaseUrl = String.fromEnvironment('SHIA_DATA_BASE_URL');

class DataInstallException implements Exception {
  const DataInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DataProgress {
  const DataProgress({
    required this.key,
    required this.phase,
    required this.received,
    required this.total,
  });

  final String key;
  final String phase;
  final int received;
  final int total;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Downloads, verifies, and installs the SQLite collections on demand.
///
/// The APK can ship without any database: on first launch the app fetches each
/// `.db.gz` from GitHub (releases first, then the repository), checks its
/// SHA-256 against the bundled manifest, decompresses it into the app-private
/// database directory, and only then marks the book as readable. Partial
/// downloads resume through HTTP `Range` requests.
class DataInstaller {
  DataInstaller({
    required Directory Function() directory,
    http.Client? client,
    this.overrideBaseUrl,
  })  : _directoryOf = directory,
        _client = client ?? http.Client();

  /// Resolved lazily: the database directory only exists once the library has
  /// been initialised, so callers pass a provider instead of a path.
  final Directory Function() _directoryOf;
  final http.Client _client;
  final String? overrideBaseUrl;

  Directory get directory => _directoryOf();

  DataCatalog _catalog = DataCatalog.empty;
  bool _cancelled = false;

  DataCatalog get catalog => _catalog;

  void cancel() {
    _cancelled = true;
  }

  void resetCancellation() {
    _cancelled = false;
  }

  Future<void> close() async {
    _cancelled = true;
    _client.close();
  }

  File fileFor(DataPackage package) => File('${directory.path}/${package.fileName}');

  bool isInstalled(DataPackage package) {
    final file = fileFor(package);
    return file.existsSync() && file.lengthSync() > 0;
  }

  /// True when the file on disk is an older edition of [package]: it exists,
  /// but its size is not the size the catalog now publishes. Reading a whole
  /// book just to compare hashes would be slow, and a replaced edition (the
  /// 1.28 Sahifa Sajjadiyya, say) never keeps the old byte count — so the
  /// size is the cheap, reliable "this copy is stale" signal. The data
  /// screen offers such books as updates instead of pretending they are
  /// current forever.
  bool isOutdated(DataPackage package) {
    if (package.sizeBytes <= 0) return false;
    final file = fileFor(package);
    return file.existsSync() && file.lengthSync() != package.sizeBytes;
  }

  /// Total size of the databases already on disk, in bytes.
  int installedBytes() {
    if (!directory.existsSync()) return 0;
    var total = 0;
    for (final entity in directory.listSync()) {
      if (entity is File && entity.path.endsWith('.db')) total += entity.lengthSync();
    }
    return total;
  }

  List<DataPackage> get missingPackages => _catalog.packages
      .where((package) => !isInstalled(package) || isOutdated(package))
      .toList();

  /// Loads the manifest from the APK first, then refreshes it from the network
  /// so newly published books appear without an app update.
  Future<DataCatalog> loadCatalog({bool allowNetwork = true}) async {
    DataCatalog catalog = DataCatalog.empty;
    try {
      final raw = await rootBundle.loadString(kCatalogAsset);
      catalog = DataCatalog.parse(raw);
    } catch (_) {
      catalog = DataCatalog.empty;
    }
    if (allowNetwork) {
      final remote = await _fetchRemoteCatalog();
      if (remote != null && !remote.isEmpty) catalog = remote;
    }
    if (catalog.isEmpty) {
      throw const DataInstallException(
        'ڈیٹا فہرست دستیاب نہیں۔ انٹرنیٹ جوڑ کر دوبارہ کوشش کریں۔',
      );
    }
    _catalog = catalog;
    return catalog;
  }

  Future<DataCatalog?> _fetchRemoteCatalog() async {
    final compiled = (overrideBaseUrl ?? '').isNotEmpty ? overrideBaseUrl! : kCompiledDataBaseUrl;
    // The release tag is pinned (not `releases/latest`) so that publishing an
    // app/APK release can never take the database downloads offline.
    final bases = <String>[
      if (compiled.isNotEmpty) _normalized(compiled),
      'https://github.com/mrghalibspcpu/Shia-Ai/releases/download/databases-v1/',
      'https://raw.githubusercontent.com/mrghalibspcpu/Shia-Ai/main/assets/',
    ];
    for (final base in bases) {
      try {
        final response = await _client
            .get(Uri.parse('${base}database-manifest.json'))
            .timeout(const Duration(seconds: 25));
        if (response.statusCode == 200) {
          // GitHub serves the manifest as application/octet-stream with no
          // charset, so response.body would decode it as Latin-1 and corrupt
          // every Urdu title. Always decode the bytes as UTF-8.
          final parsed = DataCatalog.parse(
            utf8.decode(response.bodyBytes, allowMalformed: true),
          );
          if (!parsed.isEmpty) return parsed;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String _normalized(String base) => base.endsWith('/') ? base : '$base/';

  /// Downloads one package, verifies it, and installs it.
  Future<void> install(
    DataPackage package, {
    void Function(DataProgress progress)? onProgress,
  }) async {
    await directory.create(recursive: true);
    // An update replaces an older edition of the same file. A half-finished
    // download of that older edition must not be resumed into the new one:
    // the bytes would never verify, and the reader would retry forever.
    if (isOutdated(package)) {
      final partial = File('${directory.path}/${package.fileName}.part');
      if (partial.existsSync()) partial.deleteSync();
    }
    try {
      final compressed = await _download(package, onProgress: onProgress);
      onProgress?.call(DataProgress(
        key: package.key,
        phase: 'تصدیق اور کشادگی',
        received: 1,
        total: 1,
      ));
      final installed = await _unpack(compressed, package);
      compressed.deleteSync();
      onProgress?.call(DataProgress(
        key: package.key,
        phase: 'مکمل',
        received: installed,
        total: installed,
      ));
    } catch (error) {
      if (error is DataInstallException) rethrow;
      throw DataInstallException(error.toString());
    }
  }

  /// Installs packages one after another; returns the keys that succeeded.
  Future<List<String>> installMany(
    Iterable<DataPackage> packages, {
    void Function(DataProgress progress)? onProgress,
    void Function(DataPackage package)? onPackageInstalled,
  }) async {
    _cancelled = false;
    final done = <String>[];
    for (final package in packages) {
      if (_cancelled) break;
      if (isInstalled(package) && !isOutdated(package)) {
        done.add(package.key);
        continue;
      }
      await install(package, onProgress: onProgress);
      done.add(package.key);
      onPackageInstalled?.call(package);
    }
    return done;
  }

  /// Re-hashes every installed database and compares it with the manifest.
  ///
  /// Returns one entry per installed package; `true` means the file on disk is
  /// byte-for-byte the published one.
  Future<List<(DataPackage, bool)>> verifyInstalled({
    void Function(int done, int total)? onProgress,
  }) async {
    final targets = _catalog.packages.where(isInstalled).toList();
    final results = <(DataPackage, bool)>[];
    for (var i = 0; i < targets.length; i++) {
      final package = targets[i];
      final file = fileFor(package);
      String digest;
      try {
        digest = (await sha256.bind(file.openRead()).first).toString().toLowerCase();
      } catch (_) {
        digest = '';
      }
      results.add((package, package.sha256.isEmpty || digest == package.sha256));
      onProgress?.call(i + 1, targets.length);
    }
    return results;
  }

  Future<File> _download(
    DataPackage package, {
    void Function(DataProgress progress)? onProgress,
  }) async {
    final urls = downloadUrlsFor(
      package: package,
      baseUrls: _catalog.baseUrls,
      extension: _catalog.extension,
      overrideBaseUrl: (overrideBaseUrl ?? '').isNotEmpty ? overrideBaseUrl : kCompiledDataBaseUrl,
    );
    if (urls.isEmpty) throw const DataInstallException('کوئی ڈاؤن لوڈ پتہ دستیاب نہیں۔');

    final partial = File('${directory.path}/${package.fileName}.part');
    Object? lastError;
    for (final url in urls) {
      if (_cancelled) throw const DataInstallException('ڈاؤن لوڈ منسوخ کر دیا گیا۔');
      try {
        final file = await _downloadTo(url, partial, package, onProgress: onProgress);
        if (file.lengthSync() == 0) {
          throw const DataInstallException('خالی فائل موصول ہوئی۔');
        }
        return file;
      } catch (error) {
        lastError = error;
        continue;
      }
    }
    throw DataInstallException(
      'فائل ڈاؤن لوڈ نہیں ہو سکی: ${lastError?.toString() ?? 'نامعلوم خرابی'}',
    );
  }

  Future<File> _downloadTo(
    String url,
    File partial,
    DataPackage package, {
    void Function(DataProgress progress)? onProgress,
  }) async {
    var resumeFrom = partial.existsSync() ? partial.lengthSync() : 0;
    if (resumeFrom > 0 && !_catalog.extension.endsWith('.gz')) resumeFrom = 0;

    final request = http.Request('GET', Uri.parse(url));
    if (resumeFrom > 0) request.headers['Range'] = 'bytes=$resumeFrom-';

    final streamed = await _client.send(request).timeout(
          const Duration(seconds: 40),
          onTimeout: () => throw const DataInstallException('سرور نے جواب نہیں دیا۔'),
        );

    final status = streamed.statusCode;
    if (status == 416) {
      // The partial file already covers the whole document.
      await streamed.stream.drain<void>();
      return partial;
    }
    if (status != 200 && status != 206) {
      await streamed.stream.drain<void>();
      throw DataInstallException('سرور نے $status بھیجا۔');
    }
    if (status == 200 && resumeFrom > 0) resumeFrom = 0;

    final lengthHeader = int.tryParse(streamed.headers['content-length'] ?? '');
    final total = (lengthHeader ?? 0) + resumeFrom;
    final sink = partial.openWrite(mode: status == 206 ? FileMode.append : FileMode.write);
    var received = resumeFrom;
    try {
      await for (final chunk in streamed.stream) {
        if (_cancelled) throw const DataInstallException('ڈاؤن لوڈ منسوخ کر دیا گیا۔');
        sink.add(chunk);
        received += chunk.length;
        if (received % (512 * 1024) < chunk.length || total <= 0) {
          onProgress?.call(DataProgress(
            key: package.key,
            phase: 'ڈاؤن لوڈ',
            received: received,
            total: total,
          ));
        }
      }
    } finally {
      await sink.close();
    }
    onProgress?.call(DataProgress(
      key: package.key,
      phase: 'ڈاؤن لوڈ',
      received: received,
      total: total > 0 ? total : received,
    ));
    return partial;
  }

  Future<int> _unpack(File source, DataPackage package) async {
    final target = File('${directory.path}/${package.fileName}');
    final staging = File('${target.path}.tmp');
    final isCompressed = source.path.endsWith('.gz') || _looksGzipped(source);
    final digestSink = _DigestSink();
    final hashInput = sha256.startChunkedConversion(digestSink);
    final output = staging.openWrite();
    try {
      if (isCompressed) {
        await for (final chunk in source.openRead().transform(gzip.decoder)) {
          hashInput.add(chunk);
          output.add(chunk);
        }
      } else {
        await for (final chunk in source.openRead()) {
          hashInput.add(chunk);
          output.add(chunk);
        }
      }
    } catch (error) {
      await output.close();
      await _deleteQuietly(staging);
      throw DataInstallException('فائل کشادہ نہیں ہو سکی: $error');
    }
    hashInput.close(); // ByteConversionSink.close() returns void
    await output.close();

    final digest = digestSink.value?.toString().toLowerCase() ?? '';
    if (package.sha256.isNotEmpty && digest != package.sha256) {
      await _deleteQuietly(staging);
      throw const DataInstallException('فائل کی تصدیق (SHA-256) ناکام رہی۔ دوبارہ ڈاؤن لوڈ کریں۔');
    }
    final size = staging.lengthSync();
    await staging.rename(target.path);
    return size;
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  bool _looksGzipped(File file) {
    try {
      final handle = file.openSync();
      try {
        final header = handle.readSync(2);
        return header.length == 2 && header[0] == 0x1f && header[1] == 0x8b;
      } finally {
        handle.closeSync();
      }
    } catch (_) {
      return false;
    }
  }
}
