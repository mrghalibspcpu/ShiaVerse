/// **روزانہ مطالعہ** — a reader's own reading plan.
///
/// The library is large: the Quran is 604 pages, Nahj al-Balagha is 241
/// sermons, 79 letters and 480 short sayings. Readers ask for a way to get
/// *through* a book instead of opening it, reading two lines and closing it —
/// so a plan splits one book into equal daily portions, shows today's portion,
/// and remembers the streak.
///
/// Everything here is pure data plus [SharedPreferences]; no network and no
/// database, so a plan costs nothing to keep and works offline like the rest of
/// the library.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Which book the plan walks through.
enum StudyTrack {
  /// ختمِ قرآن: the 604 pages of the mushaf.
  quran('قرآنِ کریم', 'مصحف کے ۶۰۴ صفحات'),

  /// نہج البلاغہ's sermons (خطبات).
  balaghaSermons('نہج البلاغہ — خطبات', 'امیر المومنین علیہ السلام کے خطبات'),

  /// نہج البلاغہ's letters (کتب و خطوط).
  balaghaLetters('نہج البلاغہ — خطوط', 'امیر المومنین علیہ السلام کے مکتوبات'),

  /// Nahj al-Balagha's short sayings (حکمت و اقوالِ قصار).
  balaghaWisdom('نہج البلاغہ — حکمت', 'اقوالِ قصار و حکمت بھری باتوں');

  const StudyTrack(this.titleUrdu, this.subtitleUrdu);

  final String titleUrdu;
  final String subtitleUrdu;

  /// `balaghatoc.TypeID` for the three Nahj al-Balagha tracks.
  int? get balaghaType => switch (this) {
        StudyTrack.balaghaSermons => 1,
        StudyTrack.balaghaLetters => 2,
        StudyTrack.balaghaWisdom => 3,
        StudyTrack.quran => null,
      };

  bool get isQuran => this == StudyTrack.quran;

  /// What one portion counts: pages of the mushaf, or entries of a section.
  String get unitLabelUrdu => isQuran ? 'صفحہ' : 'نمبر';
}

/// The mushaf's page count, fixed in every printed edition.
const int kQuranPages = 604;

/// A plan the reader chose: one book, one length, one start day.
///
/// A reader can also aim at more than one book at a time — the Quran and one
/// section of Nahj al-Balagha, say — so the plan carries the first book in
/// [track] and the rest in [extraTracks]. Every book is split over the same
/// number of days, so one day means one portion of each of them.
///
/// Since 1.28 the plan can also walk ANY installed library book on its own —
/// an hadith collection, Mafatih al-Jinan, Sahifa Sajjadiyya, the fatawa,
/// the encyclopaedia — named by book key in [bookKeys]. Those books are
/// split by their sections (ابواب / دعائیں / مضامین), which is why they do
/// not fit the fixed [StudyTrack] list. A plan made only of such books has
/// no [track] at all.
class StudyPlan {
  const StudyPlan({
    this.track,
    required this.days,
    required this.startedOn,
    this.completedDays = const <int>{},
    this.extraTracks = const <StudyTrack>[],
    this.bookKeys = const <String>[],
  });

  /// The classic track the plan starts with, when it has one.
  final StudyTrack? track;

  /// The other classic tracks of the same plan, read in the same days.
  final List<StudyTrack> extraTracks;

  /// Library books (by `BookDefinition.key`) walked section by section
  /// alongside — or instead of — the classic tracks.
  final List<String> bookKeys;

  /// How many days the whole book should take.
  final int days;

  /// The day the reader began, as `yyyy-MM-dd` (local). Portions are counted
  /// from here, so a plan that is not opened for a week does not silently
  /// re-flow — the reader simply has a week of days waiting.
  final String startedOn;

  /// Plan-day numbers the reader marked as finished (1-based).
  final Set<int> completedDays;

  /// Every classic track this plan walks through, the first one first.
  List<StudyTrack> get tracks => <StudyTrack>[if (track != null) track!, ...extraTracks];

  /// How many books the plan walks in all (classic tracks + library books).
  int get selectionCount => tracks.length + bookKeys.length;

  /// True when the reader aimed at more than one book at a time.
  bool get isMultiBook => selectionCount > 1;

  StudyPlan copyWith({
    int? days,
    String? startedOn,
    Set<int>? completedDays,
    List<StudyTrack>? extraTracks,
    List<String>? bookKeys,
  }) =>
      StudyPlan(
        track: track,
        days: days ?? this.days,
        startedOn: startedOn ?? this.startedOn,
        completedDays: completedDays ?? this.completedDays,
        extraTracks: extraTracks ?? this.extraTracks,
        bookKeys: bookKeys ?? this.bookKeys,
      );

  /// A day is finished, or un-finished again on a second tap.
  StudyPlan toggledDay(int day) {
    final next = <int>{...completedDays};
    if (!next.remove(day)) next.add(day);
    return copyWith(completedDays: next);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'track': track?.name,
        'extraTracks': <String>[for (final value in extraTracks) value.name],
        'bookKeys': bookKeys,
        'days': days,
        'startedOn': startedOn,
        'completedDays': (completedDays.toList()..sort()),
      };

