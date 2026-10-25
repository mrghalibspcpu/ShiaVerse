enum CorpusSource { hadith, quran, dua, balagha, sahifa, fatwa, encyclopedia }

extension CorpusSourceX on CorpusSource {
  /// Urdu label used by the search filter and library sections.
  String get label => switch (this) {
        CorpusSource.hadith => 'کتبِ احادیث',
        CorpusSource.quran => 'قرآنِ کریم',
        CorpusSource.dua => 'دعائیں و اعمال',
        CorpusSource.balagha => 'نہج البلاغہ',
        CorpusSource.sahifa => 'صحیفہ سجادیہ',
        CorpusSource.fatwa => 'فتاویٰ',
        CorpusSource.encyclopedia => 'نئی کتابیں',
      };

  /// Wire value stored in the search index and the manifest.
  String get wire => switch (this) {
        CorpusSource.hadith => 'hadith',
        CorpusSource.quran => 'quran',
        CorpusSource.dua => 'dua',
        CorpusSource.balagha => 'balagha',
        CorpusSource.sahifa => 'sahifa',
        CorpusSource.fatwa => 'fatwa',
        CorpusSource.encyclopedia => 'encyclopedia',
      };
}

/// The Urdu fatawa books are offered as ONE library entry — the reader picks a
/// marja on the next screen instead of choosing between nearly identical tiles
/// on the home row.
const String kFatawaCollectionKey = 'dini_masail';
const String kFatawaCollectionTitle = 'دینی مسائل (احکام و فتاویٰ)';
const String kFatawaCollectionSubtitle = 'فتاویٰ، احکامِ شرعیہ اور سوال و جواب';
const String kFatawaCollectionHint = 'اپنا مرجعِ تقلید منتخب کریں';

/// Every fatwa book, in marja order (Sistani, then Najafi). The Khamenei
/// edition was removed in 1.28 at the owner's request.
List<BookDefinition> get fatawaBooks =>
    BookDefinition.all.where((book) => book.source == CorpusSource.fatwa).toList();

/// Mafatih al-Jinan and Sahifa Sajjadiyya are offered as ONE library entry
/// too: the reader opens the dua collection and picks the book there, the
/// same way the fatawa tile offers the two marjas.
const String kDuaCollectionKey = 'dua_collection';
const String kDuaCollectionTitle = 'مفاتیح الجنان و صحیفہ سجادیہ';
const String kDuaCollectionSubtitle = 'دعائیں، زیارات، اعمال اور مناجات';
const String kDuaCollectionHint = 'کتاب منتخب کریں';

/// The two books behind the combined dua tile: Mafatih first, then Sahifa.
List<BookDefinition> get duaCollectionBooks => [
      BookDefinition.bookFor(CorpusSource.dua)!,
      BookDefinition.bookFor(CorpusSource.sahifa)!,
    ];

/// Collections with a card of their own on the home row. The fatawa and the
/// dua books each sit behind one combined card instead.
List<BookDefinition> get featuredCollections => [
      BookDefinition.bookFor(CorpusSource.quran)!,
      BookDefinition.bookFor(CorpusSource.balagha)!,
    ];

CorpusSource corpusSourceFromWire(String? value) => switch (value) {
      'quran' => CorpusSource.quran,
      'dua' => CorpusSource.dua,
      'balagha' => CorpusSource.balagha,
      'sahifa' => CorpusSource.sahifa,
      'fatwa' => CorpusSource.fatwa,
      'encyclopedia' => CorpusSource.encyclopedia,
      _ => CorpusSource.hadith,
    };

class BookDefinition {
  const BookDefinition({
    required this.key,
    required this.fileName,
    required this.titleUrdu,
    required this.titleLatin,
    this.description = '',
    this.source = CorpusSource.hadith,
    this.recordLabel = 'حدیث نمبر',
    this.imageAsset,
    this.marjaName = '',
  });

  final String key;
  final String fileName;
  final String titleUrdu;
  final String titleLatin;
  final String description;
  final CorpusSource source;
  final String recordLabel;

  /// Portrait shown on the marja picker (`دینی مسائل`). Null for every other
  /// collection — the home row uses an icon for those.
  final String? imageAsset;

