import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../astro/hijri_calendar.dart';
import '../astro/lunar_hijri.dart';
import '../astro/prayer_calculator.dart';
import '../astro/prayer_format.dart';
import 'alerts.dart';
import 'place_names.dart';
import 'prayer_locations.dart';
import 'prayer_notifications.dart';

/// The location chain the controller drives: device fix → IP lookup → null.
typedef LocationResolver = Future<PrayerLocation?> Function();

/// A background fix that never shows a permission prompt.
typedef QuietLocationResolver = Future<DeviceFix> Function();

/// Names a coordinate precisely (the online reverse geocoder).
typedef PlaceNamer = Future<PlaceName?> Function(double latitude, double longitude);

/// Today's Hijri date as the card prints it. After Maghrib the Islamic day has
/// already begun, so the next date is shown as its eve ("شبِ …").
class HijriDay {
  const HijriDay(this.date, {this.eve = false});

  final HijriDate date;
  final bool eve;

  String get labelUrdu => eve ? 'شبِ ${formatHijriUrdu(date)}' : formatHijriUrdu(date);
}

/// A prayer whose time has just arrived — what the home screen turns into a
/// "نماز کا وقت" alert with a Tasbeeh-e-Zahra (s.a.) shortcut.
class PrayerAlertEvent {
  const PrayerAlertEvent({required this.marker, required this.at});

  final PrayerMarker marker;
  final DateTime at;
}

/// One place for everything the three features share:
///
/// * the coordinates (asked for once, stored, reused by the Qibla bearing);
/// * the day's [PrayerSchedule] and the live clock the countdowns read;
/// * the reader's alert/sound/chime preferences;
/// * the prayer-time watcher that fires [PrayerAlertEvent]s.
///
/// It is created once by `main.dart` and passed down, so the Qibla screen never
/// triggers a second location request and the home banner, the timings screen
/// and the compass can never disagree about where the reader is.
class PrayerController extends ChangeNotifier with WidgetsBindingObserver {
  PrayerController({
    DateTime Function()? clock,
    FeedbackSink? feedback,
    LocationResolver? locate,
    QuietLocationResolver? locateQuietly,
    PlaceNamer? namePlace,
  })  : _clock = clock ?? DateTime.now,
        _feedback = feedback ?? Alerts.instance,
        _locate = locate ?? resolveLocation,
        // A test that injects its own location chain gets no GPS and no
        // network behind its back either, unless it asks for them.
        _live = locate == null,
        _locateQuietly = locateQuietly ?? (locate == null ? _quietFix : _noQuietFix),
        _namePlace = namePlace ?? (locate == null ? OnlinePlaces.reverse : _noName) {
    _schedule = PrayerCalculator.schedule(
      latitude: PrayerLocation.fallback.latitude,
      longitude: PrayerLocation.fallback.longitude,
      locationLabel: PrayerLocation.fallback.label,
      clock: _clock(),
    );
    now.value = _displayNow(_clock());
  }

  /// The location chain, injectable so tests never touch the GPS or the
  /// network: a device fix first (named from the offline list), then the IP
  /// lookup, then nothing. Why the fix failed is kept for the screen.
  static Future<PrayerLocation?> resolveLocation() async {
    final fix = await PrayerLocations.deviceFix();
    _resolverProblem = fix.problem;
    if (fix.location != null) return fix.location;
    final ip = await PrayerLocations.fromIp();
    return ip == null ? null : PrayerLocations.localiseIp(ip);
  }

  /// Set by [resolveLocation] for the controller that called it.
  static LocationProblem? _resolverProblem;

  static Future<DeviceFix> _quietFix() => PrayerLocations.deviceFix(interactive: false);

  static Future<DeviceFix> _noQuietFix() async => const DeviceFix.failed(LocationProblem.noFix);

  static Future<PlaceName?> _noName(double latitude, double longitude) async => null;

  static const String presetKeyStorage = 'prayer_preset_v1';
  static const String alertStorage = 'prayer_alert_v1';
  static const String hijriStorage = 'hijri_adjust_v1';

  /// Where the launcher widget reads the next prayer and the Hijri date. The
  /// Android side reads these from the same preferences file.
  static const String widgetNextPrayerKey = 'widget_next_prayer';
  static const String widgetHijriKey = 'widget_hijri';

  /// A GPS location older than this is re-checked quietly on the next launch,
  /// so a reader who travelled sees the new town without touching anything.
  static const Duration staleFixAge = Duration(hours: 3);

