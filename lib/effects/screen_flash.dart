import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Soft full-screen tint — keep it subtle so it doesn't burn the eyes.
class ScreenFlash extends Component {
  ScreenFlash({
    this.color = const Color(0xFFEF5350),
    this.peakAlpha = 0.14,
    this.duration = 0.32,
  }) : super(priority: 200);

  final Color color;
  final double peakAlpha;
  final double duration;
  double _t = 0;
  final Paint _paint = Paint();
  double _lastW = -1;
  double _lastH = -1;
  late Rect _rect;

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_t >= duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final game = findGame();
    if (game == null) return;
    final w = game.size.x;
    final h = game.size.y;
    if (w != _lastW || h != _lastH) {
      _lastW = w;
      _lastH = h;
      _rect = Rect.fromLTWH(0, 0, w, h);
    }
    final t = (_t / duration).clamp(0.0, 1.0);
    // Soft rise, long soft fall.
    final a = t < 0.25
        ? (t / 0.25) * peakAlpha
        : peakAlpha * (1 - ((t - 0.25) / 0.75));
    _paint.color = color.withValues(alpha: a.clamp(0.0, 1.0));
    canvas.drawRect(_rect, _paint);
  }
}
