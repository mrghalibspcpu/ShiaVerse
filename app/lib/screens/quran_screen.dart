import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../daily_study.dart';
import '../library_repository.dart';
import '../models.dart';
import '../text_utils.dart' show arabicNumerals, parseReaderNumber;
import '../widgets/reader_kit.dart';
import '../widgets/reader_chrome.dart';
import '../widgets/reader_display.dart';
import '../widgets/chapter_wallpaper.dart';
import '../widgets/mushaf_text.dart';
import '../widgets/resume_card.dart';

/// Separate from reader palette/font keys, so the normal Quran cards and all
/// other book readers keep their existing saved choices.
const String kQuranMushafKey = 'quran_mushaf_mode_v1';

/// Surah / juz / page browser for the Quran collection.
class QuranHomeScreen extends StatefulWidget {
  const QuranHomeScreen({super.key, required this.library, this.focusSurah});

  final LibraryRepository library;

  /// Scrolls the surah list to this surah. Set when the reader was opened from
  /// last seen, so back returns to that surah instead of the top of the list.
  final int? focusSurah;

  @override
  State<QuranHomeScreen> createState() => _QuranHomeScreenState();
}

class _QuranHomeScreenState extends State<QuranHomeScreen> {
  Future<void> _openMushaf() async {
    try {
      final surahs = await widget.library.getSurahs();
      if (!mounted) return;
      if (surahs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('قرآنِ کریم کا متن ابھی دستیاب نہیں۔')),
        );
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kQuranMushafKey, true);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SurahReaderScreen(
          library: widget.library,
          surah: surahs.first,
          startInMushaf: true,
        ),
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const JustifiedText('قرآنِ کریم'),
          bottom: const TabBar(
            tabs: [Tab(text: 'سورتیں'), Tab(text: 'پارے')],
          ),
          actions: [
            TextButton.icon(
              key: const ValueKey<String>('quran-go-to-ayah-surah'),
              onPressed: () => showQuranJump(context, widget.library),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
              icon: const Icon(Icons.my_location, size: 17),
              label: const Text('جائیں', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: ResumeCard(
                library: widget.library,
                book: BookDefinition.bookFor(CorpusSource.quran)!,
                margin: EdgeInsets.zero,
                onOpened: () {
                  if (mounted) setState(() {});
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
              child: OutlinedButton.icon(
                key: const ValueKey<String>('quran-open-mushaf'),
                onPressed: _openMushaf,
                icon: const Icon(Icons.auto_stories_rounded, size: 19),
                label: const Text('مصحف موڈ — صرف عربی متن'),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _SurahList(library: widget.library, focusSurah: widget.focusSurah),
                  _JuzList(library: widget.library),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurahList extends StatefulWidget {
  const _SurahList({required this.library, this.focusSurah});

  final LibraryRepository library;
  final int? focusSurah;

  @override
  State<_SurahList> createState() => _SurahListState();
}

class _SurahListState extends State<_SurahList> {
  @override
  void initState() {
    super.initState();
    // Warm the cache so the first frame already shows the saved surahs.
    unawaited(widget.library.warmSurahBookmarks().then((_) {
      if (mounted) setState(() {});
    }));
  }

  Future<void> _toggle(QuranSurah surah) async {
    await widget.library.toggleSurahBookmark(surah.number);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: JustifiedText(
          widget.library.isSurahBookmarkedNow(surah.number)
              ? 'مکمل سورة محفوظات میں محفوظ ہو گئی۔'
              : 'سورة محفوظات سے ہٹا دی گئی۔',
          style: const TextStyle(fontSize: 13),
        ),
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QuranSurah>>(
      future: widget.library.getSurahs(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return ErrorPanel(error: snapshot.error.toString());
        final surahs = snapshot.data ?? const [];
        if (surahs.isEmpty) {
          return const CollectionMessage('سورتیں دستیاب نہیں۔', icon: Icons.menu_book);
        }
        final focus = widget.focusSurah;
        final focusIndex = focus == null ? 0 : surahs.indexWhere((surah) => surah.number == focus);
        return ScrollablePositionedList.separated(
          padding: const EdgeInsets.all(14),
          initialScrollIndex: focusIndex < 0 ? 0 : focusIndex,
          itemCount: surahs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final surah = surahs[index];
            final saved = widget.library.isSurahBookmarkedNow(surah.number);
            final highlighted = focus != null && surah.number == focus;
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: highlighted ? Border.all(color: kGold, width: 1.8) : null,
              ),
              child: ChapterWallpaperCard(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(arabicNumerals(surah.number), textDirection: TextDirection.rtl),
                ),
                title: JustifiedText(
                  surah.nameUrdu.isEmpty ? surah.nameArabic : surah.nameUrdu,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  maxLines: 1,
                ),
                subtitle: JustifiedText(
                  '${surah.nameArabic} • ${surah.verseCount} آیات • ${surah.revelationPlace}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  maxLines: 1,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // The whole surah, not one verse: the button sits on the
                    // row so it never opens the reader by accident.
                    IconButton(
                      key: ValueKey<String>('surah-bookmark-${surah.number}'),
                      tooltip: saved ? 'محفوظات سے ہٹائیں' : 'مکمل سورة محفوظ کریں',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        color: saved ? kGold : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => unawaited(_toggle(surah)),
                    ),
                    const Icon(Icons.chevron_left),
                  ],
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SurahReaderScreen(library: widget.library, surah: surah),
                )),
              ),
            ),
            );
          },
        );
      },
    );
  }
}

