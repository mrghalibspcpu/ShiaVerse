import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiaverse/library_repository.dart';
import 'package:shiaverse/models.dart';

void main() {
  group('local Arabic/Urdu search', () {
    test('normalizes diacritics and common Arabic/Persian letter variants', () {
      expect(normalizeArabicUrdu('آلِ كَافِيٌّ'), 'ال کافی');
      expect(normalizeArabicUrdu('قَالَ الشَّيْخُ عَلِيٌّ'), 'قال الشیخ علی');
    });

    test('compacts Arabic display text used by the reader', () {
      final passage = Passage.fromMap({
        'record_id': 1,
        'arabic': 'قَالَ\u200f  أَبُو جَعْفَرٍ',
        'urdu': 'امام  نے  فرمایا',
      });
      expect(passage.arabic.contains('  '), isFalse);
      expect(passage.urdu, 'امام نے فرمایا');
    });

    test('does not produce terms for punctuation-only input', () {
      expect(normalizeArabicUrdu('  ؟ ؛ ،  '), isEmpty);
    });

    test('compacting a row only rewrites what actually needs it', () {
      final passage = Passage.fromMap({
        'record_id': 2,
        'arabic': 'بِسْمِ  اللّٰهِ\r\nالرَّحْمٰنِ\n\n\n\nالرَّحِيْمِ',
        'urdu': 'شروع   اللہ کے نام سے\n   جو بڑا مہربان',
      });
      expect(passage.arabic, isNot(contains('\r')));
      expect(passage.arabic, isNot(contains('\n\n\n')));
      expect(passage.arabic, 'بِسْمِ اللّٰهِ\nالرَّحْمٰنِ\n\nالرَّحِيْمِ');
      expect(passage.urdu, 'شروع اللہ کے نام سے\nجو بڑا مہربان');
      // A row that is already clean is returned untouched.
      expect(
        Passage.fromMap({'record_id': 3, 'arabic': 'صلى الله عليه وآله'}).arabic,
        'صلى الله عليه وآله',
      );
    });
  });

  group('corpus catalogue', () {
    test('lists the 14 hadith books plus the curated collections', () {
      // Ten extra collections: Quran, Mafatih, Sahifa, Nahj al-Balagha, the
      // curated encyclopaedia and the three marjas.
      expect(BookDefinition.all, hasLength(22));
      expect(BookDefinition.hadithBooks, hasLength(14));
      expect(
        BookDefinition.newBooks.map((book) => book.key),
        <String>['athna_ashari_encyclopedia'],
      );
      expect(BookDefinition.byKey('athna_ashari_encyclopedia')?.source,
          CorpusSource.encyclopedia);
      expect(BookDefinition.byKey('tahzeeb')?.fileName, 'Tahzeeb.db');
      expect(BookDefinition.byKey('quran')?.source, CorpusSource.quran);
      expect(BookDefinition.byKey('mafatih')?.fileName, 'mafatihdb-v4.db');
      expect(BookDefinition.byKey('nahjul_balagha')?.source, CorpusSource.balagha);
      expect(BookDefinition.byKey('does-not-exist'), isNull);
    });

    test('every book resolves from its own source', () {
      for (final source in CorpusSource.values) {
        expect(BookDefinition.bookFor(source), isNotNull, reason: source.wire);
      }
      expect(BookDefinition.bookFor(CorpusSource.quran)?.key, 'quran');
      expect(corpusSourceFromWire('dua'), CorpusSource.dua);
      expect(corpusSourceFromWire('nonsense'), CorpusSource.hadith);
    });

    test('file names stay unique so downloads cannot overwrite each other', () {
      final names = BookDefinition.all.map((book) => book.fileName).toSet();
      expect(names, hasLength(BookDefinition.all.length));
      final keys = BookDefinition.all.map((book) => book.key).toSet();
      expect(keys, hasLength(BookDefinition.all.length));
    });
  });

  group('reader records', () {
    test('reads the shared columns of every collection', () {
      final passage = Passage.fromMap({
        'record_id': 12,
        'arabic': 'بِسْمِ اللَّهِ',
        'urdu': 'اللہ کے نام سے',
        'commentary': 'تفسیری حاشیہ',
        'locator': 'آیت 1',
        'container_type': 1,
        'container_id': 1,
      });
      expect(passage.recordId, 12);
      expect(passage.locator, 'آیت 1');
      expect(passage.containerType, 1);
      expect(passage.commentary, 'تفسیری حاشیہ');
      expect(passage.copyableText, contains('بِسْمِ اللَّهِ'));
      expect(passage.copyWith(footnote: 'حاشیہ').footnote, 'حاشیہ');
    });

    test('hadith citations keep the record locator', () {
      final source = ReaderTarget.fromJson({
        'book': 'alkafi',
        'record_id': 9001,
        'section_id': 7,
        'page': 12,
      });
      expect(source.book, 'alkafi');
      expect(source.recordId, 9001);
      expect(source.sectionId, 7);
      expect(source.page, 12);
    });
  });

  group('new collections', () {
    test('maps surah rows and adds the Urdu name', () {
      final surah = QuranSurah.fromMap(
        {'Id': 1, 'Name': 'الْفَاتِحَة', 'Nozol': 'مکی', 'Verse': 7, 'revel': 5},
        index: 0,
      );
      expect(surah.nameUrdu, 'الفاتحہ');
      expect(surah.verseCount, 7);
      expect(surah.revelationOrder, 5);
      expect(surah.displayTitle, contains('الْفَاتِحَة'));
    });

    test('surah name list covers the whole mushaf', () {
      expect(urduSurahNames, hasLength(114));
      expect(urduSurahNames.first, 'الفاتحہ');
      expect(urduSurahNames.last, 'الناس');
    });

    test('maps Mafatih catalogue rows', () {
      final header = DuaItem.fromMap({
        'row_id': 1,
        'M_name': 'تعقیبات نماز',
        'M_cat_id': 2,
        'M_type': 2,
        'M_montakhab': 0,
        'line_count': 0,
      });
      final leaf = DuaItem.fromMap({
        'row_id': 2,
        'M_name': 'تعقیبات مشترکہ',
        'M_cat_id': 2,
        'M_type': 1,
        'M_montakhab': 1,
        'line_count': 41,
      });
      expect(header.isHeader, isTrue);
      expect(leaf.isHeader, isFalse);
      expect(leaf.isFeatured, isTrue);
      expect(leaf.lineCount, 41);
      expect(duaCategoryTitles, hasLength(6));
    });

    test('names every Nahj al-Balagha division', () {
      expect(balaghaSectionTitles[1], 'خطبات');
      expect(polishBalaghaTitle('خطب، خطوط اور حکمت'), 'خطبات، خطوط اور حکمت');
      expect(polishBalaghaTitle('خطبات'), 'خطبات');
      expect(polishBalaghaTitle('خطبہ'), 'خطبہ');
      expect(balaghaSectionTitles[2], 'کتب و خطوط');
      expect(balaghaSectionTitles[3], 'حکمت و اقوالِ قصار');
      expect(balaghaSectionTitles[4], contains('احادیث'));
      expect(balaghaSectionTitles[5], contains('مقدمات'));
    });

    test('describes where a juz starts', () {
      const entry = QuranJuzEntry(juz: 30, firstRecordId: 5678, surah: 78, verse: 1);
      expect(entry.title, contains('پارہ 30'));
      expect(entry.title, contains('النبا'));
      expect(entry.title, contains('آیت 1'));
    });
  });

  group('last seen', () {
    test('keeps the reference and the time through a JSON round trip', () {
      final entry = LastReadEntry(
        bookKey: 'quran',
        recordId: 42,
        sectionId: 7,
        title: 'البقرہ',
        reference: 'آیت 12 • پارہ 1',
        savedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final restored = LastReadEntry.fromJson(entry.toJson());
      expect(restored.bookKey, 'quran');
      expect(restored.recordId, 42);
      expect(restored.sectionId, 7);
      expect(restored.referenceOrTitle, contains('آیت 12'));
      expect(restored.savedAt, entry.savedAt);
      expect(restored.isValid, isTrue);
      expect(restored.target.recordId, 42);
    });

    test('reads the pre-1.5 book:recordId:sectionId value', () {
      final entry = LastReadEntry.fromLegacy('mafatih:812:0');
      expect(entry.bookKey, 'mafatih');
      expect(entry.recordId, 812);
      expect(entry.isValid, isTrue);
      expect(LastReadEntry.fromLegacy('nope:0').isValid, isFalse);
    });

    test('labels today, yesterday, and older days', () {
      final now = DateTime.now();
      expect(LastReadEntry(bookKey: 'quran', recordId: 1, savedAt: now).timeLabel, startsWith('آج'));
      final yesterday = now.subtract(const Duration(days: 1));
      expect(
        LastReadEntry(bookKey: 'quran', recordId: 1, savedAt: yesterday).timeLabel,
        startsWith('کل'),
      );
      final older = DateTime(2024, 3, 4, 9, 5);
      expect(LastReadEntry(bookKey: 'quran', recordId: 1, savedAt: older).timeLabel, '4/3/2024');
    });

    test('falls back to the book name when a passage has no locator', () {
      final book = BookDefinition.bookFor(CorpusSource.quran)!;
      const bare = Passage(recordId: 5, arabic: 'x', urdu: 'y');
      expect(readingReference(book, bare), book.titleUrdu);
      const located = Passage(
        recordId: 5,
        arabic: 'x',
        urdu: 'y',
        locator: 'آیت 5',
        sectionTitle: 'البقرہ',
      );
      expect(readingReference(book, located), contains('آیت 5'));
    });
  });

  group('fatawa library entry', () {
    test('offers every marja behind one tile', () {
      // The Khamenei edition was removed in 1.28; two marjas remain.
      expect(
        fatawaBooks.map((book) => book.key).toList(),
        ['sistani', 'najafi'],
      );
      expect(BookDefinition.byKey('khamenei'), isNull);
      for (final book in fatawaBooks) {
        expect(book.source, CorpusSource.fatwa);
        expect(book.marjaName, isNotEmpty);
        expect(book.imageAsset, isNotNull);
      }
      expect(kFatawaCollectionTitle, contains('دینی مسائل'));
    });

    test('the Najafi edition is the marja\'s own 8,104 rulings', () {
      final najafi = BookDefinition.byKey('najafi')!;
      expect(najafi.fileName, 'najafi_urdu_fatawa.sqlite');
      expect(najafi.marjaName, contains('حافظ بشیر حسین نجفی'));
      expect(najafi.imageAsset, 'assets/images/marja_najafi.png');
      // The portrait is bundled, or the card would fall back to an icon.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains(najafi.imageAsset!));
    });

    test('the home row keeps one card per collection, never two fatawa', () {
      final keys = featuredCollections.map((book) => book.key).toList();
      expect(keys, ['quran', 'nahjul_balagha']);
      for (final book in fatawaBooks) {
        expect(keys, isNot(contains(book.key)));
      }
    });
  });

  group('dua library entry', () {
    test('Mafatih al-Jinan and Sahifa Sajjadiyya share one tile', () {
      expect(duaCollectionBooks.map((book) => book.key).toList(), ['mafatih', 'sahifa']);
      expect(duaCollectionBooks.first.source, CorpusSource.dua);
      expect(duaCollectionBooks.last.source, CorpusSource.sahifa);
      expect(kDuaCollectionTitle, contains('مفاتیح الجنان'));
      expect(kDuaCollectionTitle, contains('صحیفہ سجادیہ'));
    });

    test('neither book also gets a card of its own', () {
      final keys = featuredCollections.map((book) => book.key).toSet();
      for (final book in duaCollectionBooks) {
        expect(keys, isNot(contains(book.key)));
      }
      // Both books are still in the library itself (search, downloads, links).
      expect(BookDefinition.byKey('mafatih'), isNotNull);
      expect(BookDefinition.byKey('sahifa'), isNotNull);
    });
  });

  group('source links', () {
    test('a fatawa passage knows the page it came from', () {
      final passage = Passage.fromMap({
        'record_id': 3,
        'urdu': 'ج: پاک ہیں۔',
        'source_url': 'https://www.sistani.org/urdu/qa/17169/',
        'source_ref': '17169',
      });
      expect(passage.hasSource, isTrue);
      expect(passage.sourceUrl, endsWith('/17169/'));
      expect(passage.sourceRef, '17169');
      expect(passage.copyWith(footnote: 'x').sourceUrl, passage.sourceUrl);
      expect(Passage.fromMap({'record_id': 4, 'urdu': 'x'}).hasSource, isFalse);
    });
  });
}
