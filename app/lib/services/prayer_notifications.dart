import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../astro/prayer_calculator.dart';
import 'alerts.dart';

/// One native alarm, expressed as an absolute UTC instant. Prayer times in the
/// calculator are location wall-clock values, so the controller converts them
/// back through that schedule's zone offset before creating these reminders.
class PrayerReminder {
  const PrayerReminder({
    required this.id,
    required this.marker,
    required this.atUtc,
    required this.location,
  });

  final int id;
  final PrayerMarker marker;
  final DateTime atUtc;
  final String location;
}

/// Pure planner for rolling prayer reminders; kept separate from platform
/// notifications so timezone and date-rollover behavior is unit-testable.
class PrayerReminderPlanner {
  const PrayerReminderPlanner._();

  static const int horizonDays = 30;

  static List<PrayerReminder> plan({
    required double latitude,
    required double longitude,
    required String location,
    required String presetKey,
    required DateTime locationWallClockNow,
    required DateTime utcNow,
    required Duration zoneOffset,
  }) {
    final firstWallDate = DateTime.utc(
      locationWallClockNow.year,
      locationWallClockNow.month,
      locationWallClockNow.day,
    );
    final reminders = <PrayerReminder>[];

    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final wallDate = firstWallDate.add(Duration(days: dayOffset));
      final locationDay = DateTime.utc(wallDate.year, wallDate.month, wallDate.day);
      // PrayerCalculator accepts a device instant and derives the location's
      // wall date from it. Subtract the known location offset so this schedule
      // lands on exactly the target wall-calendar day.
      final syntheticClock = locationDay.subtract(zoneOffset);
      final daySchedule = PrayerCalculator.schedule(
        latitude: latitude,
        longitude: longitude,
        locationLabel: location,
        presetKey: presetKey,
        clock: syntheticClock,
        zoneOffset: zoneOffset,
      );
      final daySerial = locationDay.difference(DateTime.utc(1970)).inDays;

      for (final entry in daySchedule.obligatory) {
        // PrayerCalculator represents a location wall clock as a UTC-coded
        // DateTime. Rebuild it explicitly as UTC, then remove that wall offset
        // to get the actual instant that the native alarm manager should fire.
        final wallTime = DateTime.utc(
          entry.time.year,
          entry.time.month,
          entry.time.day,
          entry.time.hour,
          entry.time.minute,
          entry.time.second,
        );
        final instant = wallTime.subtract(daySchedule.zoneOffset);
        if (!instant.isAfter(utcNow.toUtc().add(const Duration(seconds: 20)))) continue;
        reminders.add(PrayerReminder(
          id: 200000 + daySerial * 8 + entry.marker.index,
          marker: entry.marker,
          atUtc: instant,
          location: location,
        ));
      }
    }
    return reminders;
  }
}

/// Android/iOS notification scheduling for the five obligatory daily prayers.
///
/// The controller refreshes a rolling month of times whenever location,
/// calculation method, date or notification preferences change. The Android
/// plugin persists its scheduled alarms across process death and device reboot.
class PrayerNotifications {
  PrayerNotifications._();

  static final PrayerNotifications instance = PrayerNotifications._();

