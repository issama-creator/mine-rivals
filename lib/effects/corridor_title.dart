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

  @override
  void onLoad() {
    _cached = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFFFFE082),
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
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
    canvas.drawLine(
      Offset(size.x * 0.5 - lineW * 0.5, size.y - 4 + slide),
      Offset(size.x * 0.5 + lineW * 0.5, size.y - 4 + slide),
      Paint()
        ..color = const Color(0xFFFFE082).withValues(alpha: a * 0.55)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );

    final tp = _cached;
    if (tp == null) return;
    final textPaint = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFFFFE082).withValues(alpha: a * 0.96),
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

    textPaint.paint(
      canvas,
      Offset((size.x - textPaint.width) * 0.5, (size.y - textPaint.height) * 0.35 + slide),
    );
  }
}
