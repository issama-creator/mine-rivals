import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/asset_library.dart';
import '../game/game_config.dart';

/// Repeats the active corridor vertically (pixel-snapped, no seam overlap).
class ParallaxBackground extends PositionComponent {
  ParallaxBackground({required Vector2 size})
      : super(size: size, priority: -100);

  double scroll = 0;
  double speed = 260;
  int corridorIndex = 0;
  Sprite? _tunnel;
  Sprite? _prevTunnel;

  double _enterT = 1;
  static const double _enterSec = 1.35;

  Paint? _hudFadePaint;
  Size? _hudFadeSize;
  // Nearest-neighbor — bilinear smear at tile joins looks like a "transparent" band.
  final Paint _tilePaint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false
    ..color = const Color(0xFFFFFFFF);
  final Paint _fadePaint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;
  final Paint _clearPaint = Paint()..color = const Color(0xFF0E0A06);
  final Paint _dimPaint = Paint();
  final Vector2 _tilePos = Vector2.zero();
  final Vector2 _tileSize = Vector2.zero();

  bool get isEnteringCorridor => _enterT < 1;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (!AssetLibrary.ready) {
      await AssetLibrary.ensureLoaded(prefetchRest: false);
    }
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
    canvas.drawRect(rect, _clearPaint);

    final prev = _prevTunnel;
    final next = _tunnel;
    final entering = prev != null && next != null && _enterT < 1;

    if (entering) {
      final t = Curves.easeInOutCubic.transform(_enterT);
      _drawTiled(canvas, prev, opacity: 1.0 - t);
      _drawTiled(canvas, next, opacity: t);
      final dim = math.sin(math.pi * t) * 0.12;
      if (dim > 0.01) {
        _dimPaint.color = Colors.black.withValues(alpha: dim);
        canvas.drawRect(rect, _dimPaint);
      }
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
    if (size.x < 8 || size.y < 8) return;

    final srcW = sprite.srcSize.x;
    final srcH = sprite.srcSize.y;
    if (srcW <= 0 || srcH <= 0) return;

    // Integer tile size so joins land on pixel boundaries.
    final tileW = size.x.roundToDouble();
    final tileH = math.max(8, (srcH * (tileW / srcW)).round()).toDouble();
    final period = tileH;
    // Pixel-snap scroll so the join doesn't smear between rows.
    final offset = (scroll % period).floorToDouble();

    final fading = opacity < 0.999;
    final paint = fading ? _fadePaint : _tilePaint;
    if (fading) {
      paint.color = Color.fromRGBO(255, 255, 255, opacity);
    }

    _tileSize.setValues(tileW, tileH);
    var drawn = 0;
    for (var y = -tileH + offset; y < size.y + tileH && drawn < 8; y += period) {
      drawn++;
      _tilePos.setValues(0, y);
      sprite.render(
        canvas,
        position: _tilePos,
        size: _tileSize,
        overridePaint: paint,
      );
    }
  }

  void setWorldSpeed(double metersPerSec) {
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