  /// Full name of the authority, for books that are one marja's fatawa.
  final String marjaName;

  static const List<BookDefinition> all = [
    BookDefinition(key: 'sahifa', fileName: 'Sahifa_Sajjadiyya_full_runtime.sqlite3',
      titleUrdu: 'صحیفہ سجادیہ', titleLatin: 'Sahifa Sajjadiyya',
      description: 'دعائیں، مناجات، ترجمہ اور حواشی', source: CorpusSource.sahifa, recordLabel: 'دعا'),
    BookDefinition(key: 'sistani', fileName: 'sistani_urdu_fatawa.sqlite',
      titleUrdu: 'فتاویٰ — آیت اللہ سیستانی', titleLatin: 'Sistani Urdu Fatawa',
      description: 'اردو سوال و جواب، اصل ماخذ کے ساتھ', source: CorpusSource.fatwa, recordLabel: 'مسئلہ',
      imageAsset: 'assets/images/marja_sistani.png',
      marjaName: 'آیت اللہ سید علی حسینی سیستانی'),
    // 1.24: 8,104 Urdu question/answer pairs from the marja's own website,
    // rebuilt by scripts/build_najafi_fatawa_db.py. Same two-table shape as
    // the other two marjas, so the reader needs no special case for it.
    BookDefinition(key: 'najafi', fileName: 'najafi_urdu_fatawa.sqlite',
      titleUrdu: 'فتاویٰ — آیت اللہ حافظ بشیر حسین نجفی', titleLatin: 'Hafiz Bashir Hussain Najafi Urdu Fatawa',
      description: 'اردو سوال و جواب، اصل ماخذ کے ساتھ', source: CorpusSource.fatwa, recordLabel: 'مسئلہ',
      imageAsset: 'assets/images/marja_najafi.png',
      marjaName: 'آیت اللہ العظمیٰ شیخ حافظ بشیر حسین نجفی'),
    BookDefinition(key: 'tahzeeb', fileName: 'Tahzeeb.db', titleUrdu: 'تہذیب الاحکام', titleLatin: 'Tahdhib al-Ahkam'),
    BookDefinition(key: 'alkafi', fileName: 'alkafi.db', titleUrdu: 'الکافی', titleLatin: 'Al-Kafi'),
    BookDefinition(key: 'alkhisal', fileName: 'alkhisal.db', titleUrdu: 'الخصال', titleLatin: 'Al-Khisal'),
    BookDefinition(key: 'hakam', fileName: 'hakam.db', titleUrdu: 'غرر الحکم', titleLatin: 'Ghurar al-Hikam'),
    BookDefinition(key: 'hidaya', fileName: 'hidaya.db', titleUrdu: 'ہدایۃ العلم', titleLatin: 'Hidayat al-Ilm'),
    BookDefinition(key: 'hikmatprophet', fileName: 'hikmatprophet.db', titleUrdu: 'حکمت نامۂ رسول اکرم(ص)', titleLatin: 'Hikmat-nama Rasul Akram (s)'),
    BookDefinition(key: 'imam', fileName: 'imam.db', titleUrdu: 'حکمت نامہ امام حسین(ع)', titleLatin: 'Hikmat-nama Imam Husain (a)'),
    BookDefinition(key: 'kamaledeen', fileName: 'kamaledeen.db', titleUrdu: 'کمال الدین و تمام النعمة', titleLatin: 'Kamal al-Din'),
    BookDefinition(key: 'maniakbar', fileName: 'maniakbar.db', titleUrdu: 'معانی الاخبار', titleLatin: "Ma'ani al-Akhbar"),
    BookDefinition(key: 'manlahyahzur', fileName: 'manlahyahzur.db', titleUrdu: 'من لا یحضره الفقیہ', titleLatin: 'Man La Yahduruhu al-Faqih'),
    BookDefinition(key: 'mezan', fileName: 'mezan.db', titleUrdu: 'میزان الحکمة', titleLatin: 'Mizan al-Hikmah'),
    BookDefinition(key: 'swab', fileName: 'swab.db', titleUrdu: 'ثواب الاعمال', titleLatin: 'Thawab al-A’mal'),
    BookDefinition(key: 'towheed', fileName: 'towheed.db', titleUrdu: 'کتاب التوحید', titleLatin: 'Kitab al-Tawhid'),
    BookDefinition(key: 'wasail', fileName: 'wasail.db', titleUrdu: 'وسائل الشیعہ', titleLatin: "Wasa'il al-Shi'a"),
    BookDefinition(
      key: 'quran',
      fileName: 'quran.db',
      titleUrdu: 'قرآنِ کریم',
      titleLatin: 'Al-Quran al-Karim',
      description: 'مکمل قرآن، اردو ترجمہ اور تفسیری حواشی کے ساتھ',
      source: CorpusSource.quran,
      recordLabel: 'آیت',
    ),
    BookDefinition(
      key: 'mafatih',
      fileName: 'mafatihdb-v4.db',
      titleUrdu: 'مفاتیح الجنان',
      titleLatin: 'Mafatih al-Jinan',
      description: 'دعائیں، زیارات، تعقیبات اور ماہانہ اعمال',
      source: CorpusSource.dua,
      recordLabel: 'دعا',
    ),
    BookDefinition(
      key: 'nahjul_balagha',
      fileName: 'nahjul_balagha.db',
      titleUrdu: 'نہج البلاغہ',
      titleLatin: 'Nahj al-Balagha',
      description: 'خطبات، مکاتبات اور حکمتیں — عربی متن اور اردو ترجمہ',
      source: CorpusSource.balagha,
      recordLabel: 'فقرا',
    ),
    // The curated encyclopaedia. It is appended LAST on purpose:
    // `bookAccent` indexes this list, so no existing book changes colour, and
    // every older key/file name stays exactly where it was.
    BookDefinition(
      key: 'athna_ashari_encyclopedia',
      fileName: 'athna_ashari_encyclopedia.db',
      titleUrdu: 'اثنا عشری انسائکلوپیڈیا',
      titleLatin: 'Twelver Shia Encyclopedia',
      description: 'ائمہ، اہل بیت، عقائد، عبادات، کتب اور مقامات — اردو ویکیپیڈیا کے منتخب ۵۷۴ مضامین، اصل ماخذ کے ساتھ',
      source: CorpusSource.encyclopedia,
      recordLabel: 'مضمون',
    ),
  ];

