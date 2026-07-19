import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Soft ground blob so the runner feels planted on the mine path.
class GroundShadow extends PositionComponent {
  GroundShadow() : super(anchor: Anchor.center, priority: -1);

  final Paint _outer = Paint()..color = Colors.black.withValues(alpha: 0.38);
  final Paint _inner = Paint()..color = Colors.black.withValues(alpha: 0.22);

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      _outer,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: w * 0.7, height: h * 0.65),
      _inner,
    );
  }
}