import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'nahjul_balagha_urdu.dart';
import 'text_utils.dart';

export 'text_utils.dart'
    show
        compactDisplayText,
        expandSearchQueries,
        searchTokens,
        normalizeArabicUrdu,
        relevanceScore;

/// Bumped whenever the text stored in the index changes for the same books, so
/// readers who already hold an index rebuild it. 9: the bundled Mafatih and
/// Sahifa replacements change the indexed source text.
const int _searchIndexVersion = 9;

/// Updated read-only books shipped in this APK. A matching digest makes the
/// migration idempotent; a stale installed copy is replaced atomically on the
/// next startup before any reader opens it.
const Map<String, String> _bundledDatabaseUpdates = <String, String>{
  'mafatihdb-v4.db': 'cc01c16db7652df6b00997c1ab7eebba354733c75334a2fc8d795702afc4c182',
  'Sahifa_Sajjadiyya_full_runtime.sqlite3':
      'ad65542a5d430be203500464355d67148b774632cd12b8918808998724fc4f05',
};
const int _indexPageSize = 400;

const String _kLastReadKey = 'last_read_v2';
const String _kLastReadPrefix = 'last_read_book_';

/// Progress of the (background) search-index build.
class IndexBuildState {
  const IndexBuildState({
    required this.active,
    required this.progress,
    required this.message,
  });

  const IndexBuildState.idle()
      : active = false,
        progress = 0,
        message = '';

  const IndexBuildState.done()
      : active = false,
        progress = 1,
        message = '';

  final bool active;
  final double progress;
  final String message;
}

/// One ordered unit a daily plan can open. `id` is a reader section id for
/// ordinary books and a Mafatih row id when [duaItem] is present.
class StudyUnit {
  const StudyUnit({required this.id, required this.title, this.duaItem});

  final int id;
  final String title;
  final DuaItem? duaItem;
}

/// Reads every collection the app can ship: the 14 hadith books, the Quran,
/// Mafatih al-Jinan, and Nahj al-Balagha.
///
/// Databases may be bundled in the APK, downloaded on demand, or a mix of both.
/// Whatever is present on disk is indexed for full-text search; books that are
/// not installed yet are simply reported as unavailable so the UI can offer a
/// download instead of crashing.
/// A footnote marker printed inside the matn: an Arabic letter followed by one
/// or two Arabic-Indic digits, e.g. the «٢» of «الْوَالِدِ الْفَانِ٢».


class LibraryRepository {
  LibraryRepository();

  final Map<String, Database> _bookDatabases = {};
  final Set<String> _installed = {};
  Database? _searchDatabase;
  bool _ftsAvailable = false;
  String? _ftsEngine;
  bool _initialized = false;
  bool _searchReady = false;
  bool _indexing = false;

  /// Set when a book is installed while a build is already running.
  bool _indexAgain = false;

  /// Serializes index work: "download all" reports each package separately and
  /// every callback used to start its own walk of the same table.
  Future<void>? _indexRun;