  static List<BookDefinition> get hadithBooks =>
      all.where((book) => book.source == CorpusSource.hadith).toList();

  /// Books added after the original corpus, shown under **Xplore → نئی کتابیں**
  /// instead of the home rail. The encyclopaedia is the first of them; adding
  /// another is one more entry here.
  static List<BookDefinition> get newBooks =>
      all.where((book) => book.source == CorpusSource.encyclopedia).toList();

  static BookDefinition? bookFor(CorpusSource source) {
    for (final book in all) {
      if (book.source == source) return book;
    }
    return null;
  }

  static BookDefinition? byKey(String? key) {
    if (key == null) return null;
    final needle = key.toLowerCase();
    for (final book in all) {
      if (book.key == needle) return book;
    }
    return null;
  }
}

class ReaderTarget {
  const ReaderTarget({
    required this.book,
    required this.recordId,
    this.sectionId,
    this.page,
  });

  final String book;
  final int recordId;
  final int? sectionId;
  final int? page;

  factory ReaderTarget.fromJson(Map<String, dynamic> json) {
    final sectionId = _asInt(json['section_id']);
    return ReaderTarget(
      book: (json['book'] ?? '').toString().toLowerCase(),
      recordId: _asInt(json['record_id']) ?? 0,
      sectionId: sectionId,
      page: _asInt(json['page']),
    );
  }
}

/// One saved reading position.
///
/// Two kinds are kept on the device: the global آخری مطالعہ — wherever the
/// reader was last across every book — and one entry per book, so the Quran
/// keeps its own place while Mafatih, Sahifa, Nahj al-Balagha and each hadith
/// book keep theirs. Both are written by
/// `LibraryRepository.saveLastRead()` and read back with `getLastRead()` /
/// `getLastReadFor(book)`.
class LastReadEntry {
  const LastReadEntry({
    required this.bookKey,
    required this.recordId,
    this.sectionId,
    this.title = '',
    this.reference = '',
    this.savedAt,
  });

