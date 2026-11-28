import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../astro/compass_math.dart' show compassPointUrdu;
import '../astro/prayer_calculator.dart';
import '../astro/prayer_format.dart';
import '../services/alerts.dart';
import '../services/city_index.dart';
import '../services/place_names.dart';
import '../services/prayer_controller.dart';
import '../services/prayer_locations.dart';
import '../services/prayer_scope.dart';
import '../astro/sky_phase.dart';
import '../widgets/glass_panel.dart';
import '../widgets/sky_backdrop.dart';
import 'qibla_screen.dart';
import 'tasbeeh_screen.dart';

/// Opens the location picker (search 73,000 places offline, any village
/// online, GPS, or raw coordinates).
Future<void> openLocationPicker(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const LocationPickerSheet(),
  );
}

/// Takes a fresh GPS fix and, when the phone could not give one, says why and
/// offers the one button that fixes it (switch location on, grant the
/// permission, open the app settings, or try again).
Future<bool> refreshLocationWithFeedback(BuildContext context) async {
  final controller = PrayerScope.read(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  await controller.refreshLocation();
  final problem = controller.locationProblem;
  if (problem == null) {
    final location = controller.location;
    messenger?.showSnackBar(
      SnackBar(
        content: Text('مقام: ${location.label}', style: const TextStyle(fontSize: 14)),
        duration: const Duration(seconds: 2),
      ),
    );
    return true;
  }
  messenger?.showSnackBar(locationProblemSnackBar(problem, controller));
  return false;
}

/// The snack bar for a failed fix, with the action that resolves it.
SnackBar locationProblemSnackBar(LocationProblem problem, PrayerController controller) {
  return SnackBar(
    duration: const Duration(seconds: 7),
    content: Text(problem.messageUrdu, style: const TextStyle(fontSize: 14, height: 1.4)),
    action: SnackBarAction(
      label: problem.actionUrdu,
      onPressed: () => unawaited(resolveLocationProblem(problem, controller)),
    ),
  );
}

/// Runs the fix for a location problem.
Future<void> resolveLocationProblem(LocationProblem problem, PrayerController controller) async {
  switch (problem) {
    case LocationProblem.servicesOff:
      // The controller retries by itself when the reader comes back.
      await PrayerLocations.openLocationSettings();
    case LocationProblem.permissionDeniedForever:
      await PrayerLocations.openAppSettings();
    case LocationProblem.permissionDenied:
    case LocationProblem.noFix:
      await controller.refreshLocation();
  }
}

/// Shia (Jafari) prayer timings for the reader's own location: a hero header
/// painted over the sky of the hour, the day's times on glass, the live
/// countdown to the next prayer, and the alert controls.
class PrayerTimesScreen extends StatefulWidget {
  const PrayerTimesScreen({super.key});

  @override
  State<PrayerTimesScreen> createState() => _PrayerTimesScreenState();
}

class _PrayerTimesScreenState extends State<PrayerTimesScreen> {
  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.of(context);
    final controller = PrayerScope.of(context);
    final schedule = controller.schedule;
    final problem = controller.locationProblem;

    return Scaffold(
      backgroundColor: palette.scaffold,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text('نماز کے اوقات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        actions: <Widget>[
          IconButton(
            tooltip: 'قبلہ نما',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const QiblaScreen()),
            ),
            icon: const Icon(Icons.explore_outlined),
          ),
          IconButton(
            tooltip: 'میرا مقام تازہ کریں',
            onPressed: controller.loadingLocation
                ? null
                : () => unawaited(refreshLocationWithFeedback(context)),
            icon: controller.loadingLocation
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 26),
        children: <Widget>[
          if (problem != null) ...<Widget>[
            _LocationProblemBanner(problem: problem, controller: controller),
            const SizedBox(height: 12),
          ],
          _HeroHeader(schedule: schedule, controller: controller),
          const SizedBox(height: 12),
          _LocationDetailsContainer(controller: controller),
          const SizedBox(height: 12),
          _NextPrayerCard(controller: controller, schedule: schedule),
          const SizedBox(height: 12),
          _DetailTiles(schedule: schedule, controller: controller),
          const SizedBox(height: 12),
          _AlertControls(
            controller: controller,
            onPickLocation: () => unawaited(openLocationPicker(context)),
          ),
          const SizedBox(height: 12),
          _FiqhNote(schedule: schedule),
        ],
      ),
    );
  }
}

/// Shown while the last GPS attempt has an unresolved problem.
class _LocationProblemBanner extends StatelessWidget {
  const _LocationProblemBanner({required this.problem, required this.controller});

