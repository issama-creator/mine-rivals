import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Soft ground blob so the runner feels planted on the mine path.
class GroundShadow extends PositionComponent {
  GroundShadow() : super(anchor: Anchor.center, priority: -1);

  final Paint _outer = Paint()..color = Colors.black.withValues(alpha: 0.36);
  final Paint _inner = Paint()..color = Colors.black.withValues(alpha: 0.20);

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    // Local (0,0) is top-left — center the oval on the size box / anchor.
    final c = Offset(w * 0.5, h * 0.5);
    canvas.drawOval(Rect.fromCenter(center: c, width: w, height: h), _outer);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: w * 0.7, height: h * 0.65),
      _inner,
    );
  }
}
