import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's sound effects. Files live in `assets/sounds/` and are synthesized
/// by `tool/generate_sounds.py`.
enum Sfx {
  tap('tap'),
  send('send'),
  receive('receive'),
  notify('notify'),
  success('success'),
  error('error'),
  voiceJoin('voice_join'),
  voiceLeave('voice_leave'),
  mute('mute'),
  unmute('unmute'),
  tripStart('trip_start'),
  tripEnd('trip_end'),
  navStart('nav_start'),
  turn('turn'),
  reroute('reroute'),
  arrive('arrive'),
  refresh('refresh');

  const Sfx(this.file);
  final String file;
}

/// One place for sound and haptics, so every call site is a single line and the
/// user's two switches (Settings → Sound effects / Haptic feedback) are honoured
/// everywhere.
///
/// Sounds are quiet UI cues that must never fight what's already playing: the
/// audio context takes no audio focus and mixes with other apps, so a message
/// "pop" doesn't pause music or cut a voice call. Every call is fire-and-forget
/// and swallows errors — feedback is decoration and must never throw.
abstract final class AppFeedback {
  static bool soundEnabled = true;
  static bool hapticsEnabled = true;

  static final Map<Sfx, AudioPlayer> _players = {};
  static bool _ready = false;

  /// Applies the user's settings (called whenever they change).
  static void configure({required bool sound, required bool haptics}) {
    soundEnabled = sound;
    hapticsEnabled = haptics;
  }

  /// Sets the shared audio context. Safe to call more than once.
  static Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            audioFocus: AndroidAudioFocus.none,
            usageType: AndroidUsageType.assistanceSonification,
            contentType: AndroidContentType.sonification,
          ),
          // `ambient` already mixes with other audio and respects the silent
          // switch; naming `mixWithOthers` explicitly isn't allowed with it.
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        ),
      );
    } catch (e) {
      debugPrint('AppFeedback: audio context failed: $e');
    }
  }

  // --- sound -------------------------------------------------------------

  /// Plays [sfx] (if sound is on). [volume] is 0–1.
  static void play(Sfx sfx, {double volume = 0.7}) {
    if (!soundEnabled) return;
    unawaited(_play(sfx, volume));
  }

  static Future<void> _play(Sfx sfx, double volume) async {
    try {
      await init();
      var player = _players[sfx];
      if (player == null) {
        player = AudioPlayer();
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        _players[sfx] = player;
      }
      await player.stop();
      await player.play(AssetSource('sounds/${sfx.file}.wav'), volume: volume);
    } catch (e) {
      debugPrint('AppFeedback: could not play ${sfx.file}: $e');
    }
  }

  // --- haptics -----------------------------------------------------------

  static void _haptic(Future<void> Function() fire) {
    if (!hapticsEnabled) return;
    unawaited(fire().catchError((_) {}));
  }

  /// A crisp tick for selections: tabs, toggles, chips.
  static void selection() => _haptic(HapticFeedback.selectionClick);

  static void light() => _haptic(HapticFeedback.lightImpact);
  static void medium() => _haptic(HapticFeedback.mediumImpact);
  static void heavy() => _haptic(HapticFeedback.heavyImpact);

  // --- combined cues -----------------------------------------------------

  /// A button / row press.
  static void tap() {
    selection();
  }

  /// A message leaving.
  static void sent() {
    light();
    play(Sfx.send);
  }

  /// A message arriving in the thread you're looking at.
  static void received() {
    selection();
    play(Sfx.receive, volume: 0.55);
  }

  /// Something that wants attention (friend request, notification).
  static void notify() {
    medium();
    play(Sfx.notify);
  }

  static void success() {
    _haptic(() async {
      await HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await HapticFeedback.mediumImpact();
    });
    play(Sfx.success);
  }

  static void error() {
    _haptic(() async {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 110));
      await HapticFeedback.heavyImpact();
    });
    play(Sfx.error);
  }

  static void refresh() {
    medium();
    play(Sfx.refresh, volume: 0.5);
  }
}