class _JuzList extends StatelessWidget {
  const _JuzList({required this.library});

  final LibraryRepository library;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QuranJuzEntry>>(
      future: library.getJuzIndex(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return ErrorPanel(error: snapshot.error.toString());
        final entries = snapshot.data ?? const [];
        if (entries.isEmpty) {
          return const CollectionMessage('پارے دستیاب نہیں۔', icon: Icons.layers_outlined);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final entry = entries[index];
            return ChapterWallpaperCard(
              child: ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: JustifiedText(entry.title, maxLines: 1),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => JuzReaderScreen(library: library, juz: entry.juz),
                )),
              ),
            );
          },
        );
      },
    );
  }
}

/// Verse reader used for a surah, a juz, or a single mushaf page.
class SurahReaderScreen extends StatefulWidget {
  const SurahReaderScreen({
    super.key,
    required this.library,
    required this.surah,
    this.initialRecordId,
    this.searchQuery = '',
    this.startInMushaf = false,
    this.onNextSection,
    this.onPreviousSection,
    this.sectionNavLabel = '',
  });

  final LibraryRepository library;
  final QuranSurah surah;
  final int? initialRecordId;
  final String searchQuery;
  final bool startInMushaf;
  final VoidCallback? onNextSection;
  final VoidCallback? onPreviousSection;
  final String sectionNavLabel;

  @override
  State<SurahReaderScreen> createState() => _SurahReaderScreenState();
}

class _SurahReaderScreenState extends State<SurahReaderScreen> {
  Future<void> _openSurah(BuildContext context, int delta) async {
    final navigator = Navigator.of(context);
    final surahs = await widget.library.getSurahs();
    final next = surahs.where((s) => s.number == widget.surah.number + delta).toList();
    if (next.isEmpty || !context.mounted) return;
    navigator.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => SurahReaderScreen(library: widget.library, surah: next.first),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _QuranVerseList(
      onNextSection: () => unawaited(_openSurah(context, 1)),
      onPreviousSection: () => unawaited(_openSurah(context, -1)),
      sectionNavLabel: 'سورة ${widget.surah.number} از 114 — اگلی / پچھلی سورة',
      library: widget.library,
      title: widget.surah.displayTitle,
      subtitle: widget.surah.verseCount > 0
          ? '${widget.surah.verseCount} آیات • ${widget.surah.revelationPlace}' : 'قرآنِ کریم',
      loader: () => widget.library.getSurahVerses(widget.surah.number),
      bismillah: widget.surah.number > 1 && widget.surah.number != 9,
      initialRecordId: widget.initialRecordId,
      searchQuery: widget.searchQuery,
      storageKey: 'quran-surah-${widget.surah.number}',
      startInMushaf: widget.startInMushaf,
      surahNumber: widget.surah.number,
    );
  }
}