  final String bookKey;
  final int recordId;
  final int? sectionId;

  /// Chapter / surah / supplication heading shown on the resume card.
  final String title;

  /// Where inside that chapter the reader stopped, e.g. `آیت ۱۲ • پارہ ۱`.
  final String reference;
  final DateTime? savedAt;

  BookDefinition? get book => BookDefinition.byKey(bookKey);

  /// Heading and locator joined, whichever of the two the reader knows.
  String get referenceOrTitle => [
        if (reference.trim().isNotEmpty) reference.trim(),
        if (title.trim().isNotEmpty) title.trim(),
      ].join(' — ');

  String get timeLabel {
    final at = savedAt;
    if (at == null) return '';
    final stamp = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    if (sameDay) return 'آج $stamp';
    final yesterday = now.subtract(const Duration(days: 1));
    if (at.year == yesterday.year && at.month == yesterday.month && at.day == yesterday.day) {
      return 'کل $stamp';
    }
    return '${at.day}/${at.month}/${at.year}';
  }

  factory LastReadEntry.fromJson(Map<String, dynamic> json) => LastReadEntry(
        bookKey: (json['book'] ?? '').toString(),
        recordId: _asInt(json['record_id']) ?? 0,
        sectionId: _asInt(json['section_id']),
        title: (json['title'] ?? '').toString(),
        reference: (json['reference'] ?? '').toString(),
        savedAt: _asInt(json['saved_at']) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(_asInt(json['saved_at'])!),
      );

  Map<String, dynamic> toJson() => {
        'book': bookKey,
        'record_id': recordId,
        if (sectionId != null) 'section_id': sectionId,
        'title': title,
        'reference': reference,
        if (savedAt != null) 'saved_at': savedAt!.millisecondsSinceEpoch,
      };

  /// The pre-1.5 storage format: `book:recordId:sectionId`.
  factory LastReadEntry.fromLegacy(String value) {
    final parts = value.split(':');
    if (parts.length < 2) {
      throw const FormatException('legacy last_read value needs at least two fields');
    }
    return LastReadEntry(
      bookKey: parts.first,
      recordId: int.tryParse(parts[1]) ?? 0,
      sectionId: parts.length > 2 ? int.tryParse(parts[2]) : null,
    );
  }

  bool get isValid => recordId != 0 && BookDefinition.byKey(bookKey) != null;

  LastReadEntry copyWith({String? title, String? reference, DateTime? savedAt}) => LastReadEntry(
        bookKey: bookKey,
        recordId: recordId,
        sectionId: sectionId,
        title: title ?? this.title,
        reference: reference ?? this.reference,
        savedAt: savedAt ?? this.savedAt,
      );

  ReaderTarget get target =>
      ReaderTarget(book: bookKey, recordId: recordId, sectionId: sectionId);
}

class Passage {
  const Passage({
    required this.recordId,
    required this.arabic,
    required this.urdu,
    this.sectionId,
    this.page,
    this.sectionTitle = '',
    this.chapterTitle = '',
    this.locator = '',
    this.containerType,
    this.containerId,
    this.commentary = '',
    this.footnote = '',
    this.format,
    this.sourceUrl = '',
    this.sourceRef = '',
  });

  final int recordId;
  final int? sectionId;
  final int? page;
  final String arabic;
  final String urdu;
  final String sectionTitle;
  final String chapterTitle;

  /// Short human locator such as "آیت ۱ • پارہ ۱".
  final String locator;

  /// Owning container inside the database (surah, section type, supplication).
  final int? containerType;
  final int? containerId;

  /// Optional explanatory text (Quran tafseer note, footnote body).
  final String commentary;
  final String footnote;

  /// Official page this answer was taken from (the fatawa collections). The app
  /// shows it as a button so a reader can open the source and verify a ruling.
  final String sourceUrl;

  /// The publisher's own reference number for that page (`س 1894`).
  final String sourceRef;

  /// Presentation role kept from the source database (Nahj al-Balagha
  /// `ParaFormat`: 1 title, 2 text, 3 sub-heading, 4 separator; Mafatih line
  /// type: 1 dua text, 2 Urdu instruction). Null for the hadith books/Quran.
  final int? format;

