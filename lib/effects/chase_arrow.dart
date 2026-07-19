import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Faint “he’s still back there” marker when the thief is barely on screen.
class ChaseArrow extends PositionComponent {
  ChaseArrow()
    : super(
          size: Vector2(36, 40),
          anchor: Anchor.bottomCenter,
          priority: 40,
        );

  double _pulse = 0;
  double _shown = 0;
  double targetShown = 0;
  double laneX = 0;
  final Paint _fill = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final Path _path = Path();

  void setActive(bool on) {
    targetShown = on ? 1 : 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _pulse += dt * 2.4;
    _shown += (targetShown - _shown) * (1 - (1 / (1 + 8 * dt)));
    position.x += (laneX - position.x) * (1 - (1 / (1 + 10 * dt)));
  }

  @override
  void render(Canvas canvas) {
    if (_shown < 0.02) return;

    final bob = sin(_pulse) * 3.5;
    final alpha = (0.18 + 0.14 * (0.5 + 0.5 * sin(_pulse))) * _shown;
    _fill.color = Color.fromRGBO(255, 200, 120, alpha);
    _stroke.color = Color.fromRGBO(40, 20, 10, alpha * 0.55);

    final cx = size.x * 0.5;
    final top = 4 + bob;
    _path
      ..reset()
      ..moveTo(cx, size.y - 2 + bob)
      ..lineTo(cx - 12, top + 10)
      ..lineTo(cx - 5, top + 10)
      ..lineTo(cx - 5, top)
      ..lineTo(cx + 5, top)
      ..lineTo(cx + 5, top + 10)
      ..lineTo(cx + 12, top + 10)
      ..close();
    canvas.drawPath(_path, _fill);
    canvas.drawPath(_path, _stroke);
  }
}
