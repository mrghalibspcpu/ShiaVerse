import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../daily_study.dart';
import '../library_repository.dart';
import '../models.dart';
import '../text_utils.dart' show arabicNumerals;
import 'balagha_screen.dart';
import 'duas_screen.dart';
import 'library_screen.dart';
import 'quran_screen.dart';

/// What one portion of a library book counts, in the reader's words: the
/// ابواب of an hadith book, the دعائیں of Mafatih and the Sahifa, the
/// زمرے of a fatawa collection, the مضامین of the encyclopaedia.
String studyBookUnitLabel(BookDefinition book) => switch (book.source) {
      CorpusSource.hadith => 'باب',
      CorpusSource.sahifa => 'دعا',
      CorpusSource.dua => 'دعا',
      CorpusSource.fatwa => 'زمرہ',
      CorpusSource.encyclopedia => 'مضمون',
      _ => 'نمبر',
    };

/// **روزانہ مطالعہ** — the Xplore feature that turns the library into a habit.
///
/// A reader picks one book (the Quran, one section of Nahj al-Balagha, or
/// any installed library book) — or several books at once — and a length in
/// days; the screen works out
/// today's portion of every one of them from the plan's start day, opens the
/// reader at exactly that page/entry, and keeps the streak. Nothing is
/// downloaded and nothing leaves the phone — the portion is pure arithmetic
/// over the book's own length, so it keeps working offline forever.
class DailyStudyScreen extends StatefulWidget {
  const DailyStudyScreen({super.key, required this.library});

  final LibraryRepository library;

  @override
  State<DailyStudyScreen> createState() => _DailyStudyScreenState();
}

class _DailyStudyScreenState extends State<DailyStudyScreen> {
  final StudyPlanStore _store = StudyPlanStore();

  StudyPlan? _plan;
  bool _loading = true;

  /// Entries of the chosen Nahj al-Balagha sections, used for the length and
  /// for naming the entry a day opens on — one list per book of the plan.
  final Map<StudyTrack, List<BalaghaEntry>> _entries = <StudyTrack, List<BalaghaEntry>>{};
  final Map<StudyTrack, int> _units = <StudyTrack, int>{};

  /// The same two facts for the library books of the plan (by book key):
  /// their ordered sections (or, for Mafatih, their ordered supplications)
  /// and how many of them there are.
  final Map<String, List<({int id, String title})>> _bookSections =
      <String, List<({int id, String title})>>{};
  final Map<String, List<DuaItem>> _duaItems = <String, List<DuaItem>>{};
  final Map<String, int> _bookUnits = <String, int>{};
  String? _dataMissing;

