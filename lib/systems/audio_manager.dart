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
      ]);
      _assetsReady = true;
    } catch (_) {
      _assetsReady = false;
    }
  }

  Future<void> play(String key) async {
    if (!enabled) return;
    _haptic(key);
    if (_assetsReady) {
      try {
        await FlameAudio.play('$key.wav', volume: 0.55);
        return;
      } catch (_) {}
    }
    switch (key) {
      case 'bomb':
        await SystemSound.play(SystemSoundType.alert);
      case 'steal':
      case 'overtake':
        await SystemSound.play(SystemSoundType.click);
        await SystemSound.play(SystemSoundType.click);
      default:
        await SystemSound.play(SystemSoundType.click);
    }
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
        HapticFeedback.selectionClick();
      case 'catch':
        HapticFeedback.selectionClick();
      default:
        break;
    }
  }
}