  factory Passage.fromMap(Map<String, Object?> row) => Passage(
        recordId: _asInt(row['record_id'] ?? row['ID']) ?? 0,
        sectionId: _asInt(row['section_id'] ?? row['Secid']),
        page: _asInt(row['page_no'] ?? row['paganum']),
        arabic: _compact((row['arabic'] ?? row['txt'] ?? '').toString()),
        urdu: _compact((row['urdu'] ?? row['mean'] ?? '').toString()),
        sectionTitle: _compact((row['section_title'] ?? '').toString()),
        chapterTitle: _compact((row['chapter_title'] ?? '').toString()),
        locator: _compact((row['locator'] ?? '').toString()),
        containerType: _asInt(row['container_type']),
        containerId: _asInt(row['container_id']),
        commentary: _compact((row['commentary'] ?? '').toString()),
        footnote: _compact((row['footnote'] ?? '').toString()),
        format: _asInt(row['format'] ?? row['ParaFormat']),
        sourceUrl: _compact((row['source_url'] ?? '').toString()),
        sourceRef: _compact((row['source_ref'] ?? '').toString()),
      );

  bool get isEmpty => arabic.trim().isEmpty && urdu.trim().isEmpty;

  /// True when this record can be verified against its published source.
  bool get hasSource => sourceUrl.startsWith('http://') || sourceUrl.startsWith('https://');

  String get copyableText {
    final parts = <String>[
      if (arabic.trim().isNotEmpty) arabic.trim(),
      if (urdu.trim().isNotEmpty) urdu.trim(),
    ];
    return parts.join('\n\n');
  }

  Passage copyWith({String? footnote, String? commentary, String? locator}) => Passage(
        recordId: recordId,
        sectionId: sectionId,
        page: page,
        arabic: arabic,
        urdu: urdu,
        sectionTitle: sectionTitle,
        chapterTitle: chapterTitle,
        locator: locator ?? this.locator,
        containerType: containerType,
        containerId: containerId,
        commentary: commentary ?? this.commentary,
        footnote: footnote ?? this.footnote,
        format: format,
        sourceUrl: sourceUrl,
        sourceRef: sourceRef,
      );
}

/// The "where you were" line shown on the resume cards: the locator (آیت ۱۲،
/// مسئلہ ۱۸۹۴) first, then the chapter, then the book.
String readingReference(BookDefinition book, Passage passage) {
  final parts = <String>[
    if (passage.locator.trim().isNotEmpty) passage.locator.trim(),
    if (passage.sectionTitle.trim().isNotEmpty &&
        passage.sectionTitle.trim() != passage.locator.trim())
      passage.sectionTitle.trim(),
  ];
  if (parts.isNotEmpty) return parts.join(' • ');
  if (passage.chapterTitle.trim().isNotEmpty) return passage.chapterTitle.trim();
  return book.titleUrdu;
}

class SearchHit {
  const SearchHit({required this.book, required this.passage, this.citation = ''});

  final BookDefinition book;
  final Passage passage;
  final String citation;
}

/// One line for the home screen's **آیت / حدیثِ وقت** card: a short Quran verse
/// with its Urdu translation, or a short narration from Mizan al-Hikmah.
///
/// [book] is null for the built-in fallbacks, which are shown before any book
/// has been downloaded — the card is never empty, and a line from an installed
/// book always wins.
class MomentPassage {
  const MomentPassage({
    required this.kind,
    required this.arabic,
    required this.urdu,
    required this.source,
    this.book,
    this.recordId = 0,
    this.sectionId,
  });

  /// `آیت` or `حدیث` — the little tag on the card.
  final String kind;

  /// The verse or narration itself.
  final String arabic;

  /// Its Urdu translation.
  final String urdu;

  /// Where it comes from, e.g. `سورہ البقرہ، آیت ۲۵۵` or `میزان الحکمہ`.
  final String source;

  final BookDefinition? book;
  final int recordId;
  final int? sectionId;

  /// True when tapping the card can open the passage in its own reader.
  bool get isOpenable => book != null && recordId != 0;
}

