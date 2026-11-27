import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../data_installer.dart';
import '../data_packages.dart';
import '../library_repository.dart';
import '../models.dart';

/// Download manager for the corpus.
///
/// The APK can be built without any database; this screen then acts as the
/// first-run setup: pick collections (or take all ~230 MB), watch the progress,
/// and every finished file is verified against its SHA-256 before it becomes
/// readable in the app.
class DataScreen extends StatefulWidget {
  const DataScreen({
    super.key,
    required this.library,
    required this.installer,
    this.setupMode = false,
  });

  final LibraryRepository library;
  final DataInstaller installer;
  final bool setupMode;

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  DataCatalog _catalog = DataCatalog.empty;
  final Map<String, DataProgress> _progress = {};
  Set<String> _installed = const {};
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await widget.installer.loadCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _installed = _installedKeys();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Set<String> _installedKeys() => {
        for (final package in _catalogOrEmpty().packages)
          if (widget.installer.isInstalled(package)) package.key,
      };

  DataCatalog _catalogOrEmpty() => _catalog.isEmpty ? widget.installer.catalog : _catalog;

  Future<void> _installOne(DataPackage package) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.installer.install(package, onProgress: _onProgress);
      await widget.library.refreshAfterInstall();
      if (!mounted) return;
      setState(() {
        _installed = _installedKeys();
        _progress.remove(package.key);
      });
      _showMessage('${package.titleUrdu} نصب ہو گیا۔');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _progress.remove(package.key);
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _installMissing() async {
    if (_working) return;
    final missing = _catalogOrEmpty().packages
        .where((package) => !widget.installer.isInstalled(package))
        .toList();
    if (missing.isEmpty) {
      _showMessage('تمام کتب پہلے سے نصب ہیں۔');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    widget.installer.resetCancellation();
    try {
      await widget.installer.installMany(
        missing,
        onProgress: _onProgress,
        onPackageInstalled: (package) => unawaited(_afterInstall(package)),
        onPackageFailed: (package, _) {
          if (mounted) setState(() => _progress.remove(package.key));
        },
      );
      if (!mounted) return;
      setState(() {
        _installed = _installedKeys();
        _progress.clear();
      });
      _showMessage('ڈاؤن لوڈ مکمل ہو گیا۔');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installed = _installedKeys();
        _progress.clear();
        _error = error.toString();
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _afterInstall(DataPackage package) async {
    await widget.library.refreshAfterInstall();
    if (!mounted) return;
    setState(() {
      _installed = _installedKeys();
      _progress.remove(package.key);
    });
  }

  void _onProgress(DataProgress progress) {
    if (!mounted) return;
    setState(() => _progress[progress.key] = progress);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalogOrEmpty();
    final missingBytes = catalog.packages
        .where((package) => !_installed.contains(package.key))
        .fold<int>(0, (sum, package) => sum + package.sizeBytes);
    final installedBytes =
        catalog.packages.where((package) => _installed.contains(package.key)).length;

    return Scaffold(
      appBar: AppBar(
        title: const JustifiedText('ڈیٹا اور ڈاؤن لوڈ'),
        actions: [
          IconButton(
            tooltip: 'فہرست تازہ کریں',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
              children: [
                if (widget.setupMode) ...[
                  const JustifiedText(
                    'خوش آمدید! یہ ایپ بغیر ڈیٹا کے انسٹال ہوتی ہے تاکہ APK چھوٹی اور تیز رہے۔ '
                    'نیچے سے کتب ڈاؤن لوڈ کریں؛ ڈاؤن لوڈ کے لیے انٹرنیٹ چاہیے؛ اس کے بعد کتابیں بغیر انٹرنیٹ کے فوری کھلتی ہیں۔',
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                ],
                _SummaryCard(
                  installed: installedBytes,
                  total: catalog.packages.length,
                  missingBytes: missingBytes,
                  working: _working,
                  onDownloadAll: _installMissing,
                  onCancel: () {
                    widget.installer.cancel();
                    _showMessage('ڈاؤن لوڈ روک دیا گیا۔');
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: JustifiedText(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 14),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                for (final source in CorpusSource.values) ...[
                  _GroupHeader(source.label),
                  const SizedBox(height: 8),
                  for (final package in catalog.packages.where((item) => item.source == source.wire))
                    _PackageTile(
                      package: package,
                      installed: _installed.contains(package.key),
                      progress: _progress[package.key],
                      busy: _working,
                      onDownload: () => _installOne(package),
                    ),
                ],
                const SizedBox(height: 12),
                const JustifiedText(
                  'بہتر ہے ڈاؤن لوڈ وائی فائی پر کیا جائے۔ فائلیں فون کی اپنی نجی جگہ پر محفوظ ہوتی ہیں اور '
                  'ہر فائل کی SHA-256 تصدیق کے بعد ہی کتاب کھلتی ہے۔ ڈاؤن لوڈ ادھورا رہ جائے تو اگلی بار '
                  'وہیں سے جاری ہوتا ہے۔',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: JustifiedText(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.installed,
    required this.total,
    required this.missingBytes,
    required this.working,
    required this.onDownloadAll,
    required this.onCancel,
  });

  final int installed;
  final int total;
  final int missingBytes;
  final bool working;
  final VoidCallback onDownloadAll;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [kForestDark, kForest],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$installed / $total کتب نصب ہیں',
            textDirection: TextDirection.rtl,
            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            missingBytes == 0
                ? 'مکمل لائبریری فون پر موجود ہے — کتابیں بغیر انٹرنیٹ کے پڑھی اور تلاش کی جا سکتی ہیں۔'
                : 'باقی ڈیٹا: ${formatBytes(missingBytes)}',
            textDirection: TextDirection.rtl,
            style: const TextStyle(color: Color(0xFFE4D7B9), fontSize: 14),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kForestDark),
                  onPressed: working || missingBytes == 0 ? null : onDownloadAll,
                  icon: const Icon(Icons.download_done),
                  label: Text(working ? 'جاری ہے…' : 'تمام کتب ڈاؤن لوڈ کریں'),
                ),
              ),
              if (working) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0x88FFFFFF)),
                  ),
                  onPressed: onCancel,
                  child: const Text('روکیں'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.package,
    required this.installed,
    required this.busy,
    required this.onDownload,
    this.progress,
  });

  final DataPackage package;
  final bool installed;
  final bool busy;
  final VoidCallback onDownload;
  final DataProgress? progress;

  @override
  Widget build(BuildContext context) {
    final progressValue = progress;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: JustifiedText(
                    package.titleUrdu,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    maxLines: 1,
                  ),
                ),
                Text(
                  formatBytes(package.sizeBytes),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 6),
                if (installed)
                  const Icon(Icons.check_circle, color: kForest, size: 20)
                else
                  IconButton(
                    tooltip: 'ڈاؤن لوڈ کریں',
                    onPressed: busy ? null : onDownload,
                    icon: const Icon(Icons.download),
                  ),
              ],
            ),
            if (progressValue != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progressValue.fraction == 0 ? null : progressValue.fraction,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${progressValue.phase} — ${formatBytes(progressValue.received)}'
                '${progressValue.total > 0 ? ' / ${formatBytes(progressValue.total)}' : ''}',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