  Future<void> _runExclusive(Future<void> Function() body) {
    final previous = _indexRun ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => body());
    _indexRun = next;
    return next;
  }

  String _databaseDirectory = '';

  bool get isInitialized => _initialized;
  bool get hasFastSearch => _ftsAvailable;
  bool get hasAnyBook => _installed.isNotEmpty;
  List<BookDefinition> get installedBooks =>
      BookDefinition.all.where((book) => _installed.contains(book.key)).toList();

  bool isInstalled(BookDefinition book) => _installed.contains(book.key);

  String get dataDirectory => _databaseDirectory;

  Directory get dataDirectoryHandle => Directory(_databaseDirectory);

  /// True once every installed book is in the search index.
  bool get isSearchReady => _searchReady;

  /// Live progress of the background index build; the UI listens to this so
  /// first launch shows the library immediately instead of a counter.
  final ValueNotifier<IndexBuildState> indexProgress =
      ValueNotifier(const IndexBuildState.idle());

  /// Bumped whenever the set of installed books changes.
  ///
  /// Downloading a database used to leave the library showing "not installed"
  /// until the screen was reopened; screens now listen to this and rebuild.
  final ValueNotifier<int> catalogVersion = ValueNotifier(0);

  void _bumpCatalog() => catalogVersion.value++;

  Future<void> initialize({
    required void Function(double progress, String message) onProgress,
    /// When false the (slow) full-text index is skipped and `ensureSearchIndex`
    /// builds it in the background. Books stay readable either way.
    bool buildSearchIndex = true,
  }) async {
    if (_initialized) return;
    final appDatabasePath = await getDatabasesPath();
    _databaseDirectory = p.join(appDatabasePath, 'shia_library');
    await Directory(_databaseDirectory).create(recursive: true);
    // The launcher widget opens these files itself. It cannot guess the
    // subdirectory, so the path is written beside the prayer times it already
    // reads.
    unawaited(_rememberWidgetDatabaseDir());

    for (var i = 0; i < BookDefinition.all.length; i++) {
      final book = BookDefinition.all[i];
      final installed = await _ensureLocalCopy(book, i, onProgress);
      if (installed) _installed.add(book.key);
    }

    for (final book in installedBooks.toList()) {
      try {
        await _ensureReaderIndexes(book);
      } catch (_) {
        _installed.remove(book.key);
      }
    }

    final searchPath = p.join(_databaseDirectory, 'shia-search.sqlite');
    _searchDatabase = await openDatabase(
      searchPath,
      version: 1,
      onCreate: (db, version) async {
        await _createSearchDocsTable(db);
        await db.execute('CREATE TABLE search_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
    );
    await _ensureSearchDocsSchema(_searchDatabase!);
    await _createFtsTable(_searchDatabase!, ifNotExists: true);
    if (buildSearchIndex) {
      await _refreshSearchIndex(onProgress);
      _searchReady = true;
      indexProgress.value = const IndexBuildState.done();
    } else {
      _searchReady = false;
    }
    _initialized = true;
    _bumpCatalog();
  }

  /// Builds (or finishes) the search index without blocking the UI.
  ///
  /// The home screen no longer waits for the ~96k-record walk; it starts
  /// downloading-reading straight away and this fills the index quietly. If the
  /// process dies half way the next launch resumes it — books never become
  /// unreadable because search is still catching up.
  Future<void> ensureSearchIndex() async {
    if (_searchDatabase == null) return;
    // A book downloaded while this is running asks for another pass; the loop
    // below picks it up instead of racing two builds over the same table.
    if (_indexing) {
      _indexAgain = true;
      return;
    }
    if (_searchReady && !_indexAgain) return;
    _indexing = true;
    indexProgress.value = const IndexBuildState(
      active: true,
      progress: 0,
      message: 'تلاش کے لیے متن کی فہرست تیار ہو رہی ہے',
    );
    try {
      do {
        _indexAgain = false;
        await _refreshSearchIndex((progress, message) {
          indexProgress.value = IndexBuildState(
            active: true,
            progress: progress,
            message: message,
          );
        });
        _searchReady = true;
      } while (_indexAgain);
      indexProgress.value = const IndexBuildState.done();
    } catch (error) {
      indexProgress.value = IndexBuildState(
        active: false,
        progress: 0,
        message: 'تلاش کی فہرست مکمل نہ ہو سکی: $error',
      );
    } finally {
      _indexing = false;
    }
  }

  /// Copies a bundled asset into app storage, or upgrades a stale copy when
  /// this APK carries a newer read-only database.
  ///
  /// The two replacement books are hash-pinned and atomically swapped before
  /// any reader opens them. Other books keep the existing install-once path.
  /// A missing asset is not an error: the download manager can fetch the book.
  Future<bool> _ensureLocalCopy(
    BookDefinition book,
    int index,
    void Function(double, String) onProgress,
  ) async {
    final output = File(p.join(_databaseDirectory, book.fileName));
    final expectedUpdateHash = _bundledDatabaseUpdates[book.fileName];

    if (expectedUpdateHash != null) {
      ByteData data;
      try {
        data = await rootBundle.load('assets/databases/${book.fileName}');
      } on FlutterError catch (_) {
        return await output.exists() && await output.length() > 0;
      }
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.isEmpty) return await output.exists() && await output.length() > 0;
      final bundledHash = sha256.convert(bytes).toString();
      if (bundledHash != expectedUpdateHash) {
        throw StateError('Bundled database checksum does not match ${book.fileName}');
      }
      if (await output.exists() && await output.length() > 0) {
        final currentHash = (await sha256.bind(output.openRead()).first).toString();
        if (currentHash == expectedUpdateHash) {
          await _removeDatabaseSidecars(output);
          return true;
        }
      }
      onProgress(
        index / BookDefinition.all.length * 0.2,
        'نیا ڈیٹا نصب ہو رہا ہے — ${book.titleUrdu}',
      );
      await _replaceDatabaseAtomically(output, bytes);
      return true;
    }

    if (await output.exists() && await output.length() > 0) return true;
    onProgress(
      index / BookDefinition.all.length * 0.2,
      'کتب تیار ہو رہی ہیں — ${book.titleUrdu}',
    );
    try {
      final data = await rootBundle.load('assets/databases/${book.fileName}');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.isEmpty) return false;
      await output.writeAsBytes(bytes, flush: true);
      return true;
    } on FlutterError catch (_) {
      // Not bundled with this APK; the download manager can fetch it later.
      return false;
    }
  }

  Future<void> _replaceDatabaseAtomically(File output, List<int> bytes) async {
    final backup = File('${output.path}.previous');
    final replacement = File('${output.path}.replacement');

    // Recover from a process interruption between the two same-directory
    // renames, then start the new swap with a clean backup path.
    if (await backup.exists()) {
      if (await output.exists()) {
        await backup.delete();
      } else {
        await backup.rename(output.path);
      }
    }
    if (await replacement.exists()) await replacement.delete();
    await replacement.writeAsBytes(bytes, flush: true);

    try {
      if (await output.exists()) await output.rename(backup.path);
      await replacement.rename(output.path);
      await _removeDatabaseSidecars(output);
      if (await backup.exists()) {
        try {
          await backup.delete();
        } on FileSystemException {
          // The new database is committed; an orphaned backup is harmless and
          // is cleaned up on the next attempt.
        }
      }
    } catch (_) {
      if (!await output.exists() && await backup.exists()) {
        await backup.rename(output.path);
      }
      rethrow;
    } finally {
      if (await replacement.exists()) await replacement.delete();
    }
  }

  Future<void> _removeDatabaseSidecars(File output) async {
    for (final suffix in <String>['-wal', '-shm', '-journal']) {
      final sidecar = File('${output.path}$suffix');
      if (!await sidecar.exists()) continue;
      try {
        await sidecar.delete();
      } on FileSystemException {
        // These are only transient SQLite journals for the replaced,
        // read-only source database; a locked leftover is harmless.
      }
    }
  }

  /// Re-checks the disk after the installer finished and indexes what is new.
  Future<void> refreshAfterInstall({

    void Function(double progress, String message)? onProgress,
  }) async {
    if (!_initialized) {
      await initialize(onProgress: onProgress ?? (_, __) {});
      return;
    }
    for (final book in BookDefinition.all) {
      if (_installed.contains(book.key)) continue;
      final file = File(p.join(_databaseDirectory, book.fileName));
      if (await file.exists() && await file.length() > 0) {
        _installed.add(book.key);
        try {
          await _ensureReaderIndexes(book);
        } catch (_) {
          _installed.remove(book.key);
        }
      }
    }
    // Tell every screen about the new book whether or not we build the index
    // now: the download must be visible immediately, without a manual refresh.
    _bumpCatalog();
    if (_indexing) {
      // A background build is already walking the books; ask for one more pass
      // when it finishes rather than opening a second writer on the index.
      _indexAgain = true;
      return;
    }
    await _runExclusive(() async {
      await _refreshSearchIndex(onProgress ?? (_, __) {});
      _searchReady = true;
      indexProgress.value = const IndexBuildState.done();
    });
  }

  /// Drops and rebuilds the local search index (used by the settings screen).
  Future<void> rebuildSearchIndex({
    required void Function(double progress, String message) onProgress,
  }) async {
    for (final db in _bookDatabases.values) {
      await db.close();
    }
    _bookDatabases.clear();
    await _searchDatabase?.close();
    _searchDatabase = null;
    _initialized = false;
    _searchReady = false;
    _indexing = false;
    final file = File(p.join(_databaseDirectory, 'shia-search.sqlite'));
    if (await file.exists()) await file.delete();
    // An explicit rebuild from Settings waits for the whole index — the UI
    // shows the progress, so there is nothing to hand to the background.
    await initialize(onProgress: onProgress);
    _searchReady = true;
    indexProgress.value = const IndexBuildState.done();
  }

  Future<void> _ensureSearchDocsSchema(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'search_docs'",
    );
    if (tables.isEmpty) {
      await _createSearchDocsTable(db);
      return;
    }
    final columns = await db.rawQuery('PRAGMA table_info(search_docs)');
    final names = columns.map((row) => row['name']?.toString()).toSet();
    for (final name in ['norm_arabic', 'norm_urdu']) {
      if (!names.contains(name)) await db.execute('ALTER TABLE search_docs ADD COLUMN $name TEXT');
    }
    if (!names.contains('norm_text')) {
      await db.execute('ALTER TABLE search_docs ADD COLUMN norm_text TEXT');
    }
    if (!names.contains('container_type')) {
      await db.execute('ALTER TABLE search_docs ADD COLUMN container_type INTEGER');
    }
    if (!names.contains('container_id')) {
      await db.execute('ALTER TABLE search_docs ADD COLUMN container_id INTEGER');
    }
  }

  Future<void> _createSearchDocsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS search_docs (
        id INTEGER PRIMARY KEY,
        book TEXT NOT NULL,
        record_id INTEGER NOT NULL,
        section_id TEXT,
        page_no TEXT,
        chapter_title TEXT NOT NULL,
        section_title TEXT NOT NULL,
        container_type INTEGER,
        container_id INTEGER,
        norm_arabic TEXT,
        norm_urdu TEXT,
        norm_text TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS search_docs_book_record ON search_docs(book, record_id)',
    );
  }

  Future<void> _refreshSearchIndex(void Function(double, String) onProgress) async {
    final index = _searchDatabase;
    if (index == null) return;

    final versionRows = await index.query(
      'search_meta',
      where: 'key = ?',
      whereArgs: const ['index_version'],
      limit: 1,
    );
    final readyRows = await index.query(
      'search_meta',
      where: 'key = ?',
      whereArgs: const ['ready'],
      limit: 1,
    );
    final versionMatches =
        versionRows.isNotEmpty && versionRows.first['value']?.toString() == '$_searchIndexVersion';
    final isReady = readyRows.isNotEmpty && readyRows.first['value']?.toString() == '1';

    if (!versionMatches || !isReady || _installed.isEmpty) {
      await _rebuildSearchIndex(onProgress);
      return;
    }

    // Additive path: only books that were installed since the last launch.
    for (final book in installedBooks) {
      if (await _isBookIndexed(book.key)) continue;
      await _indexBook(book, await _nextSearchId(), onProgress, total: null, completed: 0);
    }
  }

  Future<bool> _isBookIndexed(String bookKey) async {
    final rows = await _searchDatabase!.query(
      'search_meta',
      where: 'key = ?',
      whereArgs: ['indexed:$bookKey'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['value']?.toString() == '1';
  }

  Future<int> _nextSearchId() async {
    final rows = await _searchDatabase!.rawQuery('SELECT COALESCE(MAX(id), 0) AS top FROM search_docs');
    return (rows.first['top'] as int? ?? 0) + 1;
  }

  Future<void> _rebuildSearchIndex(void Function(double, String) onProgress) async {
    final index = _searchDatabase!;
    await index.execute('DROP TABLE IF EXISTS search_docs');
    await _createSearchDocsTable(index);
    await _createFtsTable(index);
    await index.delete('search_meta');
    await index.insert('search_meta', {'key': 'ready', 'value': '0'});

    if (_installed.isEmpty) {
      await index.insert('search_meta', {'key': 'index_version', 'value': '$_searchIndexVersion'});
      await index.update('search_meta', {'value': '1'}, where: 'key = ?', whereArgs: const ['ready']);
      onProgress(1, 'کتب کا انتظار ہے');
      return;
    }

    var totalRows = 0;
    final counts = <String, int>{};
    for (final book in installedBooks) {
      final count = await _countIndexableRows(book);
      counts[book.key] = count;
      totalRows += count;
    }

    var nextId = 1;
    var completed = 0;
    for (final book in installedBooks) {
      final added = await _indexBook(book, nextId, onProgress, total: totalRows, completed: completed);
      nextId += added;
      completed += counts[book.key] ?? 0;
    }

    await index.insert('search_meta', {'key': 'index_version', 'value': '$_searchIndexVersion'});
    await index.update('search_meta', {'value': '1'}, where: 'key = ?', whereArgs: const ['ready']);
    onProgress(1, 'کتب تیار ہیں');
  }

  /// Row count that the indexer will actually walk (blank placeholders skipped).
  Future<int> _countIndexableRows(BookDefinition book, {Database? database}) async {
    final source = database ?? await _openBook(book);
    // Sahifa and the fatawa are read through `_extraQuery`, which filters
    // (Sahifa hides everything after the 83 duas). Count what the indexer will
    // actually walk — `_indexBook` asserts the two numbers agree.
    if (book.source == CorpusSource.sahifa || book.source == CorpusSource.fatwa) {
      final rows = await source.rawQuery('SELECT COUNT(*) AS count FROM (${_extraQuery(book)})');
      return (rows.first['count'] as int?) ?? 0;
    }
    final statement = book.source == CorpusSource.hadith
        ? 'SELECT COUNT(*) AS count FROM Parags '
              'WHERE LENGTH(COALESCE(txt, \'\')) > 0 OR LENGTH(COALESCE(mean, \'\')) > 0'
        : book.source == CorpusSource.balagha
            ? 'SELECT COUNT(*) AS count FROM balaghatext WHERE Type BETWEEN 1 AND 3'
            : 'SELECT COUNT(*) AS count FROM ${_sourceTable(book)}';
    final rows = await source.rawQuery(statement);
    return (rows.first['count'] as int?) ?? 0;
  }

  /// The index must hold exactly the Urdu the page shows. Since 1.21.1 the
  /// database is proofread and `repairNahjulBalaghaUrdu` returns it unchanged;
  /// on a phone that still holds the old, letter-shuffled file the same call
  /// repairs the paragraph, and indexing the stored text instead would make the
  /// reader find a page by a word the page no longer shows.
  String _indexedUrdu(BookDefinition book, int recordId, String urdu) {
    if (book.source != CorpusSource.balagha) return urdu;
    // Footnote and introduction rows carry negative ids and were never part of
    // the damage, so they are indexed exactly as stored.
    if (recordId <= 0) return urdu;
    // Same text the reader is shown: no-op on the proofread file, a repair on a
    // phone that still holds the old one.
    return repairNahjulBalaghaUrdu(recordId, urdu);
  }

  String _sourceTable(BookDefinition book) => switch (book.source) {
        CorpusSource.hadith => 'Parags',
        CorpusSource.quran => 'Quran',
        CorpusSource.dua => 'M_items',
        CorpusSource.balagha => 'balaghatext',
        CorpusSource.sahifa => 'saheefa_data',
        CorpusSource.fatwa => 'question_answers',
        CorpusSource.encyclopedia => 'sections',
      };

  /// Copies one book into `search_docs` (and the FTS mirror) starting at [startId].
  ///
  /// Returns the number of rows written.
  Future<int> _indexBook(
    BookDefinition book,
    int startId,
    void Function(double, String) onProgress, {
    required int? total,
    required int completed,
  }) async {
    final index = _searchDatabase!;
    final source = await _openBook(book);
    final bookRows = await _countIndexableRows(book, database: source);
    // A killed incremental install may leave partial rows but no completion
    // marker. Remove only this book's unfinished index before retrying it.
    if (_ftsAvailable) {
      final partial = await index.query('search_docs', columns: ['id'], where: 'book = ?', whereArgs: [book.key]);
      if (partial.isNotEmpty) {
        // Contentless FTS tables cannot delete rows reliably on older SQLite.
        // Rebuild from scratch rather than leave a duplicate/stale mirror.
        await _rebuildSearchIndex(onProgress);
        return 0;
      }
    } else {
      await index.delete('search_docs', where: 'book = ?', whereArgs: [book.key]);
    }
    var id = startId;
    var written = 0;

    for (var offset = 0; offset < bookRows; offset += _indexPageSize) {
      final rows = await _readIndexRows(book, source, offset);
      if (rows.isEmpty) break;
      final batch = index.batch();
      for (final row in rows) {
        final recordId = _asInt(row['record_id']);
        if (recordId == null) continue;
        final titles = _titlesFor(book, row);
        final arabic = (row['arabic'] ?? '').toString();
        final urdu = _indexedUrdu(book, recordId, (row['urdu'] ?? '').toString());
        final sectionId = row['section_id']?.toString();
        final page = row['page_no']?.toString();
        final normalized = [
          normalizeArabicUrdu(titles.chapter),
          normalizeArabicUrdu(titles.section),
          normalizeArabicUrdu(arabic),
          normalizeArabicUrdu('$urdu ${(row['commentary'] ?? '')} ${(row['footnote'] ?? '')}'),
        ];
        batch.insert('search_docs', {
          'id': id,
          'book': book.key,
          'record_id': recordId,
          'section_id': sectionId == null || sectionId.isEmpty ? null : sectionId,
          'page_no': page == null || page.isEmpty ? null : page,
          'chapter_title': titles.chapter,
          'section_title': titles.section,
          'container_type': _asInt(row['container_type']),
          'container_id': _asInt(row['container_id']),
          'norm_arabic': normalized[2],
          'norm_urdu': normalized[3],
          'norm_text': normalized.where((part) => part.isNotEmpty).join(' '),
        });
        if (_ftsAvailable && normalized.any((part) => part.isNotEmpty)) {
          batch.rawInsert(
            'INSERT INTO search_fts(rowid, chapter_title, section_title, arabic, urdu) '
            'VALUES (?, ?, ?, ?, ?)',
            [id, ...normalized],
          );
        }
        id++;
        written++;
      }
      await batch.commit(noResult: true);
      // Hand the frame back to Flutter between batches. The index is built
      // while the reader is already scrolling, and a tight loop over ~96k rows
      // starved the UI thread — every scroll stuttered until it finished.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      if (total != null && total > 0) {
        final done = completed + offset + rows.length;
        final progress = 0.2 + (0.8 * done / total);
        onProgress(
          progress.clamp(0.2, 0.99).toDouble(),
          'متن کی تلاش تیار ہو رہی ہے — $done / $total',
        );
      } else {
        onProgress(0.99, 'نئی کتاب کی فہرست تیار ہو رہی ہے — ${book.titleUrdu}');
      }
    }

    if (written != bookRows) throw StateError('Incomplete index: ${book.key}: $written / $bookRows');
    await index.insert(
      'search_meta',
      {'key': 'indexed:${book.key}', 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return written;
  }

  ({String chapter, String section}) _titlesFor(BookDefinition book, Map<String, Object?> row) {
    switch (book.source) {
      case CorpusSource.quran:
        final chapter = _asInt(row['container_type']) ?? 1;
        final juz = _asInt(row['juz']);
        final urduName = chapter >= 1 && chapter <= urduSurahNames.length
            ? urduSurahNames[chapter - 1]
            : '';
        final arabicName = (row['surah_name'] ?? '').toString();
        return (
          chapter: 'سورہ ${urduName.isEmpty ? arabicName : '$urduName $arabicName'}',
          section: juz == null ? '' : 'پارہ $juz',
        );
      case CorpusSource.dua:
        final category = _asInt(row['container_type']) ?? 0;
        return (
          chapter: duaCategoryTitles[category] ?? 'مفاتیح الجنان',
          section: (row['section_title'] ?? '').toString(),
        );
      case CorpusSource.balagha:
        final type = _asInt(row['container_type']) ?? 1;
        return (
          chapter: balaghaSectionTitles[type] ?? 'نہج البلاغہ',
          section: polishBalaghaTitle((row['section_title'] ?? '').toString()),
        );
      case CorpusSource.sahifa:
      case CorpusSource.fatwa:
        return (chapter: book.titleUrdu, section: (row['section_title'] ?? '').toString());
      case CorpusSource.encyclopedia:
        // Each section is indexed with its article as the chapter and the
        // section heading as the sub-heading, so a hit reads
        // «تقلید (اصطلاح) — لغوی معنی» instead of a bare paragraph.
        return (
          chapter: (row['chapter_title'] ?? '').toString(),
          section: (row['section_title'] ?? '').toString(),
        );
      case CorpusSource.hadith:
        final chapter = (row['chapter_title'] ?? '').toString();
        // Twenty records across four books point at a section id that has no
        // Sections row. They stay readable through the LEFT JOIN; give them the
        // book name instead of an empty header.
        return (
          chapter: chapter.isEmpty ? book.titleUrdu : chapter,
          section: (row['section_title'] ?? '').toString(),
        );
    }
  }

  Future<List<Map<String, Object?>>> _readIndexRows(
    BookDefinition book,
    Database source,
    int offset,
  ) async {
    switch (book.source) {
      case CorpusSource.sahifa:
      case CorpusSource.fatwa:
        return source.rawQuery('${_extraQuery(book)} ORDER BY record_id LIMIT ? OFFSET ?', [_indexPageSize, offset]);
      case CorpusSource.hadith:
        return source.rawQuery('''
          SELECT COALESCE(NULLIF(p.ID, ''), -p.rowid) AS record_id, p.txt AS arabic, p.Secid AS section_id,
                 p.paganum AS page_no, p.mean AS urdu,
                 COALESCE(s.title, '') AS section_title,
                 COALESCE(c.title, '') AS chapter_title
          FROM Parags AS p
          LEFT JOIN Sections AS s ON s.Secid = p.Secid
          LEFT JOIN Chaps AS c ON c.cid = s.Chapid
          WHERE LENGTH(COALESCE(p.txt, '')) > 0 OR LENGTH(COALESCE(p.mean, '')) > 0
          ORDER BY p.rowid
          LIMIT ? OFFSET ?
        ''', [_indexPageSize, offset]);
      case CorpusSource.quran:
        return source.rawQuery('''
          SELECT q.ID AS record_id, q.Arabic AS arabic, q.tr AS urdu, q.talighe AS commentary, q.page AS page_no,
                 q.chapter AS container_type, q.chapter AS container_id,
                 q.juz AS juz, q.verse AS verse, COALESCE(cp.Name, '') AS surah_name
          FROM Quran AS q
          LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter
          ORDER BY q.ID
          LIMIT ? OFFSET ?
        ''', [_indexPageSize, offset]);
      case CorpusSource.dua:
        return source.rawQuery('''
          SELECT m.rowid AS record_id, m.M_name AS section_title, m.M_cat_id AS container_type,
                 m._id AS container_id,
                 COALESCE((SELECT GROUP_CONCAT(t.body, ' ') FROM (
                     SELECT L_text AS body FROM Lines
                     WHERE L_M_id = m._id AND L_type = 1 ORDER BY L_prio, rowid
                 ) AS t), '') AS arabic,
                 COALESCE((SELECT GROUP_CONCAT(u.body, ' ') FROM (
                     SELECT COALESCE(NULLIF(L_Translate, '0'), L_text) AS body FROM Lines
                     WHERE L_M_id = m._id ORDER BY L_prio, rowid
                 ) AS u), '') AS urdu
          FROM M_items AS m
          ORDER BY m.rowid
          LIMIT ? OFFSET ?
        ''', [_indexPageSize, offset]);
      case CorpusSource.encyclopedia:
        return source.rawQuery('''
          SELECT s.id AS record_id, s.article_id AS section_id,
                 '' AS arabic, s.plain_text AS urdu,
                 s.heading_ur AS section_title, a.title_ur AS chapter_title
          FROM sections AS s JOIN articles AS a ON a.id = s.article_id
          ORDER BY s.article_id, s.ordinal
          LIMIT ? OFFSET ?
        ''', [_indexPageSize, offset]);
      case CorpusSource.balagha:
        // Sermons, letters and sayings only. Footnotes, introductions and the
        // two extra divisions are not part of the reader any more, so search
        // must not offer them either.
        return source.rawQuery('''
          SELECT x.ID AS record_id, x.AR AS arabic, x.UR AS urdu, x.ParaNo AS page_no,
                 x.Type AS container_type, x.TypeNo AS container_id,
                 COALESCE(t.ShortDesc, t.Description, '') AS section_title
          FROM balaghatext AS x
          LEFT JOIN balaghatoc AS t ON t.TypeID = x.Type AND t.TypeNo = x.TypeNo
          WHERE x.Type BETWEEN 1 AND 3
          ORDER BY record_id
          LIMIT ? OFFSET ?
        ''', [_indexPageSize, offset]);
    }
  }

  Future<void> _ensureReaderIndexes(BookDefinition book) async {
    final path = p.join(_databaseDirectory, book.fileName);
    Database? database;
    try {
      database = await openDatabase(path);
      final statements = switch (book.source) {
        CorpusSource.sahifa => const [
            'CREATE INDEX IF NOT EXISTS shia_sahifa_container ON saheefa_data(t_id, t_no, p_no, ID)',
          ],
        CorpusSource.fatwa => const [
            'CREATE INDEX IF NOT EXISTS shia_fatwa_category ON question_answers(category_id)',
          ],
        CorpusSource.hadith => const [
            'CREATE INDEX IF NOT EXISTS shia_parags_record ON Parags(ID)',
            'CREATE INDEX IF NOT EXISTS shia_parags_section ON Parags(Secid)',
            'CREATE INDEX IF NOT EXISTS shia_sections_chapter ON Sections(Chapid)',
            'CREATE INDEX IF NOT EXISTS shia_sections_record ON Sections(Secid)',
            'CREATE INDEX IF NOT EXISTS shia_chapters_record ON Chaps(cid)',
          ],
        CorpusSource.quran => const [
            'CREATE INDEX IF NOT EXISTS shia_quran_record ON Quran(ID)',
            'CREATE INDEX IF NOT EXISTS shia_quran_chapter_verse ON Quran(chapter, verse)',
            'CREATE INDEX IF NOT EXISTS shia_quran_juz ON Quran(juz)',
            'CREATE INDEX IF NOT EXISTS shia_quran_page ON Quran(page)',
            'CREATE INDEX IF NOT EXISTS shia_quran_surah ON ChapterProperty(Id)',
          ],
        CorpusSource.dua => const [
            'CREATE INDEX IF NOT EXISTS shia_mafatih_items_order ON M_items(M_cat_id, M_type, M_prio)',
            'CREATE INDEX IF NOT EXISTS shia_mafatih_lines_item ON Lines(L_M_id, L_prio)',
            'CREATE INDEX IF NOT EXISTS shia_mafatih_lines_record ON Lines(_id)',
          ],
        CorpusSource.balagha => const [
            'CREATE INDEX IF NOT EXISTS shia_balagha_text_locate ON balaghatext(Type, TypeNo, ParaNo)',
            'CREATE INDEX IF NOT EXISTS shia_balagha_toc_type ON balaghatoc(TypeID, TypeNo)',
            'CREATE INDEX IF NOT EXISTS shia_balagha_hawashi_locate ON balaghatext_hawashi(Type, TypeNo, ParaNo)',
            'CREATE INDEX IF NOT EXISTS shia_balagha_muqadamat_type ON balaghatext_muqadamat(Type, ParaFormat, ID)',
          ],
        CorpusSource.encyclopedia => const [
            'CREATE INDEX IF NOT EXISTS shia_encyclopedia_sections_article ON sections(article_id, ordinal)',
            'CREATE INDEX IF NOT EXISTS shia_encyclopedia_articles_title ON articles(title_ur)',
            'CREATE INDEX IF NOT EXISTS shia_encyclopedia_articles_group ON articles(group_id, title_ur)',
            'CREATE INDEX IF NOT EXISTS shia_encyclopedia_links_source ON related_articles(source_article_id)',
            'CREATE INDEX IF NOT EXISTS shia_encyclopedia_references_article ON source_references(article_id)',
          ],
      };
      final existing = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );
      final names = existing.map((row) => row['name']?.toString()).toSet();
      for (final statement in statements) {
        final name = RegExp(r'INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)', caseSensitive: false)
            .firstMatch(statement)
            ?.group(1);
        if (name != null && names.contains(name)) continue;
        await database.execute(statement);
      }
    } finally {
      await database?.close();
    }
  }

  Future<void> _createFtsTable(Database db, {bool ifNotExists = false}) async {
    if (ifNotExists) {
      final existing = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'search_fts' LIMIT 1",
      );
      if (existing.isNotEmpty) {
        final definition = (existing.first['sql'] ?? '').toString().toLowerCase();
        if (definition.contains('using fts5')) {
          _ftsEngine = 'fts5';
          _ftsAvailable = true;
          return;
        }
        if (definition.contains('using fts4')) {
          _ftsEngine = 'fts4';
          _ftsAvailable = true;
          return;
        }
        await db.execute('DROP TABLE search_fts');
      }
    } else {
      await db.execute('DROP TABLE IF EXISTS search_fts');
    }

    try {
      await db.execute('''
        CREATE VIRTUAL TABLE search_fts USING fts5(
          chapter_title, section_title, arabic, urdu,
          content='', tokenize='unicode61 remove_diacritics 0'
        )
      ''');
      _ftsEngine = 'fts5';
      _ftsAvailable = true;
      return;
    } catch (_) {}
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE search_fts USING fts4(
          chapter_title, section_title, arabic, urdu,
          content='', tokenize=unicode61
        )
      ''');
      _ftsEngine = 'fts4';
      _ftsAvailable = true;
      return;
    } catch (_) {}
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE search_fts USING fts4(
          chapter_title, section_title, arabic, urdu,
          content=''
        )
      ''');
      _ftsEngine = 'fts4';
      _ftsAvailable = true;
    } catch (_) {
      _ftsEngine = null;
      _ftsAvailable = false;
    }
  }

  Future<Database> _openBook(BookDefinition book) async {
    final cached = _bookDatabases[book.key];
    if (cached != null && cached.isOpen) return cached;
    final path = p.join(_databaseDirectory, book.fileName);
    if (!await File(path).exists()) {
      throw StateError('${book.titleUrdu} ابھی نصب نہیں ہے۔ ڈیٹا اسکرین سے ڈاؤن لوڈ کریں۔');
    }
    final database = await openDatabase(path, readOnly: true, singleInstance: false);
    _bookDatabases[book.key] = database;
    return database;
  }

  /// The Sahifa reader shows the book's 83 supplications only: `t_id` 1 carries
  /// the 54 duas of Sahifa Sajjadiyya, 2 the seven "مزید دعائیں", 3 the seven
  /// دعائیں of the week, and 4 the fifteen Munajat Khamsa Ashar — 54 + 7 + 7 +
  /// 15 = 83. Everything else in `saheefa_data` (t_id 5–8 and 115–116) is site
  /// furniture: the Imam's biography, "ہمارے بارے میں", lecture videos, and
  /// quiz pages. Those were never part of the book and used to appear as
  /// numbered entries 84 and up.
  String _extraQuery(BookDefinition book) => book.source == CorpusSource.sahifa
      ? """
        SELECT d.ID AS record_id, d.t_id * 10000 + d.t_no AS section_id,
          CASE WHEN d.oe = 'a' THEN d.p_text ELSE '' END AS arabic,
          CASE WHEN d.oe != 'a' THEN d.p_text ELSE '' END AS urdu,
          COALESCE((SELECT i.lnk_text FROM saheefa_index i
            WHERE CAST(i.lnk_cat AS INTEGER) = d.t_id AND i.lnk_id = d.t_no LIMIT 1),
            'حصہ ' || d.t_id || ' / ' || d.t_no) AS section_title,
          d.t_id AS container_type, d.t_no AS container_id, d.p_format AS format
        FROM saheefa_data d
        WHERE d.t_id IN (1, 2, 3, 4)
      """
      : """
        SELECT q.rowid AS record_id, q.category_id AS section_id, '' AS arabic,
          q.question_ur || char(10) || char(10) || q.answer_ur AS urdu,
          c.category_title_ur AS section_title, q.collection_title_ur AS chapter_title,
          q.source_url AS source_url, q.source_ref AS source_ref,
          CASE WHEN COALESCE(q.source_ref, '') <> '' THEN 'مسئلہ ' || q.source_ref
               ELSE c.category_title_ur END AS locator
        FROM question_answers q JOIN categories c ON c.category_id = q.category_id
      """;

  // ---------------------------------------------------------------- hadith

  /// How many records a book offers (0 when it is not installed yet).
  ///
  /// Counts exactly what the reader can open: the Sahifa figure is the 83
  /// supplications, not every row in the database.
  Future<int> countRecords(BookDefinition book) async {
    if (!_installed.contains(book.key)) return 0;
    try {
      if (book.source == CorpusSource.encyclopedia) {
        // The shelf counts articles (مضامین), not prose sections: after the
        // a 574-article edition the reader can open.
        final db = await _openBook(book);
        final rows = await db.rawQuery('SELECT COUNT(*) AS count FROM articles');
        return (rows.first['count'] as int?) ?? 0;
      }
      return await _countIndexableRows(book);
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, Object?>>> getChapters(BookDefinition book) async {
    final db = await _openBook(book);
    if (book.source == CorpusSource.encyclopedia) {
      // The ten curated groups of the corpus are the chapters, in reading
      // order (ائمہ، اہل بیت و کربلا، عقائد …).
      return db.rawQuery('''
        SELECT g.id AS ID, g.id AS cid, g.title_ur AS title, g.article_count AS count
        FROM groups AS g
        ORDER BY g.sort_order
      ''');
    }
    if (book.source == CorpusSource.sahifa || book.source == CorpusSource.fatwa) {
      return db.rawQuery('SELECT section_id AS ID, section_id AS cid, section_title AS title '
          'FROM (${_extraQuery(book)}) GROUP BY section_id ORDER BY section_id');
    }
    return db.rawQuery('SELECT ID, cid, title FROM Chaps ORDER BY cid');
  }

  Future<List<Map<String, Object?>>> getSections(BookDefinition book, int chapterId) async {
    final db = await _openBook(book);
    if (book.source == CorpusSource.encyclopedia) {
      return db.rawQuery('''
        SELECT a.id AS ID, a.title_ur AS title, a.group_id AS Chapid,
               a.id AS Secid, a.source_url AS source_url,
               a.character_count AS count,
               (SELECT COUNT(*) FROM sections s WHERE s.article_id = a.id) AS part_count
        FROM articles AS a
        WHERE a.group_id = ?
        ORDER BY a.title_ur
      ''', [chapterId]);
    }
    if (book.source == CorpusSource.sahifa || book.source == CorpusSource.fatwa) {
      return db.rawQuery('SELECT section_id AS ID, section_title AS title, section_id AS Chapid, section_id AS Secid '
          'FROM (${_extraQuery(book)}) WHERE section_id = ? GROUP BY section_id', [chapterId]);
    }
    return db.rawQuery(
      'SELECT ID, title, Chapid, Secid FROM Sections WHERE Chapid = ? ORDER BY Secid',
      [chapterId],
    );
  }

  /// Ordered daily-study units for a library book. Hadith, Sahifa, fatawa, and
  /// encyclopedia books use the same section ids their normal readers navigate;
  /// Mafatih uses its individual dua entries so a plan can advance dua by dua.
  Future<List<StudyUnit>> getStudyUnits(BookDefinition book) async {
    if (book.source == CorpusSource.dua) {
      final units = <StudyUnit>[];
      for (final category in await getDuaCategories()) {
        for (final item in await getDuaItems(category.id)) {
          if (!item.isHeader) {
            units.add(StudyUnit(id: item.rowId, title: item.name, duaItem: item));
          }
        }
      }
      return units;
    }
    if (book.source == CorpusSource.quran || book.source == CorpusSource.balagha) {
      return const <StudyUnit>[];
    }

    final units = <StudyUnit>[];
    final seen = <int>{};
    for (final chapter in await getChapters(book)) {
      final chapterId = _asInt(chapter['cid']) ?? _asInt(chapter['ID']);
      if (chapterId == null) continue;
      final chapterTitle = (chapter['title'] ?? book.titleUrdu).toString().trim();
      for (final section in await getSections(book, chapterId)) {
        final id = _asInt(section['Secid']) ?? _asInt(section['ID']);
        if (id == null || !seen.add(id)) continue;
        final title = (section['title'] ?? '').toString().trim();
        units.add(StudyUnit(
          id: id,
          title: title.isEmpty ? chapterTitle : title,
        ));
      }
    }
    return units;
  }

  Future<List<Passage>> getSectionPassages(BookDefinition book, int sectionId) async {
    final db = await _openBook(book);
    if (book.source == CorpusSource.encyclopedia) {
      return _encyclopediaArticlePassages(db, sectionId);
    }
    if (book.source == CorpusSource.sahifa || book.source == CorpusSource.fatwa) {
      final rows = await db.rawQuery('SELECT * FROM (${_extraQuery(book)}) WHERE section_id = ? ORDER BY record_id', [sectionId]);
      return rows.map(Passage.fromMap).toList();
    }
    final rows = await db.rawQuery('''
      SELECT COALESCE(NULLIF(p.ID, ''), -p.rowid) AS record_id, p.txt AS arabic, p.Secid AS section_id,
             p.paganum AS page_no, p.mean AS urdu,
             COALESCE(s.title, '') AS section_title,
             COALESCE(c.title, '') AS chapter_title
      FROM Parags AS p
      LEFT JOIN Sections AS s ON s.Secid = p.Secid
      LEFT JOIN Chaps AS c ON c.cid = s.Chapid
      WHERE p.Secid = ?
      ORDER BY p.rowid
    ''', [sectionId]);
    return rows.map(Passage.fromMap).toList();
  }

  /// Every section of one encyclopaedia article, in reading order, closed by
  /// a numbered **ماخذ** card.
  ///
  /// The reader shows the article as one continuous متن: the heading of each
  /// section is the card header, its text is the Urdu body, and the section's
  /// own permanent Wikipedia URL is attached to that card, so the small
  /// «ماخذ» button under any passage opens exactly the revision the words came
  /// from. The closing card lists the article's references — deduplicated and
  /// numbered — so the reader can see where a claim came from without leaving
  /// the app.
  Future<List<Passage>> _encyclopediaArticlePassages(Database db, int articleId) async {
    final rows = await db.rawQuery('''
      SELECT s.id AS record_id, s.article_id AS section_id,
             '' AS arabic, s.plain_text AS urdu,
             a.title_ur AS section_title, s.heading_ur AS locator,
             s.source_url AS source_url, a.source_url AS article_url,
             s.ordinal AS ordinal
      FROM sections AS s JOIN articles AS a ON a.id = s.article_id
      WHERE s.article_id = ?
      ORDER BY s.ordinal
    ''', [articleId]);
    final passages = <Passage>[
      for (final row in rows)
        Passage.fromMap({
          ...row,
          // A section without a verified fragment still carries its article's
          // canonical page: never leave an article card without a source.
          'source_url': (row['source_url'] ?? '').toString().isEmpty
              ? (row['article_url'] ?? '').toString()
              : row['source_url'],
        }),
    ];
    final closing = await _encyclopediaReferenceCard(db, articleId);
    if (closing != null) passages.add(closing);
    return passages;
  }

  /// The «ماخذ و حوالہ جات» card: the article's references as یک numbered list.
  Future<Passage?> _encyclopediaReferenceCard(Database db, int articleId) async {
    try {
      final rows = await db.rawQuery('''
        SELECT reference_text, source_url FROM source_references
        WHERE article_id = ? ORDER BY id
      ''', [articleId]);
      final seen = <String>{};
      final lines = <String>[];
      var sourceUrl = '';
      var truncated = false;
      for (final row in rows) {
        final text = (row['reference_text'] ?? '').toString().trim();
        if (text.isEmpty || !seen.add(text)) continue;
        if (lines.length >= 40) {
          truncated = true;
          break;
        }
        lines.add('${arabicNumerals(lines.length + 1)}. $text');
        if (sourceUrl.isEmpty) sourceUrl = (row['source_url'] ?? '').toString();
      }
      if (lines.isEmpty) return null;
      if (truncated) {
        lines.add('… مکمل حوالہ جات اصل صفحے پر موجود ہیں۔');
      }
      return Passage(
        recordId: -100000 - articleId,
        sectionId: articleId,
        arabic: '',
        urdu: lines.join('\n'),
        sectionTitle: 'ماخذ و حوالہ جات',
        locator: 'حوالہ جات',
        sourceUrl: sourceUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// Articles the current one links to (its «مزید پڑھیں» row). Only titles that
  /// resolve to a real article in this edition come back, so nothing is a dead
  /// end.
  Future<List<({int id, String title})>> getEncyclopediaRelated(
    BookDefinition book,
    int articleId,
  ) async {
    if (!_installed.contains(book.key)) return const [];
    try {
      final db = await _openBook(book);
      final rows = await db.rawQuery('''
        SELECT DISTINCT a.id AS id, a.title_ur AS title
        FROM related_articles AS r JOIN articles AS a ON a.id = r.target_article_id
        WHERE r.source_article_id = ? AND a.id <> ?
        ORDER BY a.title_ur
        LIMIT 8
      ''', [articleId, articleId]);
      return [
        for (final row in rows)
          if (_asInt(row['id']) != null)
            (id: _asInt(row['id'])!, title: (row['title'] ?? '').toString()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The article's numbered references, as **tappable links**.
  ///
  /// The closing ماخذ card lists the same lines as text; this list is what the
  /// reader taps to open the exact page in the browser. Duplicate URLs are
  /// folded (a revision page is often cited from several
  /// sections) and the list is capped so a heavily-referenced biography cannot
  /// build a thousand-row widget.
  Future<List<({String text, String url})>> getEncyclopediaReferences(
    BookDefinition book,
    int articleId, {
    int limit = 40,
  }) async {
    if (!_installed.contains(book.key)) return const [];
    try {
      final db = await _openBook(book);
      final rows = await db.rawQuery(
        'SELECT reference_text, source_url FROM source_references WHERE article_id = ? ORDER BY id',
        [articleId],
      );
      final seen = <String>{};
      final links = <({String text, String url})>[];
      for (final row in rows) {
        final url = (row['source_url'] ?? '').toString().trim();
        if (!url.startsWith('http') || !seen.add(url)) continue;
        final text = (row['reference_text'] ?? '').toString().trim();
        links.add((text: text.isEmpty ? url : text, url: url));
        if (links.length >= limit) break;
      }
      return links;
    } catch (_) {
      return const [];
    }
  }

  // ------------------------------------------------------- encyclopedia

  /// Counts shown on the نئی کتابیں page (مقالے، حصے، ماخذ).
  Future<({int articles, int sections, int references})> encyclopediaStats() async {
    const empty = (articles: 0, sections: 0, references: 0);
    final book = BookDefinition.byKey('athna_ashari_encyclopedia');
    if (book == null || !_installed.contains(book.key)) return empty;
    try {
      final db = await _openBook(book);
      Future<int> count(String sql) async =>
          (await db.rawQuery(sql)).first.values.first as int? ?? 0;
      return (
        articles: await count('SELECT COUNT(*) FROM articles'),
        sections: await count('SELECT COUNT(*) FROM sections'),
        references: await count('SELECT COUNT(*) FROM source_references'),
      );
    } catch (_) {
      return empty;
    }
  }

  /// The twelve Imams of the corpus, in order: the article id opens the full
  /// biography as one متن.
  Future<List<Map<String, Object?>>> getEncyclopediaImams() async {
    final book = BookDefinition.byKey('athna_ashari_encyclopedia');
    if (book == null || !_installed.contains(book.key)) return const [];
    try {
      final db = await _openBook(book);
      return await db.rawQuery('''
        SELECT i.imam_number AS number, a.id AS article_id, a.title_ur AS title,
               a.character_count AS count
        FROM imams AS i JOIN articles AS a ON a.id = i.article_id
        ORDER BY i.imam_number
      ''');
    } catch (_) {
      return const [];
    }
  }

  /// The curated topical entry points (غدیر، کربلا، امامت …), each pointing at
  /// a real article rather than an invented page.
  Future<List<Map<String, Object?>>> getEncyclopediaTopics() async {
    final book = BookDefinition.byKey('athna_ashari_encyclopedia');
    if (book == null || !_installed.contains(book.key)) return const [];
    try {
      final db = await _openBook(book);
      return await db.rawQuery('''
        SELECT t.id AS id, t.title_ur AS title, a.id AS article_id, a.title_ur AS article_title,
               (SELECT COUNT(*) FROM topic_articles ta WHERE ta.topic_id = t.id) AS related
        FROM topics AS t JOIN articles AS a ON a.id = t.article_id
        ORDER BY t.id
      ''');
    } catch (_) {
      return const [];
    }
  }

  // ----------------------------------------------------------------- quran

  Future<List<QuranSurah>> getSurahs() async {
    final book = BookDefinition.bookFor(CorpusSource.quran);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery(
      'SELECT Id, Name, Nozol, Verse, revel FROM ChapterProperty ORDER BY Id',
    );
    return [
      for (var i = 0; i < rows.length; i++) QuranSurah.fromMap(rows[i], index: i),
    ];
  }

  Future<Passage?> getQuranVerse(int chapter, int verse) async {
    final book = BookDefinition.bookFor(CorpusSource.quran)!;
    final db = await _openBook(book);
    final rows = await db.rawQuery('SELECT ID FROM Quran WHERE chapter = ? AND verse = ? LIMIT 1', [chapter, verse]);
    return rows.isEmpty ? null : getPassageById(book, _asInt(rows.first['ID'])!);
  }

  Future<List<Passage>> getSurahVerses(int chapter) async {
    final book = BookDefinition.bookFor(CorpusSource.quran);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery('''
      SELECT q.ID AS record_id, q.Arabic AS arabic, q.tr AS urdu, q.talighe AS commentary,
             q.chapter AS container_type, q.chapter AS container_id, q.page AS page_no,
             q.juz AS juz, q.verse AS verse, COALESCE(cp.Name, '') AS surah_name
      FROM Quran AS q LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter
      WHERE q.chapter = ?
      ORDER BY q.verse
    ''', [chapter]);
    return rows.map(_quranPassage).toList();
  }

  Future<List<QuranJuzEntry>> getJuzIndex() async {
    final book = BookDefinition.bookFor(CorpusSource.quran);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery('''
      SELECT j.juz AS juz, q.ID AS first_id, q.chapter AS surah, q.verse AS verse
      FROM (SELECT juz, MIN(ID) AS first_id FROM Quran GROUP BY juz) AS j
      JOIN Quran AS q ON q.ID = j.first_id
      ORDER BY j.juz
    ''');
    return [
      for (final row in rows)
        QuranJuzEntry(
          juz: _asInt(row['juz']) ?? 0,
          firstRecordId: _asInt(row['first_id']) ?? 0,
          surah: _asInt(row['surah']) ?? 1,
          verse: _asInt(row['verse']) ?? 1,
        ),
    ];
  }

  Future<List<Passage>> getJuzVerses(int juz) async {
    final book = BookDefinition.bookFor(CorpusSource.quran);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery('''
      SELECT q.ID AS record_id, q.Arabic AS arabic, q.tr AS urdu, q.talighe AS commentary,
             q.chapter AS container_type, q.chapter AS container_id, q.page AS page_no,
             q.juz AS juz, q.verse AS verse, COALESCE(cp.Name, '') AS surah_name
      FROM Quran AS q LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter
      WHERE q.juz = ?
      ORDER BY q.ID
    ''', [juz]);
    return rows.map(_quranPassage).toList();
  }

  Future<List<Passage>> getQuranPage(int page) async {
    final book = BookDefinition.bookFor(CorpusSource.quran);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery('''
      SELECT q.ID AS record_id, q.Arabic AS arabic, q.tr AS urdu, q.talighe AS commentary,
             q.chapter AS container_type, q.chapter AS container_id, q.page AS page_no,
             q.juz AS juz, q.verse AS verse, COALESCE(cp.Name, '') AS surah_name
      FROM Quran AS q LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter
      WHERE q.page = ?
      ORDER BY q.ID
    ''', [page]);
    return rows.map(_quranPassage).toList();
  }

  /// The verses of a run of mushaf pages, in order. The daily study opens a
  /// whole portion this way, so the reader shows the days' pages and not only
  /// the first one.
  Future<List<Passage>> getQuranPages(int firstPage, int lastPage) async {
    final book = BookDefinition.bookFor(CorpusSource.quran);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery('''
      SELECT q.ID AS record_id, q.Arabic AS arabic, q.tr AS urdu, q.talighe AS commentary,
             q.chapter AS container_type, q.chapter AS container_id, q.page AS page_no,
             q.juz AS juz, q.verse AS verse, COALESCE(cp.Name, '') AS surah_name
      FROM Quran AS q LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter
      WHERE q.page >= ? AND q.page <= ?
      ORDER BY q.ID
    ''', [firstPage, lastPage]);
    return rows.map(_quranPassage).toList();
  }

  Passage _quranPassage(Map<String, Object?> row) {
    final chapter = _asInt(row['container_type']) ?? 1;
    final verse = _asInt(row['verse']) ?? 0;
    final juz = _asInt(row['juz']);
    final page = _asInt(row['page_no']);
    final urduName = chapter >= 1 && chapter <= urduSurahNames.length
        ? urduSurahNames[chapter - 1]
        : '';
    final arabicName = (row['surah_name'] ?? '').toString();
    final locatorParts = <String>[
      if (verse > 0) 'آیت $verse',
      if (juz != null) 'پارہ $juz',
      if (page != null) 'صفحہ $page',
    ];
    return Passage(
      recordId: _asInt(row['record_id']) ?? 0,
      arabic: _compact((row['arabic'] ?? '').toString()),
      urdu: _compact((row['urdu'] ?? '').toString()),
      commentary: _compact((row['commentary'] ?? '').toString()),
      page: page,
      containerType: chapter,
      containerId: chapter,
      chapterTitle: urduName.isEmpty ? arabicName : '$urduName · $arabicName',
      sectionTitle: arabicName,
      locator: locatorParts.join(' • '),
    );
  }

  // ------------------------------------------------------------------ duas

  Future<List<DuaCategory>> getDuaCategories() async {
    final book = BookDefinition.bookFor(CorpusSource.dua);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery('''
      SELECT M_cat_id AS cat, COUNT(*) AS total,
             SUM(CASE WHEN M_type = 1 THEN 1 ELSE 0 END) AS leaves
      FROM M_items GROUP BY M_cat_id ORDER BY M_cat_id
    ''');
    return rows.map((row) {
      final id = _asInt(row['cat']) ?? 0;
      return DuaCategory(
        id: id,
        titleUrdu: duaCategoryTitles[id] ?? 'حصہ $id',
        itemCount: _asInt(row['leaves']) ?? _asInt(row['total']) ?? 0,
      );
    }).toList();
  }

  Future<List<DuaItem>> getDuaItems(int categoryId) async {
    final book = BookDefinition.bookFor(CorpusSource.dua);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery('''
      SELECT m.rowid AS row_id, m.M_name, m.M_cat_id, m.M_type, m.M_montakhab,
             (SELECT COUNT(*) FROM Lines AS l WHERE l.L_M_id = m._id) AS line_count
      FROM M_items AS m
      WHERE m.M_cat_id = ?
      ORDER BY m.M_prio, m.rowid
    ''', [categoryId]);
    return rows.map(DuaItem.fromMap).toList();
  }

  Future<List<DuaItem>> getFeaturedDuas({int limit = 12}) async {
    final book = BookDefinition.bookFor(CorpusSource.dua);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery('''
      SELECT m.rowid AS row_id, m.M_name, m.M_cat_id, m.M_type, m.M_montakhab,
             (SELECT COUNT(*) FROM Lines AS l WHERE l.L_M_id = m._id) AS line_count
      FROM M_items AS m
      WHERE m.M_montakhab = 1 AND m.M_type = 1
      ORDER BY m.M_cat_id, m.M_prio, m.rowid
      LIMIT ?
    ''', [limit]);
    return rows.map(DuaItem.fromMap).toList();
  }

  Future<List<Passage>> getDuaLines(int itemRowId) async {
    final book = BookDefinition.bookFor(CorpusSource.dua);
    if (book == null) return const [];
    final db = await _openBook(book);
    final itemRows = await db.rawQuery(
      'SELECT rowid AS row_id, _id, M_name, M_cat_id FROM M_items WHERE rowid = ? LIMIT 1',
      [itemRowId],
    );
    if (itemRows.isEmpty) return const [];
    final itemId = _asInt(itemRows.first['_id']);
    final title = (itemRows.first['M_name'] ?? '').toString();
    final category = _asInt(itemRows.first['M_cat_id']) ?? 0;
    final rows = await db.rawQuery('''
      SELECT rowid AS record_id, L_text, L_Translate, L_prio, L_type
      FROM Lines WHERE L_M_id = ?
      ORDER BY L_prio, rowid
    ''', [itemId]);
    // The source holds a few completely blank rows; never render them.
    return [
      for (final row in rows) _duaPassage(row, title: title, category: category, itemRowId: itemRowId)
    ].where((passage) => !passage.isEmpty).toList();
  }

  Passage _duaPassage(
    Map<String, Object?> row, {
    required String title,
    required int category,
    required int itemRowId,
  }) {
    final text = _compact((row['L_text'] ?? '').toString());
    final translate = _compact((row['L_Translate'] ?? '').toString());
    final type = _asInt(row['L_type']) ?? 1;
    // Mafatih rows are of two kinds in the source database: the dua itself
    // (Arabic with an Urdu translation) and Urdu instructions to the reciter
    // printed between segments ("پھر سات مرتبہ پڑھیں"), where L_Translate
    // holds the sentinel '0'. Keep the kinds distinct so the reader renders
    // each the way the book does — no "سطر نمبر" labels, and instructions are
    // never dressed up as tafseer.
    final isInstruction = type == 2;
    return Passage(
      recordId: _asInt(row['record_id']) ?? 0,
      arabic: isInstruction ? '' : text,
      urdu: isInstruction ? text : (translate == '0' ? '' : translate),
      containerType: category,
      containerId: itemRowId,
      chapterTitle: duaCategoryTitles[category] ?? 'مفاتیح الجنان',
      sectionTitle: title,
      format: type,
    );
  }

  // ------------------------------------------------------- nahj al-balagha

  Future<List<BalaghaSection>> getBalaghaSections() async {
    final book = BookDefinition.bookFor(CorpusSource.balagha);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery('''
      SELECT t.TypeID AS type, COUNT(DISTINCT t.TypeNo) AS entries,
             (SELECT COUNT(*) FROM balaghatext_muqadamat AS m WHERE m.Type = t.TypeID) AS intro
      FROM balaghatoc AS t
      GROUP BY t.TypeID ORDER BY t.TypeID
    ''');
    return rows.map((row) {
      final type = _asInt(row['type']) ?? 0;
      return BalaghaSection(
        type: type,
        titleUrdu: balaghaSectionTitles[type] ?? 'حصہ $type',
        entryCount: _asInt(row['entries']) ?? 0,
        // Introductions (مقدمات) are not shown. The reader keeps the Arabic
        // matn and the Urdu translation of sermons, letters and sayings.
        hasIntroduction: false,
      );
    }).where((section) => section.type >= 1 && section.type <= 3).toList();
  }

  Future<List<BalaghaEntry>> getBalaghaEntries(int type) async {
    final book = BookDefinition.bookFor(CorpusSource.balagha);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery('''
      SELECT t.TypeNo AS type_no, COALESCE(NULLIF(t.ShortDesc, ''), t.Description, '') AS title,
             (SELECT COUNT(*) FROM balaghatext AS x WHERE x.Type = t.TypeID AND x.TypeNo = t.TypeNo)
               + (SELECT COUNT(*) FROM balaghatext_hawashi AS h
                   WHERE h.Type = 5 AND t.TypeID = 5 AND h.TypeNo = t.TypeNo) AS paragraphs
      FROM balaghatoc AS t
      WHERE t.TypeID = ?
      ORDER BY t.TypeNo
    ''', [type]);
    return rows.map((row) => BalaghaEntry(
          typeNo: _asInt(row['type_no']) ?? 0,
          title: polishBalaghaTitle(_compact((row['title'] ?? '').toString())),
          paragraphCount: _asInt(row['paragraphs']) ?? 0,
        )).toList();
  }

  Future<List<Passage>> getBalaghaEntry(int type, int typeNo) async {
    final book = BookDefinition.bookFor(CorpusSource.balagha);
    // خطبات، مکتوبات اور حکمتیں only. Types 4 and 5 (احادیثِ رسول، مقدمات)
    // are no longer opened.
    if (book == null || type < 1 || type > 3 || typeNo <= 0) return const [];
    final db = await _openBook(book);
    final paragraphs = <Passage>[];

    final rows = await db.rawQuery('''
      SELECT x.ID AS record_id, x.AR AS arabic, x.UR AS urdu, x.ParaNo AS page_no,
             x.ParaFormat AS format, x.Type AS container_type, x.TypeNo AS container_id
      FROM balaghatext AS x
      WHERE x.Type = ? AND x.TypeNo = ?
      ORDER BY (x.ParaNo IS NULL), x.ParaNo, x.ID
    ''', [type, typeNo]);
    for (final row in rows) {
      final recordId = _asInt(row['record_id']) ?? 0;
      final passage = Passage(
        recordId: recordId,
        arabic: _compact((row['arabic'] ?? '').toString()),
        urdu: repairNahjulBalaghaUrdu(recordId, _compact((row['urdu'] ?? '').toString())),
        page: _asInt(row['page_no']),
        containerType: type,
        containerId: typeNo,
        chapterTitle: balaghaSectionTitles[type] ?? 'نہج البلاغہ',
        // The database's own paragraph role (title / text / sub-heading /
        // separator) — shown as book typography, never as a "فقرا نمبر" label,
        // which is an internal ordering field readers found confusing.
        format: _asInt(row['format']),
      );
      paragraphs.add(passage);
    }

    // Footnotes (حواشی) stay out of the page. The reader keeps the Arabic matn
    // and the Urdu translation; introductions and the numbered حاشیه block
    // used to follow the matn and made «متن کچھ، حاشیہ کچھ».
    return paragraphs.where((passage) => !passage.isEmpty).toList();
  }

  /// The notes of one entry in the book's own order, each with a negative
  /// record id so it can never collide with a matn paragraph.
  Future<List<Passage>> _balaghaNoteRows(Database db, int type, int typeNo) async {
    final rows = await db.rawQuery('''
      SELECT ID AS record_id, hawashi AS body FROM balaghatext_hawashi
      WHERE Type = ? AND TypeNo = ? ORDER BY ID
    ''', [type, typeNo]);
    final notes = <Passage>[];
    for (final row in rows) {
      final body = _compact((row['body'] ?? '').toString());
      if (body.isEmpty) continue;
      notes.add(Passage(
        recordId: -(_asInt(row['record_id']) ?? 0),
        arabic: '',
        urdu: body,
        containerType: type,
        containerId: typeNo,
        sectionTitle: 'حواشی',
      ));
    }
    return notes;
  }

  /// The entry's notes on their own page, numbered the way the printed book
  /// numbers them (`حاشیہ ۳`), in the book's own order.
  Future<List<Passage>> getBalaghaNotes(int type, int typeNo) async {
    final book = BookDefinition.bookFor(CorpusSource.balagha)!;
    final db = await _openBook(book);
    final notes = await _balaghaNoteRows(db, type, typeNo);
    return <Passage>[
      for (var index = 0; index < notes.length; index++)
        Passage(
          recordId: notes[index].recordId,
          arabic: '',
          urdu: notes[index].urdu,
          containerType: type,
          containerId: typeNo,
          sectionTitle: 'حواشی',
          locator: 'حاشیہ ${index + 1}',
        ),
    ];
  }

  Future<List<Passage>> getBalaghaIntroduction(int type) async {
    final book = BookDefinition.bookFor(CorpusSource.balagha);
    if (book == null) return const [];
    final db = await _openBook(book);
    final rows = await db.rawQuery('''
      SELECT ID AS record_id, mqar AS arabic, mqur AS urdu
      FROM balaghatext_muqadamat WHERE Type = ? ORDER BY ID
    ''', [type]);
    return rows.map((row) => Passage(
          recordId: -1000000 - (_asInt(row['record_id']) ?? 0),
          arabic: _compact((row['arabic'] ?? '').toString()),
          urdu: _compact((row['urdu'] ?? '').toString()),
          containerType: type,
          containerId: 0,
          chapterTitle: balaghaSectionTitles[type] ?? 'نہج البلاغہ',
          sectionTitle: 'مقدمہ',
        )).toList();
  }

  // --------------------------------------------------------------- lookups

  /// A handful of short lines for the home screen's **آیت / حدیثِ وقت** card
  /// and the launcher widget.
  ///
  /// A short Quran verse (with its Urdu translation) and a short saying from
  /// Ghurar al-Hikam while those books are installed — the card's next button
  /// walks this list, so a tap never waits on the database. Mizan al-Hikmah and
  /// Hidayat al-Ilm still contribute when they are installed, so a phone that
  /// already used them does not lose that rotation. The list comes back shuffled.
  ///
  /// Returns an empty list when none of the books is installed (the card then
  /// shows its built-in lines) or when a book cannot be opened. Whatever was
  /// fetched is also written for the home-screen widget, which cannot open the
  /// Flutter database itself until this process has run once.
  Future<List<MomentPassage>> momentPassages({int limit = 6, math.Random? random}) async {
    if (!_initialized || limit <= 0) return const <MomentPassage>[];
    final lines = <MomentPassage>[];
    final quran = BookDefinition.bookFor(CorpusSource.quran);
    final ghurar = BookDefinition.byKey('hakam');
    final mizan = BookDefinition.byKey('mezan');
    final hidaya = BookDefinition.byKey('hidaya');
    if (quran != null && isInstalled(quran)) lines.addAll(await _quranMoments(quran, limit));
    if (ghurar != null && isInstalled(ghurar)) lines.addAll(await _hadithMoments(ghurar, limit));
    if (mizan != null && isInstalled(mizan)) lines.addAll(await _hadithMoments(mizan, limit));
    if (hidaya != null && isInstalled(hidaya)) lines.addAll(await _hidayaMoments(hidaya, limit));
    lines.shuffle(random ?? math.Random());
    if (lines.isNotEmpty) unawaited(_publishWidgetMoments(lines));
    return lines;
  }

  /// Where the launcher widget should look for `quran.db` and `hakam.db`.
  Future<void> _rememberWidgetDatabaseDir() async {
    if (_databaseDirectory.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_db_dir', _databaseDirectory);
    } catch (_) {}
  }

  /// The widget reads this JSON from the same preferences file as the next
  /// prayer. Each object is `{text, reference, kind}`.
  Future<void> _publishWidgetMoments(List<MomentPassage> lines) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_db_dir', _databaseDirectory);
      await prefs.setString(
        'widget_moments',
        jsonEncode(<Map<String, String>>[
          for (final line in lines)
            <String, String>{
              'text': line.urdu.trim().isNotEmpty ? line.urdu.trim() : line.arabic.trim(),
              'reference': line.source,
              'kind': line.kind,
            },
        ]),
      );
      const channel = MethodChannel('com.shiaai.app/widget');
      await channel.invokeMethod<void>('refresh');
    } catch (_) {}
  }

  /// The chapter a section belongs to, so "back" from a last-seen passage can
  /// land on that chapter instead of the screen the reader happened to open from.
  ///
  /// Fatawa and Sahifa use the section id as the chapter id. Hadith and the
  /// encyclopaedia look the parent up. Returns null when the book has no such
  /// ladder (Quran, Nahj, Mafatih resolve their own containers).
  Future<int?> chapterIdFor(BookDefinition book, int sectionId) async {
    if (sectionId == 0) return null;
    if (book.source == CorpusSource.fatwa || book.source == CorpusSource.sahifa) {
      return sectionId;
    }
    try {
      final db = await _openBook(book);
      if (book.source == CorpusSource.encyclopedia) {
        final rows = await db.rawQuery(
          'SELECT group_id AS cid FROM articles WHERE id = ? LIMIT 1',
          [sectionId],
        );
        return rows.isEmpty ? null : _asInt(rows.first['cid']);
      }
      if (book.source == CorpusSource.hadith) {
        final rows = await db.rawQuery(
          'SELECT Chapid AS cid FROM Sections WHERE Secid = ? LIMIT 1',
          [sectionId],
        );
        return rows.isEmpty ? null : _asInt(rows.first['cid']);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Short ayahs: a translation of 40–130 characters, so the card holds it in
  /// two lines. `ORDER BY RANDOM()` over the 6,236 rows is instant.
  Future<List<MomentPassage>> _quranMoments(BookDefinition book, int limit) async {
    final lines = <MomentPassage>[];
    try {
      final db = await _openBook(book);
      final rows = await db.rawQuery('''
        SELECT q.ID AS record_id, q.Arabic AS arabic, q.tr AS urdu, q.talighe AS commentary,
               q.chapter AS container_type, q.chapter AS container_id, q.page AS page_no,
               q.juz AS juz, q.verse AS verse, COALESCE(cp.Name, '') AS surah_name
        FROM Quran AS q LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter
        WHERE LENGTH(COALESCE(q.tr, '')) BETWEEN 12 AND 240
          AND LENGTH(COALESCE(q.Arabic, '')) BETWEEN 6 AND 220
        ORDER BY RANDOM() LIMIT ?
      ''', [limit]);
      for (final row in rows) {
        final passage = _quranPassage(row);
        if (passage.arabic.isEmpty || passage.urdu.isEmpty) continue;
        // `chapter` is selected as container_type. Reading the bare name
        // always came back null, so the Urdu surah name never appeared.
        final chapter = passage.containerType ?? _asInt(row['container_type']) ?? 0;
        final name = chapter >= 1 && chapter <= urduSurahNames.length
            ? urduSurahNames[chapter - 1]
            : (row['surah_name'] ?? '').toString();
        final verse = _asInt(row['verse']) ?? 0;
        lines.add(MomentPassage(
          kind: 'آیت',
          arabic: passage.arabic,
          urdu: passage.urdu,
          source: name.isEmpty
              ? book.titleUrdu
              : 'سورہ $name، آیت $verse',
          book: book,
          recordId: passage.recordId,
          sectionId: passage.sectionId,
        ));
      }
    } catch (_) {
      return const <MomentPassage>[];
    }
    return lines;
  }

  /// Short narrations of Mizan al-Hikmah: `Parags.mean` is the Urdu line,
  /// `Parags.txt` the Arabic. The length filter keeps only what fits the card.
  Future<List<MomentPassage>> _hadithMoments(BookDefinition book, int limit) async {
    final lines = <MomentPassage>[];
    try {
      final db = await _openBook(book);
      final rows = await db.rawQuery('''
        SELECT COALESCE(NULLIF(p.ID, ''), -p.rowid) AS record_id, p.txt AS arabic, p.mean AS urdu,
               p.Secid AS section_id, p.paganum AS page_no,
               COALESCE(s.title, '') AS section_title
        FROM Parags AS p
        LEFT JOIN Sections AS s ON s.Secid = p.Secid
        WHERE LENGTH(COALESCE(p.mean, '')) BETWEEN 12 AND 220
          AND LENGTH(COALESCE(p.txt, '')) BETWEEN 8 AND 240
        ORDER BY RANDOM() LIMIT ?
      ''', [limit]);
      // A book whose lines are all longer than the card still has to feed the
      // moment: the card ellipsizes, an empty list does not.
      final usable = rows.isNotEmpty
          ? rows
          : await db.rawQuery('''
        SELECT COALESCE(NULLIF(p.ID, ''), -p.rowid) AS record_id, p.txt AS arabic, p.mean AS urdu,
               p.Secid AS section_id, p.paganum AS page_no,
               COALESCE(s.title, '') AS section_title
        FROM Parags AS p
        LEFT JOIN Sections AS s ON s.Secid = p.Secid
        WHERE LENGTH(COALESCE(p.mean, '')) > 8 AND LENGTH(COALESCE(p.txt, '')) > 4
        ORDER BY RANDOM() LIMIT ?
      ''', [limit]);
      for (final row in usable) {
        final passage = Passage.fromMap(row);
        if (passage.arabic.isEmpty || passage.urdu.isEmpty) continue;
        final section = passage.sectionTitle.trim();
        lines.add(MomentPassage(
          kind: 'حدیث',
          arabic: passage.arabic,
          urdu: passage.urdu,
          source: section.isEmpty ? book.titleUrdu : '${book.titleUrdu} — $section',
          book: book,
          recordId: passage.recordId,
          sectionId: passage.sectionId,
        ));
      }
    } catch (_) {
      return const <MomentPassage>[];
    }
    return lines;
  }

  /// Urdu-only wisdom lines from **ہدایۃ العلم**.
  ///
  /// This collection is already an Urdu translation of the narration, so the
  /// card shows only the Urdu sentence and its reference — no Arabic column,
  /// which leaves room for noticeably larger type. Some rows carry their
  /// citation as a `(۹۴۱۸ .. ۸۰)` prefix in `mean`; it is stripped here so the
  /// sentence starts the line and the reference lives in `source`.
  Future<List<MomentPassage>> _hidayaMoments(BookDefinition book, int limit) async {
    final lines = <MomentPassage>[];
    try {
      final db = await _openBook(book);
      final rows = await db.rawQuery('''
        SELECT COALESCE(NULLIF(p.ID, ''), -p.rowid) AS record_id,
               p.mean AS urdu, p.Secid AS section_id,
               COALESCE(s.title, '') AS section_title,
               COALESCE(c.title, '') AS chapter_title
        FROM Parags AS p
        LEFT JOIN Sections AS s ON s.Secid = p.Secid
        LEFT JOIN Chaps AS c ON c.cid = s.Chapid
        WHERE LENGTH(COALESCE(p.mean, '')) BETWEEN 45 AND 190
        ORDER BY RANDOM() LIMIT ?
      ''', [limit]);
      for (final row in rows) {
        final urdu = _stripHidayaCitation((row['urdu'] ?? '').toString());
        if (urdu.length < 35) continue;
        final section = (row['section_title'] ?? '').toString().trim();
        final chapter = (row['chapter_title'] ?? '').toString().trim();
        final reference = section.isNotEmpty ? section : chapter;
        lines.add(MomentPassage(
          kind: 'حکمت',
          arabic: '',
          urdu: urdu,
          source: reference.isEmpty ? book.titleUrdu : '${book.titleUrdu} — $reference',
          book: book,
          recordId: _asInt(row['record_id']) ?? 0,
          sectionId: _asInt(row['section_id']),
        ));
      }
    } catch (_) {
      return const <MomentPassage>[];
    }
    return lines;
  }

  Future<Passage?> getPassageById(BookDefinition book, int recordId) async {
    final db = await _openBook(book);
    switch (book.source) {
      case CorpusSource.sahifa:
      case CorpusSource.fatwa:
        final rows = await db.rawQuery('SELECT * FROM (${_extraQuery(book)}) WHERE record_id = ?', [recordId]);
        return rows.isEmpty ? null : Passage.fromMap(rows.first);
      case CorpusSource.encyclopedia:
        final rows = await db.rawQuery('''
          SELECT s.id AS record_id, s.article_id AS section_id,
                 '' AS arabic, s.plain_text AS urdu,
                 a.title_ur AS section_title, s.heading_ur AS locator,
                 s.source_url AS source_url
          FROM sections AS s JOIN articles AS a ON a.id = s.article_id
          WHERE s.id = ? LIMIT 1
        ''', [recordId]);
        return rows.isEmpty ? null : Passage.fromMap(rows.first);
      case CorpusSource.hadith:
        final rows = await db.rawQuery('''
          SELECT COALESCE(NULLIF(p.ID, ''), -p.rowid) AS record_id, p.txt AS arabic, p.Secid AS section_id,
                 p.paganum AS page_no, p.mean AS urdu,
                 COALESCE(s.title, '') AS section_title,
                 COALESCE(c.title, '') AS chapter_title
          FROM Parags AS p
          LEFT JOIN Sections AS s ON s.Secid = p.Secid
          LEFT JOIN Chaps AS c ON c.cid = s.Chapid
          WHERE COALESCE(NULLIF(p.ID, ''), -p.rowid) = ?
          LIMIT 1
        ''', [recordId]);
        return rows.isEmpty ? null : Passage.fromMap(rows.first);
      case CorpusSource.quran:
        final rows = await db.rawQuery('''
          SELECT q.ID AS record_id, q.Arabic AS arabic, q.tr AS urdu, q.talighe AS commentary,
                 q.chapter AS container_type, q.chapter AS container_id, q.page AS page_no,
                 q.juz AS juz, q.verse AS verse, COALESCE(cp.Name, '') AS surah_name
          FROM Quran AS q LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter
          WHERE q.ID = ?
          LIMIT 1
        ''', [recordId]);
        return rows.isEmpty ? null : _quranPassage(rows.first);
      case CorpusSource.dua:
        final itemRows = await db.rawQuery(
          'SELECT rowid AS row_id, _id, M_name, M_cat_id FROM M_items WHERE rowid = ? LIMIT 1',
          [recordId],
        );
        if (itemRows.isEmpty) return null;
        final title = (itemRows.first['M_name'] ?? '').toString();
        final category = _asInt(itemRows.first['M_cat_id']) ?? 0;
        return Passage(
          recordId: recordId,
          arabic: '',
          urdu: title,
          containerType: category,
          containerId: recordId,
          chapterTitle: duaCategoryTitles[category] ?? 'مفاتیح الجنان',
          sectionTitle: title,
          locator: 'دعا',
        );
      case CorpusSource.balagha:
        // حواشی and مقدمے are not part of the reader any more. A negative id
        // used to point at those tables; it now resolves to nothing.
        if (recordId <= 0) return null;
        final rows = await db.rawQuery('''
          SELECT x.ID AS record_id, x.AR AS arabic, x.UR AS urdu, x.ParaNo AS page_no,
                 x.Type AS container_type, x.TypeNo AS container_id,
                 COALESCE(t.ShortDesc, t.Description, '') AS section_title
          FROM balaghatext AS x
          LEFT JOIN balaghatoc AS t ON t.TypeID = x.Type AND t.TypeNo = x.TypeNo
          WHERE x.ID = ?
          LIMIT 1
        ''', [recordId]);
        if (rows.isEmpty) return null;
        final row = rows.first;
        final type = _asInt(row['container_type']) ?? 1;
        if (type < 1 || type > 3) return null;
        return Passage(
          recordId: recordId,
          arabic: _compact((row['arabic'] ?? '').toString()),
          urdu: repairNahjulBalaghaUrdu(recordId, _compact((row['urdu'] ?? '').toString())),
          page: _asInt(row['page_no']),
          containerType: type,
          containerId: _asInt(row['container_id']),
          chapterTitle: balaghaSectionTitles[type] ?? 'نہج البلاغہ',
          sectionTitle: polishBalaghaTitle(_compact((row['section_title'] ?? '').toString())),
        );
    }
  }

  /// Literal normalized substring search over EVERY indexed record. Pagination
  /// limits hydration/rendering, never which part of the book is searched.
  Future<({List<SearchHit> hits, int total})> searchPage(String query, {
    int offset = 0, int limit = 40, String? bookKey,
    String language = 'all', CorpusSource? source,
  }) async {
    final tokens = normalizeArabicUrdu(query).split(' ').where((t) => t.isNotEmpty).toSet();
    final db = _searchDatabase;
    if (tokens.isEmpty || db == null) return (hits: <SearchHit>[], total: 0);
    final column = language == 'arabic' ? 'norm_arabic' : language == 'urdu' ? 'norm_urdu' : 'norm_text';
    final conditions = <String>[];
    final args = <Object?>[];
    for (final token in tokens) {
      conditions.add("COALESCE($column, '') LIKE ?");
      args.add(likeNeedle(token));
    }
    if (bookKey != null) { conditions.add('book = ?'); args.add(bookKey); }
    final keys = source == null ? _installed.toList() : _installedBookKeysFor(source);
    if (keys.isEmpty) return (hits: <SearchHit>[], total: 0);
    conditions.add('book IN (${List.filled(keys.length, '?').join(',')})');
    args.addAll(keys);
    final where = conditions.join(' AND ');
    final counts = await db.rawQuery('SELECT COUNT(*) AS total FROM search_docs WHERE $where', args);
    final total = _asInt(counts.first['total']) ?? 0;
    final docs = await db.rawQuery('SELECT * FROM search_docs WHERE $where ORDER BY id LIMIT ? OFFSET ?', [...args, limit, offset]);
    final hits = <SearchHit>[];
    for (final doc in docs) {
      final book = BookDefinition.byKey(doc['book']?.toString());
      final id = _asInt(doc['record_id']);
      if (book == null || id == null) continue;
      final hydrated = await _hydrate(book, [id], tokens.toList());
      final passage = hydrated[id];
      if (passage == null) throw StateError('Indexed passage missing: ${book.key}:$id');
      hits.add(SearchHit(book: book, passage: passage, citation: formatCitation(
        bookTitle: book.titleUrdu, chapterTitle: passage.chapterTitle,
        sectionTitle: passage.sectionTitle, locator: passage.locator, page: passage.page)));
    }
    return (hits: hits, total: total);
  }

  // ---------------------------------------------------------------- search

  Future<List<SearchHit>> search(
    String query, {
    int limit = 40,
    String? bookKey,
    String language = 'all',
    CorpusSource? source,
  }) async {
    final tokens = searchTokens(query);
    if (tokens.isEmpty) return [];
    final selectedLanguage = const {'arabic', 'urdu'}.contains(language) ? language : 'all';
    final fts4 = _ftsEngine == 'fts4';
    final bookFilter = bookKey ?? _singleBookKeyFor(source);

    List<Map<String, Object?>> docs = [];
    if (_ftsAvailable) {
      for (final prefix in const [true, false]) {
        final strict = buildFtsQuery(tokens, fts4: fts4, prefix: prefix, andMode: true);
        if (strict.isNotEmpty) docs = await _searchFts(strict, limit, bookFilter, source);
        if (docs.isNotEmpty) break;
        final broad = buildFtsQuery(tokens, fts4: fts4, prefix: prefix, andMode: false);
        if (broad.isNotEmpty && broad != strict) {
          docs = await _searchFts(broad, limit, bookFilter, source);
        }
        if (docs.isNotEmpty) break;
      }
    }
    if (docs.isEmpty) {
      docs = await _searchNormalizedLike(tokens, limit, bookFilter, source);
    }
    if (docs.isEmpty && tokens.length > 2) {
      final distinctive = [...tokens]..sort((a, b) => b.length.compareTo(a.length));
      docs = await _searchNormalizedLike(distinctive.take(2).toList(), limit, bookFilter, source);
    }
    if (docs.isEmpty) return [];

    final grouped = <String, List<Map<String, Object?>>>{};
    for (final doc in docs) {
      final key = (doc['book'] ?? '').toString();
      grouped.putIfAbsent(key, () => []).add(doc);
    }
    final passageCache = <String, Map<int, Passage>>{};
    for (final entry in grouped.entries) {
      final book = BookDefinition.byKey(entry.key);
      if (book == null || !_installed.contains(book.key)) continue;
      final ids = entry.value.map((doc) => _asInt(doc['record_id'])).whereType<int>().toList();
      if (ids.isEmpty) continue;
      passageCache[entry.key] = await _hydrate(book, ids, tokens);
    }

    final hits = <SearchHit>[];
    for (final doc in docs) {
      final hitBookKey = (doc['book'] ?? '').toString();
      final book = BookDefinition.byKey(hitBookKey);
      final id = _asInt(doc['record_id']);
      if (book == null || id == null) continue;
      final passage = passageCache[hitBookKey]?[id];
      if (passage == null) continue;
      if (selectedLanguage == 'arabic' && passage.arabic.trim().isEmpty) continue;
      if (selectedLanguage == 'urdu' &&
          passage.urdu.trim().isEmpty &&
          passage.commentary.trim().isEmpty) {
        continue;
      }
      final chapter = passage.chapterTitle.isNotEmpty
          ? passage.chapterTitle
          : (doc['chapter_title'] ?? '').toString();
      final section = passage.sectionTitle.isNotEmpty
          ? passage.sectionTitle
          : (doc['section_title'] ?? '').toString();
      hits.add(SearchHit(
        book: book,
        passage: Passage(
          recordId: passage.recordId,
          sectionId: passage.sectionId,
          page: passage.page,
          arabic: passage.arabic,
          urdu: passage.urdu,
          commentary: passage.commentary,
          locator: passage.locator,
          containerType: _asInt(doc['container_type']) ?? passage.containerType,
          containerId: _asInt(doc['container_id']) ?? passage.containerId,
          chapterTitle: chapter,
          sectionTitle: section,
        ),
        citation: formatCitation(
          bookTitle: book.titleUrdu,
          chapterTitle: chapter,
          sectionTitle: section,
          locator: passage.locator,
          page: passage.page,
        ),
      ));
    }
    return hits.take(limit).toList();
  }

  String? _singleBookKeyFor(CorpusSource? source) {
    if (source == null) return null;
    final matches = BookDefinition.all
        .where((book) => book.source == source && _installed.contains(book.key))
        .toList();
    return matches.length == 1 ? matches.first.key : null;
  }

  /// Loads the full text for search results, using the query to pick the best
  /// snippet for collections that are indexed per supplication.
  Future<Map<int, Passage>> _hydrate(
    BookDefinition book,
    List<int> ids,
    List<String> tokens,
  ) async {
    final db = await _openBook(book);
    final placeholders = List.filled(ids.length, '?').join(',');
    switch (book.source) {
      case CorpusSource.sahifa:
      case CorpusSource.fatwa:
        final rows = await db.rawQuery('SELECT * FROM (${_extraQuery(book)}) WHERE record_id IN ($placeholders)', ids);
        return {for (final row in rows) _asInt(row['record_id'])!: Passage.fromMap(row)};
      case CorpusSource.encyclopedia:
        final rows = await db.rawQuery('''
          SELECT s.id AS record_id, s.article_id AS section_id,
                 '' AS arabic, s.plain_text AS urdu,
                 a.title_ur AS section_title, s.heading_ur AS locator,
                 s.source_url AS source_url
          FROM sections AS s JOIN articles AS a ON a.id = s.article_id
          WHERE s.id IN ($placeholders)
        ''', ids);
        return {
          for (final row in rows)
            if (_asInt(row['record_id']) != null) _asInt(row['record_id'])!: Passage.fromMap(row),
        };
      case CorpusSource.hadith:
        final rows = await db.rawQuery('''
          SELECT COALESCE(NULLIF(p.ID, ''), -p.rowid) AS record_id, p.txt AS arabic, p.Secid AS section_id,
                 p.paganum AS page_no, p.mean AS urdu,
                 COALESCE(s.title, '') AS section_title,
                 COALESCE(c.title, '') AS chapter_title
          FROM Parags AS p
          LEFT JOIN Sections AS s ON s.Secid = p.Secid
          LEFT JOIN Chaps AS c ON c.cid = s.Chapid
          WHERE COALESCE(NULLIF(p.ID, ''), -p.rowid) IN ($placeholders)
        ''', ids);
        return {
          for (final row in rows)
            if (_asInt(row['record_id']) != null) _asInt(row['record_id'])!: Passage.fromMap(row),
        };
      case CorpusSource.quran:
        final rows = await db.rawQuery('''
          SELECT q.ID AS record_id, q.Arabic AS arabic, q.tr AS urdu, q.talighe AS commentary,
                 q.chapter AS container_type, q.chapter AS container_id, q.page AS page_no,
                 q.juz AS juz, q.verse AS verse, COALESCE(cp.Name, '') AS surah_name
          FROM Quran AS q LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter
          WHERE q.ID IN ($placeholders)
        ''', ids);
        return {
          for (final row in rows)
            if (_asInt(row['record_id']) != null) _asInt(row['record_id'])!: _quranPassage(row),
        };
      case CorpusSource.balagha:
        final result = <int, Passage>{};
        for (final id in ids) {
          final passage = await getPassageById(book, id);
          if (passage != null) result[id] = passage;
        }
        return result;
      case CorpusSource.dua:
        final rows = await db.rawQuery('''
          SELECT m.rowid AS record_id, m.M_name AS section_title, m.M_cat_id AS container_type,
                 m._id AS container_id
          FROM M_items AS m WHERE m.rowid IN ($placeholders)
        ''', ids);
        final itemIds = rows.map((row) => _asInt(row['container_id'])).whereType<int>().toList();
        final lineRows = itemIds.isEmpty
            ? <Map<String, Object?>>[]
            : await db.rawQuery('''
                SELECT L_M_id, L_text, L_Translate, L_prio, L_type
                FROM Lines WHERE L_M_id IN (${List.filled(itemIds.length, '?').join(',')})
                ORDER BY L_M_id, L_prio, rowid
              ''', itemIds);
        final linesByItem = <int, List<Map<String, Object?>>>{};
        for (final row in lineRows) {
          final key = _asInt(row['L_M_id']);
          if (key == null) continue;
          linesByItem.putIfAbsent(key, () => []).add(row);
        }
        final result = <int, Passage>{};
        for (final row in rows) {
          final recordId = _asInt(row['record_id']);
          final itemId = _asInt(row['container_id']);
          if (recordId == null || itemId == null) continue;
          final lines = linesByItem[itemId] ?? const [];
          final best = _bestMatchingLine(lines, tokens);
          final category = _asInt(row['container_type']) ?? 0;
          final title = _compact((row['section_title'] ?? '').toString());
          if (best == null) {
            result[recordId] = Passage(
              recordId: recordId,
              arabic: '',
              urdu: title,
              containerType: category,
              containerId: recordId,
              chapterTitle: duaCategoryTitles[category] ?? 'مفاتیح الجنان',
              sectionTitle: title,
            );
            continue;
          }
          final text = _compact((best['L_text'] ?? '').toString());
          final translate = _compact((best['L_Translate'] ?? '').toString());
          final isNote = _asInt(best['L_type']) == 2 || translate.isEmpty || translate == '0';
          result[recordId] = Passage(
            recordId: recordId,
            arabic: isNote ? '' : text,
            urdu: isNote ? text : translate,
            containerType: category,
            containerId: recordId,
            chapterTitle: duaCategoryTitles[category] ?? 'مفاتیح الجنان',
            sectionTitle: title,
          );
        }
        return result;
    }
  }

  Map<String, Object?>? _bestMatchingLine(List<Map<String, Object?>> lines, List<String> tokens) {
    if (lines.isEmpty) return null;
    Map<String, Object?>? best;
    var bestScore = -1;
    for (final line in lines) {
      final blob = '${line['L_text'] ?? ''} ${line['L_Translate'] ?? ''}';
      final score = relevanceScore(blob, tokens);
      if (score > bestScore) {
        bestScore = score;
        best = line;
      }
    }
    return best ?? lines.first;
  }

  Future<List<SearchHit>> searchMany(
    List<String> queries, {
    int limit = 12,
    String? bookKey,
    String language = 'all',
    CorpusSource? source,
  }) async {
    final seen = <String>{};
    final merged = <SearchHit>[];
    for (final query in queries.take(12)) {
      if (query.trim().isEmpty) continue;
      final batch = await search(
        query,
        limit: limit,
        bookKey: bookKey,
        language: language,
        source: source,
      );
      for (final hit in batch) {
        final id = '${hit.book.key}:${hit.passage.recordId}';
        if (seen.add(id)) merged.add(hit);
      }
    }
    if (merged.isEmpty) return const [];
    final terms = queries.expand(searchTokens).toSet();
    int scoreOf(SearchHit hit) {
      final title =
          relevanceScore('${hit.passage.chapterTitle} ${hit.passage.sectionTitle}', terms) * 4;
      final body = relevanceScore(
        '${hit.passage.arabic} ${hit.passage.urdu} ${hit.passage.commentary}',
        terms,
      );
      return title + body;
    }

    merged.sort((left, right) => scoreOf(right).compareTo(scoreOf(left)));
    return merged.take(limit).toList();
  }

  Future<List<Map<String, Object?>>> _searchFts(
    String expression,
    int limit,
    String? bookKey,
    CorpusSource? source,
  ) async {
    if (expression.isEmpty || _searchDatabase == null) return [];
    final where = <String>[];
    final args = <Object?>[expression];
    if (bookKey != null) {
      where.add('d.book = ?');
      args.add(bookKey);
    }
    if (source != null) {
      final keys = _installedBookKeysFor(source);
      if (keys.isEmpty) return [];
      where.add('d.book IN (${List.filled(keys.length, '?').join(',')})');
      args.addAll(keys);
    }
    args.add(limit);
    final clause = where.isEmpty ? '' : ' AND ${where.join(' AND ')}';
    final rank = _ftsEngine == 'fts5' ? 'bm25(search_fts, 0.35, 0.6, 1.2, 1.2)' : 'd.id';
    try {
      return await _searchDatabase!.rawQuery('''
        SELECT d.*, $rank AS rank
        FROM search_fts
        JOIN search_docs AS d ON d.id = search_fts.rowid
        WHERE search_fts MATCH ?$clause
        ORDER BY rank
        LIMIT ?
      ''', args);
    } catch (_) {
      return [];
    }
  }

  List<String> _installedBookKeysFor(CorpusSource source) => BookDefinition.all
      .where((book) => book.source == source && _installed.contains(book.key))
      .map((book) => book.key)
      .toList();

  Future<List<Map<String, Object?>>> _searchNormalizedLike(
    List<String> tokens,
    int limit,
    String? bookKey,
    CorpusSource? source,
  ) async {
    if (_searchDatabase == null || tokens.isEmpty) return [];
    final conditions = <String>[];
    final args = <Object?>[];
    for (final token in tokens) {
      conditions.add("COALESCE(d.norm_text, '') LIKE ?");
      args.add(likeNeedle(token));
    }
    if (bookKey != null) {
      conditions.add('d.book = ?');
      args.add(bookKey);
    }
    if (source != null) {
      final keys = _installedBookKeysFor(source);
      if (keys.isEmpty) return [];
      conditions.add('d.book IN (${List.filled(keys.length, '?').join(',')})');
      args.addAll(keys);
    }
    args.add(limit);
    try {
      return await _searchDatabase!.rawQuery('''
        SELECT d.*
        FROM search_docs AS d
        WHERE ${conditions.join(' AND ')}
        ORDER BY d.id
        LIMIT ?
      ''', args);
    } catch (_) {
      return [];
    }
  }

  // ------------------------------------------------------ saved user state

  /// Bookmarks and notes are consulted for every card the readers build.
  ///
  /// Two SharedPreferences reads per card is two platform-channel round trips
  /// per card — hundreds of them while a 286-verse surah or a long chapter
  /// scrolls in, which is exactly where the stutter came from. Both are read
  /// once and kept in sync on write.
  Set<String>? _bookmarkCache;
  Map<String, String>? _noteCache;

  Future<Set<String>> _bookmarkSet() async {
    final cached = _bookmarkCache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    return _bookmarkCache = (prefs.getStringList('bookmarks') ?? const <String>[]).toSet();
  }

  Future<Map<String, String>> _noteMap() async {
    final cached = _noteCache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final notes = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('note:')) continue;
      final value = prefs.getString(key);
      if (value != null && value.trim().isNotEmpty) notes[key] = value;
    }
    return _noteCache = notes;
  }

  Future<bool> isBookmarked(String bookKey, int recordId) async =>
      (await _bookmarkSet()).contains('$bookKey:$recordId');

  /// Same answers, without the `await`, for readers that build cards by the
  /// hundred: when the cache is warm these return immediately and the card can
  /// paint once instead of rebuilding after every lookup.
  bool isBookmarkedNow(String bookKey, int recordId) =>
      _bookmarkCache?.contains('$bookKey:$recordId') ?? false;

  String? noteNow(String bookKey, int recordId) => _noteCache?['note:$bookKey:$recordId'];

  Future<void> toggleBookmark(String bookKey, int recordId) async {
    final bookmarks = await _bookmarkSet();
    final key = '$bookKey:$recordId';
    if (bookmarks.contains(key)) {
      bookmarks.remove(key);
    } else {
      bookmarks.add(key);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bookmarks', bookmarks.toList());
  }

  Future<List<ReaderTarget>> getBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList('bookmarks') ?? <String>[];
    return values.map((value) {
      final parts = value.split(':');
      return ReaderTarget(book: parts.first, recordId: int.tryParse(parts.last) ?? 0);
    }).where((target) => target.recordId != 0).toList();
  }

  // ------------------------------------------------- whole-surah bookmarks
  //
  // A verse bookmark stores `quran:<recordId>`, which is one card in the
  // reader. Readers also asked to keep an entire surah on the shelf — that is
  // a different thing (it opens the reader at verse 1, not at one passage), so
  // it gets its own list under its own key and never collides with the verse
  // bookmarks above.

  Set<int>? _surahBookmarkCache;

  Future<Set<int>> _surahBookmarkSet() async {
    final cached = _surahBookmarkCache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    return _surahBookmarkCache = (prefs.getStringList('surah_bookmarks') ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  Future<bool> isSurahBookmarked(int number) async =>
      (await _surahBookmarkSet()).contains(number);

  /// Same answer without the `await`, for a list that paints 114 rows.
  bool isSurahBookmarkedNow(int number) =>
      _surahBookmarkCache?.contains(number) ?? false;

  Future<void> toggleSurahBookmark(int number) async {
    final saved = await _surahBookmarkSet();
    if (!saved.remove(number)) saved.add(number);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'surah_bookmarks',
      (saved.toList()..sort()).map((number) => number.toString()).toList(),
    );
  }

  /// The saved surah numbers, in mushaf order.
  Future<List<int>> getSurahBookmarks() async =>
      (await _surahBookmarkSet()).toList()..sort();

  /// Loads the surah bookmarks into the cache before a list renders, so the
  /// first frame already shows the right icons instead of flickering.
  Future<void> warmSurahBookmarks() async {
    await _surahBookmarkSet();
  }

  Future<String?> getNote(String bookKey, int recordId) async =>
      (await _noteMap())['note:$bookKey:$recordId'];

  Future<void> saveNote(String bookKey, int recordId, String text) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'note:$bookKey:$recordId';
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(key);
      _noteCache?.remove(key);
    } else {
      await prefs.setString(key, trimmed);
      // Only touch a cache that is already loaded; building a partial one here
      // would make every other note invisible.
      final cache = _noteCache;
      if (cache != null) cache[key] = trimmed;
    }
  }

  Future<List<(BookDefinition, Passage, String)>> getNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final output = <(BookDefinition, Passage, String)>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('note:')) continue;
      final parts = key.split(':');
      if (parts.length < 3) continue;
      final book = BookDefinition.byKey(parts[1]);
      final recordId = int.tryParse(parts.sublist(2).join(':'));
      final note = prefs.getString(key);
      if (book == null || recordId == null || note == null || note.trim().isEmpty) continue;
      if (!_installed.contains(book.key)) continue;
      final passage = await getPassageById(book, recordId);
      if (passage != null) output.add((book, passage, note));
    }
    return output;
  }

  /// Remembers where the reader stopped.
  ///
  /// Two entries are written every time: the global one (آخری مطالعہ — the last
  /// book that was open, with its chapter and locator) and one keyed by the
  /// book, so the Quran, Mafatih, Sahifa, Nahj al-Balagha and every hadith book
  /// each keep their own place.
  Future<void> saveLastRead({
    required String bookKey,
    required int recordId,
    int? sectionId,
    String title = '',
    String reference = '',
  }) async {
    if (recordId == 0 || BookDefinition.byKey(bookKey) == null) return;
    final entry = LastReadEntry(
      bookKey: bookKey,
      recordId: recordId,
      sectionId: sectionId,
      title: title,
      reference: reference,
      savedAt: DateTime.now(),
    );
    final encoded = jsonEncode(entry.toJson());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastReadKey, encoded);
    await prefs.setString('$_kLastReadPrefix$bookKey', encoded);
  }

  /// The last position across every book (آخری مطالعہ).
  Future<LastReadEntry?> getLastRead() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastReadKey);
    if (raw != null && raw.isNotEmpty) {
      final entry = _decodeLastRead(raw);
      if (entry != null) return entry;
    }
    // Pre-1.5 installs stored `book:recordId:sectionId`.
    final legacy = prefs.getString('last_read');
    if (legacy == null || legacy.isEmpty) return null;
    try {
      final entry = LastReadEntry.fromLegacy(legacy);
      return entry.isValid ? entry : null;
    } catch (_) {
      return null;
    }
  }

  /// The saved position inside one book, if it has been opened before.
  Future<LastReadEntry?> getLastReadFor(String bookKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_kLastReadPrefix$bookKey');
    return raw == null ? null : _decodeLastRead(raw);
  }

  /// Every book's own last position, most recently read first.
  Future<List<LastReadEntry>> getLastReads() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <LastReadEntry>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_kLastReadPrefix)) continue;
      final entry = _decodeLastRead(prefs.getString(key) ?? '');
      if (entry != null) entries.add(entry);
    }
    entries.sort((a, b) {
      final left = a.savedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.savedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    return entries;
  }

  static LastReadEntry? _decodeLastRead(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final entry = LastReadEntry.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      return entry.isValid ? entry : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async {
    for (final db in _bookDatabases.values) {
      await db.close();
    }
    _bookDatabases.clear();
    await _searchDatabase?.close();
    _searchDatabase = null;
    _installed.clear();
    _initialized = false;
    _searchReady = false;
    _indexing = false;
    _indexAgain = false;
  }
}

/// Pre-compiled patterns for [_compact], which runs on every field of every
/// row a section loads — worth keeping out of the hot path.
final RegExp _bidiMarks = RegExp(r'[\u200e\u200f\u200b\ufeff]');
final RegExp _runsOfSpace = RegExp(r'[^\S\n]+');
final RegExp _spaceAroundNewline = RegExp(r' *\n *');
final RegExp _manyNewlines = RegExp(r'\n{3,}');

String _compact(String value) {
  if (value.isEmpty) return value;
  // Most rows are already clean. A `contains` check is a fast native scan,
  // while a RegExp over every field of every row of a long chapter was enough
  // work to stall the frame that loaded it.
  var text = value;
  if (text.contains('\r')) text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (text.contains('\u0640')) text = text.replaceAll('\u0640', '');
  if (_bidiMarks.hasMatch(text)) text = text.replaceAll(_bidiMarks, '');
  if (text.contains('  ') || text.contains('\t')) text = text.replaceAll(_runsOfSpace, ' ');
  if (text.contains('\n')) {
    text = text.replaceAll(_spaceAroundNewline, '\n');
    if (text.contains('\n\n\n')) text = text.replaceAll(_manyNewlines, '\n\n');
  }
  return text.trim();
}

int? _asInt(Object? value) {
  if (value == null || value == '') return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

/// «(۹۴۱۸ .. ۸۰) بدترین وزیر …» → «بدترین وزیر …».
///
/// Hidayat al-Ilm keeps its citation as a parenthesised number prefix inside
/// the Urdu column. The moment card shows the sentence and its reference
/// separately, so the prefix is stripped only when the brackets hold numbers.
String _stripHidayaCitation(String raw) {
  final text = raw.trim();
  if (!text.startsWith('(')) return text;
  final close = text.indexOf(')');
  if (close < 2 || close > 24) return text;
  final inside = text.substring(1, close);
  if (!RegExp(r'^[0-9۰-۹ .·]+$').hasMatch(inside)) return text;
  return text.substring(close + 1).trim();
}
