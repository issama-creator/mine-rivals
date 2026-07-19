import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/services.dart';

import 'game_settings.dart';

/// Soft audio layer — uses assets when present, otherwise system clicks + haptics.
class AudioManager {
  bool _assetsReady = false;

  bool get enabled => GameSettings.instance.soundEnabled;

  Future<void> init() async {
    try {
      await FlameAudio.audioCache.loadAll([
        'catch.wav',
        'bomb.wav',
        'rare.wav',
        'combo.wav',
        'overtake.wav',
        'steal.wav',
        'miss.wav',
      ]).timeout(const Duration(seconds: 8));
      _assetsReady = true;
    } catch (_) {
      _assetsReady = false;
    }
  }

  Future<void> play(String key) async {
    if (!enabled) return;
    _haptic(key);
    if (_assetsReady) {
      // Fire-and-forget — awaiting audio stalls the frame on catch spam.
      unawaited(_playAsset(key));
      return;
    }
    switch (key) {
      case 'bomb':
        SystemSound.play(SystemSoundType.alert);
      case 'steal':
      case 'overtake':
        SystemSound.play(SystemSoundType.click);
        SystemSound.play(SystemSoundType.click);
      default:
        SystemSound.play(SystemSoundType.click);
    }
  }

  /// Finish sting — win feels brighter than loss (same assets, different key).
  Future<void> playFinish({required bool won}) =>
      play(won ? 'combo' : 'miss');

  /// Coin streak pitch-up — each catch a bit higher (Subway-style combo feel).
  Future<void> playCatchPitched(double pitch) async {
    if (!enabled) return;
    _haptic('catch');
    if (!_assetsReady) {
      SystemSound.play(SystemSoundType.click);
      return;
    }
    unawaited(_playAssetPitched('catch', pitch.clamp(0.92, 1.55)));
  }

  Future<void> _playAsset(String key) async {
    try {
      await FlameAudio.play('$key.wav', volume: 0.55);
    } catch (_) {}
  }

  Future<void> _playAssetPitched(String key, double pitch) async {
    try {
      final player = await FlameAudio.play('$key.wav', volume: 0.55);
      await player.setPlaybackRate(pitch);
    } catch (_) {}
  }

  void _haptic(String key) {
    switch (key) {
      case 'bomb':
        HapticFeedback.heavyImpact();
      case 'steal':
      case 'overtake':
        HapticFeedback.mediumImpact();
      case 'rare':
      case 'combo':
        HapticFeedback.lightImpact();
      case 'miss':
      case 'catch':
        HapticFeedback.selectionClick();
      default:
        break;
    }
  }
}