  /// Books the picker can add beyond the classic tracks: everything
  /// installed that the Quran and Nahj al-Balagha tracks do not already
  /// cover — the hadith collections, Mafatih, the Sahifa, the fatawa and
  /// the encyclopaedia, each added on its own.
  List<BookDefinition> get _genericBooks => widget.library.installedBooks
      .where((book) =>
          book.source != CorpusSource.quran && book.source != CorpusSource.balagha)
      .toList();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final plan = await _store.load();
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _loading = false;
    });
    if (plan != null) await _measureAll(plan);
  }

  /// How many units every chosen book has, asked of the library itself so the
  /// plan never promises a length the installed data cannot fill.
  Future<void> _measureAll(StudyPlan plan) async {
    final units = <StudyTrack, int>{};
    final entries = <StudyTrack, List<BalaghaEntry>>{};
    final bookUnits = <String, int>{};
    final bookSections = <String, List<({int id, String title})>>{};
    final duaItems = <String, List<DuaItem>>{};
    String? missing;
    final tracks = plan.tracks;
    final quranInstalled =
        widget.library.installedBooks.any((book) => book.source == CorpusSource.quran);
    final balaghaInstalled =
        widget.library.installedBooks.any((book) => book.source == CorpusSource.balagha);
    for (final track in tracks) {
      if (track.isQuran) {
        if (!quranInstalled) {
          missing ??= 'قرآنِ کریم کا متن ابھی انسٹال نہیں — ڈیٹا سیکشن سے ڈاؤن لوڈ کریں۔';
          continue;
        }
        units[track] = kQuranPages;
        entries[track] = const <BalaghaEntry>[];
        continue;
      }
      final type = track.balaghaType;
      if (type == null || !balaghaInstalled) {
        missing ??= 'نہج البلاغہ ابھی انسٹال نہیں — ڈیٹا سیکشن سے ڈاؤن لوڈ کریں۔';
        continue;
      }
      List<BalaghaEntry> list = const <BalaghaEntry>[];
      try {
        list = await widget.library.getBalaghaEntries(type);
      } catch (_) {
        list = const <BalaghaEntry>[];
      }
      entries[track] = list;
      units[track] = list.length;
      if (list.isEmpty) missing ??= 'اس حصے کا متن ابھی دستیاب نہیں۔';
    }
    // The library books of the plan: counted by their sections (Mafatih by
    // its supplications, category after category, headers left out).
    for (final key in plan.bookKeys) {
      final book = BookDefinition.byKey(key);
      if (book == null) continue; // a book this app no longer carries
      if (!widget.library.isInstalled(book)) {
        missing ??= '«${book.titleUrdu}» ابھی انسٹال نہیں — ڈیٹا سیکشن سے ڈاؤن لوڈ کریں۔';
        continue;
      }
      try {
        if (book.source == CorpusSource.dua) {
          final items = <DuaItem>[];
          for (final category in await widget.library.getDuaCategories()) {
            for (final item in await widget.library.getDuaItems(category.id)) {
              if (!item.isHeader) items.add(item);
            }
          }
          duaItems[key] = items;
          bookUnits[key] = items.length;
        } else {
          final sections = await widget.library.getBookSectionsInOrder(book);
          bookSections[key] = sections;
          bookUnits[key] = sections.length;
        }
      } catch (_) {
        bookUnits[key] = 0;
      }
      if ((bookUnits[key] ?? 0) <= 0) missing ??= 'اس کتاب کا متن ابھی دستیاب نہیں۔';
    }
    if (!mounted) return;
    setState(() {
      _entries
        ..clear()
        ..addAll(entries);
      _units
        ..clear()
        ..addAll(units);
      _bookSections
        ..clear()
        ..addAll(bookSections);
      _duaItems
        ..clear()
        ..addAll(duaItems);
      _bookUnits
        ..clear()
        ..addAll(bookUnits);
      _dataMissing = missing;
    });
  }

  Future<void> _start(List<StudyTrack> tracks, List<String> bookKeys, int days) async {
    if (tracks.isEmpty && bookKeys.isEmpty) return;
    final plan = StudyPlan(
      track: tracks.isEmpty ? null : tracks.first,
      extraTracks: tracks.isEmpty ? const <StudyTrack>[] : tracks.skip(1).toList(),
      bookKeys: bookKeys,
      days: days,
      startedOn: studyDayKey(DateTime.now()),
    );
    await _store.save(plan);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _entries.clear();
      _units.clear();
      _bookSections.clear();
      _duaItems.clear();
      _bookUnits.clear();
      _dataMissing = null;
    });
    await _measureAll(plan);
  }

  Future<void> _toggleDay(int day) async {
    final plan = _plan;
    if (plan == null) return;
    final next = plan.toggledDay(day);
    setState(() => _plan = next);
    await _store.save(next);
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const JustifiedText('منصوبہ ختم کریں؟'),
        content: const JustifiedText(
          'آپ کی پڑھائی کا ریکارڈ مٹ جائے گا اور آپ نیا منصوبہ بنا سکیں گے۔ کتابیں اور بک مارکس محفوظ رہیں گے۔',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('نہیں')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ختم کریں')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.clear();
    if (!mounted) return;
    setState(() {
      _plan = null;
      _entries.clear();
      _units.clear();
      _bookSections.clear();
      _duaItems.clear();
      _bookUnits.clear();
      _dataMissing = null;
    });
  }

  /// Opens one book of the plan at today's portion of it: the whole run of
  /// pages or entries, not only its first one.
  Future<void> _openPortion(StudyTrack track, StudyPortion portion) async {
    if (track.isQuran) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => QuranPageReaderScreen(
          library: widget.library,
          page: portion.first,
          lastPage: portion.last,
        ),
      ));
      return;
    }
    final type = track.balaghaType;
    if (type == null) return;
    String? title;
    for (final entry in _entries[track] ?? const <BalaghaEntry>[]) {
      if (entry.typeNo == portion.first) {
        title = entry.title;
        break;
      }
    }
    final label = portion.first == portion.last
        ? (title ?? '${track.titleUrdu} ${arabicNumerals(portion.first)}')
        : '${track.titleUrdu} ${arabicNumerals(portion.first)} تا ${arabicNumerals(portion.last)}';
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BalaghaReaderScreen(
        library: widget.library,
        type: type,
        typeNo: portion.first,
        lastTypeNo: portion.last,
        title: label,
      ),
    ));
  }

  /// Opens a library book of the plan at the first section of today's
  /// portion. The section reader's own next/previous walk then carries the
  /// reader through the rest of the day's sections in order.
  Future<void> _openBookPortion(BookDefinition book, StudyPortion portion) async {
    if (book.source == CorpusSource.dua) {
      final items = _duaItems[book.key] ?? const <DuaItem>[];
      if (items.isEmpty) return;
      final item = items[(portion.first - 1).clamp(0, items.length - 1)];
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DuaReaderScreen(library: widget.library, item: item),
      ));
      return;
    }
    final sections = _bookSections[book.key] ?? const <({int id, String title})>[];
    if (sections.isEmpty) return;
    final section = sections[(portion.first - 1).clamp(0, sections.length - 1)];
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(
        library: widget.library,
        book: book,
        sectionId: section.id,
        sectionTitle: section.title.isEmpty ? book.titleUrdu : section.title,
      ),
    ));
  }

  /// The heading of the unit a generic portion opens on, for its card.
  String _portionHeadline(BookDefinition book, StudyPortion portion) {
    if (book.source == CorpusSource.dua) {
      final items = _duaItems[book.key] ?? const <DuaItem>[];
      if (items.isEmpty) return '';
      return items[(portion.first - 1).clamp(0, items.length - 1)].name;
    }
    final sections = _bookSections[book.key] ?? const <({int id, String title})>[];
    if (sections.isEmpty) return '';
    return sections[(portion.first - 1).clamp(0, sections.length - 1)].title;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFF0A1512),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        title: const JustifiedText(
          'روزانہ مطالعہ',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: <Color>[Color(0xFF123A31), Color(0xFF0B1D19), Color(0xFF07100E)],
            stops: <double>[0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: <Widget>[
                    const _StudyIntro(),
                    const SizedBox(height: 16),
                    if (_plan == null)
                      _PlanBuilder(active: false, onStart: _start, genericBooks: _genericBooks)
                    else
                      ..._planBody(_plan!),
                  ],
                ),
        ),
      ),
    );
  }

  List<Widget> _planBody(StudyPlan plan) {
    final now = DateTime.now();
    final today = StudyPortion.dayNumberFor(plan.startedOn, now);
    // The books whose data is installed: a plan may name more than one book,
    // and only the installed ones can be read.
    final ready = <StudyTrack>[
      for (final track in plan.tracks)
        if ((_units[track] ?? 0) > 0) track,
    ];
    final readyBooks = <BookDefinition>[
      for (final key in plan.bookKeys)
        if ((_bookUnits[key] ?? 0) > 0 && BookDefinition.byKey(key) != null)
          BookDefinition.byKey(key)!,
    ];
    if (ready.isEmpty && readyBooks.isEmpty) {
      return <Widget>[
        if (_dataMissing != null) _Notice(_dataMissing!),
        const SizedBox(height: 14),
        _PlanBuilder(
          active: true,
          onStart: _start,
          genericBooks: _genericBooks,
          initialTracks: plan.tracks,
          initialBookKeys: plan.bookKeys,
          initialDays: plan.days,
        ),
      ];
    }
    // A plan day beyond the book's length (the reader finished early or the
    // clock moved) simply shows the last portion instead of an empty card.
    final portions = <(StudyTrack, StudyPortion)>[
      for (final track in ready)
        (
          track,
          StudyPortion.forDay(
            day: today,
            days: plan.days,
            totalUnits: _units[track]!,
            unitLabelUrdu: track.unitLabelUrdu,
          ),
        ),
    ];
    final bookPortions = <(BookDefinition, StudyPortion)>[
      for (final book in readyBooks)
        (
          book,
          StudyPortion.forDay(
            day: today,
            days: plan.days,
            totalUnits: _bookUnits[book.key]!,
            unitLabelUrdu: studyBookUnitLabel(book),
          ),
        ),
    ];
    final done = plan.completedDays.length;
    final streak = studyStreak(plan, today);
    final finished = today > plan.days || (done >= plan.days);
    final day = today.clamp(1, plan.days);
    return <Widget>[
      for (final (track, portion) in portions) ...<Widget>[
        _TodayCard(
          title: track.titleUrdu,
          portion: portion,
          onOpen: () => unawaited(_openPortion(track, portion)),
        ),
        const SizedBox(height: 12),
      ],
      for (final (book, portion) in bookPortions) ...<Widget>[
        _TodayCard(
          title: book.titleUrdu,
          portion: portion,
          headline: _portionHeadline(book, portion),
          onOpen: () => unawaited(_openBookPortion(book, portion)),
        ),
        const SizedBox(height: 12),
      ],
      _DayCard(
        finished: plan.completedDays.contains(day) || finished,
        books: ready.length + readyBooks.length,
        onToggle: () => unawaited(_toggleDay(day)),
      ),
      const SizedBox(height: 14),
      Row(
        children: <Widget>[
          Expanded(
            child: _StatTile(
              icon: Icons.local_fire_department_rounded,
              value: arabicNumerals(streak),
              label: 'مسلسل دن',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.check_circle_outline_rounded,
              value: '${arabicNumerals(done)} / ${arabicNumerals(plan.days)}',
              label: 'مکمل دن',
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _ProgressCard(plan: plan, today: today, onToggleDay: (day) => unawaited(_toggleDay(day))),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: _reset,
        icon: const Icon(Icons.restart_alt, size: 18),
        label: const JustifiedText('نیا منصوبہ بنائیں'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFE9D8FF),
          side: BorderSide(color: kGold.withValues(alpha: 0.55)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    ];
  }
}

class _StudyIntro extends StatelessWidget {
  const _StudyIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[Color(0xFF1E4F42), Color(0xFF14332C)],
        ),
        border: Border.all(color: kGold.withValues(alpha: 0.42), width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: const LinearGradient(colors: <Color>[Color(0xFFC59A50), Color(0xFF8E6A2C)]),
                ),
                child: const Icon(Icons.menu_book_rounded, color: Color(0xFF1B1206), size: 26),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: JustifiedText(
                  'ایک یا چند کتابیں، مقررہ دنوں میں',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const JustifiedText(
            'بڑی کتابیں کھول کر دو صفحے پڑھنا آسان ہے، مکمل کرنا مشکل۔ یہاں اپنی کتاب (یا ایک سے زیادہ کتابیں) '
            'اور مدت چنیں: ایپ ہر دن کا حصہ خود مقرر کر دے گی، آپ صرف آج کا حصہ کھولیں اور مکمل ہونے پر نشان لگا دیں۔ '
            'حصے آپ کے شروع کرنے کے دن سے شمار ہوتے ہیں، اور سارا حساب آف لائن چلتا ہے۔',
            style: TextStyle(fontSize: 13.5, height: 1.8, color: Color(0xFFD9EAE2)),
          ),
        ],
      ),
    );
  }
}

