import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Soft top title when entering a new corridor — shows ~2s then fades away.
class CorridorTitle extends PositionComponent with HasPaint {
  CorridorTitle({
    required this.label,
    required Vector2 position,
  }) : super(
          position: position,
          size: Vector2(280, 36),
          anchor: Anchor.topCenter,
          priority: 80,
        );

  final String label;
  double _life = 0;
  static const double _duration = 2.0;

  @override
  void update(double dt) {
    super.update(dt);
    _life += dt;
    // Fade in 0–0.35s, hold, fade out last 0.55s.
    if (_life < 0.35) {
      opacity = (_life / 0.35).clamp(0.0, 1.0);
    } else if (_life > _duration - 0.55) {
      opacity = ((_duration - _life) / 0.55).clamp(0.0, 1.0);
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

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFFFFE082).withValues(alpha: a * 0.92),
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          shadows: [
            Shadow(
              blurRadius: 8,
              color: Colors.black.withValues(alpha: a * 0.65),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(
      canvas,
      Offset((size.x - tp.width) * 0.5, (size.y - tp.height) * 0.5),
    );
  }
}
