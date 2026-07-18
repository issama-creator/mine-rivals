import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/asset_library.dart';
import '../game/game_config.dart';

/// Repeats the active corridor vertically — soft-blends seams so the join
/// is not a hard cut (bgc art is not perfectly tileable).
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

  /// Soft “run into the next shaft”.
  static const double _enterSec = 1.55;

  /// Soft seam only — larger values double lanterns/gems on the walls.
  static const double _seamBlend = 0.08;

  Paint? _hudFadePaint;
  Size? _hudFadeSize;

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

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _hudFadePaint = null;
    _hudFadeSize = null;
  }

  /// Begin a soft enter into biome [index] (0..corridorCount-1).
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
      _drawTiled(canvas, prev, opacity: (1.0 - eased).clamp(0.0, 1.0));
      _drawTiled(canvas, next, opacity: eased.clamp(0.0, 1.0));
    } else if (next != null) {
      _drawTiled(canvas, next, opacity: 1);
    }

    _drawHudFade(canvas, rect);
  }

  void _drawHudFade(Canvas canvas, Rect rect) {
    final sz = Size(rect.width, rect.height);
    if (_hudFadePaint == null || _hudFadeSize != sz) {
      _hudFadeSize = sz;
      _hudFadePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.4),
            Colors.transparent,
            Colors.transparent,
          ],
          stops: const [0, 0.16, 1],
        ).createShader(rect);
    }
    canvas.drawRect(rect, _hudFadePaint!);
  }

  void _drawTiled(Canvas canvas, Sprite sprite, {required double opacity}) {
    if (opacity <= 0.01) return;

    final drawW = size.x;
    final drawH = sprite.srcSize.y * (drawW / sprite.srcSize.x);
    final blend = drawH * _seamBlend;
    // Step shorter than tile height so neighbors overlap for the crossfade.
    final period = drawH - blend;
    final offset = scroll % period;

    final fading = opacity < 0.999;
    if (fading) {
      canvas.saveLayer(
        size.toRect(),
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
      );
    }

    for (var y = -drawH + offset; y < size.y + drawH; y += period) {
      _drawSeamlessTile(canvas, sprite, y, drawW, drawH, blend);
    }

    if (fading) {
      canvas.restore();
    }
  }

  /// Full tile with transparent→opaque ramp on the top edge so it melts
  /// into the previous tile instead of showing a hard glue line.
  void _drawSeamlessTile(
    Canvas canvas,
    Sprite sprite,
    double y,
    double drawW,
    double drawH,
    double blend,
  ) {
    // Snap to device pixels — kills 1px black hairlines from subpixel gaps.
    final yy = y.roundToDouble();
    final ww = drawW.ceilToDouble();
    final hh = drawH.ceilToDouble() + 1; // +1px overlap safety
    final layer = Rect.fromLTWH(0, yy, ww, hh);
    canvas.saveLayer(layer, Paint());
    sprite.render(
      canvas,
      position: Vector2(0, yy),
      size: Vector2(ww, drawH),
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
          stops: [0.0, (blend / drawH).clamp(0.04, 0.35), 1.0],
        ).createShader(layer),
    );
    canvas.restore();
  }

  void setWorldSpeed(double metersPerSec) {
    // Scroll tracks pace hard — ~3× visual speed from start → end.
    speed = 90 + metersPerSec * 12.5;
  }

  void resetCorridors() {
    corridorIndex = 0;
    _tunnel = AssetLibrary.corridorAt(0);
    _prevTunnel = null;
    _enterT = 1;
    scroll = 0;
  }
}
