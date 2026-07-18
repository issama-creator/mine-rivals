import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/game_config.dart';
import '../game/mine_rivals_game.dart';

/// Short golden spark trail while a coin streak is alive.
class GoldTrail extends Component with HasGameReference<MineRivalsGame> {
  GoldTrail() : super(priority: 18);

  final List<_Spark> _sparks = [];
  final Random _rng = Random();
  double _emit = 0;
  final Paint _paint = Paint();

  @override
  void update(double dt) {
    super.update(dt);
    final g = game;
    if (!g.started || g.finished) {
      _sparks.clear();
      return;
    }

    final active = g.goldStreak >= GameConfig.coinTrailFromStreak;
    if (active) {
      _emit += dt;
      final rate = g.coinMultiplier >= 3 ? 0.028 : 0.045;
      if (_emit >= rate) {
        _emit = 0;
        final p = g.player.position;
        _sparks.add(
          _Spark(
            pos: Vector2(
              p.x + (_rng.nextDouble() - 0.5) * 14,
              p.y - 8 - _rng.nextDouble() * 10,
            ),
            life: 0.28 + _rng.nextDouble() * 0.12,
            radius: 2.2 + _rng.nextDouble() * 2.4,
          ),
        );
      }
    }

    for (var i = _sparks.length - 1; i >= 0; i--) {
      final s = _sparks[i];
      s.life -= dt;
      s.pos.y += 28 * dt;
      s.pos.x += s.drift * dt;
      if (s.life <= 0) _sparks.removeAt(i);
    }
    if (_sparks.length > 28) {
      _sparks.removeRange(0, _sparks.length - 28);
    }
  }

  @override
  void render(Canvas canvas) {
    for (final s in _sparks) {
      final t = (s.life / 0.4).clamp(0.0, 1.0);
      _paint.color = Color.lerp(
        const Color(0xFFFF8F00),
        const Color(0xFFFFF59D),
        t,
      )!.withValues(alpha: 0.55 * t);
      canvas.drawCircle(Offset(s.pos.x, s.pos.y), s.radius * t, _paint);
    }
  }
}

class _Spark {
  _Spark({required this.pos, required this.life, required this.radius})
      : drift = (Random().nextDouble() - 0.5) * 40;

  Vector2 pos;
  double life;
  double radius;
  final double drift;
}
