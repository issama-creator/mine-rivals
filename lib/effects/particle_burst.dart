import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class DustPuff extends PositionComponent {
  DustPuff({required Vector2 position})
      : super(position: position, anchor: Anchor.center, priority: 5);

  final Random _rng = Random();
  late final List<_Particle> _particles;
  double _life = 0.45;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _particles = List.generate(8, (_) {
      final a = _rng.nextDouble() * pi * 2;
      final s = 40 + _rng.nextDouble() * 80;
      return _Particle(
        velocity: Vector2(cos(a), sin(a)) * s,
        radius: 2 + _rng.nextDouble() * 4,
      );
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    _life -= dt;
    for (final p in _particles) {
      p.offset += p.velocity * dt;
      p.velocity.y += 40 * dt;
    }
    if (_life <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (_life / 0.45).clamp(0.0, 1.0);
    final paint = Paint()..color = Colors.brown.withValues(alpha: 0.35 * t);
    for (final p in _particles) {
      canvas.drawCircle(Offset(p.offset.x, p.offset.y), p.radius * t, paint);
    }
  }
}

class ParticleBurst extends PositionComponent {
  ParticleBurst({
    required Vector2 position,
    required this.color,
    this.count = 14,
  }) : super(position: position, anchor: Anchor.center, priority: 40);

  final Color color;
  final int count;
  final Random _rng = Random();
  late final List<_Particle> _particles;
  double _life = 0.55;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _particles = List.generate(count, (_) {
      final a = _rng.nextDouble() * pi * 2;
      final s = 60 + _rng.nextDouble() * 140;
      return _Particle(
        velocity: Vector2(cos(a), sin(a)) * s,
        radius: 2 + _rng.nextDouble() * 3.5,
      );
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    _life -= dt;
    for (final p in _particles) {
      p.offset += p.velocity * dt;
      p.velocity *= 0.96;
    }
    if (_life <= 0) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final t = (_life / 0.55).clamp(0.0, 1.0);
    final paint = Paint()..color = color.withValues(alpha: 0.45 * t);
    for (final p in _particles) {
      canvas.drawCircle(Offset(p.offset.x, p.offset.y), p.radius * 0.85, paint);
    }
  }
}

class _Particle {
  _Particle({required this.velocity, required this.radius});
  Vector2 offset = Vector2.zero();
  Vector2 velocity;
  double radius;
}