  final DateTime Function() _clock;
  final FeedbackSink _feedback;
  final LocationResolver _locate;
  final QuietLocationResolver _locateQuietly;
  final PlaceNamer _namePlace;
  final bool _live;

  /// The live clock in the *location's* zone, ticking once a second. Widgets
  /// that only show a countdown listen to this instead of the whole
  /// controller, so nothing else rebuilds while the app sits open.
  final ValueNotifier<DateTime> now = ValueNotifier<DateTime>(DateTime.now());

  PrayerLocation _location = PrayerLocation.fallback;
  late PrayerSchedule _schedule;
  bool _loadingLocation = false;
  bool _started = false;
  bool _nativeAlertsReady = false;
  bool _nativeNotificationsGranted = false;
  Timer? _ticker;
  String? _lastFiredKey;
  /// The prayer the launcher widget was last told about, so the plate is
  /// written only when the next prayer actually changes.
  PrayerMarker? _widgetMarker;
  final List<PrayerAlertEvent> _pendingAlerts = <PrayerAlertEvent>[];

  bool _alertsEnabled = true;
  bool _soundEnabled = true;
  PrayerSoundMode _soundMode = PrayerSoundMode.shortAzan;
  bool _hapticsEnabled = true;
  String _presetKey = 'jafari';
  LocationProblem? _locationProblem;

  /// Days added to the Hijri date; null means "automatic for this location".
  int? _hijriAdjustment;

  /// The Hijri calendar of the reader's own sky: the new crescent, watched
  /// from their latitude and longitude, opens every month. Nothing about the
  /// date needs setting by hand.
  ///
  /// Made again whenever the coordinates change; the months it has already
  /// worked out travel with it.
  LunarHijri _lunarHijri = LunarHijri(
    latitude: PrayerLocation.fallback.latitude,
    longitude: PrayerLocation.fallback.longitude,
  );

  PrayerLocation get location => _location;

  /// Why the last GPS attempt failed (null when it worked or never ran).
  LocationProblem? get locationProblem => _locationProblem;

  /// The reader's Hijri shift, or null for automatic.
  int? get hijriAdjustment => _hijriAdjustment;

  /// The shift actually applied: the reader's, or the location's default.
  int get effectiveHijriAdjustment =>
      _hijriAdjustment ?? autoHijriAdjustment(_location.latitude, _location.longitude);

  /// The Hijri date for [at] (the location's wall clock), switching to the
  /// next date at Maghrib.
  HijriDay hijriFor(DateTime at) {
    final maghrib = _schedule.entryFor(PrayerMarker.maghrib).time;
    final sameDay =
        maghrib.year == at.year && maghrib.month == at.month && maghrib.day == at.day;
    final eve = sameDay && !at.isBefore(maghrib);
    final civil = DateTime.utc(at.year, at.month, at.day);
    return HijriDay(
      _lunarHijri.dateFor(
        eve ? civil.add(const Duration(days: 1)) : civil,
        adjustDays: _hijriAdjustment ?? 0,
      ),
      eve: eve,
    );
  }

  /// Today's Hijri date at the live clock.
  HijriDay get hijriToday => hijriFor(now.value);

  /// The crescent of the reader's own sky: the evening that opened this
  /// month, and what the next one will do.
  LunarHijri get lunarHijri => _lunarHijri;
  PrayerSchedule get schedule => _schedule;
  bool get loadingLocation => _loadingLocation;
  bool get alertsEnabled => _alertsEnabled;
  bool get soundEnabled => _soundEnabled;
  PrayerSoundMode get soundMode => _soundMode;
  bool get hapticsEnabled => _hapticsEnabled;
  String get presetKey => _presetKey;

  /// Degrees from true north to the Kaaba, from the same coordinates the
  /// timings use.
  double get qiblaBearing =>
      PrayerCalculator.qiblaBearing(_location.latitude, _location.longitude);

  double get distanceToKaabaKm =>
      PrayerCalculator.distanceToKaabaKm(_location.latitude, _location.longitude);

  /// The prayer window running right now.
  PrayerWindow get window => _schedule.window(now.value);

  /// The next countdown target (Fajr, Dhuhr, Asr, Maghrib, Isha, or Nisf al-Layl).
  PrayerEntry get nextEntry => _schedule.nextEntry(now.value);

  /// The prayer the reader has just finished, if any — the trigger for the
  /// post-prayer Tasbeeh-e-Zahra (s.a.) shortcut.
  PrayerMarker? get justPrayed => _schedule.justPrayed(now.value);