class JuzReaderScreen extends StatelessWidget {
  const JuzReaderScreen({super.key, required this.library, required this.juz});

  final LibraryRepository library;
  final int juz;

  @override
  Widget build(BuildContext context) {
    return _QuranVerseList(
      library: library,
      title: 'پارہ $juz',
      subtitle: 'مکمل پارہ',
      loader: () => library.getJuzVerses(juz),
      storageKey: 'quran-juz-$juz',
      onNextSection: juz < 30
          ? () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                builder: (_) => JuzReaderScreen(library: library, juz: juz + 1)))
          : null,
      onPreviousSection: juz > 1
          ? () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                builder: (_) => JuzReaderScreen(library: library, juz: juz - 1)))
          : null,
      sectionNavLabel: 'پارہ $juz از 30 — اگلا / پچھلا پارہ',
    );
  }
}

/// The mushaf page reader — also the reader the daily study opens.
///
/// It can carry a whole run of pages: the daily study opens today's portion
/// of the mushaf, so the reader shows every page of the day and not only the
/// first one. At the end of the run the reader offers the next and the
/// previous run of pages, and the next and the previous surah.
class QuranPageReaderScreen extends StatelessWidget {
  const QuranPageReaderScreen({
    super.key,
    required this.library,
    required this.page,
    this.lastPage,
  });

  final LibraryRepository library;
  final int page;

  /// The last page of the run, when the reader was opened for a portion.
  final int? lastPage;

  @override
  Widget build(BuildContext context) {
    final end = lastPage ?? page;
    final range = end > page;
    return _QuranVerseList(
      library: library,
      title: range ? 'صفحات $page تا $end' : 'صفحہ $page',
      subtitle: range ? 'مصحف کے صفحات — آج کا حصہ' : 'مصحف کا صفحہ',
      loader: () => library.getQuranPages(page, end),
      storageKey: 'quran-page-$page-$end',
      firstPage: page,
      lastPage: end,
      surahSections: true,
    );
  }
}

class _QuranVerseList extends StatefulWidget {
  const _QuranVerseList({
    required this.library,
    required this.title,
    required this.subtitle,
    required this.loader,
    required this.storageKey,
    this.bismillah = false,
    this.initialRecordId,
    this.searchQuery = '',
    this.startInMushaf = false,
    this.onNextSection,
    this.onPreviousSection,
    this.sectionNavLabel = '',
    this.surahNumber,
    this.firstPage,
    this.lastPage,
    this.surahSections = false,
  });

  final LibraryRepository library;
  final String title;
  final String subtitle;
  final Future<List<Passage>> Function() loader;
  final String storageKey;

  /// Set only by the surah reader: a bookmark button for the whole surah then
  /// sits in the app bar (juz and page readers have no single surah to save).
  final int? surahNumber;
  final bool bismillah;
  final int? initialRecordId;
  final String searchQuery;
  final bool startInMushaf;
  final VoidCallback? onNextSection;
  final VoidCallback? onPreviousSection;
  final String sectionNavLabel;

  /// The run of mushaf pages the reader shows, when it was opened for a
  /// portion: the page reader walks from one run to the next.
  final int? firstPage;
  final int? lastPage;

  /// The page reader offers the surah before and the surah after the pages it
  /// shows; the surah reader has its own cross-text navigation.
  final bool surahSections;

  @override
  State<_QuranVerseList> createState() => _QuranVerseListState();
}

