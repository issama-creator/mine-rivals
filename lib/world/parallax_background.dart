import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/asset_library.dart';
import '../game/game_config.dart';

/// Repeats the active corridor vertically.
/// Biome changes: long soft wipe + crossfade (enter-the-tunnel feel).
class ParallaxBackground extends PositionComponent {
  ParallaxBackground({required Vector2 size})
      : super(size: size, priority: -100);

  double scroll = 0;
  double speed = 260;
  int corridorIndex = 0;
  Sprite? _tunnel;
  Sprite? _prevTunnel;

  /// 0 = still old corridor, 1 = fully in the new one.
  double _enterT = 1;

  static const double _seamBlend = 0.07;
  /// Soft “run into the next shaft” — longer = prettier.
  static const double _enterSec = 3.8;

  bool get isEnteringCorridor => _enterT < 1;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await AssetLibrary.ensureLoaded();
    corridorIndex = 0;
    _tunnel = AssetLibrary.corridorAt(0);
    _prevTunnel = null;
    _enterT = 1;
  }

  /// Begin a smooth enter into biome [index] (0..corridorCount-1).
  void setCorridorIndex(int index) {
    final next = index.clamp(0, GameConfig.corridorCount - 1);
    if (next == corridorIndex && _tunnel != null) return;
    _prevTunnel = _tunnel;
    corridorIndex = next;
    _tunnel = AssetLibrary.corridorAt(next);
    _enterT = _prevTunnel == null ? 1 : 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    scroll += speed * dt;
    if (_enterT < 1) {
      _enterT = (_enterT + dt / _enterSec).clamp(0.0, 1.0);
      if (_enterT >= 1) _prevTunnel = null;
    }
  }

  @override
  void render(Canvas canvas) {
    final rect = size.toRect();
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0E0A06));

    final prev = _prevTunnel;
    final next = _tunnel;
    final entering = prev != null && next != null && _enterT < 1;

    if (entering) {
      final eased = Curves.easeInOutCubic.transform(_enterT);
      // Old dissolves while new blooms in — no hard cut.
      _drawTiled(
        canvas,
        prev,
        opacity: (1.0 - Curves.easeIn.transform(eased) * 0.92)
            .clamp(0.08, 1.0),
      );
      _drawEnterWipe(
        canvas,
        next,
        _enterT,
        opacity: 0.22 + Curves.easeOutCubic.transform(eased) * 0.78,
      );
      _drawThresholdVeil(canvas, _enterT);
    } else if (next != null) {
      _drawTiled(canvas, next, opacity: 1);
    }

    // Soft top fade for HUD readability.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.4),
            Colors.transparent,
            Colors.transparent,
          ],
          stops: const [0, 0.16, 1],
        ).createShader(rect),
    );
  }

  /// Reveals [sprite] from the top downward with a wide soft edge.
  void _drawEnterWipe(
    Canvas canvas,
    Sprite sprite,
    double t, {
    required double opacity,
  }) {
    final eased = Curves.easeInOutCubic.transform(t);
    // Extra-wide feather — the whole reveal stays soft.
    final edge = 0.38;
    final reveal = (eased * (1 + edge)).clamp(0.0, 1.0 + edge);

    canvas.saveLayer(
      size.toRect(),
      Paint()..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0)),
    );
    _drawTiled(canvas, sprite, opacity: 1);
    canvas.drawRect(
      size.toRect(),
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [
            0.0,
            (reveal - edge).clamp(0.0, 1.0),
            reveal.clamp(0.0, 1.0),
            1.0,
          ],
        ).createShader(size.toRect()),
    );
    canvas.restore();
  }

  /// Soft warm breath at the midpoint — shaft threshold, not a flash.
  void _drawThresholdVeil(Canvas canvas, double t) {
    final mid = Curves.easeInOut.transform(
      (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0),
    );
    if (mid <= 0.01) return;
    canvas.drawRect(
      size.toRect(),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.15),
          radius: 1.05,
          colors: [
            const Color(0xFFFFE0B2).withValues(alpha: 0.07 * mid),
            Colors.black.withValues(alpha: 0.14 * mid),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(size.toRect()),
    );
  }

  void _drawTiled(Canvas canvas, Sprite sprite, {required double opacity}) {
    final drawW = size.x;
    final drawH = sprite.srcSize.y * (drawW / sprite.srcSize.x);
    final blend = drawH * _seamBlend;
    final period = drawH - blend;
    final offset = scroll % period;

    final paint = opacity >= 0.999
        ? null
        : (Paint()..color = Color.fromRGBO(255, 255, 255, opacity));

    if (paint != null) {
      canvas.saveLayer(size.toRect(), paint);
    }

    for (var y = -drawH + offset; y < size.y + drawH; y += period) {
      _drawSeamlessTile(canvas, sprite, y, drawW, drawH, blend);
    }

    if (paint != null) {
      canvas.restore();
    }
  }

  void _drawSeamlessTile(
    Canvas canvas,
    Sprite sprite,
    double y,
    double drawW,
    double drawH,
    double blend,
  ) {
    final layer = Rect.fromLTWH(0, y, drawW, drawH);
    canvas.saveLayer(layer, Paint());
    sprite.render(
      canvas,
      position: Vector2(0, y),
      size: Vector2(drawW, drawH),
    );
    canvas.drawRect(
      layer,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00FFFFFF),
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
          ],
          stops: [0.0, (blend / drawH).clamp(0.05, 0.45), 1.0],
        ).createShader(layer),
    );
    canvas.restore();
  }

  void setWorldSpeed(double metersPerSec) {
    speed = 180 + metersPerSec * 5.0;
  }

  void resetCorridors() {
    corridorIndex = 0;
    _tunnel = AssetLibrary.corridorAt(0);
    _prevTunnel = null;
    _enterT = 1;
    scroll = 0;
  }
}
