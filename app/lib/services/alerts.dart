import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which sound a prayer-time alert plays when sound is enabled.
enum PrayerSoundMode {
  chime('نرم چائم', 'shiaverse_prayer_chime', 'audio/chime_prayer.wav'),
  shortAzan('مختصر اذان', 'shiaverse_short_azan', 'audio/azan_short.wav');

  const PrayerSoundMode(this.labelUrdu, this.rawResource, this.assetPath);

  final String labelUrdu;
  final String rawResource;
  final String assetPath;

  static PrayerSoundMode fromWire(String? value) =>
      value == 'short_azan' ? PrayerSoundMode.shortAzan : PrayerSoundMode.chime;

  String get wire =>
      this == PrayerSoundMode.shortAzan ? 'short_azan' : 'chime';
}

/// What the prayer watcher and the tasbeeh counter do to the phone: a sound
/// and a buzz. An interface, so the controllers can be tested (and can run on
/// a device that can do neither) without touching a platform channel.
abstract class FeedbackSink {
  Future<void> playPrayerChime();
  Future<void> playShortAzan();
  Future<void> stopPrayerAudio();
  Future<void> playCompleteChime();
  Future<void> playTap();
  Future<void> tapHaptic();
  Future<void> completionHaptic();
  Future<void> prayerHaptic();
}

/// A sink that does nothing — the default in tests, and the safe fallback when
/// the audio or vibration platform is unavailable.
class SilentFeedback implements FeedbackSink {
  const SilentFeedback();

  @override
  Future<void> playPrayerChime() async {}

  @override
  Future<void> playShortAzan() async {}

  @override
  Future<void> stopPrayerAudio() async {}

  @override
  @override
  Future<void> playCompleteChime() async {}

  @override
  @override
  Future<void> playTap() async {}

  @override
  Future<void> tapHaptic() async {}

  @override
  @override
  Future<void> completionHaptic() async {}

  @override
  @override
  Future<void> prayerHaptic() async {}
}

/// Sound and vibration for the prayer card and the tasbeeh counter.
///
/// Everything here is best-effort: a device with no speaker route, a platform
/// that refuses vibration, or a missing audio session must never take the
/// screen down, so every call is wrapped and every failure is a no-op.
class Alerts implements FeedbackSink {
  Alerts._();

  static final Alerts instance = Alerts._();

  final AudioPlayer _chimePlayer = AudioPlayer(playerId: 'shiaverse-chime');
  final AudioPlayer _tapPlayer = AudioPlayer(playerId: 'shiaverse-tap');
  bool _ready = false;

  static const String prayerChime = 'audio/chime_prayer.wav';
  static const String shortAzan = 'audio/azan_short.wav';
  static const String completeChime = 'audio/chime_complete.wav';
  static const String tapClick = 'audio/tap_click.wav';

  /// Prepared once, on the first sound, so opening the app costs nothing.
  Future<void> _prepare() async {
    if (_ready) return;
    _ready = true;
    try {
      await _chimePlayer.setReleaseMode(ReleaseMode.stop);
      await _chimePlayer.setVolume(0.85);
      await _tapPlayer.setReleaseMode(ReleaseMode.stop);
      await _tapPlayer.setVolume(0.35);
      // SoundPool-backed playback is what makes a tasbeeh tap feel instant on
      // Android; elsewhere the media player is used as-is.
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _tapPlayer.setPlayerMode(PlayerMode.lowLatency);
      }
    } catch (_) {
      return;
    }
  }

  @override
  Future<void> playPrayerChime() async {
    await _prepare();
    try {
      await _chimePlayer.stop();
      await _chimePlayer.play(AssetSource(prayerChime));
    } catch (_) {
      return;
    }
  }

  @override
  Future<void> playShortAzan() async {
    await _prepare();
    try {
      await _chimePlayer.stop();
      await _chimePlayer.play(AssetSource(shortAzan));
    } catch (_) {
      return;
    }
  }

  @override
  Future<void> stopPrayerAudio() async {
    if (!_ready) return;
    try {
      await _chimePlayer.stop();
    } catch (_) {
      return;
    }
  }

  @override
  Future<void> playCompleteChime() async {
    await _prepare();
    try {
      await _chimePlayer.stop();
      await _chimePlayer.play(AssetSource(completeChime));
    } catch (_) {
      return;
    }
  }

  @override
  Future<void> playTap() async {
    await _prepare();
    try {
      await _tapPlayer.stop();
      await _tapPlayer.play(AssetSource(tapClick));
    } catch (_) {
      return;
    }
  }

  /// A single bead of a tasbeeh, felt in the hand.
  @override
  Future<void> tapHaptic() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {
      return;
    }
  }

  /// Target reached: a firmer double beat, the phone's own way of saying
  /// "complete".
  @override
  Future<void> completionHaptic() async {
    try {
      await HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await HapticFeedback.mediumImpact();
    } catch (_) {
      return;
    }
  }

  /// The prayer-time alert: a longer, unmistakable buzz.
  @override
  Future<void> prayerHaptic() async {
    try {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      await HapticFeedback.heavyImpact();
    } catch (_) {
      return;
    }
  }

  Future<void> dispose() async {
    try {
      await _chimePlayer.dispose();
      await _tapPlayer.dispose();
    } catch (_) {
      return;
    }
  }
}