  static StudyPlan? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final trackName = raw['track'];
    StudyTrack? track;
    for (final value in StudyTrack.values) {
      if (value.name == trackName) track = value;
    }
    final days = raw['days'];
    final startedOn = raw['startedOn'];
    if (days is! int || days <= 0 || startedOn is! String) return null;
    final completed = <int>{
      for (final day in (raw['completedDays'] as List<Object?>? ?? const <Object?>[]))
        if (day is int && day > 0) day,
    };
    // The other books of the plan: a name that is no longer known is simply
    // left out, the same way an unknown first book leaves no plan at all.
    final extra = <StudyTrack>[];
    for (final value in (raw['extraTracks'] as List<Object?>? ?? const <Object?>[])) {
      for (final candidate in StudyTrack.values) {
        if (candidate.name == value && candidate != track && !extra.contains(candidate)) {
          extra.add(candidate);
        }
      }
    }
    // Library books named by key. Whether a key still names a book is the
    // screen's business (this file stays free of the catalogue), so any
    // plain non-empty string is kept here and checked when it is measured.
    final keys = <String>[];
    for (final value in (raw['bookKeys'] as List<Object?>? ?? const <Object?>[])) {
      final key = value.toString().trim();
      if (key.isNotEmpty && !keys.contains(key)) keys.add(key);
    }
    // A plan needs at least one book, classic or library.
    if (track == null && extra.isEmpty && keys.isEmpty) return null;
    return StudyPlan(
      track: track,
      days: days,
      startedOn: startedOn,
      completedDays: completed,
      extraTracks: extra,
      bookKeys: keys,
    );
  }
}

/// Where one plan-day sits inside the book.
class StudyPortion {
  const StudyPortion({
    required this.day,
    required this.first,
    required this.last,
    required this.totalUnits,
    required this.days,
    required this.unitLabelUrdu,
  });

  /// 1-based plan day.
  final int day;

  /// 1-based, inclusive range of pages (Quran) or entries (Nahj al-Balagha).
  final int first;
  final int last;

  /// How long the book is in the plan's units: 604 pages, 241 sermons …
  final int totalUnits;
  final int days;
  final String unitLabelUrdu;

  /// «صفحہ ۲۱ تا ۲۷» / «نمبر ۵ تا ۸».
  String rangeUrdu(String Function(int) numeral) => first == last
      ? '$unitLabelUrdu ${numeral(first)}'
      : '$unitLabelUrdu ${numeral(first)} تا ${numeral(last)}';

  bool get isLastDay => day >= days;

  /// The plan-day a moment falls on, given the plan's start day: 1 on the start
  /// day itself. A clock that moved backwards still reads as day 1.
  static int dayNumberFor(String startedOn, DateTime now) {
    final start = DateTime.tryParse(startedOn);
    if (start == null) return 1;
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(start.year, start.month, start.day);
    return today.difference(first).inDays + 1;
  }

  /// Splits [totalUnits] into [days] portions as evenly as arithmetic allows.
  ///
  /// The remainder is spread over the first days, so the first portions are one
  /// unit longer and no day is ever more than one unit away from another; the
  /// last day always ends on the book's last unit.
  factory StudyPortion.forDay({
    required int day,
    required int days,
    required int totalUnits,
    required String unitLabelUrdu,
  }) {
    final safeDays = days <= 0 ? 1 : days;
    final safeUnits = totalUnits <= 0 ? 1 : totalUnits;
    final clamped = day.clamp(1, safeDays);
    final base = safeUnits ~/ safeDays;
    final extra = safeUnits % safeDays;
    final before = clamped - 1;
    final first = 1 + before * base + (before < extra ? before : extra);
    final length = base + (clamped <= extra ? 1 : 0);
    return StudyPortion(
      day: clamped,
      first: first,
      last: (first + (length <= 0 ? 1 : length) - 1).clamp(1, safeUnits),
      totalUnits: safeUnits,
      days: safeDays,
      unitLabelUrdu: unitLabelUrdu,
    );
  }

  @override
  String toString() => 'StudyPortion(day $day of $days, $first–$last of $totalUnits)';
}

/// Consecutive finished plan-days, counting back from [today].
///
/// Today counts only once it is marked, but yesterday still counts — so a
/// reader who reads in the evening does not see the streak break all morning.
int studyStreak(StudyPlan plan, int today) {
  var streak = 0;
  for (var day = today; day >= 1; day--) {
    if (plan.completedDays.contains(day)) {
      streak++;
      continue;
    }
    if (day == today) continue;
    break;
  }
  return streak;
}

/// Persists the plan. A reader who never chose one simply has `null`.
class StudyPlanStore {
  StudyPlanStore({SharedPreferences? preferences}) : _cached = preferences;

  static const String _key = 'daily_study_plan_v1';
  SharedPreferences? _cached;

  Future<SharedPreferences> _prefs() async => _cached ??= await SharedPreferences.getInstance();

  Future<StudyPlan?> load() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return StudyPlan.fromJson(jsonDecode(raw));
    } catch (_) {
      return null; // a corrupt value must not lock the reader out of the screen
    }
  }

  Future<void> save(StudyPlan plan) async {
    final prefs = await _prefs();
    await prefs.setString(_key, jsonEncode(plan.toJson()));
  }

  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_key);
  }
}

/// `yyyy-MM-dd` for the local day, the format [StudyPlan.startedOn] keeps.
String studyDayKey(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