  /// Loads stored coordinates and preferences, then starts the clock. Safe to
  /// call twice.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    await _loadPreferences();
    // The clock starts before the location is known, so the card and its
    // countdown are live from the first frame; the times below simply become
    // exact once the coordinates land.
    _rebuildSchedule();
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
    // The first Hijri date costs a few lunations of the Moon's series; it is
    // paid here, off the first frame, and cached for the rest of the day.
    _lunarHijri.dateFor(DateTime.utc(now.value.year, now.value.month, now.value.day));

    final stored = await PrayerLocations.loadStored();
    if (stored != null) {
      // A stored location opens the app offline and instantly with the
      // reader's own city; anything less than a fresh, named GPS fix is then
      // improved quietly in the background — never with a prompt.
      await _applyLocation(stored, persist: false);
      _nativeAlertsReady = true;
      unawaited(_syncNativePrayerNotifications());
      unawaited(_improveInBackground(stored));
      return;
    }
    // First run only: a device fix, then the IP lookup, and Islamabad last.
    await refreshLocation();
    _nativeAlertsReady = true;
    unawaited(_syncNativePrayerNotifications());
  }

  /// After a stored location: name an unnamed fix, re-check a stale one, and
  /// replace a guess (IP, default) with a real fix when the permission is
  /// already there. A manually chosen city is left alone.
  Future<void> _improveInBackground(PrayerLocation stored) async {
    switch (stored.source) {
      case LocationSource.manual:
        return;
      case LocationSource.gps:
        final savedAt = stored.savedAt;
        final stale = savedAt == null || DateTime.now().difference(savedAt) > staleFixAge;
        if (stale) {
          await _quietRefresh(minimumMoveKm: 1.0);
        }
        if (identical(_location, stored)) await _refinePlaceName();
      case LocationSource.ip:
      case LocationSource.fallback:
        final improved = await _quietRefresh(minimumMoveKm: 0);
        if (!improved && _live && identical(_location, stored)) {
          await _promptLocationOnceIfUnanswered(stored);
        }
        if (!improved && stored.source == LocationSource.fallback && _live && identical(_location, stored)) {
          final ip = await PrayerLocations.fromIp();
          if (ip != null && identical(_location, stored)) {
            final named = PrayerLocations.localiseIp(ip);
            await PrayerLocations.store(named);
            await _applyLocation(named, persist: false);
          }
        }
    }
  }

  /// Ensures upgrading users whose previous launch stored an IP or default
  /// fallback without ever answering the OS location prompt are asked once on
  /// startup so prayer times lock onto their exact town automatically.
  Future<void> _promptLocationOnceIfUnanswered(PrayerLocation stored) async {
    const promptKey = 'location_install_prompt_v1';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(promptKey) == true) return;
      await prefs.setBool(promptKey, true);
      final fix = await PrayerLocations.deviceFix(interactive: true);
      _locationProblem = fix.problem;
      if (fix.location != null && identical(_location, stored)) {
        await PrayerLocations.store(fix.location!);
        await _applyLocation(fix.location!, persist: false);
        unawaited(_refinePlaceName());
      } else {
        notifyListeners();
      }
    } catch (_) {
      return;
    }
  }

  /// A fix without a prompt. Applied when it is a different place (more than
  /// [minimumMoveKm] away) or replaces a non-GPS location. True when applied.
  Future<bool> _quietRefresh({required double minimumMoveKm}) async {
    if (_loadingLocation) return false;
    final before = _location;
    final fix = await _locateQuietly();
    final fresh = fix.location;
    if (fresh == null) return false;
    // The reader may have picked a city while the fix was being taken.
    if (!identical(_location, before) || _location.source == LocationSource.manual) {
      return false;
    }
    final moved = PrayerLocations.distanceKm(before, fresh);
    if (before.source == LocationSource.gps && moved < minimumMoveKm) return false;
    _locationProblem = null;
    await PrayerLocations.store(fresh);
    await _applyLocation(fresh, persist: false);
    unawaited(_refinePlaceName());
    return true;
  }

  /// Upgrades the offline name of a GPS fix with the exact place from the
  /// online reverse geocoder ("Islamabad" → "G-11، اسلام آباد").
  Future<void> _refinePlaceName() async {
    final target = _location;
    if (target.source != LocationSource.gps || target.refined) return;
    final name = await _namePlace(target.latitude, target.longitude);
    if (name == null || name.label.trim().isEmpty) return;
    if (!identical(_location, target)) return;
    final refined = PrayerLocation(
      latitude: target.latitude,
      longitude: target.longitude,
      label: name.label.trim(),
      detail: name.detail.trim().isNotEmpty ? name.detail.trim() : target.detail,
      source: target.source,
      savedAt: target.savedAt ?? DateTime.now(),
      accuracyMeters: target.accuracyMeters,
      refined: true,
    );
    await PrayerLocations.store(refined);
    await _applyLocation(refined, persist: false);
  }

  /// The location chain: high-accuracy GPS → IP lookup → whatever is stored →
  /// Islamabad. Returns the location that ended up in use.
  Future<PrayerLocation> refreshLocation() async {
    if (_loadingLocation) return _location;
    _loadingLocation = true;
    notifyListeners();

    _resolverProblem = null;
    final resolved = await _locate();
    _locationProblem = _resolverProblem;
    _resolverProblem = null;
    if (resolved != null) {
      await PrayerLocations.store(resolved);
      await _applyLocation(resolved, persist: false);
      unawaited(_refinePlaceName());
    } else if (_location.isFallback) {
      const seeded = PrayerLocation(
        latitude: kFallbackLatitude,
        longitude: kFallbackLongitude,
        label: 'اسلام آباد (ڈیفالٹ)',
        source: LocationSource.fallback,
      );
      await PrayerLocations.store(seeded);
      await _applyLocation(seeded, persist: false);
    }

    _loadingLocation = false;
    notifyListeners();
    return _location;
  }

  /// Manual city selection from the picker.
  Future<void> useCity(PlaceSuggestion city) async {
    final location = PrayerLocation(
      latitude: city.latitude,
      longitude: city.longitude,
      label: city.nameUrdu,
      detail: city.nameLatin,
      source: LocationSource.manual,
      savedAt: DateTime.now(),
      refined: true,
    );
    _locationProblem = null;
    await _applyLocation(location, persist: true);
  }

  /// Any row of the picker: a curated city, a place from the bundled list, or
  /// an online search result.
  Future<void> usePlace(PlaceResult place) async {
    _locationProblem = null;
    await _applyLocation(
      PrayerLocation(
        latitude: place.latitude,
        longitude: place.longitude,
        label: place.title,
        detail: place.subtitle,
        source: LocationSource.manual,
        savedAt: DateTime.now(),
        refined: true,
      ),
      persist: true,
    );
  }

  /// Coordinates typed straight into the search box. Without a [label] the
  /// place is named from the offline list once it is applied.
  Future<void> useCoordinates(double latitude, double longitude, {String? label}) async {
    final location = PrayerLocation(
      latitude: latitude,
      longitude: longitude,
      label: label ?? 'دستی مقام',
      source: LocationSource.manual,
      savedAt: DateTime.now(),
    );
    _locationProblem = null;
    await _applyLocation(location, persist: true);
    if (label != null || !_live) return;
    final name = await PrayerLocations.nameOffline(latitude, longitude);
    if (name == null || !identical(_location, location)) return;
    await _applyLocation(
      PrayerLocation(
        latitude: latitude,
        longitude: longitude,
        label: name.label,
        detail: name.detail,
        source: LocationSource.manual,
        savedAt: location.savedAt,
        refined: true,
      ),
      persist: true,
    );
  }

  /// Forgets the last GPS problem (the banner was dismissed).
  void clearLocationProblem() {
    if (_locationProblem == null) return;
    _locationProblem = null;
    notifyListeners();
  }

  /// The reader's Hijri shift (−2…+2), or null for automatic.
  void setHijriAdjustment(int? days) {
    final value = days?.clamp(-2, 2);
    if (value == _hijriAdjustment) return;
    _hijriAdjustment = value;
    unawaited(_savePreferences());
    notifyListeners();
  }

  Future<void> _applyLocation(PrayerLocation location, {required bool persist}) async {
    _location = location;
    if (_lunarHijri.latitude != location.latitude ||
        _lunarHijri.longitude != location.longitude) {
      _lunarHijri = LunarHijri(latitude: location.latitude, longitude: location.longitude);
    }
    _rebuildSchedule();
    if (persist) await PrayerLocations.store(location);
    notifyListeners();
  }

  void setPreset(String key) {
    if (_presetKey == key) return;
    _presetKey = key;
    _rebuildSchedule();
    unawaited(_savePreferences());
    notifyListeners();
  }

  void setAlertsEnabled(bool value) {
    if (_alertsEnabled == value) return;
    _alertsEnabled = value;
    unawaited(_savePreferences());
    if (_nativeAlertsReady) {
      if (value && _live) {
        // The toggle is an explicit action, so it is an appropriate moment to
        // request Android 13+ notification and optional exact-alarm access.
        unawaited(requestNativePrayerNotifications());
      } else {
        unawaited(_syncNativePrayerNotifications());
      }
    }
    notifyListeners();
  }

  void setSoundEnabled(bool value) {
    if (_soundEnabled == value) return;
    _soundEnabled = value;
    if (!value) unawaited(_feedback.stopPrayerAudio());
    unawaited(_savePreferences());
    unawaited(_syncNativePrayerNotifications());
    notifyListeners();
  }

  void setSoundMode(PrayerSoundMode mode) {
    if (_soundMode == mode) return;
    _soundMode = mode;
    if (!_soundEnabled) _soundEnabled = true;
    unawaited(_savePreferences());
    unawaited(_syncNativePrayerNotifications());
    notifyListeners();
  }

  /// Plays the currently selected prayer alert audio once as a preview.
  Future<void> previewAlertSound([PrayerSoundMode? overrideMode]) async {
    final mode = overrideMode ?? _soundMode;
    if (mode == PrayerSoundMode.shortAzan) {
      await _feedback.playShortAzan();
    } else {
      await _feedback.playPrayerChime();
    }
  }

  Future<void> stopAlertSoundPreview() => _feedback.stopPrayerAudio();

  void setHapticsEnabled(bool value) {
    if (_hapticsEnabled == value) return;
    _hapticsEnabled = value;
    unawaited(_savePreferences());
    unawaited(_syncNativePrayerNotifications());
    notifyListeners();
  }

  /// Explicit permission action shown alongside the existing alert controls.
  /// Returns whether the platform granted notification permission; exact
  /// alarms can still fall back to Android's inexact while-idle schedule.
  Future<bool> requestNativePrayerNotifications() async {
    if (!_live) return false;
    final granted = await PrayerNotifications.instance.requestPermissions();
    await _syncNativePrayerNotifications();
    return granted;
  }

  /// Pops the oldest prayer alert, if the UI has not consumed it yet.
  PrayerAlertEvent? takePendingAlert() {
    if (_pendingAlerts.isEmpty) return null;
    if (now.value.difference(_pendingAlerts.first.at) > const Duration(minutes: 30)) {
      _pendingAlerts.removeAt(0);
      return takePendingAlert();
    }
    return _pendingAlerts.removeAt(0);
  }

  /// The device clock expressed as the wall clock of the reader's location.
  DateTime _displayNow(DateTime deviceClock) => _schedule.zoneWallClock(deviceClock);

  /// Rebuilds the day for the current location, preset and calendar day, and
  /// re-points the live clock at the display zone.
  void _rebuildSchedule() {
    final raw = _clock();
    _schedule = PrayerCalculator.schedule(
      latitude: _location.latitude,
      longitude: _location.longitude,
      locationLabel: _location.label,
      presetKey: _presetKey,
      clock: raw,
    );
    now.value = _displayNow(raw);
    _widgetMarker = null;
    _syncWidgetData();
    if (_nativeAlertsReady) unawaited(_syncNativePrayerNotifications());
  }

  /// The launcher widget reads the next prayer and the Hijri date from the
  /// app's own preferences, so the plate on the home screen shows the same
  /// times the card in the app does.
  void _syncWidgetData() {
    try {
      final next = _schedule.nextEntry(now.value);
      if (next.marker == _widgetMarker) return;
      _widgetMarker = next.marker;
    } catch (_) {
      return;
    }
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final next = _schedule.nextEntry(now.value);
        await prefs.setString(
          widgetNextPrayerKey,
          'اگلی نماز: ${next.marker.labelUrdu} ${formatClockUrdu(next.time)}',
        );
        await prefs.setString(widgetHijriKey, hijriFor(now.value).labelUrdu);
      } catch (_) {
        return;
      }
    }());
  }

  Future<void> _syncNativePrayerNotifications() async {
    if (!_live || !_nativeAlertsReady) return;
    final notifications = PrayerNotifications.instance;
    _nativeNotificationsGranted = await notifications.notificationsEnabled();
    final reminders = _alertsEnabled ? _buildPrayerReminders() : const <PrayerReminder>[];
    await notifications.synchronize(
      reminders: reminders,
      enabled: _alertsEnabled,
      soundEnabled: _soundEnabled,
      soundMode: _soundMode,
      hapticsEnabled: _hapticsEnabled,
    );
  }

  List<PrayerReminder> _buildPrayerReminders() => PrayerReminderPlanner.plan(
        latitude: _location.latitude,
        longitude: _location.longitude,
        location: _location.label,
        presetKey: _presetKey,
        locationWallClockNow: now.value,
        utcNow: _clock().toUtc(),
        zoneOffset: _schedule.zoneOffset,
      );

  void _tick() {
    final raw = _clock();
    final previous = now.value;
    now.value = _displayNow(raw);

    // Midnight rollover and timezone/DST drift: recompute in place, so the
    // card stays correct even if the app has been open since yesterday or the
    // phone crossed into daylight saving time while it sat in a pocket.
    final crossedDay = now.value.day != previous.day;
    final zoneMoved =
        _schedule.zoneOffset != PrayerCalculator.solarZoneOffset(raw, _location.longitude);
    if (crossedDay || zoneMoved) {
      _rebuildSchedule();
      notifyListeners();
    }

    // The home-screen plate follows the next prayer as the day passes.
    _syncWidgetData();

    _checkPrayerAlerts();
  }

  /// One tick of the clock, without waiting for the timer — used by the tests
  /// (they cannot wait a real second).
  @visibleForTesting
  void tickNow() => _tick();

  void _checkPrayerAlerts() {
    final clock = now.value;
    for (final entry in _schedule.entries) {
      if (entry.marker.isObligatory) {
        final key = '${entry.time.toIso8601String()}:${entry.marker.name}';
        if (key == _lastFiredKey) continue;
        final elapsed = clock.difference(entry.time);
        // Fire once, inside the first minute, and never for a time that was
        // already in the past when the app opened.
        if (elapsed.isNegative || elapsed.inMinutes >= 1) continue;
        _lastFiredKey = key;
        _pendingAlerts.add(PrayerAlertEvent(marker: entry.marker, at: entry.time));
        // A granted native notification also sounds/vibrates when the app is
        // open. Avoid firing the same chime twice; keep the in-process
        // feedback as a fallback when Android notifications are not allowed.
        if (_alertsEnabled && _soundEnabled && !_nativeNotificationsGranted) {
          unawaited(
            _soundMode == PrayerSoundMode.shortAzan
                ? _feedback.playShortAzan()
                : _feedback.playPrayerChime(),
          );
        }
        if (_hapticsEnabled && (!_alertsEnabled || !_nativeNotificationsGranted)) {
          unawaited(_feedback.prayerHaptic());
        }
        notifyListeners();
        return;
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Coming back to the app: catch up on the clock, and recover the day or
    // the zone if either moved while the app slept.
    _rebuildSchedule();
    notifyListeners();
    // The reader may be back from switching the GPS on (or granting the
    // permission) after the app said it was off: try again, quietly.
    if (_locationProblem != null && _location.source != LocationSource.manual) {
      unawaited(_retryAfterResume());
    }
  }

  Future<void> _retryAfterResume() async {
    final applied = await _quietRefresh(minimumMoveKm: 0);
    if (applied) notifyListeners();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _presetKey = prefs.getString(presetKeyStorage) ?? 'jafari';
      final hijri = prefs.getString(hijriStorage);
      _hijriAdjustment = hijri == null || hijri == 'auto' ? null : int.tryParse(hijri)?.clamp(-2, 2);
      final raw = prefs.getString(alertStorage);
      if (raw != null) {
        final stored = Uri.splitQueryString(raw);
        _alertsEnabled = stored['alerts'] != 'false';
        _soundEnabled = stored['sound'] != 'false';
        _soundMode = stored.containsKey('mode')
            ? PrayerSoundMode.fromWire(stored['mode'])
            : PrayerSoundMode.shortAzan;
        _hapticsEnabled = stored['haptics'] != 'false';
      }
    } catch (_) {
      return;
    }
    _rebuildSchedule();
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(presetKeyStorage, _presetKey);
      await prefs.setString(hijriStorage, _hijriAdjustment?.toString() ?? 'auto');
      await prefs.setString(
        alertStorage,
        'alerts=$_alertsEnabled&sound=$_soundEnabled&mode=${_soundMode.wire}&haptics=$_hapticsEnabled',
      );
    } catch (_) {
      return;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    now.dispose();
    super.dispose();
  }
}
