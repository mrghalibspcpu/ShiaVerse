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

/// **روزانہ مطالعہ** — the Xplore feature that turns the library into a habit.
///
/// A reader picks one or several books from the library — Quran, dua, hadith,
/// Nahj al-Balagha, fatawa, or the encyclopedia — and a length in days. The
/// screen works out today's portion of every book, opens its existing reader,
/// and keeps the streak. Nothing leaves the phone; each book uses its own
/// installed sections, entries, or pages and the plan works offline.
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

  /// Entries of the chosen Nahj al-Balagha divisions.
  final Map<StudyTrack, List<BalaghaEntry>> _entries = <StudyTrack, List<BalaghaEntry>>{};

  /// Ordered sections/duas for all the other selected library books.
  final Map<StudyTrack, List<StudyUnit>> _studyUnits = <StudyTrack, List<StudyUnit>>{};
  final Map<StudyTrack, int> _units = <StudyTrack, int>{};
  String? _dataMissing;

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
    if (plan != null) await _measure(plan.tracks);
  }

  /// How many units every chosen track has, asked of the library itself so the
  /// plan never promises a length the installed data cannot fill.
  Future<void> _measure(List<StudyTrack> tracks) async {
    final units = <StudyTrack, int>{};
    final entries = <StudyTrack, List<BalaghaEntry>>{};
    final bookUnits = <StudyTrack, List<StudyUnit>>{};
    String? missing;
    for (final track in tracks) {
      final book = BookDefinition.byKey(track.bookKey);
      if (book == null || !widget.library.isInstalled(book)) {
        missing ??= '${track.titleUrdu} کا متن ابھی انسٹال نہیں — ڈیٹا سیکشن سے ڈاؤن لوڈ کریں۔';
        continue;
      }
      if (track.isQuran) {
        units[track] = kQuranPages;
        continue;
      }
      final type = track.balaghaType;
      if (type != null) {
        List<BalaghaEntry> list = const <BalaghaEntry>[];
        try {
          list = await widget.library.getBalaghaEntries(type);
        } catch (_) {
          list = const <BalaghaEntry>[];
        }
        entries[track] = list;
        units[track] = list.length;
        if (list.isEmpty) missing ??= '${track.titleUrdu} کا متن ابھی دستیاب نہیں۔';
        continue;
      }

      List<StudyUnit> list = const <StudyUnit>[];
      try {
        list = await widget.library.getStudyUnits(book);
      } catch (_) {
        list = const <StudyUnit>[];
      }
      bookUnits[track] = list;
      units[track] = list.length;
      if (list.isEmpty) missing ??= '${track.titleUrdu} کا متن ابھی دستیاب نہیں۔';
    }
    if (!mounted) return;
    setState(() {
      _entries
        ..clear()
        ..addAll(entries);
      _studyUnits
        ..clear()
        ..addAll(bookUnits);
      _units
        ..clear()
        ..addAll(units);
      _dataMissing = missing;
    });
  }

  Future<void> _start(List<StudyTrack> tracks, int days) async {
    if (tracks.isEmpty) return;
    final plan = StudyPlan(
      track: tracks.first,
      extraTracks: tracks.skip(1).toList(),
      days: days,
      startedOn: studyDayKey(DateTime.now()),
    );
    await _store.save(plan);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _entries.clear();
      _studyUnits.clear();
      _units.clear();
      _dataMissing = null;
    });
    await _measure(plan.tracks);
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
      _studyUnits.clear();
      _units.clear();
      _dataMissing = null;
    });
  }

  /// Opens one book at today's portion. Each reader keeps its own normal
  /// section navigation; Mafatih additionally receives the exact dua run so
  /// its next/previous controls stay inside the day's assignment.
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
    if (type != null) {
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
      return;
    }

    final units = _studyUnits[track] ?? const <StudyUnit>[];
    if (units.isEmpty) return;
    final firstIndex = (portion.first - 1).clamp(0, units.length - 1).toInt();
    final lastIndex = (portion.last - 1).clamp(firstIndex, units.length - 1).toInt();
    final run = units.sublist(firstIndex, lastIndex + 1);
    if (track.isMafatih) {
      final duas = <DuaItem>[
        for (final unit in run)
          if (unit.duaItem != null) unit.duaItem!,
      ];
      if (duas.isEmpty) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DuaReaderScreen(
          library: widget.library,
          item: duas.first,
          studyItems: duas,
        ),
      ));
      return;
    }

    final book = BookDefinition.byKey(track.bookKey);
    if (book == null) return;
    final firstUnit = run.first;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(
        library: widget.library,
        book: book,
        sectionId: firstUnit.id,
        sectionTitle: firstUnit.title,
        studyFirstSectionId: firstUnit.id,
        studyLastSectionId: run.last.id,
      ),
    ));
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
                      _PlanBuilder(active: false, onStart: _start)
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
    if (ready.isEmpty) {
      return <Widget>[
        if (_dataMissing != null) _Notice(_dataMissing!),
        const SizedBox(height: 14),
        _PlanBuilder(active: true, onStart: _start, initialTracks: plan.tracks, initialDays: plan.days),
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
    final done = plan.completedDays.length;
    final streak = studyStreak(plan, today);
    final finished = today > plan.days || (done >= plan.days);
    final day = portions.first.$2.day;
    return <Widget>[
      if (_dataMissing != null) ...<Widget>[
        _Notice(_dataMissing!),
        const SizedBox(height: 12),
      ],
      for (final (track, portion) in portions) ...<Widget>[
        _TodayCard(
          track: track,
          portion: portion,
          onOpen: () => unawaited(_openPortion(track, portion)),
        ),
        const SizedBox(height: 12),
      ],
      _DayCard(
        finished: plan.completedDays.contains(day) || finished,
        books: ready.length,
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
    this.initialTracks,
    this.initialDays,
  });

  final bool active;
  final void Function(List<StudyTrack> tracks, int days) onStart;
  final List<StudyTrack>? initialTracks;
  final int? initialDays;

  @override
  State<_PlanBuilder> createState() => _PlanBuilderState();
}

class _PlanBuilderState extends State<_PlanBuilder> {
  static const List<int> _lengths = <int>[7, 14, 30, 60, 90, 180];

  late List<StudyTrack> _tracks = <StudyTrack>[
    ...(widget.initialTracks ?? const <StudyTrack>[StudyTrack.quran]),
  ];
  late int _days = widget.initialDays ?? 90;

  /// Adds or removes a book. The last one never goes: a plan without a book
  /// has nothing to read.
  void _toggle(StudyTrack track) {
    setState(() {
      if (_tracks.contains(track)) {
        if (_tracks.length > 1) _tracks.remove(track);
      } else {
        _tracks.add(track);
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
            _TrackRow(
              track: track,
              selected: _tracks.contains(track),
              onTap: () => _toggle(track),
            ),
            const SizedBox(height: 8),
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
            onPressed: _tracks.isEmpty ? null : () => widget.onStart(_tracks, _days),
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

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.selected, required this.onTap});

  final StudyTrack track;
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
                      track.titleUrdu,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? const Color(0xFFFFE1A1) : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    JustifiedText(
                      track.subtitleUrdu,
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
    required this.track,
    required this.portion,
    required this.onOpen,
  });

  final StudyTrack track;
  final StudyPortion portion;
  final VoidCallback onOpen;

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
            track.titleUrdu,
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
