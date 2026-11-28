import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiaverse/astro/prayer_calculator.dart';
import 'package:shiaverse/services/alerts.dart';
import 'package:shiaverse/services/prayer_notifications.dart';

void main() {
  group('notification channels', () {
    test('every sound and vibration combination has its own channel', () {
      final ids = <String>{
        for (final vibration in <bool>[false, true]) ...<String>[
          PrayerNotifications.prayerChannelId(
            sound: false,
            vibration: vibration,
            mode: PrayerSoundMode.chime,
          ),
          for (final mode in PrayerSoundMode.values)
            PrayerNotifications.prayerChannelId(
              sound: true,
              vibration: vibration,
              mode: mode,
            ),
        ],
      };
      // A silent channel, a chime channel, and a short-Azan channel, each in a
      // vibrating and a quiet edition: six channels, all distinct.
      expect(ids, <String>{
        'prayer_silent_quiet',
        'prayer_silent_vibrate',
        'prayer_sound_quiet',
        'prayer_sound_vibrate',
        'prayer_short_azan_quiet',
        'prayer_short_azan_vibrate',
      });
    });

    test('the short Azan is the default sound and carries a real file', () {
      expect(PrayerSoundMode.shortAzan.rawResource, 'shiaverse_short_azan');
      expect(PrayerSoundMode.shortAzan.assetPath, 'audio/azan_short.wav');
      expect(PrayerSoundMode.fromWire('short_azan'), PrayerSoundMode.shortAzan);
      expect(PrayerSoundMode.fromWire('chime'), PrayerSoundMode.chime);
      expect(PrayerSoundMode.fromWire(null), PrayerSoundMode.chime);
      // Both copies ship: the notification channel plays the raw resource and
      // the in-app preview plays the bundled asset.
      final raw = File('android/app/src/main/res/raw/shiaverse_short_azan.wav');
      final asset = File('assets/audio/azan_short.wav');
      expect(raw.existsSync(), isTrue, reason: 'the channel needs its raw resource');
      expect(asset.existsSync(), isTrue, reason: 'the preview needs the asset');
      expect(raw.lengthSync(), greaterThan(200000));
      expect(raw.lengthSync(), asset.lengthSync());
    });
  });

  group('PrayerReminderPlanner', () {
    const offset = Duration(hours: 5);
    const latitude = 33.6844;
    const longitude = 73.0479;
    const location = 'اسلام آباد';
    const preset = 'jafari';

    test('keeps a rolling 30-day schedule for the five obligatory prayers', () {
      final wallNow = DateTime.utc(2026, 10, 15);
      final schedule = PrayerCalculator.schedule(
        latitude: latitude,
        longitude: longitude,
        locationLabel: location,
        presetKey: preset,
        clock: wallNow.subtract(offset),
        zoneOffset: offset,
      );
      final reminders = PrayerReminderPlanner.plan(
        latitude: latitude,
        longitude: longitude,
        location: location,
        presetKey: preset,
        locationWallClockNow: wallNow,
        utcNow: wallNow.subtract(offset),
        zoneOffset: offset,
      );

      expect(reminders, hasLength(PrayerReminderPlanner.horizonDays * 5));
      expect(reminders.map((reminder) => reminder.id).toSet(), hasLength(reminders.length));
      expect(
        reminders.map((reminder) => reminder.marker).toSet(),
        <PrayerMarker>{
          PrayerMarker.fajr,
          PrayerMarker.dhuhr,
          PrayerMarker.asr,
          PrayerMarker.maghrib,
          PrayerMarker.isha,
        },
      );
      expect(reminders.every((reminder) => reminder.atUtc.isAfter(wallNow.subtract(offset))), isTrue);
      expect(reminders.every((reminder) => reminder.location == location), isTrue);

      final dhuhr = reminders.firstWhere((reminder) => reminder.marker == PrayerMarker.dhuhr);
      final wallDhuhr = schedule.entryFor(PrayerMarker.dhuhr).time;
      expect(
        dhuhr.atUtc,
        DateTime.utc(
          wallDhuhr.year,
          wallDhuhr.month,
          wallDhuhr.day,
          wallDhuhr.hour,
          wallDhuhr.minute,
          wallDhuhr.second,
        ).subtract(offset),
      );
    });

    test('does not schedule a prayer whose location-wall time has passed', () {
      final wallNow = DateTime.utc(2026, 10, 15, 8);
      final utcNow = wallNow.subtract(offset);
      final reminders = PrayerReminderPlanner.plan(
        latitude: latitude,
        longitude: longitude,
        location: location,
        presetKey: preset,
        locationWallClockNow: wallNow,
        utcNow: utcNow,
        zoneOffset: offset,
      );

      expect(
        reminders.where((reminder) => reminder.atUtc.isAtSameMomentAs(utcNow) || reminder.atUtc.isBefore(utcNow)),
        isEmpty,
      );
      expect(
        reminders.where((reminder) => reminder.atUtc.isAfter(utcNow)).length,
        greaterThanOrEqualTo((PrayerReminderPlanner.horizonDays - 1) * 5),
      );
    });
  });
}
