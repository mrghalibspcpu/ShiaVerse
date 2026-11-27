import 'package:flutter_test/flutter_test.dart';

import 'package:shiaverse/astro/hijri_calendar.dart';
import 'package:shiaverse/astro/lunar_hijri.dart';

/// The Julian Day at 00:00 UT of a civil date: the shape `observeEvening` takes.
double _midnight(int year, int month, int day) =>
    HijriDate.julianDayNumber(year, month, day).toDouble() - 0.5;

/// Islamabad (33.6844, 73.0479) — the first civil day of every month from
/// Dhu al-Qadah 1445 to Shawwal 1451, the Hijri month it opens, and how many
/// days the month before it had.
final _kMonthStarts = <(DateTime, int, int, int)>[
    // Islamabad (33.6844, 73.0479) — the first civil day of every month
    // from Shawwal 1445 to Dhu al-Quddah 1451, with the month it opens.
    (DateTime.utc(2024, 5, 10), 1445, 11, 30),  // (2024, 5, 10)
    (DateTime.utc(2024, 6, 8), 1445, 12, 29),  // (2024, 6, 8)
    (DateTime.utc(2024, 7, 8), 1446, 1, 30),  // (2024, 7, 8)
    (DateTime.utc(2024, 8, 6), 1446, 2, 29),  // (2024, 8, 6)
    (DateTime.utc(2024, 9, 5), 1446, 3, 30),  // (2024, 9, 5)
    (DateTime.utc(2024, 10, 5), 1446, 4, 30),  // (2024, 10, 5)
    (DateTime.utc(2024, 11, 4), 1446, 5, 30),  // (2024, 11, 4)
    (DateTime.utc(2024, 12, 3), 1446, 6, 29),  // (2024, 12, 3)
    (DateTime.utc(2025, 1, 2), 1446, 7, 30),  // (2025, 1, 2)
    (DateTime.utc(2025, 1, 31), 1446, 8, 29),  // (2025, 1, 31)
    (DateTime.utc(2025, 3, 2), 1446, 9, 30),  // (2025, 3, 2)
    (DateTime.utc(2025, 3, 31), 1446, 10, 29),  // (2025, 3, 31)
    (DateTime.utc(2025, 4, 29), 1446, 11, 29),  // (2025, 4, 29)
    (DateTime.utc(2025, 5, 29), 1446, 12, 30),  // (2025, 5, 29)
    (DateTime.utc(2025, 6, 27), 1447, 1, 29),  // (2025, 6, 27)
    (DateTime.utc(2025, 7, 26), 1447, 2, 29),  // (2025, 7, 26)
    (DateTime.utc(2025, 8, 25), 1447, 3, 30),  // (2025, 8, 25)
    (DateTime.utc(2025, 9, 24), 1447, 4, 30),  // (2025, 9, 24)
    (DateTime.utc(2025, 10, 24), 1447, 5, 30),  // (2025, 10, 24)
    (DateTime.utc(2025, 11, 23), 1447, 6, 30),  // (2025, 11, 23)
    (DateTime.utc(2025, 12, 22), 1447, 7, 29),  // (2025, 12, 22)
    (DateTime.utc(2026, 1, 21), 1447, 8, 30),  // (2026, 1, 21)
    (DateTime.utc(2026, 2, 19), 1447, 9, 29),  // (2026, 2, 19)
    (DateTime.utc(2026, 3, 21), 1447, 10, 30),  // (2026, 3, 21)
    (DateTime.utc(2026, 4, 19), 1447, 11, 29),  // (2026, 4, 19)
    (DateTime.utc(2026, 5, 18), 1447, 12, 29),  // (2026, 5, 18)
    (DateTime.utc(2026, 6, 17), 1448, 1, 30),  // (2026, 6, 17)
    (DateTime.utc(2026, 7, 16), 1448, 2, 29),  // (2026, 7, 16)
    (DateTime.utc(2026, 8, 15), 1448, 3, 30),  // (2026, 8, 15)
    (DateTime.utc(2026, 9, 13), 1448, 4, 29),  // (2026, 9, 13)
    (DateTime.utc(2026, 10, 13), 1448, 5, 30),  // (2026, 10, 13)
    (DateTime.utc(2026, 11, 12), 1448, 6, 30),  // (2026, 11, 12)
    (DateTime.utc(2026, 12, 11), 1448, 7, 29),  // (2026, 12, 11)
    (DateTime.utc(2027, 1, 10), 1448, 8, 30),  // (2027, 1, 10)
    (DateTime.utc(2027, 2, 8), 1448, 9, 29),  // (2027, 2, 8)
    (DateTime.utc(2027, 3, 10), 1448, 10, 30),  // (2027, 3, 10)
    (DateTime.utc(2027, 4, 9), 1448, 11, 30),  // (2027, 4, 9)
    (DateTime.utc(2027, 5, 8), 1448, 12, 29),  // (2027, 5, 8)
    (DateTime.utc(2027, 6, 6), 1449, 1, 29),  // (2027, 6, 6)
    (DateTime.utc(2027, 7, 6), 1449, 2, 30),  // (2027, 7, 6)
    (DateTime.utc(2027, 8, 4), 1449, 3, 29),  // (2027, 8, 4)
    (DateTime.utc(2027, 9, 3), 1449, 4, 30),  // (2027, 9, 3)
    (DateTime.utc(2027, 10, 2), 1449, 5, 29),  // (2027, 10, 2)
    (DateTime.utc(2027, 11, 1), 1449, 6, 30),  // (2027, 11, 1)
    (DateTime.utc(2027, 11, 30), 1449, 7, 29),  // (2027, 11, 30)
    (DateTime.utc(2027, 12, 30), 1449, 8, 30),  // (2027, 12, 30)
    (DateTime.utc(2028, 1, 28), 1449, 9, 29),  // (2028, 1, 28)
    (DateTime.utc(2028, 2, 27), 1449, 10, 30),  // (2028, 2, 27)
    (DateTime.utc(2028, 3, 28), 1449, 11, 30),  // (2028, 3, 28)
    (DateTime.utc(2028, 4, 26), 1449, 12, 29),  // (2028, 4, 26)
    (DateTime.utc(2028, 5, 26), 1450, 1, 30),  // (2028, 5, 26)
    (DateTime.utc(2028, 6, 24), 1450, 2, 29),  // (2028, 6, 24)
    (DateTime.utc(2028, 7, 24), 1450, 3, 30),  // (2028, 7, 24)
    (DateTime.utc(2028, 8, 23), 1450, 4, 30),  // (2028, 8, 23)
    (DateTime.utc(2028, 9, 21), 1450, 5, 29),  // (2028, 9, 21)
    (DateTime.utc(2028, 10, 20), 1450, 6, 29),  // (2028, 10, 20)
    (DateTime.utc(2028, 11, 19), 1450, 7, 30),  // (2028, 11, 19)
    (DateTime.utc(2028, 12, 18), 1450, 8, 29),  // (2028, 12, 18)
    (DateTime.utc(2029, 1, 16), 1450, 9, 29),  // (2029, 1, 16)
    (DateTime.utc(2029, 2, 15), 1450, 10, 30),  // (2029, 2, 15)
    (DateTime.utc(2029, 3, 17), 1450, 11, 30),  // (2029, 3, 17)
    (DateTime.utc(2029, 4, 16), 1450, 12, 30),  // (2029, 4, 16)
    (DateTime.utc(2029, 5, 15), 1451, 1, 29),  // (2029, 5, 15)
    (DateTime.utc(2029, 6, 14), 1451, 2, 30),  // (2029, 6, 14)
    (DateTime.utc(2029, 7, 14), 1451, 3, 30),  // (2029, 7, 14)
    (DateTime.utc(2029, 8, 12), 1451, 4, 29),  // (2029, 8, 12)
    (DateTime.utc(2029, 9, 11), 1451, 5, 30),  // (2029, 9, 11)
    (DateTime.utc(2029, 10, 10), 1451, 6, 29),  // (2029, 10, 10)
    (DateTime.utc(2029, 11, 8), 1451, 7, 29),  // (2029, 11, 8)
    (DateTime.utc(2029, 12, 7), 1451, 8, 29),  // (2029, 12, 7)
    (DateTime.utc(2030, 1, 6), 1451, 9, 30),  // (2030, 1, 6)
    (DateTime.utc(2030, 2, 4), 1451, 10, 29),  // (2030, 2, 4)
];