/// Track + length picker. Used both for a fresh plan and for a plan whose data
/// is not installed yet. More than one book can be picked: the plan then walks
/// all of them over the same number of days.
class _PlanBuilder extends StatefulWidget {
  const _PlanBuilder({
    required this.active,
    required this.onStart,
    required this.genericBooks,
    this.initialTracks,
    this.initialBookKeys,
    this.initialDays,
  });

  final bool active;
  final void Function(List<StudyTrack> tracks, List<String> bookKeys, int days) onStart;

  /// Installed library books that can be added one by one, beside the
  /// classic Quran / Nahj al-Balagha tracks.
  final List<BookDefinition> genericBooks;
  final List<StudyTrack>? initialTracks;
  final List<String>? initialBookKeys;
  final int? initialDays;

  @override
  State<_PlanBuilder> createState() => _PlanBuilderState();
}

class _PlanBuilderState extends State<_PlanBuilder> {
  static const List<int> _lengths = <int>[7, 14, 30, 60, 90, 180];

  late List<StudyTrack> _tracks = <StudyTrack>[
    ...(widget.initialTracks ??
        (widget.initialBookKeys?.isNotEmpty == true
            ? const <StudyTrack>[]
            : const <StudyTrack>[StudyTrack.quran])),
  ];
  late List<String> _bookKeys = <String>[...(widget.initialBookKeys ?? const <String>[])];
  late int _days = widget.initialDays ?? 90;