class _QuranVerseListState extends State<_QuranVerseList> with ReaderDisplayMode<_QuranVerseList> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  int _initialIndex = 0;
  int? _lastSavedRecord;

  final BookDefinition _book = BookDefinition.bookFor(CorpusSource.quran)!;

  List<Passage> _verses = const [];
  List<MushafGroup> _mushafGroups = const [];
  ReaderPreferences _preferences = const ReaderPreferences();
  bool _mushafMode = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    disposeReaderDisplay();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final preferences = await ReaderPreferences.load();
      final stored = await SharedPreferences.getInstance();
      final mushaf = widget.searchQuery.isEmpty &&
          (widget.startInMushaf || (stored.getBool(kQuranMushafKey) ?? false));
      final verses = await widget.loader();
      if (!mounted) return;
      final groups = groupMushafVerses(verses, focusRecordId: widget.initialRecordId);
      setState(() {
        _preferences = preferences;
        _verses = verses;
        _mushafGroups = groups;
        _mushafMode = mushaf;
        final index = verses.indexWhere((v) => v.recordId == widget.initialRecordId);
        final groupIndex = groups.indexWhere((g) => g.firstRecordId == widget.initialRecordId);
        _initialIndex = mushaf
            ? (groupIndex < 0 ? 0 : groupIndex)
            : (index < 0 ? 0 : index) + (widget.bismillah ? 1 : 0);
        _loading = false;
      });
      final target = widget.initialRecordId;
      if (verses.isNotEmpty) {
        final opened = target != null && verses.any((verse) => verse.recordId == target)
            ? target
            : verses.first.recordId;
        unawaited(_saveLast(verses, opened));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  /// O(visible items), not a scan/layout of hundreds of offscreen verses.
  /// In mushaf mode the first visible *page group* is the saved anchor.
  int? _visibleRecordId() {
    final visible = _positions.itemPositions.value
        .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
        .toList()..sort((a, b) => a.index.compareTo(b.index));
    for (final item in visible) {
      if (_mushafMode) {
        if (item.index < _mushafGroups.length) return _mushafGroups[item.index].firstRecordId;
      } else {
        final index = item.index - (widget.bismillah ? 1 : 0);
        if (index >= 0 && index < _verses.length) return _verses[index].recordId;
      }
    }
    return null;
  }

  void _saveLastRead() {
    final record = _visibleRecordId();
    if (record == null || record == _lastSavedRecord) return;
    _lastSavedRecord = record;
    unawaited(_saveLast(_verses, record));
  }

  Future<void> _saveMushafMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kQuranMushafKey, value);
  }

  void _toggleMushaf() {
    if (_verses.isEmpty) return;
    final focus = _visibleRecordId() ?? widget.initialRecordId ?? _verses.first.recordId;
    final next = !_mushafMode;
    setState(() {
      _mushafMode = next;
      if (next) {
        _mushafGroups = groupMushafVerses(_verses, focusRecordId: focus);
        _initialIndex = _mushafGroups.indexWhere((g) => g.firstRecordId == focus);
      } else {
        _initialIndex = _verses.indexWhere((v) => v.recordId == focus) + (widget.bismillah ? 1 : 0);
      }
      if (_initialIndex < 0) _initialIndex = 0;
    });
    _lastSavedRecord = focus;
    unawaited(_saveLast(_verses, focus));
    unawaited(_saveMushafMode(next));
  }

  /// Stores the surah and the verse number so the resume card can name them.
  Future<void> _saveLast(List<Passage> verses, int recordId) async {
    final index = verses.indexWhere((verse) => verse.recordId == recordId);
    if (index < 0) return;
    final verse = verses[index];
    await widget.library.saveLastRead(
      bookKey: _book.key,
      recordId: recordId,
      sectionId: verse.sectionId,
      title: verse.chapterTitle.isEmpty ? widget.title : verse.chapterTitle,
      reference: readingReference(_book, verse),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _preferences.palette;
    return ReaderScaffold(
      book: _book,
      title: widget.title,
      subtitle: widget.subtitle,
      preferences: _preferences,
      onPreferencesChanged: (value) => setState(() => _preferences = value),
      showAppearanceLabel: true,
      fullScreen: readerFullScreen,
      overlay: readerDisplayOverlay(context),
      actions: <Widget>[
        if (widget.surahNumber != null)
          // The whole surah, not one verse. `setState` after the toggle keeps
          // the icon honest; the repository answers from memory.
          Builder(builder: (context) {
            final saved = widget.library.isSurahBookmarkedNow(widget.surahNumber!);
            return IconButton(
              key: const ValueKey<String>('surah-reader-bookmark'),
              // The app bar is already tight on a 320 px phone (display
              // actions, «جائیں», reader controls); a full 48 px target pushed
              // the row 2 px past its width in the mushaf test.
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              tooltip: saved ? 'محفوظات سے ہٹائیں' : 'مکمل سورة محفوظ کریں',
              icon: Icon(
                saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                color: saved ? kGold : palette.accent,
              ),
              onPressed: () async {
                await widget.library.toggleSurahBookmark(widget.surahNumber!);
                if (!mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(
                    content: JustifiedText(
                      widget.library.isSurahBookmarkedNow(widget.surahNumber!)
                          ? 'مکمل سورة محفوظات میں محفوظ ہو گئی۔'
                          : 'سورة محفوظات سے ہٹا دی گئی۔',
                      style: const TextStyle(fontSize: 13),
                    ),
                    duration: const Duration(seconds: 2),
                  ));
              },
            );
          }),
        readerDisplayActions(context, color: palette.accent),
        TextButton.icon(
          onPressed: () => showQuranJump(context, widget.library),
          style: TextButton.styleFrom(
            foregroundColor: palette.accent,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            minimumSize: const Size(0, 40),
          ),
          icon: const Icon(Icons.my_location, size: 18),
          label: const Text('جائیں', style: TextStyle(fontSize: 13)),
        ),
      ],
      headerAction: OutlinedButton.icon(
        key: const ValueKey<String>('quran-mushaf-toggle'),
        onPressed: _loading || _verses.isEmpty ? null : _toggleMushaf,
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accent,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          side: BorderSide(color: palette.border),
        ),
        icon: Icon(_mushafMode ? Icons.check_circle_rounded : Icons.auto_stories_rounded, size: 18),
        label: Text(
          _mushafMode ? 'مصحف موڈ • آیت پر ٹیپ کریں' : 'مصحف موڈ',
          style: const TextStyle(fontSize: 13),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorPanel(error: _error!)
              : _verses.isEmpty
                  ? const CollectionMessage('اس حصے میں متن موجود نہیں۔')
                  : NotificationListener<ScrollEndNotification>(
                      onNotification: (_) {
                        _saveLastRead();
                        return false;
                      },
                      child: SelectionArea(
                        child: _mushafMode
                            ? ScrollablePositionedList.builder(
                                key: PageStorageKey<String>('${widget.storageKey}-mushaf'),
                                itemScrollController: _itemScrollController,
                                scrollOffsetController: scrollOffsetController,
                                itemPositionsListener: _positions,
                                initialScrollIndex: _initialIndex,
                                initialAlignment: 0.04,
                                addAutomaticKeepAlives: false,
                                minCacheExtent: 400,
                                padding: const EdgeInsets.fromLTRB(14, 8, 14, 112),
                                itemCount: _mushafGroups.length + 1,
                                itemBuilder: (context, index) {
                                  if (index >= _mushafGroups.length) {
                                    return _verseFooter();
                                  }
                                  return MushafText(
                                    group: _mushafGroups[index],
                                    palette: palette,
                                    fontScale: _preferences.fontScale,
                                    onVerseTap: _showVerseSheet,
                                  );
                                },
                              )
                            : ScrollablePositionedList.builder(
                          key: PageStorageKey(widget.storageKey),
                          itemScrollController: _itemScrollController,
                          scrollOffsetController: scrollOffsetController,
                          itemPositionsListener: _positions,
                          initialScrollIndex: _initialIndex,
                          initialAlignment: 0.04,
                          addAutomaticKeepAlives: false,
                          minCacheExtent: 400,
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 112),
                          itemCount: _verses.length + (widget.bismillah ? 1 : 0) + 1,
                          itemBuilder: (context, index) {
                            if (widget.bismillah && index == 0) return _Bismillah(scale: _preferences.fontScale, color: palette.accent);
                            if (index - (widget.bismillah ? 1 : 0) >= _verses.length) {
                                    return _verseFooter();
                            }
                            final verse = _verses[index - (widget.bismillah ? 1 : 0)];
                            return PassageCard(
                              key: ValueKey('quran-${verse.recordId}'),
                              library: widget.library, book: _book, passage: verse,
                              palette: palette, fontScale: _preferences.fontScale,
                              script: widget.searchQuery.isEmpty ? _preferences.script : 'both',
                              searchQuery: widget.searchQuery,
                              focusMatch: verse.recordId == widget.initialRecordId,
                              indexLabel: 'آیت ${arabicNumerals(_verseNumber(verse))}',
                            );
                          },
                        ),
                      ),
                    ),
    );
  }

  /// The mushaf is Arabic only by design; a tap on an ayah opens its Urdu
  /// translation and, when the database has one, its tafseer note with its own
  /// show/hide control.
  void _showVerseSheet(Passage verse) {
    final palette = _preferences.palette;
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _QuranVerseSheet(
        verse: verse,
        palette: palette,
        fontScale: _preferences.fontScale,
        surahTitle: widget.title,
      ),
    ));
  }

  void _goToVerse(int index) {
    if (_verses.isEmpty || !_itemScrollController.isAttached) return;
    final target = index.clamp(0, _verses.length - 1);
    var scrollIndex = target + (widget.bismillah ? 1 : 0);
    if (_mushafMode) {
      final record = _verses[target].recordId;
      final group = _mushafGroups.indexWhere((g) => g.verses.any((v) => v.recordId == record));
      scrollIndex = group < 0 ? target : group;
    }
    _itemScrollController.scrollTo(
      index: scrollIndex,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.04,
    );
  }

  int get _visibleVerseIndex {
    final record = _visibleRecordId();
    if (record == null) return 0;
    final index = _verses.indexWhere((v) => v.recordId == record);
    return index < 0 ? 0 : index;
  }

  Widget _verseFooter() {
    final surahs = _surahsOnPages;
    final previousSurah = surahs == null ? null : surahs.$1 - 1;
    final nextSurah = surahs == null ? null : surahs.$2 + 1;
    final firstPage = widget.firstPage;
    final lastPage = widget.lastPage;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReaderPrevNextBar(
          hasPrevious: _visibleVerseIndex > 0,
          hasNext: _visibleVerseIndex < _verses.length - 1,
          onPrevious: () => _goToVerse(_visibleVerseIndex - 1),
          onNext: () => _goToVerse(_visibleVerseIndex + 1),
          previousLabel: 'پچھلی آیت',
          nextLabel: 'اگلی آیت',
          label: 'آیت ${_visibleVerseIndex + 1} از ${_verses.length} — اسی سورة کے اندر',
        ),
        if (widget.onNextSection != null || widget.onPreviousSection != null) ...[
          const SizedBox(height: 10),
          ReaderPrevNextBar(
            key: const ValueKey<String>('quran-section-prev-next'),
            hasPrevious: widget.onPreviousSection != null,
            hasNext: widget.onNextSection != null,
            onPrevious: widget.onPreviousSection,
            onNext: widget.onNextSection,
            previousLabel: 'پچھلا متن',
            nextLabel: 'اگلا متن',
            label: widget.sectionNavLabel,
          ),
        ],
        // The page reader ends with the surah before and the surah after the
        // pages it shows, so a reader who opens the Quran from the daily
        // study can walk on to the next surah without looking anything up.
        if (widget.surahSections && surahs != null) ...[
          const SizedBox(height: 10),
          ReaderPrevNextBar(
            key: const ValueKey<String>('quran-surah-prev-next'),
            hasPrevious: previousSurah != null && previousSurah >= 1,
            hasNext: nextSurah != null && nextSurah <= 114,
            onPrevious: previousSurah != null && previousSurah >= 1
                ? () => unawaited(_openSurah(previousSurah))
                : null,
            onNext: nextSurah != null && nextSurah <= 114
                ? () => unawaited(_openSurah(nextSurah))
                : null,
            previousLabel: 'پچھلا سورہ',
            nextLabel: 'اگلا سورہ',
            label: 'سورہ ${surahs.$1} — اگلا / پچھلا سورہ',
          ),
        ],
        // And with the run of pages before and after this one.
        if (firstPage != null && lastPage != null) ...[
          const SizedBox(height: 10),
          ReaderPrevNextBar(
            key: const ValueKey<String>('quran-page-prev-next'),
            hasPrevious: firstPage > 1,
            hasNext: lastPage < kQuranPages,
            onPrevious: () => _openPageRun(false),
            onNext: () => _openPageRun(true),
            previousLabel: 'پچھلا صفحہ',
            nextLabel: 'اگلا صفحہ',
            label: 'صفحات ${arabicNumerals(firstPage)} تا ${arabicNumerals(lastPage)} — اگلا / پچھلا صفحہ',
          ),
        ],
      ],
    );
  }

  /// The first and the last surah on the pages the reader shows.
  (int, int)? get _surahsOnPages {
    if (_verses.isEmpty) return null;
    final first = _verses.first.containerId;
    final last = _verses.last.containerId;
    if (first == null || last == null) return null;
    return (first, last);
  }

  /// Opens the surah before or after the pages on the screen.
  Future<void> _openSurah(int number) async {
    final surahs = await widget.library.getSurahs();
    final next = surahs.where((s) => s.number == number).toList();
    if (next.isEmpty || !mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => SurahReaderScreen(library: widget.library, surah: next.first),
    ));
  }

  /// Opens the run of pages before or after the one on the screen: the daily
  /// study's portion is a run of pages, and the reader walks from one run to
  /// the next.
  void _openPageRun(bool forward) {
    final first = widget.firstPage;
    final last = widget.lastPage;
    if (first == null || last == null) return;
    final length = last - first + 1;
    final start = forward ? last + 1 : math.max(1, first - length);
    final end = forward ? math.min(kQuranPages, last + length) : first - 1;
    if (end < start) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => QuranPageReaderScreen(
        library: widget.library,
        page: start,
        lastPage: end,
      ),
    ));
  }

  int _verseNumber(Passage verse) {
    final match = RegExp(r'آیت (\d+)').firstMatch(verse.locator);
    return match == null ? verse.recordId : int.tryParse(match.group(1) ?? '') ?? verse.recordId;
  }
}

