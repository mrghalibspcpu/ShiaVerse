import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiaverse/astro/hijri_calendar.dart';
import 'package:shiaverse/astro/prayer_calculator.dart';
import 'package:shiaverse/services/alerts.dart';
import 'package:shiaverse/services/place_names.dart';
import 'package:shiaverse/services/prayer_controller.dart';
import 'package:shiaverse/services/prayer_locations.dart';

/// The controller that ties the three features together: the shared location
/// (asked for once), the display-zone clock, the prayer-time watcher that
/// raises the post-prayer Tasbeeh-e-Zahra (s.a.) prompt, and the stored
/// preferences.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A controller with no GPS, no network and no sound.
  Future<PrayerController> controllerFor(
    DateTime Function() clock, {
    PrayerLocation? location,
  }) async {
    final controller = PrayerController(
      clock: clock,
      feedback: const SilentFeedback(),
      locate: () async =>
          location ??
          const PrayerLocation(
            latitude: 33.6844,
            longitude: 73.0479,
            label: 'اسلام آباد',
            source: LocationSource.gps,
          ),
    );
    await controller.start();
    return controller;
  }

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('the published clock is the device instant in the location’s zone', () async {
    // The zone itself is derived from the longitude (see the engine test for
    // the rule); what matters here is that *every* comparison in the app uses
    // that zone rather than the phone's own.
    var device = DateTime.utc(2026, 10, 15, 7, 30);
    final controller = await controllerFor(() => device);
    final offset = controller.schedule.zoneOffset;
    expect(controller.now.value, controller.schedule.zoneWallClock(device));
    expect(controller.now.value.isAtSameMomentAs(device.add(offset)), isTrue);
    // And it ticks with the device clock.
    device = device.add(const Duration(seconds: 1));
    controller.tickNow();
    expect(controller.now.value.second, controller.schedule.zoneWallClock(device).second);
    expect(controller.now.value.difference(controller.schedule.zoneWallClock(DateTime.utc(2026, 10, 15, 7, 30))).inSeconds, 1);
  });

  test('the coordinates feed the Qibla bearing and the distance in one step', () async {
    final controller = await controllerFor(() => DateTime.utc(2026, 10, 15, 6));
    expect(controller.qiblaBearing, closeTo(255.91, 0.05));
    expect(controller.distanceToKaabaKm, closeTo(3528, 150));
    expect(controller.location.label, 'اسلام آباد');
    expect(controller.location.source, LocationSource.gps);
  });

  test('a prayer time arriving raises exactly one alert', () async {
    var device = DateTime.utc(2026, 10, 15, 6);
    final controller = await controllerFor(() => device);
    final offset = controller.schedule.zoneOffset;
    final dhuhr = controller.schedule.entryFor(PrayerMarker.dhuhr).time;

    // Two seconds after Dhuhr, in the device's own terms.
    device = dhuhr.subtract(offset).add(const Duration(seconds: 2));
    controller.tickNow();

    final alert = controller.takePendingAlert();
    expect(alert, isNotNull);
    expect(alert!.marker, PrayerMarker.dhuhr);
    expect(alert.at, dhuhr);
    // Drained: the prompt must not reappear on the next tick.
    expect(controller.takePendingAlert(), isNull);
    device = device.add(const Duration(seconds: 1));
    controller.tickNow();
    expect(controller.takePendingAlert(), isNull);
  });

  test('the watcher ignores prayers that were already past when the app opened', () async {
    var device = DateTime.utc(2026, 10, 15, 6);
    final controller = await controllerFor(() => device);
    final offset = controller.schedule.zoneOffset;
    final dhuhr = controller.schedule.entryFor(PrayerMarker.dhuhr).time;
    // Open the app two hours after Dhuhr: the time is history, not news.
    device = dhuhr.subtract(offset).add(const Duration(hours: 2));
    controller.tickNow();
    expect(controller.takePendingAlert(), isNull);
    expect(controller.justPrayed, isNull, reason: 'the grace period is long over');
  });

  test('the alert follows the chosen preset', () async {
    var device = DateTime.utc(2026, 10, 15, 6);
    final controller = await controllerFor(() => device);
    final offset = controller.schedule.zoneOffset;
    final jafariFajr = controller.schedule.entryFor(PrayerMarker.fajr).time;

    controller.setPreset('leva');
    expect(controller.presetKey, 'leva');
    final levaFajr = controller.schedule.entryFor(PrayerMarker.fajr).time;
    expect(levaFajr.isBefore(jafariFajr), isTrue);

    // The Tehran preset moves Fajr about eight minutes earlier, so a clock
    // that was waiting for the Jafari Fajr is already inside its window.
    device = levaFajr.subtract(offset).add(const Duration(seconds: 3));
    controller.tickNow();
    final alert = controller.takePendingAlert();
    expect(alert?.marker, PrayerMarker.fajr);
    expect(alert?.at, levaFajr);
  });

  test('a manual city replaces the fix without another location request', () async {
    var requests = 0;
    final controller = PrayerController(
      clock: () => DateTime.utc(2026, 10, 15, 6),
      feedback: const SilentFeedback(),
      locate: () async {
        requests++;
        return const PrayerLocation(
          latitude: 33.6844,
          longitude: 73.0479,
          label: 'اسلام آباد',
          source: LocationSource.gps,
        );
      },
    );
    await controller.start();
    expect(requests, 1);
    await controller.useCity(
      const PlaceSuggestion('کربلا', 'Karbala', 32.6160, 44.0249),
    );
    expect(controller.location.label, 'کربلا');
    expect(controller.location.source, LocationSource.manual);
    expect(controller.qiblaBearing, closeTo(199.47, 0.1));
    expect(requests, 1, reason: 'picking a city must not re-run the location chain');
  });

  test('a stored location is used on the next launch, offline and instantly', () async {
    await PrayerLocations.store(
      const PrayerLocation(
        latitude: 24.8607,
        longitude: 67.0011,
        label: 'کراچی',
        source: LocationSource.manual,
      ),
    );
    var requests = 0;
    final controller = PrayerController(
      clock: () => DateTime.utc(2026, 10, 15, 6),
      feedback: const SilentFeedback(),
      locate: () async {
        requests++;
        return null;
      },
    );
    await controller.start();
    expect(controller.location.label, 'کراچی');
    expect(controller.qiblaBearing, closeTo(267.74, 0.05));
    expect(requests, 0, reason: 'a stored location means no location request at all');
  });

  test('with no fix, no IP and nothing stored, the fallback keeps the card alive', () async {
    final controller = PrayerController(
      clock: () => DateTime.utc(2026, 10, 15, 6),
      feedback: const SilentFeedback(),
      locate: () async => null,
    );
    await controller.start();
    expect(controller.location.isFallback, isTrue);
    expect(controller.location.latitude, closeTo(33.6844, 1e-9));
    final resolved = await controller.refreshLocation();
    expect(resolved.isFallback, isTrue);
    expect(controller.schedule.entries.length, 8);
  });

  test('the alert, sound and vibration switches persist', () async {
    final controller = await controllerFor(() => DateTime.utc(2026, 10, 15, 6));
    expect(controller.alertsEnabled, isTrue);
    expect(controller.soundEnabled, isTrue);
    expect(controller.soundMode, PrayerSoundMode.shortAzan);
    controller.setSoundMode(PrayerSoundMode.chime);
    controller.setAlertsEnabled(false);
    controller.setSoundEnabled(false);
    controller.setHapticsEnabled(false);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final reloaded = PrayerController(
      clock: () => DateTime.utc(2026, 10, 15, 6),
      feedback: const SilentFeedback(),
      locate: () async => null,
    );
    await reloaded.start();
    expect(reloaded.alertsEnabled, isFalse);
    expect(reloaded.soundEnabled, isFalse);
    expect(reloaded.soundMode, PrayerSoundMode.chime);
    expect(reloaded.hapticsEnabled, isFalse);
  });

  test('justPrayed exposes the post-prayer shortcut for the home screen', () async {
    var device = DateTime.utc(2026, 10, 15, 6);
    final controller = await controllerFor(() => device);
    final offset = controller.schedule.zoneOffset;
    final maghrib = controller.schedule.entryFor(PrayerMarker.maghrib).time;

    expect(controller.justPrayed, isNull);
    device = maghrib.subtract(offset).add(const Duration(minutes: 4));
    controller.tickNow();
    expect(controller.justPrayed, PrayerMarker.maghrib);
    expect(controller.window.marker, PrayerMarker.maghrib);
    expect(controller.nextEntry.marker, PrayerMarker.isha);
  });

  group('1.9: exact place names, quiet re-detection, Hijri date', () {
    const gpsFix = PrayerLocation(
      latitude: 33.6686,
      longitude: 72.9973,
      label: 'اسلام آباد',
      source: LocationSource.gps,
    );

    test('a GPS fix is renamed with the exact place once the namer answers', () async {
      final controller = PrayerController(
        clock: () => DateTime.utc(2026, 10, 15, 6),
        feedback: const SilentFeedback(),
        locate: () async => gpsFix,
        namePlace: (latitude, longitude) async =>
            const PlaceName(label: 'G-11، اسلام آباد', detail: 'اسلام آباد، پاکستان'),
      );
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.location.label, 'G-11، اسلام آباد');
      expect(controller.location.detail, 'اسلام آباد، پاکستان');
      expect(controller.location.refined, isTrue);
      expect(controller.location.latitude, closeTo(33.6686, 1e-9));
      final stored = await PrayerLocations.loadStored();
      expect(stored!.label, 'G-11، اسلام آباد');
      expect(stored.refined, isTrue);
    });

    test('a city picked while the namer is busy is never overwritten', () async {
      final answer = Completer<PlaceName?>();
      final controller = PrayerController(
        clock: () => DateTime.utc(2026, 10, 15, 6),
        feedback: const SilentFeedback(),
        locate: () async => gpsFix,
        namePlace: (latitude, longitude) => answer.future,
      );
      await controller.start();
      await controller.useCity(const PlaceSuggestion('کربلا', 'Karbala', 32.6160, 44.0249));
      answer.complete(const PlaceName(label: 'G-11'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.location.label, 'کربلا');
      expect(controller.location.source, LocationSource.manual);
    });

    test('a stored IP guess is replaced by a quiet GPS fix on the next launch', () async {
      await PrayerLocations.store(
        const PrayerLocation(
          latitude: 33.7,
          longitude: 73.0,
          label: 'Islamabad, Pakistan',
          source: LocationSource.ip,
        ),
      );
      var prompts = 0;
      final controller = PrayerController(
        clock: () => DateTime.utc(2026, 10, 15, 6),
        feedback: const SilentFeedback(),
        locate: () async {
          prompts++;
          return null;
        },
        locateQuietly: () async => const DeviceFix(
          PrayerLocation(
            latitude: 32.933,
            longitude: 72.854,
            label: 'چکوال',
            source: LocationSource.gps,
          ),
        ),
      );
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.location.label, 'چکوال');
      expect(controller.location.source, LocationSource.gps);
      expect(prompts, 0, reason: 'the background check never shows a permission prompt');
      expect((await PrayerLocations.loadStored())!.label, 'چکوال');
    });

    test('a fresh fix is left alone; a stale one is re-checked and moves only for a real move', () async {
      var quietCalls = 0;
      await PrayerLocations.store(
        PrayerLocation(
          latitude: 33.6844,
          longitude: 73.0479,
          label: 'اسلام آباد',
          source: LocationSource.gps,
          savedAt: DateTime.now(),
          refined: true,
        ),
      );
      final fresh = PrayerController(
        clock: () => DateTime.utc(2026, 10, 15, 6),
        feedback: const SilentFeedback(),
        locate: () async => null,
        locateQuietly: () async {
          quietCalls++;
          return const DeviceFix.failed(LocationProblem.noFix);
        },
      );
      await fresh.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(quietCalls, 0);

      await PrayerLocations.store(
        PrayerLocation(
          latitude: 33.6844,
          longitude: 73.0479,
          label: 'اسلام آباد',
          source: LocationSource.gps,
          savedAt: DateTime.now().subtract(const Duration(days: 1)),
          refined: true,
        ),
      );
      final stale = PrayerController(
        clock: () => DateTime.utc(2026, 10, 15, 6),
        feedback: const SilentFeedback(),
        locate: () async => null,
        locateQuietly: () async {
          quietCalls++;
          // 300 m away: the same place, not a journey.
          return const DeviceFix(
            PrayerLocation(latitude: 33.6871, longitude: 73.0479, label: 'x', source: LocationSource.gps),
          );
        },
      );
      await stale.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(quietCalls, 1);
      expect(stale.location.label, 'اسلام آباد');
    });

    test('a manually chosen city is never re-detected', () async {
      await PrayerLocations.store(
        PrayerLocation(
          latitude: 32.6160,
          longitude: 44.0249,
          label: 'کربلا',
          source: LocationSource.manual,
          savedAt: DateTime.now().subtract(const Duration(days: 30)),
        ),
      );
      var quietCalls = 0;
      final controller = PrayerController(
        clock: () => DateTime.utc(2026, 10, 15, 6),
        feedback: const SilentFeedback(),
        locate: () async => null,
        locateQuietly: () async {
          quietCalls++;
          return const DeviceFix(gpsFix);
        },
      );
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(quietCalls, 0);
      expect(controller.location.label, 'کربلا');
    });

    test('any picker row can become the location', () async {
      final controller = await controllerFor(() => DateTime.utc(2026, 10, 15, 6));
      await controller.usePlace(
        const PlaceResult(
          title: 'Kharmang',
          subtitle: 'Gilgit-Baltistan، پاکستان',
          latitude: 34.94,
          longitude: 76.22,
          origin: PlaceOrigin.online,
        ),
      );
      expect(controller.location.label, 'Kharmang');
      expect(controller.location.detail, 'Gilgit-Baltistan، پاکستان');
      expect(controller.location.source, LocationSource.manual);
      expect((await PrayerLocations.loadStored())!.label, 'Kharmang');
    });

    test('the Hijri date turns at Maghrib and follows the reader\'s shift', () async {
      var device = DateTime.utc(2026, 10, 15, 6);
      final controller = await controllerFor(() => device);
      // The crescent, not a printed table: read from Islamabad it opens
      // Jumada al-Awwal on 13 October 2026, a day behind Umm al-Qura.
      expect(controller.hijriAdjustment, isNull);
      expect(controller.effectiveHijriAdjustment, -1);
      expect(controller.hijriToday.date, const HijriDate(1448, 5, 3));
      expect(controller.hijriToday.eve, isFalse);

      final offset = controller.schedule.zoneOffset;
      final maghrib = controller.schedule.entryFor(PrayerMarker.maghrib).time;
      device = maghrib.subtract(offset).add(const Duration(minutes: 1));
      controller.tickNow();
      expect(controller.hijriToday.eve, isTrue);
      expect(controller.hijriToday.date, const HijriDate(1448, 5, 4));
      expect(controller.hijriToday.labelUrdu, startsWith('شبِ'));

      // Nothing needs shifting: the sighting has already been read. A shift
      // is only for a reader whose own calendar differs by a day or two.
      controller.setHijriAdjustment(0);
      expect(controller.hijriToday.date, const HijriDate(1448, 5, 4));
      controller.setHijriAdjustment(1);
      expect(controller.hijriToday.date, const HijriDate(1448, 5, 5));
      controller.setHijriAdjustment(7);
      expect(controller.hijriAdjustment, 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final reloaded = PrayerController(
        clock: () => device,
        feedback: const SilentFeedback(),
        locate: () async => null,
      );
      await reloaded.start();
      expect(reloaded.hijriAdjustment, 2);
      reloaded.setHijriAdjustment(null);
      expect(reloaded.effectiveHijriAdjustment, -1);
    });
  });
}