  int get _selectionCount => _tracks.length + _bookKeys.length;

  /// Adds or removes a book. The last one never goes: a plan without a book
  /// has nothing to read.
  void _toggle(StudyTrack track) {
    setState(() {
      if (_tracks.contains(track)) {
        if (_selectionCount > 1) _tracks.remove(track);
      } else {
        _tracks.add(track);
      }
    });
  }

  void _toggleBook(BookDefinition book) {
    setState(() {
      if (_bookKeys.contains(book.key)) {
        if (_selectionCount > 1) _bookKeys.remove(book.key);
      } else {
        _bookKeys.add(book.key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const JustifiedText(
            'کون سی کتابیں؟',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFFFE1A1)),
          ),
          const SizedBox(height: 4),
          const JustifiedText(
            'ایک کتاب چنیں، یا ایک سے زیادہ — سب ایک ہی منصوبے میں چلیں گی۔',
            style: TextStyle(fontSize: 11.5, height: 1.6, color: Color(0xFFB9CEC4)),
          ),
          const SizedBox(height: 10),
          for (final track in StudyTrack.values) ...<Widget>[
            _SelectionRow(
              title: track.titleUrdu,
              subtitle: track.subtitleUrdu,
              selected: _tracks.contains(track),
              onTap: () => _toggle(track),
            ),
            const SizedBox(height: 8),
          ],
          // Every other installed book, added on its own: an hadith
          // collection walks its ابواب, Mafatih and the Sahifa their
          // دعائیں, the encyclopaedia its مضامین.
          if (widget.genericBooks.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            const JustifiedText(
              'انسٹال شدہ کتب سے',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFFFE1A1)),
            ),
            const SizedBox(height: 4),
            const JustifiedText(
              'ہر کتاب الگ شامل کریں — وہ اپنے ابواب / دعاؤں / مضامین میں دنوں پر تقسیم ہو جائے گی۔',
              style: TextStyle(fontSize: 11.5, height: 1.6, color: Color(0xFFB9CEC4)),
            ),
            const SizedBox(height: 10),
            for (final book in widget.genericBooks) ...<Widget>[
              _SelectionRow(
                title: book.titleUrdu,
                subtitle: book.description.isEmpty ? book.source.label : book.description,
                selected: _bookKeys.contains(book.key),
                onTap: () => _toggleBook(book),
              ),
              const SizedBox(height: 8),
            ],
          ] else ...<Widget>[
            const SizedBox(height: 2),
            const JustifiedText(
              'مزید کتابیں (کتبِ احادیث، مفاتیح الجنان، صحیفہ سجادیہ…) ڈیٹا سیکشن سے انسٹال کرنے کے بعد یہیں سے الگ الگ شامل کی جا سکیں گی۔',
              style: TextStyle(fontSize: 11.5, height: 1.6, color: Color(0xFFB9CEC4)),
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 6),
          const JustifiedText(
            'کتنی مدت میں؟',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFFFFE1A1)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final days in _lengths)
                ChoiceChip(
                  label: Text('${arabicNumerals(days)} دن'),
                  selected: _days == days,
                  onSelected: (_) => setState(() => _days = days),
                  selectedColor: kGold.withValues(alpha: 0.30),
                  labelStyle: TextStyle(
                    color: _days == days ? const Color(0xFFFFE1A1) : const Color(0xFFCFE3D9),
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: BorderSide(color: kGold.withValues(alpha: 0.35)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                _selectionCount == 0 ? null : () => widget.onStart(_tracks, _bookKeys, _days),
            icon: const Icon(Icons.play_arrow_rounded),
            label: JustifiedText(widget.active ? 'منصوبہ نئے سرے سے شروع کریں' : 'منصوبہ شروع کریں'),
            style: FilledButton.styleFrom(
              backgroundColor: kGold,
              foregroundColor: const Color(0xFF1B1206),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (widget.active) ...<Widget>[
            const SizedBox(height: 8),
            const JustifiedText(
              'نئے منصوبے سے پرانا ریکارڈ بدل جائے گا۔',
              style: TextStyle(fontSize: 12, color: Color(0xFFB9CEC4)),
            ),
          ],
        ],
      ),
    );
  }
}

/// One pickable book of the plan — a classic track or an installed library
/// book, drawn the same either way.
class _SelectionRow extends StatelessWidget {
  const _SelectionRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kGold.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? kGold.withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: <Widget>[
              // A tick box, not a radio: more than one book may be picked.
              Icon(
                selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                size: 18,
                color: selected ? kGold : const Color(0xFF8FA79C),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    JustifiedText(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? const Color(0xFFFFE1A1) : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    JustifiedText(
                      subtitle,
                      style: const TextStyle(fontSize: 11.5, height: 1.5, color: Color(0xFFB9CEC4)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's portion of one book of the plan, with the button that opens it.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.title,
    required this.portion,
    required this.onOpen,
    this.headline = '',
  });

  final String title;
  final StudyPortion portion;
  final VoidCallback onOpen;

  /// Where the portion begins, in the book's own words (the باب / دعا /
  /// مضمون the reader opens on). Empty for the classic tracks, whose range
  /// already names the place.
  final String headline;

  @override
  Widget build(BuildContext context) {
    final label = portion.isLastDay ? 'آخری حصہ' : 'آج کا حصہ — دن ${arabicNumerals(portion.day)}';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: <Color>[Color(0xFF3B2358), Color(0xFF14586B)],
        ),
        border: Border.all(color: kGold.withValues(alpha: 0.65), width: 1.2),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.32), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          JustifiedText(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFCFE3D9)),
          ),
          const SizedBox(height: 6),
          JustifiedText(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 6),
          JustifiedText(
            portion.rangeUrdu(arabicNumerals),
            style: const TextStyle(
              fontFamily: kDigitFont,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFFFFE1A1),
            ),
          ),
          if (headline.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            JustifiedText(
              'آغاز: ${headline.trim()}',
              style: const TextStyle(fontSize: 12.5, height: 1.6, color: Color(0xFFD9EAE2)),
              maxLines: 2,
            ),
          ],
          const SizedBox(height: 4),
          JustifiedText(
            'کل ${arabicNumerals(portion.totalUnits)} میں سے، ${arabicNumerals(portion.days)} دن کے منصوبے میں',
            style: const TextStyle(fontSize: 12, color: Color(0xFFB9CEC4)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.auto_stories_rounded, size: 18),
            label: const JustifiedText('پڑھنا شروع کریں'),
            style: FilledButton.styleFrom(
              backgroundColor: kGold,
              foregroundColor: const Color(0xFF1B1206),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tick that closes the plan-day: one day of the plan is done when every
/// book of it has been read.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.finished,
    required this.books,
    required this.onToggle,
  });

