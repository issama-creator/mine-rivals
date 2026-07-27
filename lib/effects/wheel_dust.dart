import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Tiny grit under the cart “wheels” — sells rolling on the path.
class WheelDust extends PositionComponent {
  WheelDust({required Vector2 position, this.onDone})
      : super(position: position, anchor: Anchor.center, priority: 4);

  final VoidCallback? onDone;
  final Random _rng = Random();
  late final List<_Bit> _bits;
  double _life = 0.28;
  final Paint _paint = Paint();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _bits = List.generate(3, (_) {
      final a = -pi * 0.15 + _rng.nextDouble() * pi * 0.3;
      final s = 18 + _rng.nextDouble() * 28;
      return _Bit(
        vx: cos(a) * s * (_rng.nextBool() ? 1 : -1) * 0.35,
        vy: 22 + _rng.nextDouble() * 30,
        radius: 1.2 + _rng.nextDouble() * 1.8,
      );
    });
  }

  @override
  void onRemove() {
    onDone?.call();
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _life -= dt;
    for (final b in _bits) {
      b.ox += b.vx * dt;
      b.oy += b.vy * dt;
    }
    if (_life <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (_life / 0.28).clamp(0.0, 1.0);
    _paint.color = const Color(0xFF5D4037).withValues(alpha: 0.22 * t);
    for (final b in _bits) {
      canvas.drawCircle(Offset(b.ox, b.oy), b.radius * t, _paint);
    }
  }
}

class _Bit {
  _Bit({required this.vx, required this.vy, required this.radius});
  double ox = 0;
  double oy = 0;
  final double vx;
  final double vy;
  final double radius;
}