class _Bismillah extends StatelessWidget {
  const _Bismillah({required this.scale, required this.color});

  final double scale;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontFamily: kArabicFont,
          fontSize: 26 * scale,
          height: 1.8,
          color: color,
        ),
      ),
    );
  }
}

/// Available from the Quran index and every surah/juz/page reader.
Future<void> showQuranJump(BuildContext context, LibraryRepository library) async {
  try {
    final surahs = await library.getSurahs();
    if (!context.mounted || surahs.isEmpty) return;
    final controller = TextEditingController(text: '1');
    var selected = surahs.first;
    String? error;
    final target = await showDialog<({QuranSurah surah, int verse})>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(
        title: const JustifiedText('سورہ / آیت پر جائیں'),
        content: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButton<int>(value: selected.number, isExpanded: true,
            items: [for (final surah in surahs) DropdownMenuItem(value: surah.number,
              child: Text('${surah.number}. ${surah.displayTitle}', overflow: TextOverflow.ellipsis))],
            onChanged: (value) => setState(() {
              selected = surahs.firstWhere((s) => s.number == value);
              error = null;
            })),
          TextField(controller: controller, keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'آیت نمبر (۱ تا ${selected.verseCount})', errorText: error),
            textDirection: TextDirection.rtl),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('منسوخ')),
          FilledButton(onPressed: () {
            final verse = parseReaderNumber(controller.text);
            if (verse == null || verse < 1 || verse > selected.verseCount) {
              setState(() => error = 'درست آیت نمبر لکھیں');
              return;
            }
            Navigator.pop(context, (surah: selected, verse: verse));
          }, child: const Text('جائیں')),
        ],
      )),
    );
    // Let the dialog's TextField leave the tree before releasing its controller.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose));
    if (target == null) return;
    final verse = await library.getQuranVerse(target.surah.number, target.verse);
    if (!context.mounted) return;
    if (verse == null) throw StateError('آیت دستیاب نہیں');
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SurahReaderScreen(
      library: library, surah: target.surah, initialRecordId: verse.recordId)));
  } catch (error) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
  }
}