/// The three lines the moment card falls back to while nothing is downloaded.
const List<MomentPassage> kFallbackMoments = <MomentPassage>[
  MomentPassage(
    kind: 'آیت',
    arabic: 'أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ',
    urdu: 'یاد رکھو! اللہ کے ذکر ہی سے دلوں کو سکون ملتا ہے۔',
    source: 'سورہ الرعد، آیت ۲۸',
  ),
  MomentPassage(
    kind: 'حدیث',
    arabic: 'قَالَ عَلِيٌّ عَلَيْهِ السَّلَامُ: الْعِلْمُ وِرَاثَةٌ كَرِيمَةٌ',
    urdu: 'علم ایک باعزت وراثت ہے۔',
    source: 'میزان الحکمہ',
  ),
  MomentPassage(
    kind: 'آیت',
    arabic: 'وَمَن يَتَوَكَّلْ عَلَى اللَّهِ فَهُوَ حَسْبُهُ',
    urdu: 'اور جو اللہ پر بھروسہ کرے تو وہ اس کے لیے کافی ہے۔',
    source: 'سورہ الطلاق، آیت ۳',
  ),
  MomentPassage(
    kind: 'حدیث',
    arabic: 'قَالَ رَسُولُ اللَّهِ ﷺ: أَفْضَلُ الْعِبَادَةِ أَخْفَاهَا',
    urdu: 'بہترین عبادت وہ ہے جو چھپ کر کی جائے۔',
    source: 'میزان الحکمہ',
  ),
];

/// One surah row from `ChapterProperty`.
class QuranSurah {
  const QuranSurah({
    required this.number,
    required this.nameArabic,
    required this.nameUrdu,
    required this.revelationPlace,
    required this.verseCount,
    required this.revelationOrder,
  });

  final int number;
  final String nameArabic;
  final String nameUrdu;
  final String revelationPlace;
  final int verseCount;
  final int revelationOrder;

  factory QuranSurah.fromMap(Map<String, Object?> row, {required int index}) => QuranSurah(
        number: _asInt(row['Id']) ?? index + 1,
        nameArabic: _compact((row['Name'] ?? '').toString()),
        nameUrdu: index >= 0 && index < urduSurahNames.length ? urduSurahNames[index] : '',
        revelationPlace: _compact((row['Nozol'] ?? '').toString()),
        verseCount: _asInt(row['Verse']) ?? 0,
        revelationOrder: _asInt(row['revel']) ?? 0,
      );

  String get displayTitle => nameUrdu.isEmpty ? nameArabic : '$nameUrdu · $nameArabic';
}

/// Where a juz begins, for the Quran's "پارے" index.
class QuranJuzEntry {
  const QuranJuzEntry({
    required this.juz,
    required this.firstRecordId,
    required this.surah,
    required this.verse,
  });

  final int juz;
  final int firstRecordId;
  final int surah;
  final int verse;

  String get title {
    final name = surah >= 1 && surah <= urduSurahNames.length ? urduSurahNames[surah - 1] : '$surah';
    return 'پارہ $juz — سورہ $name، آیت $verse';
  }
}

/// One entry of the Mafatih catalogue (`M_items`).
class DuaItem {
  const DuaItem({
    required this.rowId,
    required this.name,
    required this.categoryId,
    required this.isHeader,
    required this.isFeatured,
    this.lineCount = 0,
  });

  final int rowId;
  final String name;
  final int categoryId;
  final bool isHeader;
  final bool isFeatured;
  final int lineCount;

  factory DuaItem.fromMap(Map<String, Object?> row) => DuaItem(
        rowId: _asInt(row['row_id'] ?? row['rowid']) ?? 0,
        name: _compact((row['M_name'] ?? '').toString()),
        categoryId: _asInt(row['M_cat_id']) ?? 0,
        isHeader: _asInt(row['M_type']) == 2,
        isFeatured: _asInt(row['M_montakhab']) == 1,
        lineCount: _asInt(row['line_count']) ?? 0,
      );
}

class DuaCategory {
  const DuaCategory({required this.id, required this.titleUrdu, required this.itemCount});

  final int id;
  final String titleUrdu;
  final int itemCount;
}

