import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiaverse/data_packages.dart';
import 'package:shiaverse/models.dart';

/// The **نئی کتابیں** shelf and its first book, **اثنا عشری انسائکلوپیڈیا**.
///
/// The shipped edition is built straight from
/// «اثنا عشری انسائکلوپیڈیا (منتخب).zip»: 574 curated Urdu-Wikipedia articles
/// and nothing else. These checks pin that — no second corpus may creep back
/// in, and every reference must point at ur.wikipedia.org.
void main() {
  final manifestFile = File('assets/database-manifest.json');
  final packedFile = File('../assets/athna_ashari_encyclopedia.db.gz');

  test('the encyclopaedia is a normal library book', () {
    final book = BookDefinition.byKey('athna_ashari_encyclopedia');
    expect(book, isNotNull);
    expect(book!.titleUrdu, 'اثنا عشری انسائکلوپیڈیا');
    expect(book.fileName, 'athna_ashari_encyclopedia.db');
    expect(book.source, CorpusSource.encyclopedia);
    expect(book.source.label, 'نئی کتابیں');
    // It must not leak into the hadith shelf (that list drives the library
    // page and the per-book download prompts).
    expect(BookDefinition.hadithBooks.map((book) => book.key),
        isNot(contains('athna_ashari_encyclopedia')));
    expect(BookDefinition.newBooks.map((book) => book.key),
        <String>['athna_ashari_encyclopedia']);
    expect(BookDefinition.all.where((book) => book.key == 'athna_ashari_encyclopedia'),
        hasLength(1));
    // Appended near the end, so existing books keep their accent colours.
    expect(BookDefinition.bookFor(CorpusSource.encyclopedia)!.key,
        'athna_ashari_encyclopedia');
  });

  test('the retired Wikipedia collection is gone from the catalogue', () {
    expect(BookDefinition.byKey('shia_wiki'), isNull);
    expect(BookDefinition.newBooks.map((book) => book.key), isNot(contains('shia_wiki')));
    expect(CorpusSource.values.map((source) => source.wire), isNot(contains('wiki')));
    final manifest = manifestFile.readAsStringSync();
    expect(manifest.contains('shia_urdu_wikipedia'), isFalse);
    expect(manifest.contains('"wiki"'), isFalse);
  });

  test('the manifest publishes the reader edition with a real digest', () {
    final catalog = DataCatalog.parse(manifestFile.readAsStringSync());
    final package = catalog.byKey('athna_ashari_encyclopedia');
    expect(package, isNotNull);
    expect(package!.fileName, 'athna_ashari_encyclopedia.db');
    expect(package.titleUrdu, 'اثنا عشری انسائکلوپیڈیا');
    expect(package.source, 'encyclopedia');
    expect(package.sha256, hasLength(64));
    expect(package.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    // The prose-only edition is around 10 MB; a manifest line advertising a
    // small or empty file would mean the build silently lost the corpus.
    // 574 articles across ten groups is 10,625,024 bytes.
    expect(package.sizeBytes, greaterThan(9 * 1024 * 1024));
    expect(package.isDownloadable, isTrue);
    // The app packages every database gzipped; the encyclopaedia is no
    // exception, and the installer unpacks and hashes it like the rest.
    expect(catalog.extension, '.gz');
    // The checked-in app copy of the manifest is the same document.
    expect(File('assets/database-manifest.json').readAsStringSync(),
        File('../assets/database-manifest.json').readAsStringSync());
  });

  test('the shipped edition carries only the selected Wikipedia corpus', () {
    // scripts/build_encyclopedia_db.py turns the Drive ZIP into the reader
    // edition. This pins the bytes committed here: every source page is an
    // ur.wikipedia.org revision, and the retired Wikishia notes are gone.
    final bytes = gzip.decode(packedFile.readAsBytesSync());
    final text = utf8.decode(bytes, allowMalformed: true);
    expect(text.contains('ur.wikipedia.org'), isTrue,
        reason: 'the Wikipedia articles are the edition');
    // Articles may *cite* a Wikishia page (a reference in the Wikipedia text),
    // but no section may carry a Wikishia revision URL: that was the merge.
    expect(text.contains('ur.wikishia.net/w/index.php?title='), isFalse,
        reason: 'the merged Wikishia notes were removed in 1.21');
    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final entry = (manifest['databases'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((item) => item['key'] == 'athna_ashari_encyclopedia');
    expect(entry['title_urdu'], 'اثنا عشری انسائکلوپیڈیا');
    expect(entry['sha256'], hasLength(64));
  });

  test('the committed .gz expands to exactly the published edition', () {
    expect(packedFile.existsSync(), isTrue,
        reason: 'assets/athna_ashari_encyclopedia.db.gz must be committed');
    final manifest = jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final entry = (manifest['databases'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((item) => item['key'] == 'athna_ashari_encyclopedia');
    final bytes = gzip.decode(packedFile.readAsBytesSync());
    expect(bytes.length, entry['size_bytes']);
    // A real SQLite database, not a text file or a truncated download.
    expect(utf8.decode(bytes.sublist(0, 15)), 'SQLite format 3');
    expect(sha256.convert(bytes).toString(), entry['sha256']);
  });
}
