import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/services.dart';

import 'game_settings.dart';

/// Soft audio layer — uses assets when present, otherwise system clicks + haptics.
class AudioManager {
  bool _assetsReady = false;
  Future<void>? _initFuture;

  /// Short sfx players — must be disposed or they pile up and stall hot restart.
  static const _maxSfxPlayers = 8;
  final List<AudioPlayer> _sfx = [];

  bool get enabled => GameSettings.instance.soundEnabled;

  Future<void> init() {
    _initFuture ??= _initOnce();
    return _initFuture!;
  }

  Future<void> _initOnce() async {
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

  Future<void> playFinish({required bool won}) =>
      play(won ? 'combo' : 'miss');

  Future<void> playCatchPitched(double pitch) async {
    if (!enabled) return;
    _haptic('catch');
    if (!_assetsReady) {
      SystemSound.play(SystemSoundType.click);
      return;
    }
    unawaited(_playAssetPitched('catch', pitch.clamp(0.92, 1.55)));
  }

  Future<void> playStealLaugh() async {
    if (!enabled) return;
    _haptic('steal');
    if (!_assetsReady) {
      SystemSound.play(SystemSoundType.click);
      SystemSound.play(SystemSoundType.click);
      return;
    }
    unawaited(_playAssetPitched('steal', 0.82));
    unawaited(Future<void>.delayed(const Duration(milliseconds: 90), () {
      unawaited(_playAssetPitched('steal', 1.08));
    }));
  }

  Future<void> playCheckpoint() => play('combo');

  Future<void> _playAsset(String key) async {
    await _playAssetPitched(key, 1.0);
  }

  Future<void> _playAssetPitched(String key, double pitch) async {
    try {
      await _trimSfx();
      final player = await FlameAudio.play('$key.wav', volume: 0.55);
      _sfx.add(player);
      if (pitch != 1.0) {
        await player.setPlaybackRate(pitch);
      }
      player.onPlayerComplete.listen((_) {
        unawaited(_disposePlayer(player));
      });
    } catch (_) {}
  }

  Future<void> _trimSfx() async {
    _sfx.removeWhere((p) {
      final s = p.state;
      return s == PlayerState.stopped || s == PlayerState.completed;
    });
    while (_sfx.length >= _maxSfxPlayers) {
      await _disposePlayer(_sfx.removeAt(0));
    }
  }

  Future<void> _disposePlayer(AudioPlayer player) async {
    _sfx.remove(player);
    try {
      await player.dispose();
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