  final LocationProblem problem;
  final PrayerController controller;

  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.of(context);
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      fill: palette.goldSoft,
      border: palette.gold.withValues(alpha: 0.45),
      child: Row(
        children: <Widget>[
          Icon(Icons.location_off_outlined, size: 22, color: palette.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  problem.messageUrdu,
                  style: TextStyle(fontSize: 14, height: 1.5, color: palette.ink, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'ابھی اوقات: ${controller.location.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: palette.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => unawaited(resolveLocationProblem(problem, controller)),
                child: Text(problem.actionUrdu, style: const TextStyle(fontSize: 13)),
              ),
              TextButton(
                onPressed: controller.clearLocationProblem,
                child: const Text('ٹھیک ہے', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// White text with a soft shadow for the sky header.
TextStyle _sky(double size, {FontWeight weight = FontWeight.w600, double alpha = 1, Color? color, bool digits = false, double? height}) =>
    TextStyle(
      fontFamily: digits ? kDigitFont : null,
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: (color ?? Colors.white).withValues(alpha: alpha),
      fontFeatures: digits ? const <FontFeature>[FontFeature.tabularFigures()] : null,
      shadows: const <Shadow>[Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1))],
    );

const Color _skyGold = Color(0xFFFFE1A1);

/// The detailed prayer page has its own portrait mosque wallpaper. The mini
/// prayer card on Home continues to use its animated time-of-day sky. All
/// words, dates, times, and the tasbeeh action remain LIVE widgets over art.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.schedule, required this.controller});

  final PrayerSchedule schedule;
  final PrayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: controller.now,
      builder: (context, now, _) => Center(
        child: ConstrainedBox(
          // Capped so a tablet gets a tall card, never a wall-sized one.
          constraints: const BoxConstraints(maxWidth: 430),
          child: AspectRatio(
            aspectRatio: 0.72,
            // The expanded prayer page now uses the SAME six dynamic animated
            // skies as the home card (night, sehr, Fajr, morning, dopahar,
            // Maghrib/evening) — phase chosen from today's prayer times.
            child: SkyBackdrop(
              key: const ValueKey<String>('prayer-details-wallpaper'),
              phase: skyPhaseFor(schedule, now),
              radius: 24,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _HeroTitleRow(controller: controller),
                    const Spacer(),
                    Flexible(flex: 4, child: _HeroClock(now: now)),
                    const Spacer(),
                    _HeroNextPrayer(controller: controller, now: now),
                    const SizedBox(height: 12),
                    _TimingGlassRow(schedule: schedule, now: now),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Location + technical details BELOW the wallpaper, in their own container
/// (place, dates, Hijri, coordinates, source) — nothing technical sits on the sky.
class _LocationDetailsContainer extends StatelessWidget {
  const _LocationDetailsContainer({required this.controller});

  final PrayerController controller;

  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.of(context);
    return ValueListenableBuilder<DateTime>(
      valueListenable: controller.now,
      builder: (context, now, _) {
        final location = controller.location;
        final hijri = controller.hijriFor(now);
        return GlassPanel(
          key: const ValueKey<String>('prayer-location-details'),
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => unawaited(openLocationPicker(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const GlassSectionHeader(title: 'مقام و تفصیل'),
                const SizedBox(height: 8),
                Row(children: <Widget>[
                  Icon(Icons.place, size: 19, color: palette.gold),
                  const SizedBox(width: 4),
                  Expanded(child: Text(controller.loadingLocation ? 'مقام تلاش کیا جا رہا ہے…' : location.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: palette.ink))),
                  _SkyPill(label: location.source.labelUrdu, icon: Icons.edit_location_alt_outlined),
                ]),
                if (location.detail.isNotEmpty)
                  Text(location.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: palette.muted)),
                const SizedBox(height: 6),
                Text('${weekdayUrdu(now)}  •  ${formatDayMonthYearUrdu(now)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
                Text('تاریخِ ہجری: ${hijri.labelUrdu}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.gold)),
                Text(formatCoordinatesUrdu(location.latitude, location.longitude),
                    style: TextStyle(fontFamily: kDigitFont, fontSize: 12.5, color: palette.muted)),
                if (location.accuracyMeters != null)
                  Text('درستگی ~${location.accuracyMeters!.round()} میٹر', style: TextStyle(fontSize: 12.5, color: palette.muted)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The live clock in the middle of the portrait sky.
class _HeroClock extends StatelessWidget {
  const _HeroClock({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text.rich(
              TextSpan(children: <InlineSpan>[
                TextSpan(
                  text: formatClockDigitsUrdu(now),
                  style: _sky(54, weight: FontWeight.w800, digits: true, height: 1),
                ),
                TextSpan(
                  text: ' ${formatClockSeconds(now)}',
                  style: _sky(18, weight: FontWeight.w600, digits: true),
                ),
              ]),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 2),
            Text(
              dayPartUrdu(now.hour),
              style: _sky(14, weight: FontWeight.w700, color: _skyGold, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroTitleRow extends StatelessWidget {
  const _HeroTitleRow({required this.controller});

  final PrayerController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(Icons.mosque, size: 20, color: Colors.white),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'شیعہ اثنا عشری — جعفری اوقات',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _sky(15, weight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 6),
        _SkyPill(
          label: 'تسبیح',
          icon: Icons.touch_app_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const TasbeehScreen()),
          ),
        ),
      ],
    );
  }
}

/// The "next prayer" headline with its live countdown and the window progress.
class _HeroNextPrayer extends StatelessWidget {
  const _HeroNextPrayer({required this.controller, required this.now});

  final PrayerController controller;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final schedule = controller.schedule;
    final next = schedule.nextEntry(now);
    final window = schedule.window(now);
    final remaining = next.time.difference(now);
    final windowProgress = _windowProgress(schedule, window, now);
    final afterSunrise = !window.previousNight && now.isAfter(window.endsAt);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('اگلی نماز', style: _sky(13, alpha: 0.88)),
              Text(
                '${next.marker.labelUrdu}  ${formatClockUrdu(next.time)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sky(23, weight: FontWeight.w800, height: 1.35),
              ),
              Text(
                '${formatCountdownClock(remaining)} باقی',
                style: _sky(17, weight: FontWeight.w800, color: _skyGold, digits: true),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 124,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                afterSunrise
                    ? 'طلوع کے بعد'
                    : '${window.previousNight ? 'گزشتہ ' : ''}${window.marker.labelUrdu} کا وقت',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sky(13, weight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: afterSunrise ? 1 : windowProgress,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation<Color>(_skyGold),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'اختتام ${formatClockUrdu(window.endsAt)}',
                style: _sky(12.5, alpha: 0.88),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The five obligatory prayers on one strip, plus the astronomical markers
/// underneath. Built so the row can never clip: every cell shrinks its own
/// digits rather than overflowing, and the markers wrap instead of pushing.
class _TimingGlassRow extends StatelessWidget {
  const _TimingGlassRow({required this.schedule, required this.now});

  final PrayerSchedule schedule;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final window = schedule.window(now);
    final next = schedule.nextEntry(now);
    // Between midnight and Fajr the running window is the previous night's
    // Isha (window.previousNight); it is still the prayer the reader is in, so
    // it carries the active mark. It no longer went blank for that half of
    // the night.
    final running = now.isBefore(window.endsAt);
    // A translucent strip rather than a blurred one: a blur over an animated
    // sky would be recomputed on every frame.
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final entry in schedule.obligatory)
                Expanded(
                  child: _PrayerCell(
                    entry: entry,
                    active: running && window.marker == entry.marker,
                    next: next.marker == entry.marker && !next.tomorrow,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: <Widget>[
              for (final entry in schedule.markers)
                _SkyPill(
                  label: '${entry.labelUrdu} ${formatClockDigitsUrdu(entry.time)}',
                  icon: switch (entry.marker) {
                    PrayerMarker.sunrise => Icons.wb_twilight,
                    PrayerMarker.sunset => Icons.nights_stay_outlined,
                    _ => Icons.dark_mode_outlined,
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrayerCell extends StatelessWidget {
  const _PrayerCell({required this.entry, required this.active, required this.next});

  final PrayerEntry entry;
  final bool active;
  final bool next;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      decoration: BoxDecoration(
        color: active ? Colors.white.withValues(alpha: 0.24) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? Colors.white.withValues(alpha: 0.6)
              : (next ? _skyGold.withValues(alpha: 0.7) : Colors.transparent),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            entry.labelUrdu,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _sky(15, weight: active ? FontWeight.w800 : FontWeight.w700, height: 1.3),
          ),
          const SizedBox(height: 2),
          // The digits are resized rather than wrapped: an Urdu label plus a
          // clock never grows wider than a fifth of the card.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatClockDigitsUrdu(entry.time),
              style: _sky(19, weight: FontWeight.w800, digits: true, color: next && !active ? _skyGold : Colors.white),
            ),
          ),
          Text(
            dayPartUrdu(entry.time.hour),
            maxLines: 1,
            style: _sky(12, alpha: 0.85, height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// A small translucent pill on the sky.
class _SkyPill extends StatelessWidget {
  const _SkyPill({required this.label, this.icon, this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(label, style: _sky(12.5, weight: FontWeight.w700, height: 1.2)),
        ],
      ),
    );
    if (onTap == null) return pill;
    return InkWell(borderRadius: BorderRadius.circular(30), onTap: onTap, child: pill);
  }
}

/// The live card under the hero: which window is running, how long is left of
/// it, the post-prayer shortcut to Tasbeeh-e-Zahra (s.a.), and the Qibla.
class _NextPrayerCard extends StatelessWidget {
  const _NextPrayerCard({required this.controller, required this.schedule});

  final PrayerController controller;
  final PrayerSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.of(context);
    return ValueListenableBuilder<DateTime>(
      valueListenable: controller.now,
      builder: (context, now, _) {
        final window = schedule.window(now);
        final next = schedule.nextEntry(now);
        final justPrayed = schedule.justPrayed(now);
        final afterSunrise = !window.previousNight && now.isAfter(window.endsAt);
        final remaining = afterSunrise ? next.time.difference(now) : window.endsAt.difference(now);

        return GlassPanel(
          radius: 20,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: palette.accentSoft,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.timelapse, size: 16, color: palette.accent),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              afterSunrise ? 'طلوعِ آفتاب کے بعد' : '${window.marker.labelUrdu} کا وقت جاری',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: palette.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'اگلی: ${next.marker.labelUrdu}',
                    style: TextStyle(fontSize: 14, color: palette.muted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          afterSunrise ? '${next.marker.labelUrdu} میں' : 'اس وقفے کے اختتام میں',
                          style: TextStyle(fontSize: 13, color: palette.muted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatCountdownUrdu(remaining),
                          style: TextStyle(
                            fontSize: 25,
                            height: 1.35,
                            fontWeight: FontWeight.w800,
                            color: palette.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        afterSunrise ? 'وقت' : 'کب تک',
                        style: TextStyle(fontSize: 13, color: palette.muted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatClockUrdu(afterSunrise ? next.time : window.endsAt),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: palette.gold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: palette.track),
              const SizedBox(height: 10),
              _QiblaStrip(controller: controller),
              if (justPrayed != null) ...<Widget>[
                const SizedBox(height: 12),
                _PostPrayerBanner(marker: justPrayed),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _QiblaStrip extends StatelessWidget {
  const _QiblaStrip({required this.controller});

  final PrayerController controller;

  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.of(context);
    final bearing = controller.qiblaBearing;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const QiblaScreen()),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.goldSoft,
                border: Border.all(color: palette.gold.withValues(alpha: 0.4)),
              ),
              child: Icon(Icons.explore, size: 21, color: palette.gold),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'سمتِ قبلہ: ${formatBearingUrdu(bearing, compassPointUrdu(bearing))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: palette.ink,
                    ),
                  ),
                  Text(
                    'کعبہ سے فاصلہ ${formatKilometresUrdu(controller.distanceToKaabaKm)}',
                    style: TextStyle(fontSize: 13, color: palette.muted),
                  ),
                ],
              ),
            ),
            Text(
              'کھولیں',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.accent,
              ),
            ),
            Icon(Icons.chevron_left, size: 20, color: palette.accent),
          ],
        ),
      ),
    );
  }
}

/// "You have just prayed — start Tasbeeh-e-Zahra (s.a.)", offered by itself in
/// the half hour after a prayer begins or after Fajr's window closes.
class _PostPrayerBanner extends StatelessWidget {
  const _PostPrayerBanner({required this.marker});

  final PrayerMarker marker;

  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: palette.goldSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.notifications_active, size: 20, color: palette.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${marker.labelUrdu} کا وقت ہو گیا',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
                  ),
                ),
                Text(
                  'نماز کے بعد تسبیحِ زہرا (س) پڑھیں',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: palette.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TasbeehScreen(startWithZahra: true),
              ),
            ),
            child: const Text('شروع کریں', style: TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
    );
  }
}

/// The day's finer numbers: Nisf al-Layl, the last third of the night, the
/// method and its angles, the Qibla, and where the coordinates came from.
class _DetailTiles extends StatelessWidget {
  const _DetailTiles({required this.schedule, required this.controller});

  final PrayerSchedule schedule;
  final PrayerController controller;

  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.of(context);
    final fajr = schedule.entryFor(PrayerMarker.fajr).time;
    final maghrib = schedule.entryFor(PrayerMarker.maghrib).time;
    final nightSeconds = schedule.fajrTomorrow.difference(maghrib).inSeconds;
    final lastThird = maghrib.add(Duration(seconds: (nightSeconds * 2 / 3).round()));
    final midnight = schedule.entryFor(PrayerMarker.midnight).time;
    final location = controller.location;

    final maghribMidnight = PrayerCalculator.maghribMidnight(
      schedule.entryFor(PrayerMarker.maghrib).time,
      schedule.fajrTomorrow,
    );

    final tiles = <(IconData, String, String, String?)>[
      (
        Icons.brightness_3,
        'نصف شب (شرعی)',
        formatClockUrdu(midnight),
        'غروبِ آفتاب تا فجر کا وسط',
      ),
      (
        Icons.brightness_3_outlined,
        'نصف شب (مغرب سے)',
        formatClockUrdu(maghribMidnight),
        'مغرب تا فجر — احتیاطاً',
      ),
      (
        Icons.nightlight_round,
        'آخری تہائی رات',
        formatClockUrdu(lastThird),
        'نمازِ شب کا وقت',
      ),
      (
        Icons.calculate_outlined,
        'طریقۂ حساب',
        schedule.methodLabel.split('—').first.trim(),
        'مغرب ${ltr('${schedule.maghribAngle.toStringAsFixed(1)}°')} پر',
      ),
      (
        Icons.explore_outlined,
        'قبلہ (شمالِ حقیقی سے)',
        formatBearingUrdu(controller.qiblaBearing, compassPointUrdu(controller.qiblaBearing)),
        'فاصلہ ${formatKilometresUrdu(controller.distanceToKaabaKm)}',
      ),
      (
        Icons.my_location,
        'مقام کا ماخذ',
        location.source.labelUrdu,
        location.accuracyMeters == null
            ? 'محفوظ شدہ متناسقات'
            : 'درستگی ~${location.accuracyMeters!.round()} میٹر',
      ),
      (
        Icons.schedule,
        'فجر تا طلوع',
        formatCountdownUrdu(
          schedule.entryFor(PrayerMarker.sunrise).time.difference(fajr),
        ),
        'صبح کا پہلا وقفہ',
      ),
    ];

    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const GlassSectionHeader(title: 'مزید اوقات و تفصیل'),
          const SizedBox(height: 10),
          for (int index = 0; index < tiles.length; index += 2) ...<Widget>[
            // IntrinsicHeight measures the taller of the two tiles and gives
            // the shorter one the same height, so a pair stays level without
            // asking a Row to stretch inside an unbounded Column.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: _DetailTile(tile: tiles[index], palette: palette)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: index + 1 < tiles.length
                        ? _DetailTile(tile: tiles[index + 1], palette: palette)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            if (index + 2 < tiles.length) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.tile, required this.palette});

  final (IconData, String, String, String?) tile;
  final GlassPalette palette;

  @override
  Widget build(BuildContext context) {
    final (icon, title, value, note) = tile;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.solid.withValues(alpha: palette.isDark ? 0.55 : 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.track),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: palette.accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 17,
                height: 1.3,
                fontWeight: FontWeight.w800,
                color: palette.ink,
              ),
            ),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              note,
              maxLines: 2,
              style: TextStyle(fontSize: 12, height: 1.35, color: palette.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sound, vibration, calculation method, the Hijri date shift, and the manual
/// location picker.
class _AlertControls extends StatelessWidget {
  const _AlertControls({required this.controller, required this.onPickLocation});

  final PrayerController controller;
  final VoidCallback onPickLocation;

  Future<void> _pickPreset(BuildContext context) async {
    final chosen = await showModalBottomSheet<(String, String)>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final palette = GlassPalette.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GlassPanel(
              radius: 22,
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const GlassSectionHeader(title: 'طریقۂ حساب'),
                  const SizedBox(height: 10),
                  for (final (key, label, params) in PrayerCalculator.presets())
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        label,
                        style: TextStyle(fontSize: 15, color: palette.ink),
                      ),
                      subtitle: Text(
                        'مغرب: سورج ${ltr('${(params.maghribAngle ?? 4).toStringAsFixed(1)}°')} '
                        'نیچے — زوالِ سرخی',
                        style: TextStyle(fontSize: 13, color: palette.muted),
                      ),
                      trailing: controller.presetKey == key
                          ? Icon(Icons.check_circle, color: palette.accent)
                          : Icon(Icons.circle_outlined, color: palette.muted),
                      onTap: () => Navigator.of(sheetContext).pop((key, label)),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'دونوں طریقے شیعہ اثنا عشری (لیوا Institute، قم) کے مطابق ہیں؛ '
                    'فرق صرف فجر کے زاویے اور احتیاط میں ہے۔',
                    style: TextStyle(fontSize: 12.5, height: 1.45, color: palette.muted),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (chosen == null) return;
    controller.setPreset(chosen.$1);
  }

  Future<void> _pickHijriShift(BuildContext context) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final palette = GlassPalette.of(sheetContext);
        final current = controller.hijriAdjustment;
        Widget option(String key, String label, bool selected) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(label, style: TextStyle(fontSize: 15, color: palette.ink)),
              trailing: selected
                  ? Icon(Icons.check_circle, color: palette.accent)
                  : Icon(Icons.circle_outlined, color: palette.muted),
              onTap: () => Navigator.of(sheetContext).pop(key),
            );
        String signed(int days) => days > 0 ? '+$days' : '$days';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GlassPanel(
              radius: 22,
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const GlassSectionHeader(title: 'ہجری تاریخ کی درستگی'),
                  const SizedBox(height: 6),
                  Text(
                    'ہر مہینے کا پہلا دن آپ ہی کے شہر سے چاند نظر آنے پر رکھا '
                    'جاتا ہے — دستی درستگی ضروری نہیں، مگر رکھی جا سکتی ہے۔ آج: '
                    '${controller.hijriToday.labelUrdu}',
                    style: TextStyle(fontSize: 13, height: 1.5, color: palette.muted),
                  ),
                  const SizedBox(height: 6),
                  option('auto', 'خودکار (چاند کی رویت)', current == null),
                  for (final days in const <int>[-2, -1, 0, 1, 2])
                    option('$days', '${signed(days)} دن', current == days),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (chosen == null) return;
    controller.setHijriAdjustment(chosen == 'auto' ? null : int.tryParse(chosen));
  }

  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.of(context);
    final shift = controller.hijriAdjustment;
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const GlassSectionHeader(title: 'الرٹ اور ترتیبات'),
          const SizedBox(height: 6),
          _ToggleRow(
            icon: Icons.notifications_active_outlined,
            label: 'نماز کے وقت اطلاع (آواز + وائبریشن)',
            value: controller.alertsEnabled,
            onChanged: controller.setAlertsEnabled,
            palette: palette,
          ),
          _ToggleRow(
            icon: Icons.volume_up_outlined,
            label: 'اطلاع کی آواز (اذان / چائم)',
            value: controller.soundEnabled,
            onChanged: controller.setSoundEnabled,
            palette: palette,
          ),
          if (controller.soundEnabled) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: GlassChip(
                    key: const ValueKey<String>('prayer-sound-short-azan'),
                    label: 'مختصر اذان (CC0)',
                    icon: Icons.mosque_outlined,
                    selected: controller.soundMode == PrayerSoundMode.shortAzan,
                    tone: palette.gold,
                    onTap: () {
                      controller.setSoundMode(PrayerSoundMode.shortAzan);
                      unawaited(controller.previewAlertSound(PrayerSoundMode.shortAzan));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GlassChip(
                    key: const ValueKey<String>('prayer-sound-chime'),
                    label: 'نرم چائم',
                    icon: Icons.music_note_outlined,
                    selected: controller.soundMode == PrayerSoundMode.chime,
                    onTap: () {
                      controller.setSoundMode(PrayerSoundMode.chime);
                      unawaited(controller.previewAlertSound(PrayerSoundMode.chime));
                    },
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  key: const ValueKey<String>('prayer-sound-preview'),
                  tooltip: 'آواز سنیں',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.play_circle_outline_rounded, color: palette.accent, size: 22),
                  onPressed: () => unawaited(controller.previewAlertSound()),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          _ToggleRow(
            icon: Icons.vibration,
            label: 'وائبریشن (ہلکا جھٹکا)',
            value: controller.hapticsEnabled,
            onChanged: controller.setHapticsEnabled,
            palette: palette,
          ),
          if (controller.alertsEnabled) ...<Widget>[
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(Icons.schedule_send_outlined, size: 16, color: palette.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'اگلے 30 دن کی اطلاع فون میں محفوظ کریں',
                    style: TextStyle(fontSize: 11.5, color: palette.muted),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final granted = await controller.requestNativePrayerNotifications();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(granted
                            ? 'فون پر نماز کی اطلاعات فعال ہیں۔'
                            : 'اطلاع کی اجازت نہیں ملی؛ فون کی ترتیبات میں اجازت دیں۔'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                  child: const Text('اجازت دیں'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: GlassChip(
                  label: 'طریقہ: ${controller.presetKey == 'leva' ? 'تہران (${ltr('17.7°')})' : 'جعفری (${ltr('16°')})'}',
                  icon: Icons.calculate_outlined,
                  onTap: () => unawaited(_pickPreset(context)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassChip(
                  label: 'شہر منتخب کریں',
                  icon: Icons.location_city,
                  onTap: onPickLocation,
                  tone: palette.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GlassChip(
            label: shift == null
                ? 'ہجری تاریخ: خودکار (چاند کی رویت)'
                : 'ہجری تاریخ: ${shift > 0 ? '+$shift' : '$shift'} دن',
            icon: Icons.nightlight_outlined,
            onTap: () => unawaited(_pickHijriShift(context)),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.palette,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final GlassPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 19, color: value ? palette.accent : palette.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.35,
              color: palette.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}

/// The footnote every printed timetable carries: these are computed times, and
/// the reader should know which angles produced them.
class _FiqhNote extends StatelessWidget {
  const _FiqhNote({required this.schedule});

  final PrayerSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.of(context);
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(12),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.info_outline, size: 17, color: palette.accent),
              const SizedBox(width: 6),
              Text(
                'طریقہ اور احتیاط',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: palette.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'اوقاتِ نماز سورج کے حقیقی زاویوں سے حساب ہوتے ہیں: '
            '${schedule.methodLabel}، مغرب سورج ${ltr('${schedule.maghribAngle.toStringAsFixed(1)}°')} '
            'نیچے آنے پر (زوالِ سرخی)، اور شرعی نصف شب غروبِ آفتاب تا فجر کے وسط پر۔ '
            'مغرب سے نصف شب کا حساب الگ دیا گیا ہے (احتیاط)۔ '
            'ہجری تاریخ اُمّ القریٰ کیلنڈر سے ہے اور مغرب کے بعد اگلی تاریخ (شب) دکھائی جاتی ہے؛ '
            'چاند کے مطابق درستگی اوپر سے کریں۔ '
            'شہروں کے اوقات میں چند منٹ کا فرق ممکن ہے — اپنے شہر کے سرکاری اوقات سے تصدیق کر لیں۔',
            style: TextStyle(fontSize: 13, height: 1.65, color: palette.muted),
          ),
        ],
      ),
    );
  }
}

/// Manual location: the curated cities (with Urdu names), 73,000 places from
/// the bundled list, any village through the online search, the GPS, and raw
/// coordinates. Used when the GPS is denied, switched off, or plainly wrong —
/// or when the reader wants another city's times.
class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet({super.key});

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final TextEditingController _query = TextEditingController();
  CityIndex? _index;
  bool _indexLoading = true;

  /// The reader's own country, whose towns are listed first.
  String? _homeCountry;
  List<PlaceResult> _offline = PrayerLocations.searchCities('').map(PrayerLocations.resultForSuggestion).toList();
  List<PlaceResult> _online = const <PlaceResult>[];
  bool _onlineBusy = false;
  bool _onlineTried = false;
  LocationProblem? _gpsProblem;
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadIndex());
  }

  Future<void> _loadIndex() async {
    final index = await CityIndexLoader.load();
    if (!mounted) return;
    final location = PrayerScope.read(context).location;
    final home = index?.nearest(location.latitude, location.longitude, maxKm: 300)?.city.countryCode;
    setState(() {
      _index = index;
      _indexLoading = false;
      _homeCountry = home;
      _offline = PrayerLocations.searchOffline(_query.text, index, preferCountry: home);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    final generation = ++_generation;
    setState(() {
      _offline = PrayerLocations.searchOffline(value, _index, preferCountry: _homeCountry);
      _online = const <PlaceResult>[];
      _onlineTried = false;
    });
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 3 || PrayerLocations.fromQuery(trimmed) != null) return;
    // Few offline answers: ask the online search too, once typing pauses.
    if (_offline.length < 6) {
      _debounce = Timer(const Duration(milliseconds: 900), () {
        if (mounted && generation == _generation) unawaited(_searchOnline(deep: false));
      });
    }
  }

  Future<void> _searchOnline({required bool deep}) async {
    final query = _query.text.trim();
    if (query.length < 2) return;
    final generation = _generation;
    setState(() => _onlineBusy = true);
    final results = await OnlinePlaces.search(query, deep: deep);
    if (!mounted || generation != _generation) return;
    setState(() {
      _onlineBusy = false;
      _onlineTried = true;
      _online = <PlaceResult>[
        for (final place in results)
          if (!_offline.any((known) => known.sameSpotAs(place, toleranceDegrees: 0.03))) place,
      ];
    });
  }

  /// The GPS button: a fresh fix closes the sheet; a failure stays here and
  /// explains itself (a snack bar would hide behind the sheet).
  Future<void> _useGps(PrayerController controller) async {
    final navigator = Navigator.of(context);
    setState(() => _gpsProblem = null);
    await controller.refreshLocation();
    if (!mounted) return;
    final problem = controller.locationProblem;
    if (problem == null) {
      navigator.pop();
      return;
    }
    setState(() => _gpsProblem = problem);
  }

  Future<void> _choose(PlaceResult place) async {
    final controller = PrayerScope.read(context);
    final navigator = Navigator.of(context);
    if (place.origin == PlaceOrigin.curated) {
      final city = PrayerLocations.cities.firstWhere(
        (candidate) => candidate.nameUrdu == place.title && candidate.nameLatin == place.subtitle,
        orElse: () => PlaceSuggestion(place.title, place.subtitle, place.latitude, place.longitude),
      );
      await controller.useCity(city);
    } else {
      await controller.usePlace(place);
    }
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.of(context);
    final controller = PrayerScope.of(context);
    final coordinates = PrayerLocations.fromQuery(_query.text);
    final media = MediaQuery.of(context);
    final hasQuery = _query.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) => GlassPanel(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.location_on_outlined, size: 20, color: palette.accent),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'مقام منتخب کریں',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'بند کریں',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 22),
                  ),
                ],
              ),
              TextField(
                controller: _query,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => unawaited(_searchOnline(deep: true)),
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'شہر، قصبہ یا گاؤں (مثلاً Chakwal) یا 33.68, 73.04',
                  prefixIcon: const Icon(Icons.search, size: 22),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _query.clear();
                            _onQueryChanged('');
                          },
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  GlassActionButton(
                    icon: Icons.gps_fixed,
                    label: 'میرا موجودہ مقام',
                    onTap: controller.loadingLocation ? null : () => unawaited(_useGps(controller)),
                    busy: controller.loadingLocation,
                  ),
                  const SizedBox(width: 8),
                  if (coordinates != null)
                    GlassActionButton(
                      icon: Icons.pin_drop_outlined,
                      label: 'یہ متناسقات',
                      selected: true,
                      onTap: () async {
                        final navigator = Navigator.of(context);
                        await controller.useCoordinates(
                          coordinates.latitude,
                          coordinates.longitude,
                        );
                        if (mounted) navigator.pop();
                      },
                    )
                  else
                    GlassActionButton(
                      icon: Icons.travel_explore,
                      label: 'انٹرنیٹ پر تلاش',
                      tone: palette.gold,
                      busy: _onlineBusy,
                      onTap: hasQuery && !_onlineBusy ? () => unawaited(_searchOnline(deep: true)) : null,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_gpsProblem != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: palette.goldSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: palette.gold.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.location_off_outlined, size: 20, color: palette.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _gpsProblem!.messageUrdu,
                          style: TextStyle(fontSize: 13, height: 1.45, color: palette.ink),
                        ),
                      ),
                      TextButton(
                        onPressed: () => unawaited(resolveLocationProblem(_gpsProblem!, controller)),
                        child: Text(_gpsProblem!.actionUrdu, style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              if (_indexLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text(
                        'شہروں کی مکمل فہرست تیار ہو رہی ہے…',
                        style: TextStyle(fontSize: 13, color: palette.muted),
                      ),
                    ],
                  ),
                )
              else if (!hasQuery)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'نام لکھیں — 73,000 سے زیادہ شہر اور قصبے بغیر انٹرنیٹ کے، '
                    'اور ہر گاؤں انٹرنیٹ سے تلاش ہو سکتا ہے۔',
                    style: TextStyle(fontSize: 12.5, height: 1.45, color: palette.muted),
                  ),
                ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: <Widget>[
                    for (final place in _offline) _PlaceRow(place: place, onTap: () => unawaited(_choose(place))),
                    if (_onlineBusy)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text('انٹرنیٹ پر تلاش جاری ہے…', style: TextStyle(fontSize: 13.5, color: palette.muted)),
                          ],
                        ),
                      ),
                    if (_online.isNotEmpty) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                        child: Text(
                          'انٹرنیٹ سے ملنے والے مقامات',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.gold),
                        ),
                      ),
                      for (final place in _online) _PlaceRow(place: place, onTap: () => unawaited(_choose(place))),
                    ],
                    if (hasQuery && !_onlineBusy && _offline.isEmpty && _online.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
                        child: Text(
                          _onlineTried
                              ? 'کوئی مقام نہیں ملا۔ ہجے بدل کر دیکھیں، یا متناسقات لکھیں (مثلاً 33.68, 73.04)۔'
                              : 'اس نام کا کوئی شہر فہرست میں نہیں — «انٹرنیٹ پر تلاش» دبائیں۔',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13.5, height: 1.5, color: palette.muted),
                        ),
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

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place, required this.onTap});

  final PlaceResult place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.of(context);
    final controller = PrayerScope.of(context);
    final location = controller.location;
    final selected = location.source == LocationSource.manual &&
        (location.latitude - place.latitude).abs() < 0.01 &&
        (location.longitude - place.longitude).abs() < 0.01;
    final icon = switch (place.origin) {
      PlaceOrigin.curated => Icons.star_rounded,
      PlaceOrigin.offline => Icons.location_city,
      PlaceOrigin.online => Icons.public,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? palette.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? palette.accent.withValues(alpha: 0.4) : palette.track,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 19,
                color: place.origin == PlaceOrigin.curated ? palette.gold : palette.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      place.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                    if (place.subtitle.isNotEmpty)
                      Text(
                        place.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: palette.muted),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 18, color: palette.accent)
              else
                Icon(Icons.chevron_left, size: 18, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// How far through its window the running prayer is (0–1).
///
/// The window starts when its own prayer's time arrived and ends at the next
/// marker — Fajr closes at sunrise, Isha at Nisf al-Layl, and the night's Isha
/// window (after midnight) runs to Fajr.
double _windowProgress(
  PrayerSchedule schedule,
  PrayerWindow window,
  DateTime now,
) {
  final start = window.previousNight
      ? schedule.entryFor(PrayerMarker.isha).time.subtract(const Duration(days: 1))
      : schedule.entryFor(window.marker).time;
  final total = window.endsAt.difference(start).inSeconds;
  if (total <= 0) return 0;
  return (now.difference(start).inSeconds / total).clamp(0.0, 1.0);
}