void main() {
  const islamabad = (33.6844, 73.0479);
  const london = (51.5074, -0.1278);

  /// The crescent on the evening of a civil date, at one place.
  CrescentObservation crescent(int year, int month, int day, (double, double) where) =>
      observeEvening(_midnight(year, month, day), where.$1, where.$2)!;

  group('the crescent, measured the way the sighting committees measure it', () {
    test('Ramadan 1447 opens with the crescent of 18 February 2026', () {
      // 17 February: the Moon went down before the Sun did, so the sighting
      // belongs to the following evening — twenty-five hours of lag, and
      // nothing to see either way.
      final night = crescent(2026, 2, 17, islamabad);
      expect(night.lagMinutes, greaterThan(24 * 60));
      expect(night.visibility, closeTo(-11.24, 0.3));
      expect(night.visibleWithAid, isFalse);
      expect(night.verdictUrdu(), 'نظر نہیں آئے گا');

      // 18 February: the crescent stands 11.8 degrees above the Sun and sets
      // 54 minutes after it. Visible to anyone who looks.
      final evening = crescent(2026, 2, 18, islamabad);
      expect(evening.visibility, closeTo(6.69, 0.3));
      expect(evening.arcOfVision, closeTo(11.76, 0.2));
      expect(evening.lagMinutes, closeTo(54.1, 1.0));
      expect(evening.visibleToTheEye, isTrue);
      expect(evening.verdictUrdu(), 'ننگی آنکھ سے دکھائی دے گا');

      // Sunset in Islamabad that evening: 17:55 PKT, 12:55 UT.
      expect(evening.sunset.isAfter(DateTime.utc(2026, 2, 18, 12, 50)), isTrue);
      expect(evening.sunset.isBefore(DateTime.utc(2026, 2, 18, 13, 0)), isTrue);
    });

    test('a crescent that goes down with the Sun cannot be seen', () {
      // 11 October 2026: under a minute of lag, and the Moon is the lower of
      // the two at the best moment.
      final evening = crescent(2026, 10, 11, islamabad);
      expect(evening.visibility, closeTo(-4.29, 0.3));
      expect(evening.visibleWithAid, isFalse);
      expect(evening.verdictUrdu(), 'نظر نہیں آئے گا');
    });

    test('the best time is four ninths of the way from sunset to moonset', () {
      final evening = crescent(2025, 6, 26, islamabad);
      final lag = evening.moonset.difference(evening.sunset).inSeconds / 60.0;
      final best = evening.bestTime.difference(evening.sunset).inSeconds / 60.0;
      expect(best / lag, closeTo(4.0 / 9.0, 0.01));
      expect(evening.visibility, closeTo(9.93, 0.3));
    });

    test('the crescent width is measured in the topocentric semi-diameter', () {
      final evening = crescent(2026, 2, 18, islamabad);
      // W = SD (1 - cos ARCL), and SD is a shade over sixteen arc minutes.
      expect(evening.crescentWidth, closeTo(0.345, 0.02));
      expect(evening.arcOfLight, closeTo(12.02, 0.2));
    });
  });

  group('the month the crescent opens', () {
    test('every month of the table begins where the crescent says it does', () {
      final calendar = LunarHijri(latitude: islamabad.$1, longitude: islamabad.$2);
      for (var i = 1; i < _kMonthStarts.length; i++) {
        final (start, year, month, length) = _kMonthStarts[i];
        final (previous, previousYear, previousMonth, _) = _kMonthStarts[i - 1];
        expect(previousYear * 12 + previousMonth + 1, year * 12 + month,
            reason: 'the table must walk the months in order');

        expect(calendar.dateFor(start), HijriDate(year, month, 1),
            reason: '$start is the first day of $month/$year');
        expect(calendar.civilStartOfMonth(year, month), start);
        expect(calendar.lengthOfMonth(previousYear, previousMonth), length);
        expect(start.difference(previous).inDays, length);
      }
    });

    test('no month is shorter than 29 days, or longer than 30', () {
      final calendar = LunarHijri(latitude: islamabad.$1, longitude: islamabad.$2);
      for (final (_, year, month, _) in _kMonthStarts) {
        expect(calendar.lengthOfMonth(year, month), inInclusiveRange(29, 30));
      }
    });

    test('the sighting of a month is the evening before its first day', () {
      final calendar = LunarHijri(latitude: islamabad.$1, longitude: islamabad.$2);
      expect(calendar.civilStartOfMonth(1447, 9), DateTime.utc(2026, 2, 19));
      final evening = calendar.sightingOfMonth(1447, 9)!;
      expect(evening.sunset.isAfter(DateTime.utc(2026, 2, 18, 12, 50)), isTrue);
      expect(evening.sunset.isBefore(DateTime.utc(2026, 2, 18, 13, 0)), isTrue);
      expect(evening.visibleToTheEye, isTrue);

      // The conjunction opens the month: it is behind the crescent, not ahead
      // of it, and never more than two days behind.
      final conjunction = calendar.conjunctionOfMonth(1447, 9);
      expect(conjunction.isBefore(evening.sunset), isTrue);
      expect(evening.sunset.difference(conjunction).inHours, lessThan(48));
    });

    test('the crescent is read for the reader\'s own sky', () {
      // One day, two cities: on 18 October 2026 London has not yet sighted
      // Jumada al-Ula, so its month runs a day behind Islamabad's.
      final here = LunarHijri(latitude: islamabad.$1, longitude: islamabad.$2);
      final there = LunarHijri(latitude: london.$1, longitude: london.$2);
      final day = DateTime.utc(2026, 10, 18);
      expect(here.dateFor(day), HijriDate(1448, 5, 6));
      expect(there.dateFor(day), HijriDate(1448, 5, 5));
    });
  });

  group('the calendar built on the crescent', () {
    test('the day advances by one, and the month with it', () {
      final calendar = LunarHijri(latitude: islamabad.$1, longitude: islamabad.$2);
      var day = DateTime.utc(2024, 5, 10);
      var previous = calendar.dateFor(day);
      expect(previous, HijriDate(1445, 11, 1));
      day = day.add(const Duration(days: 1));
      final last = DateTime.utc(2030, 2, 3);
      while (day.isBefore(last)) {
        final date = calendar.dateFor(day);
        if (date.day == 1) {
          expect(date.year * 12 + date.month,
              previous.year * 12 + previous.month + 1,
              reason: '$day opens the month after $previous');
          expect(previous.day, inInclusiveRange(29, 30));
        } else {
          expect(date.day, previous.day + 1, reason: '$day follows $previous');
          expect(date.year, previous.year);
          expect(date.month, previous.month);
        }
        previous = date;
        day = day.add(const Duration(days: 1));
      }
      expect(previous, HijriDate(1451, 9, 28));
    });

    test('the manual shift the reader keeps still moves the date', () {
      final calendar = LunarHijri(latitude: islamabad.$1, longitude: islamabad.$2);
      final day = DateTime.utc(2026, 10, 18);
      expect(calendar.dateFor(day), HijriDate(1448, 5, 6));
      expect(calendar.dateFor(day, adjustDays: 1), HijriDate(1448, 5, 7));
      expect(calendar.dateFor(day, adjustDays: -1), HijriDate(1448, 5, 5));
    });

    test('civilDateFor round-trips every Hijri day back to its exact Gregorian day', () {
      final calendar = LunarHijri(latitude: islamabad.$1, longitude: islamabad.$2);
      var day = DateTime.utc(2024, 5, 10);
      final last = DateTime.utc(2030, 2, 3);
      while (day.isBefore(last)) {
        for (final adj in const <int>[-1, 0, 1]) {
          final hijri = calendar.dateFor(day, adjustDays: adj);
          expect(calendar.civilDateFor(hijri, adjustDays: adj), day,
              reason: '$hijri (adj=$adj) must invert back to $day');
        }
        day = day.add(const Duration(days: 1));
      }
      // 30th of a 29-day month (Sha'ban 1447 is 29 days: Jan 21 to Feb 18, 2026)
      // is rejected cleanly instead of rolling into Ramadan.
      expect(calendar.lengthOfMonth(1447, 8), 29);
      expect(calendar.civilDateFor(const HijriDate(1447, 8, 30)), isNull);
    });

    test('a day before the crescent is asked for still answers', () {
      // March 1995 is well before the Umm al-Qura table begins, and the
      // astronomy does not stop where the table does: 29 Ramadan 1415.
      final calendar = LunarHijri(latitude: islamabad.$1, longitude: islamabad.$2);
      expect(calendar.dateFor(DateTime.utc(1995, 3, 2)), HijriDate(1415, 9, 29));
    });
  });
}