/// One ayah, opened from the mushaf: the Arabic stays the hero, the Urdu
/// translation is always visible, and tafseer is folded behind its own button.
class _QuranVerseSheet extends StatefulWidget {
  const _QuranVerseSheet({
    required this.verse,
    required this.palette,
    required this.fontScale,
    required this.surahTitle,
  });

  final Passage verse;
  final ReaderPalette palette;
  final double fontScale;
  final String surahTitle;

  @override
  State<_QuranVerseSheet> createState() => _QuranVerseSheetState();
}

class _QuranVerseSheetState extends State<_QuranVerseSheet> {
  bool _showTafseer = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final verse = widget.verse;
    final hasTafseer = verse.commentary.trim().isNotEmpty;
    final header = verse.locator.trim().isEmpty ? widget.surahTitle : verse.locator;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
          children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.surahTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.accent),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      header,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: palette.accent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                verse.arabic,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.justify,
                style: TextStyle(
                  fontFamily: kArabicFont,
                  fontSize: 27 * widget.fontScale,
                  height: 1.9,
                  color: palette.foreground,
                ),
              ),
              const SizedBox(height: 12),
              Divider(color: palette.border),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Icon(Icons.translate_rounded, size: 17, color: palette.accent),
                  const SizedBox(width: 6),
                  Text(
                    'ترجمہ',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.accent),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                verse.urdu.trim().isEmpty ? 'اس آیت کا ترجمہ دستیاب نہیں۔' : verse.urdu,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: kUrduFont,
                  fontSize: 18 * widget.fontScale,
                  height: 1.75,
                  color: palette.foreground,
                ),
              ),
              if (hasTafseer) ...<Widget>[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  key: const ValueKey<String>('quran-tafseer-toggle'),
                  onPressed: () => setState(() => _showTafseer = !_showTafseer),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.accent,
                    side: BorderSide(color: palette.border),
                    alignment: AlignmentDirectional.centerStart,
                  ),
                  icon: Icon(_showTafseer ? Icons.expand_less : Icons.expand_more, size: 19),
                  label: Text(
                    _showTafseer ? 'تفسیر چھپائیں' : 'تفسیر دکھائیں',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_showTafseer)
                  Container(
                    key: const ValueKey<String>('quran-tafseer-body'),
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: palette.border),
                    ),
                    child: Text(
                      verse.commentary,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: kUrduFont,
                        fontSize: 16.5 * widget.fontScale,
                        height: 1.8,
                        color: palette.foreground,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                          text: '${verse.arabic}\n\n${verse.urdu}\n\n${widget.surahTitle} • $header',
                        ));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('آیت کاپی ہو گئی۔')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('کاپی کریں'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('بند کریں'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
    );
  }
}