/// One section of Nahj al-Balagha (khutbas, letters, wisdoms, traditions, intro).
class BalaghaSection {
  const BalaghaSection({
    required this.type,
    required this.titleUrdu,
    required this.entryCount,
    required this.hasIntroduction,
  });

  final int type;
  final String titleUrdu;
  final int entryCount;
  final bool hasIntroduction;
}

class BalaghaEntry {
  const BalaghaEntry({
    required this.typeNo,
    required this.title,
    required this.paragraphCount,
  });

  final int typeNo;
  final String title;
  final int paragraphCount;
}

int? _asInt(Object? value) {
  if (value == null || value == '') return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
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

/// Urdu names of the 114 surahs, in mushaf order (index 0 = al-Fatiha).
const List<String> urduSurahNames = [
  'الفاتحہ', 'البقرہ', 'آلِ عمران', 'النساء', 'المائدہ', 'الانعام', 'الاعراف', 'الانفال',
  'التوبہ', 'یونس', 'ھود', 'یوسف', 'الرعد', 'ابراہیم', 'الحجر', 'النحل', 'بنی اسرائیل',
  'الکہف', 'مریم', 'طٰہٰ', 'الانبیاء', 'الحج', 'المؤمنون', 'النور', 'الفرقان', 'الشعراء',
  'النمل', 'القصص', 'العنکبوت', 'الروم', 'لقمان', 'السجدہ', 'الاحزاب', 'سبا', 'فاطر',
  'یٰسٰین', 'الصافات', 'ص', 'الزمر', 'المومن', 'حم السجدہ', 'الشوری', 'الزخرف', 'الدخان',
  'الجاثیہ', 'الاحقاف', 'محمد', 'الفتح', 'الحجرات', 'ق', 'الذاریات', 'الطور', 'النجم',
  'القمر', 'الرحمٰن', 'الواقعہ', 'الحدید', 'المجادلہ', 'الحشر', 'الممتحنہ', 'الصف',
  'الجمعہ', 'المنافقون', 'التغابن', 'الطلاق', 'التحریم', 'الملک', 'القلم', 'الحاقہ',
  'المعارج', 'نوح', 'الجن', 'المزمل', 'المدثر', 'القیامہ', 'الدھر', 'المرسلات', 'النبا',
  'النازعات', 'عبس', 'التکویر', 'الانفطار', 'المطففین', 'الانشقاق', 'البروج', 'الطارق',
  'الاعلیٰ', 'الغاشیہ', 'الفجر', 'البلد', 'الشمس', 'اللیل', 'الضحیٰ', 'الم نشرح', 'التین',
  'العلق', 'القدر', 'البینہ', 'الزلزال', 'العادیات', 'القارعہ', 'التکاثر', 'العصر',
  'الہمزہ', 'الفیل', 'قریش', 'الماعون', 'الکوثر', 'الکافرون', 'النصر', 'اللہب', 'الاخلاص',
  'الفلق', 'الناس',
];

/// Urdu titles of the six chapters of Mafatih al-Jinan (`M_cat_id`).
const Map<int, String> duaCategoryTitles = {
  1: 'قرآنی سورتیں اور ان کے خواص',
  2: 'تعقیبات اور نماز کے اعمال',
  3: 'مہینوں کے اعمال (رجب تا ربیع الثانی)',
  4: 'زیارات اور آدابِ سفر',
  5: 'مشہور دعائیں اور زیارات',
  6: 'شب و روز کے اعمال اور ملحقات',
};

/// Older database headings use the truncated plural «خطب». Correct the
/// *standalone* label to «خطبات» everywhere a title is presented, without
/// altering body text or words such as «خطبہ» / already-correct «خطبات».
String polishBalaghaTitle(String value) =>
    value.replaceAll(RegExp(r'خطب(?=\s|[،,:؛۔\-]|$)'), 'خطبات');

/// Urdu titles of the Nahj al-Balagha divisions (`Type` / `TypeID`).
const Map<int, String> balaghaSectionTitles = {
  1: 'خطبات',
  2: 'کتب و خطوط',
  3: 'حکمت و اقوالِ قصار',
  4: 'احادیثِ رسولِ خدا ﷺ',
  5: 'مقدمات و تعارف',
};
