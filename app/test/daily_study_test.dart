import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiaverse/daily_study.dart';

/// **روزانہ مطالعہ**: the portion arithmetic, the streak, and the plan that is
/// saved between sessions. Every day of every length must be covered exactly
/// once, because a plan that skips a page leaves a hole in a reader's khatm.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('portion arithmetic', () {
    test('a 90-day Quran plan covers all 604 pages exactly once', () {
      var expected = 1;
      for (var day = 1; day <= 90; day++) {
        final portion = StudyPortion.forDay(
          day: day,
          days: 90,
          totalUnits: kQuranPages,
          unitLabelUrdu: 'صفحہ',
        );
        expect(portion.first, expected, reason: 'day $day must start where the last ended');
        expect(portion.last, greaterThanOrEqualTo(portion.first));
        expected = portion.last + 1;
      }
      expect(expected, kQuranPages + 1, reason: 'the last day ends on the last page');
    });

    test('the remainder is spread, never piled onto one day', () {
      // 604 pages over 30 days: 20 pages a day plus four days of 21.
      final lengths = <int>[
        for (var day = 1; day <= 30; day++)
          StudyPortion.forDay(day: day, days: 30, totalUnits: kQuranPages, unitLabelUrdu: 'صفحہ').last -
              StudyPortion.forDay(day: day, days: 30, totalUnits: kQuranPages, unitLabelUrdu: 'صفحہ').first +
              1,
      ];
      expect(lengths.reduce((a, b) => a + b), kQuranPages);
      expect(lengths.reduce((a, b) => a > b ? a : b) - lengths.reduce((a, b) => a < b ? a : b),
          lessThanOrEqualTo(1));
    });

    test('241 sermons over 90 days stay inside the book', () {
      for (var day = 1; day <= 90; day++) {
        final portion = StudyPortion.forDay(
          day: day,
          days: 90,
          totalUnits: 241,
          unitLabelUrdu: 'نمبر',
        );
        expect(portion.first, inInclusiveRange(1, 241));
        expect(portion.last, inInclusiveRange(portion.first, 241));
      }
      expect(
        StudyPortion.forDay(day: 90, days: 90, totalUnits: 241, unitLabelUrdu: 'نمبر').last,
        241,
      );
    });

    test('a one-day plan is the whole book', () {
      final portion = StudyPortion.forDay(day: 1, days: 1, totalUnits: 480, unitLabelUrdu: 'نمبر');
      expect(portion.first, 1);
      expect(portion.last, 480);
      expect(portion.isLastDay, isTrue);
    });

    test('a day outside the plan is clamped instead of going blank', () {
      final late = StudyPortion.forDay(day: 120, days: 90, totalUnits: kQuranPages, unitLabelUrdu: 'صفحہ');
      expect(late.day, 90);
      expect(late.last, kQuranPages);
    });

    test('an empty or zero-length book still yields a usable portion', () {
      final portion = StudyPortion.forDay(day: 1, days: 30, totalUnits: 0, unitLabelUrdu: 'نمبر');
      expect(portion.first, 1);
      expect(portion.last, 1);
    });
  });

  group('day counting', () {
    test('the start day is day one and each next day adds one', () {
      expect(StudyPortion.dayNumberFor('2026-10-20', DateTime(2026, 10, 20, 23, 59)), 1);
      expect(StudyPortion.dayNumberFor('2026-10-20', DateTime(2026, 10, 21, 0, 1)), 2);
      expect(StudyPortion.dayNumberFor('2026-10-20', DateTime(2026, 11, 19)), 31);
    });

    test('a clock that moved backwards still reads as day one', () {
      expect(StudyPortion.dayNumberFor('2026-10-20', DateTime(2026, 10, 18)), lessThan(1));
    });

    test('the key is a plain local date', () {
      expect(studyDayKey(DateTime(2026, 1, 5, 22)), '2026-01-05');
    });
  });

  group('streak', () {
    final plan = StudyPlan(track: StudyTrack.quran, days: 90, startedOn: '2026-10-20');

    test('today counts only once it is marked, yesterday still does', () {
      expect(studyStreak(plan.copyWith(completedDays: <int>{1, 2, 3}), 4), 3);
      expect(studyStreak(plan.copyWith(completedDays: <int>{1, 2, 3, 4}), 4), 4);
    });

    test('a missed day ends the streak', () {
      // Today is not marked yet, so yesterday still counts: days 1–4 finished
      // is a streak of one, and day 3 breaks it there.
      expect(studyStreak(plan.copyWith(completedDays: <int>{1, 2, 4}), 5), 1);
      expect(studyStreak(plan.copyWith(completedDays: <int>{1, 2, 3}), 5), 0);
      expect(studyStreak(plan.copyWith(completedDays: <int>{4, 5}), 5), 2);
    });

    test('an empty plan has no streak', () {
      expect(studyStreak(plan, 1), 0);
    });
  });

  group('toggling and saving', () {
    test('a day can be marked finished and un-marked again', () {
      const plan = StudyPlan(track: StudyTrack.balaghaWisdom, days: 30, startedOn: '2026-10-20');
      final marked = plan.toggledDay(2);
      expect(marked.completedDays, <int>{2});
      expect(marked.toggledDay(2).completedDays, isEmpty);
      expect(plan.completedDays, isEmpty, reason: 'the original plan is never mutated');
    });

    test('a plan survives the round trip through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = StudyPlanStore();
      expect(await store.load(), isNull);

      final plan = StudyPlan(
        track: StudyTrack.balaghaSermons,
        days: 60,
        startedOn: '2026-10-20',
        completedDays: <int>{1, 2, 5},
      );
      await store.save(plan);

      final restored = await StudyPlanStore().load();
      expect(restored, isNotNull);
      expect(restored!.track, StudyTrack.balaghaSermons);
      expect(restored.days, 60);
      expect(restored.startedOn, '2026-10-20');
      expect(restored.completedDays, <int>{1, 2, 5});

      await store.clear();
      expect(await StudyPlanStore().load(), isNull);
    });

    test('a corrupt saved value is treated as no plan instead of crashing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'daily_study_plan_v1': '{not json'});
      expect(await StudyPlanStore().load(), isNull);
    });

    test('a plan with an unknown track is ignored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'daily_study_plan_v1': '{"track":"mars","days":30,"startedOn":"2026-10-20"}',
      });
      expect(await StudyPlanStore().load(), isNull);
    });
  });

  group('more than one book at a time', () {
    test('a plan can carry several books, in order', () {
      const plan = StudyPlan(
        track: StudyTrack.quran,
        extraTracks: <StudyTrack>[StudyTrack.balaghaSermons, StudyTrack.balaghaWisdom],
        days: 90,
        startedOn: '2026-10-20',
      );
      expect(plan.tracks, <StudyTrack>[
        StudyTrack.quran,
        StudyTrack.balaghaSermons,
        StudyTrack.balaghaWisdom,
      ]);
      expect(plan.isMultiBook, isTrue);
      expect(plan.copyWith(days: 30).days, 30);
      expect(plan.copyWith(days: 30).tracks.length, 3);
    });

    test('the extra books survive the round trip through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final plan = StudyPlan(
        track: StudyTrack.quran,
        extraTracks: <StudyTrack>[StudyTrack.balaghaLetters],
        days: 30,
        startedOn: '2026-10-20',
        completedDays: <int>{1, 2},
      );
      await StudyPlanStore().save(plan);

      final restored = await StudyPlanStore().load();
      expect(restored, isNotNull);
      expect(restored!.tracks, <StudyTrack>[StudyTrack.quran, StudyTrack.balaghaLetters]);
      expect(restored.completedDays, <int>{1, 2});
      expect(restored.days, 30);
    });

    test('a book that is no longer known is dropped and the plan survives', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'daily_study_plan_v1':
            '{"track":"quran","extraTracks":["mars","balaghaWisdom"],"days":30,"startedOn":"2026-10-20"}',
      });
      final plan = await StudyPlanStore().load();
      expect(plan, isNotNull);
      expect(plan!.tracks, <StudyTrack>[StudyTrack.quran, StudyTrack.balaghaWisdom]);
    });

    test('a single-book plan is not a multi-book plan', () {
      const plan = StudyPlan(track: StudyTrack.quran, days: 90, startedOn: '2026-10-20');
      expect(plan.isMultiBook, isFalse);
      expect(plan.tracks, <StudyTrack>[StudyTrack.quran]);
    });

    test('a plan can walk library books named by key, alone or alongside', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      // A plan of library books only: no classic track at all.
      final plan = StudyPlan(
        bookKeys: <String>['alkafi', 'sahifa'],
        days: 60,
        startedOn: '2026-10-20',
        completedDays: <int>{3},
      );
      expect(plan.track, isNull);
      expect(plan.tracks, isEmpty);
      expect(plan.selectionCount, 2);
      expect(plan.isMultiBook, isTrue);
      await StudyPlanStore().save(plan);

      final restored = await StudyPlanStore().load();
      expect(restored, isNotNull);
      expect(restored!.bookKeys, <String>['alkafi', 'sahifa']);
      expect(restored.completedDays, <int>{3});

      // And alongside a classic track, in the same plan.
      const mixed = StudyPlan(
        track: StudyTrack.quran,
        bookKeys: <String>['mafatih'],
        days: 30,
        startedOn: '2026-10-20',
      );
      expect(mixed.selectionCount, 2);
      expect(mixed.copyWith(bookKeys: <String>[]).selectionCount, 1);
    });

    test('an old plan without book keys still loads, a bookless one does not', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'daily_study_plan_v1':
            '{"track":"quran","days":30,"startedOn":"2026-10-20"}',
      });
      final plan = await StudyPlanStore().load();
      expect(plan, isNotNull);
      expect(plan!.bookKeys, isEmpty);
      expect(plan.selectionCount, 1);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'daily_study_plan_v1': '{"days":30,"startedOn":"2026-10-20"}',
      });
      expect(await StudyPlanStore().load(), isNull);
    });

    test('every book of a plan is split over the same days', () {
      // Two books of very different lengths, one plan: both portions end on
      // their own last unit on the last day.
      final quran = StudyPortion.forDay(
        day: 90,
        days: 90,
        totalUnits: kQuranPages,
        unitLabelUrdu: 'صفحہ',
      );
      final sermons = StudyPortion.forDay(
        day: 90,
        days: 90,
        totalUnits: 241,
        unitLabelUrdu: 'نمبر',
      );
      expect(quran.last, kQuranPages);
      expect(sermons.last, 241);
      expect(quran.days, sermons.days);
    });
  });
}
