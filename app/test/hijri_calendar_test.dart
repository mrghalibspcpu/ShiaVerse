import 'package:flutter_test/flutter_test.dart';
import 'package:shiaverse/astro/hijri_calendar.dart';
import 'package:shiaverse/astro/prayer_calculator.dart';
import 'package:shiaverse/astro/sky_phase.dart';

/// The Hijri date on the prayer card and the four skies behind it.
///
/// The expected dates are the Umm al-Qura calendar as `hijri-converter`
/// (Python) prints them for the same days.
void main() {
  group('Umm al-Qura dates', () {
    test('known days convert exactly', () {
      expect(HijriDate.fromGregorian(DateTime(2026, 10, 15)), const HijriDate(1448, 5, 4));
      expect(HijriDate.fromGregorian(DateTime(2025, 6, 26)), const HijriDate(1447, 1, 1));
      expect(HijriDate.fromGregorian(DateTime(2025, 7, 5)), const HijriDate(1447, 1, 10));
      expect(HijriDate.fromGregorian(DateTime(2026, 2, 18)), const HijriDate(1447, 9, 1));
      expect(HijriDate.fromGregorian(DateTime(2026, 3, 20)), const HijriDate(1447, 10, 1));
    });

    test('only the date fields are read, so UTC-coded wall clocks work too', () {
      expect(
        HijriDate.fromGregorian(DateTime.utc(2026, 10, 15, 23, 59)),
        HijriDate.fromGregorian(DateTime(2026, 10, 15, 0, 1)),
      );
    });

    test('the moon-sighting shift moves the date by whole days', () {
      expect(HijriDate.fromGregorian(DateTime(2026, 10, 15), adjustDays: -1), const HijriDate(1448, 5, 3));
      expect(HijriDate.fromGregorian(DateTime(2026, 10, 15), adjustDays: 1), const HijriDate(1448, 5, 5));
      // Across a month boundary: 1 Muharram 1447 minus a day is the 29th or
      // 30th of Dhu al-Hijjah 1446.
      final eve = HijriDate.fromGregorian(DateTime(2025, 6, 26), adjustDays: -1);
      expect(eve.year, 1446);
      expect(eve.month, 12);
      expect(eve.day, greaterThanOrEqualTo(29));
    });

    test('outside the table the arithmetical calendar takes over', () {
      expect(HijriDate.fromGregorian(DateTime(1990, 1, 1)), const HijriDate(1410, 6, 3));
      expect(HijriDate.fromGregorian(DateTime(2080, 6, 15)), const HijriDate(1503, 8, 26));
    });

    test('every day of the table is a valid date, and days advance one at a time', () {
      final start = DateTime.utc(2009, 1, 1);
      var previous = HijriDate.fromGregorian(start);
      for (var day = 1; day < 365 * 48; day++) {
        final civil = start.add(Duration(days: day));
        final date = HijriDate.fromGregorian(civil);
        expect(date.month, inInclusiveRange(1, 12));
        expect(date.day, inInclusiveRange(1, 30));
        expect(date.toGregorian(), civil);
        final nextDay = date.day == previous.day + 1 && date.month == previous.month;
        final nextMonth = date.day == 1 &&
            previous.day >= 29 &&
            (date.month == previous.month + 1 || (date.month == 1 && previous.month == 12));
        expect(nextDay || nextMonth, isTrue, reason: '$previous → $date');
        previous = date;
      }
    });

    test('tabular Hijri toGregorian round-trips outside the Umm al-Qura table', () {
      for (final civil in <DateTime>[
        DateTime.utc(1990, 1, 1),
        DateTime.utc(2000, 12, 27),
        DateTime.utc(2080, 6, 15),
      ]) {
        final hijri = HijriDate.fromGregorian(civil);
        expect(hijri.toGregorian(), civil);
      }
    });
  });

  group('formatting and the default shift', () {
    test('month names and the printed date', () {
      expect(kHijriMonthsUrdu.length, 12);
      expect(kHijriMonthsUrdu.first, 'محرم');
      expect(kHijriMonthsUrdu[8], 'رمضان');
      expect(formatHijriUrdu(const HijriDate(1448, 5, 4)), '4 جمادی الاول 1448ھ');
    });

    test('South Asia starts a day behind Makkah by default, elsewhere not', () {
      expect(autoHijriAdjustment(33.68, 73.05), -1); // Islamabad
      expect(autoHijriAdjustment(24.86, 67.00), -1); // Karachi
      expect(autoHijriAdjustment(28.61, 77.21), -1); // Delhi
      expect(autoHijriAdjustment(32.00, 44.33), 0); // Najaf
      expect(autoHijriAdjustment(51.51, -0.13), 0); // London
    });
  });

  group('sky phases', () {
    PrayerSchedule day() {
      DateTime at(int hour, int minute) => DateTime.utc(2026, 10, 15, hour, minute);
      return PrayerSchedule(
        locationLabel: 'ٹیسٹ',
        latitude: 33.6844,
        longitude: 73.0479,
        zoneOffset: Duration.zero,
        methodLabel: 'جعفری',
        maghribAngle: 4,
        entries: <PrayerEntry>[
          PrayerEntry(marker: PrayerMarker.fajr, time: at(5, 0)),
          PrayerEntry(marker: PrayerMarker.sunrise, time: at(6, 30)),
          PrayerEntry(marker: PrayerMarker.dhuhr, time: at(12, 30)),
          PrayerEntry(marker: PrayerMarker.asr, time: at(15, 30)),
          PrayerEntry(marker: PrayerMarker.sunset, time: at(18, 0)),
          PrayerEntry(marker: PrayerMarker.maghrib, time: at(18, 12)),
          PrayerEntry(marker: PrayerMarker.isha, time: at(19, 20)),
          PrayerEntry(marker: PrayerMarker.midnight, time: at(23, 30)),
        ],
        fajrTomorrow: DateTime.utc(2026, 10, 16, 5, 0),
      );
    }

    SkyPhase phaseAt(int hour, int minute) =>
        skyPhaseFor(day(), DateTime.utc(2026, 10, 15, hour, minute));

    test('the sky follows the prayer times', () {
      expect(phaseAt(3, 0), SkyPhase.night);
      expect(phaseAt(4, 0), SkyPhase.sehr, reason: 'sehri starts 90 minutes before Fajr');
      expect(phaseAt(5, 0), SkyPhase.dawn);
      expect(phaseAt(7, 5), SkyPhase.dawn, reason: 'dawn lasts a little past sunrise');
      expect(phaseAt(7, 15), SkyPhase.morning, reason: 'morning follows the Fajr glow');
      expect(phaseAt(11, 0), SkyPhase.day, reason: 'dopahar follows the morning');
      expect(phaseAt(15, 29), SkyPhase.day);
      expect(phaseAt(15, 30), SkyPhase.evening);
      expect(phaseAt(18, 30), SkyPhase.evening, reason: 'the glow lingers after Maghrib');
      expect(phaseAt(18, 40), SkyPhase.night);
      expect(phaseAt(23, 59), SkyPhase.night);
    });

    test('every sky has its own painting and an Urdu name', () {
      final assets = SkyPhase.values.map((phase) => phase.asset).toSet();
      expect(assets.length, 6);
      for (final phase in SkyPhase.values) {
        expect(phase.asset, startsWith('assets/images/sky_'));
        expect(phase.labelUrdu, isNotEmpty);
      }
    });
  });
}
