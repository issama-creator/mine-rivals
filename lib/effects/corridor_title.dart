import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Soft top title when entering a new corridor — slides in, holds, fades out.
class CorridorTitle extends PositionComponent with HasPaint {
  CorridorTitle({
    required this.label,
    required Vector2 position,
  }) : super(
          position: position,
          size: Vector2(260, 44),
          anchor: Anchor.topCenter,
          priority: 80,
        );

  final String label;
  double _life = 0;
  static const double _duration = 2.4;
  TextPainter? _cached;
  int _alphaBucket = -1;
  final Paint _linePaint = Paint()
    ..strokeWidth = 1.4
    ..strokeCap = StrokeCap.round;

  @override
  void onLoad() {
    _rebuildText(1);
  }

  void _rebuildText(double a) {
    _cached = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Color(0xFFFFE082).withValues(alpha: a * 0.96),
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          shadows: [
            Shadow(
              blurRadius: 12,
              color: Colors.black.withValues(alpha: a * 0.75),
            ),
            Shadow(
              blurRadius: 18,
              color: const Color(0xFFFFB300).withValues(alpha: a * 0.25),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _life += dt;
    if (_life < 0.45) {
      opacity = Curves.easeOutCubic.transform((_life / 0.45).clamp(0.0, 1.0));
    } else if (_life > _duration - 0.7) {
      opacity = Curves.easeIn
          .transform(((_duration - _life) / 0.7).clamp(0.0, 1.0));
    } else {
      opacity = 1;
    }
    if (_life >= _duration && isMounted) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final a = opacity.clamp(0.0, 1.0);
    if (a <= 0.01) return;

    // Gentle drop-in from above while fading in.
    final slide = (1 - a) * 10;

    // Soft gold underline.
    final lineW = 72.0 * a;
    _linePaint.color = const Color(0xFFFFE082).withValues(alpha: a * 0.55);
    canvas.drawLine(
      Offset(size.x * 0.5 - lineW * 0.5, size.y - 4 + slide),
      Offset(size.x * 0.5 + lineW * 0.5, size.y - 4 + slide),
      _linePaint,
    );

    // Rebuild text ~20 alpha steps — avoids per-frame TextPainter alloc.
    final bucket = (a * 20).round();
    if (bucket != _alphaBucket) {
      _alphaBucket = bucket;
      _rebuildText(a);
    }
    final tp = _cached;
    if (tp == null) return;

    tp.paint(
      canvas,
      Offset((size.x - tp.width) * 0.5, (size.y - tp.height) * 0.35 + slide),
    );
  }
}
