import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Faint chase marker — bottom when thief is behind, top when he bolted ahead.
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
  /// True = point toward top of screen (thief ahead / off-screen).
  bool pointUp = false;
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
    final hot = pointUp ? 1.35 : 1.0;
    final alpha = (0.22 + 0.16 * (0.5 + 0.5 * sin(_pulse))) * _shown * hot;
    _fill.color = pointUp
        ? Color.fromRGBO(255, 120, 90, alpha.clamp(0.0, 1.0))
        : Color.fromRGBO(255, 200, 120, alpha.clamp(0.0, 1.0));
    _stroke.color = Color.fromRGBO(40, 20, 10, alpha * 0.55);

    final cx = size.x * 0.5;
    canvas.save();
    if (pointUp) {
      canvas.translate(cx, size.y * 0.5);
      canvas.rotate(pi);
      canvas.translate(-cx, -size.y * 0.5);
    }
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
    canvas.restore();
  }
}
