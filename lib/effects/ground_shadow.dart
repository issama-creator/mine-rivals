import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Soft ground blob so the runner feels planted on the mine path.
class GroundShadow extends PositionComponent {
  GroundShadow() : super(anchor: Anchor.center, priority: -1);

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Paint()..color = Colors.black.withValues(alpha: 0.38),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w * 0.7, height: h * 0.65),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );
  }
}