  static const int _prayerIdStart = 200000;
  static const int _prayerIdEnd = 1000000;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  Future<void> _queue = Future<void>.value();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> _ensureInitialized() async {
    final pending = _initialization ??= _initialize();
    try {
      await pending;
    } catch (_) {
      if (identical(_initialization, pending)) _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (_) {},
    );

    final android = _android;
    if (android == null) return;
    // Android 8+ fixes sound/vibration on a channel once it is first created.
    // Prepare every sound/vibration combination so switching between silent,
    // soft chime, and short Azan takes effect immediately without mutating a
    // user's existing channel.
    for (final vibration in <bool>[false, true]) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          prayerChannelId(sound: false, vibration: vibration, mode: PrayerSoundMode.chime),
          'نماز کی یاد دہانی (خاموش)',
          description: 'نماز کے اوقات پر ShiaVerse کی اطلاع',
          importance: Importance.max,
          playSound: false,
          enableVibration: vibration,
        ),
      );
      for (final mode in PrayerSoundMode.values) {
        await android.createNotificationChannel(
          AndroidNotificationChannel(
            prayerChannelId(sound: true, vibration: vibration, mode: mode),
            'نماز کی یاد دہانی (${mode.labelUrdu})',
            description: 'نماز کے اوقات پر ShiaVerse کی اطلاع',
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(mode.rawResource),
            enableVibration: vibration,
          ),
        );
      }
    }
  }

  /// Ask only after the reader explicitly asks to enable native prayer alerts.
  /// Exact-alarm access is optional: denied access falls back to an inexact
  /// while-idle alarm instead of silently disabling the reminder altogether.
  Future<bool> requestPermissions() async {
    try {
      await _ensureInitialized();
      final android = _android;
      if (android != null) {
        final result = await android.requestNotificationsPermission();
        if (result == false) return false;
        try {
          final exact = await android.canScheduleExactNotifications();
          if (exact != true) await android.requestExactAlarmsPermission();
        } catch (_) {
          // Android versions/devices without the exact-alarm settings panel
          // still receive the inexact scheduled prayer reminders.
        }
        return true;
      }

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final result = await ios?.requestPermissions(alert: true, badge: false, sound: true);
      return result ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Whether the operating system currently lets this app present alerts.
  /// A false result keeps the existing foreground chime/haptic path active.
  Future<bool> notificationsEnabled() async {
    try {
      await _ensureInitialized();
      final android = _android;
      if (android != null) return await android.areNotificationsEnabled() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final permissions = await ios?.checkPermissions();
      return permissions?.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Serialized so a location change and a preference tap cannot leave a
  /// stale batch of alarms scheduled after the newer one.
  Future<void> synchronize({
    required List<PrayerReminder> reminders,
    required bool enabled,
    required bool soundEnabled,
    required PrayerSoundMode soundMode,
    required bool hapticsEnabled,
  }) {
    final current = _queue.then<void>((_) => _synchronize(
          reminders: reminders,
          enabled: enabled,
          soundEnabled: soundEnabled,
          soundMode: soundMode,
          hapticsEnabled: hapticsEnabled,
        ));
    _queue = current.catchError((Object _) {});
    return current;
  }

  Future<void> _synchronize({
    required List<PrayerReminder> reminders,
    required bool enabled,
    required bool soundEnabled,
    required PrayerSoundMode soundMode,
    required bool hapticsEnabled,
  }) async {
    try {
      await _ensureInitialized();
      await _cancelPrayerReminders();
      if (!enabled) return;

      final exact = await _android?.canScheduleExactNotifications() ?? false;
      final scheduleMode = exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final channel = prayerChannelId(
        sound: soundEnabled,
        vibration: hapticsEnabled,
        mode: soundMode,
      );
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          soundEnabled
              ? 'نماز کی یاد دہانی (${soundMode.labelUrdu})'
              : 'نماز کی یاد دہانی (خاموش)',
          channelDescription: 'نماز کے اوقات پر ShiaVerse کی اطلاع',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          playSound: soundEnabled,
          sound: soundEnabled
              ? RawResourceAndroidNotificationSound(soundMode.rawResource)
              : null,
          enableVibration: hapticsEnabled,
          onlyAlertOnce: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: soundEnabled,
        ),
      );

      for (final reminder in reminders) {
        await _plugin.zonedSchedule(
          reminder.id,
          'نماز کا وقت',
          'وقتِ ${reminder.marker.labelUrdu} ہو گیا ہے · ${reminder.location}',
          tz.TZDateTime.from(reminder.atUtc.toUtc(), tz.UTC),
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: scheduleMode,
          payload: 'prayer:${reminder.marker.name}',
        );
      }
    } catch (_) {
      // A notification permission, exact-alarm setting, or vendor alarm
      // manager can fail independently of reading and prayer-time calculation.
      // Keep the existing in-app alert path working rather than crash the app.
    }
  }

  Future<void> _cancelPrayerReminders() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (request.id >= _prayerIdStart && request.id < _prayerIdEnd) {
        await _plugin.cancel(request.id);
      }
    }
  }

  /// The channel a reminder uses for one sound/vibration combination.
  ///
  /// Android 8+ freezes a channel's sound the first time it is created, so the
  /// id carries the sound: switching from the soft chime to the short Azan must
  /// land on a different channel instead of mutating the reader's own.
  static String prayerChannelId({
    required bool sound,
    required bool vibration,
    required PrayerSoundMode mode,
  }) {
    final soundTag = !sound ? 'silent' : (mode == PrayerSoundMode.shortAzan ? 'short_azan' : 'sound');
    return 'prayer_${soundTag}_${vibration ? 'vibrate' : 'quiet'}';
  }
}