  final bool finished;
  final int books;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: finished ? kForest.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          color: finished ? Colors.white.withValues(alpha: 0.5) : kGold.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            finished ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: finished ? Colors.white : kGold,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: JustifiedText(
              finished
                  ? 'آج کا دن مکمل ہے'
                  : (books > 1 ? 'آج کی ${arabicNumerals(books)} کتابیں مکمل کریں' : 'آج کا حصہ مکمل کریں'),
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          Tooltip(
            message: finished ? 'نشان ہٹائیں' : 'آج کا حصہ مکمل',
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onToggle,
              child: Container(
                width: 50,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: finished ? kForest : Colors.white.withValues(alpha: 0.10),
                  border: Border.all(color: finished ? Colors.white : kGold.withValues(alpha: 0.55)),
                ),
                child: Icon(
                  finished ? Icons.check_rounded : Icons.check_circle_outline,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 22, color: kGold),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: kDigitFont,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                JustifiedText(label, style: const TextStyle(fontSize: 11.5, color: Color(0xFFB9CEC4))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The whole plan as a grid of days: tap a day to mark it, so a reader who read
/// ahead (or caught up on a missed day) can fix the record without hunting.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.plan, required this.today, required this.onToggleDay});

  final StudyPlan plan;
  final int today;
  final void Function(int day) onToggleDay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          JustifiedText(
            'منصوبے کے دن',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kGold),
          ),
          const SizedBox(height: 4),
          const JustifiedText(
            'کسی بھی دن پر انگلی رکھ کر اسے مکمل یا ادھورا کر سکتے ہیں۔',
            style: TextStyle(fontSize: 11.5, color: Color(0xFFB9CEC4)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (var day = 1; day <= plan.days; day++)
                _DayDot(
                  day: day,
                  done: plan.completedDays.contains(day),
                  isToday: day == today,
                  onTap: () => onToggleDay(day),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.day, required this.done, required this.isToday, required this.onTap});

  final int day;
  final bool done;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: done
              ? kForest
              : (isToday ? kGold.withValues(alpha: 0.24) : Colors.white.withValues(alpha: 0.06)),
          border: Border.all(
            color: isToday
                ? kGold
                : (done ? Colors.white.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.12)),
            width: isToday ? 1.6 : 1,
          ),
        ),
        child: Text(
          '$day',
          style: TextStyle(
            fontFamily: kDigitFont,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: done || isToday ? Colors.white : const Color(0xFF9FB6AB),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF6B2F2F).withValues(alpha: 0.45),
        border: Border.all(color: const Color(0xFFE7B9A1).withValues(alpha: 0.5)),
      ),
      child: JustifiedText(
        message,
        style: const TextStyle(fontSize: 13, height: 1.7, color: Color(0xFFFFE7DA)),
      ),
    );
  }
}
