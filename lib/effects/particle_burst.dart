import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class DustPuff extends PositionComponent {
  DustPuff({required Vector2 position, this.onDone})
      : super(position: position, anchor: Anchor.center, priority: 5);

  final VoidCallback? onDone;
  final Random _rng = Random();
  late final List<_Particle> _particles;
  double _life = 0.35;
  final Paint _paint = Paint();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _particles = List.generate(4, (_) {
      final a = _rng.nextDouble() * pi * 2;
      final s = 30 + _rng.nextDouble() * 55;
      return _Particle(
        vx: cos(a) * s,
        vy: sin(a) * s,
        radius: 2 + _rng.nextDouble() * 3,
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
    for (final p in _particles) {
      p.ox += p.vx * dt;
      p.oy += p.vy * dt;
      p.vy += 40 * dt;
    }
    if (_life <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (_life / 0.35).clamp(0.0, 1.0);
    _paint.color = Colors.brown.withValues(alpha: 0.28 * t);
    for (final p in _particles) {
      canvas.drawCircle(Offset(p.ox, p.oy), p.radius * t, _paint);
    }
  }
}

class ParticleBurst extends PositionComponent {
  ParticleBurst({
    required Vector2 position,
    required this.color,
    this.count = 8,
  }) : super(position: position, anchor: Anchor.center, priority: 40);

  final Color color;
  final int count;
  final Random _rng = Random();
  late final List<_Particle> _particles;
  double _life = 0.4;
  final Paint _paint = Paint();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _particles = List.generate(count, (_) {
      final a = _rng.nextDouble() * pi * 2;
      final s = 50 + _rng.nextDouble() * 110;
      return _Particle(
        vx: cos(a) * s,
        vy: sin(a) * s,
        radius: 2 + _rng.nextDouble() * 3,
      );
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    _life -= dt;
    for (final p in _particles) {
      p.ox += p.vx * dt;
      p.oy += p.vy * dt;
      p.vx *= 0.96;
      p.vy *= 0.96;
    }
    if (_life <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (_life / 0.4).clamp(0.0, 1.0);
    _paint.color = color.withValues(alpha: 0.4 * t);
    for (final p in _particles) {
      canvas.drawCircle(Offset(p.ox, p.oy), p.radius * 0.85, _paint);
    }
  }
}

/// Tiny basket spark on coin catch (1–2 frames of juice).
class BasketSpark extends PositionComponent {
  BasketSpark({required Vector2 position})
      : super(position: position, anchor: Anchor.center, priority: 45);

  double _life = 0.12;
  final Paint _paint = Paint()..color = const Color(0xFFFFF59D);

  @override
  void update(double dt) {
    super.update(dt);
    _life -= dt;
    if (_life <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (_life / 0.12).clamp(0.0, 1.0);
    _paint.color = const Color(0xFFFFF59D).withValues(alpha: 0.85 * t);
    canvas.drawCircle(Offset.zero, 7 + 5 * (1 - t), _paint);
    _paint.color = const Color(0xFFFFC107).withValues(alpha: 0.55 * t);
    canvas.drawCircle(Offset.zero, 3.5 * t, _paint);
  }
}

class _Particle {
  _Particle({required this.vx, required this.vy, required this.radius});
  double ox = 0;
  double oy = 0;
  double vx;
  double vy;
  double radius;
}
