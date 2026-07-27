import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/animation.dart';

import '../game/mine_rivals_game.dart';

/// Glowing cargo pile in the cart bed — denser as crystals fill the bank.
class CartCargoGlow extends PositionComponent
    with HasGameReference<MineRivalsGame> {
  CartCargoGlow()
      : super(
          anchor: Anchor.center,
          priority: 5,
        );

  final Paint _glow = Paint()..blendMode = BlendMode.plus;
  final Paint _core = Paint();
  double _pulse = 0;

  /// Pop when a crystal lands in the cart.
  void pulse() {
    _pulse = 1;
  }

  @override
  void onMount() {
    super.onMount();
    _layout();
  }

  void _layout() {
    final parentSize = (parent as PositionComponent?)?.size;
    if (parentSize == null) return;
    // Cart bed sits in the lower-middle of the back-view sprite.
    size = Vector2(parentSize.x * 0.42, parentSize.y * 0.22);
    position = Vector2(parentSize.x * 0.5, parentSize.y * 0.62);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _layout();
    if (_pulse > 0) {
      _pulse = (_pulse - dt * 2.8).clamp(0.0, 1.0);
    }
  }

  @override
  void render(Canvas canvas) {
    final n = game.stats.player.rareTotal;
    if (n <= 0 && _pulse <= 0) return;

    canvas.save();
    if (_pulse > 0) {
      final s = 1.0 + 0.28 * Curves.easeOutBack.transform(_pulse);
      canvas.translate(size.x * 0.5, size.y * 0.5);
      canvas.scale(s);
      canvas.translate(-size.x * 0.5, -size.y * 0.5);
    }

    // Tier: 1 spark → pile → rich cart.
    final shown = n <= 0 ? 1 : n;
    final tier = shown >= 18
        ? 4
        : (shown >= 10 ? 3 : (shown >= 5 ? 2 : (shown >= 2 ? 1 : 0)));
    final gems = (tier + 1).clamp(1, 5);
    final base = Offset(size.x * 0.5, size.y * 0.72);

    for (var i = 0; i < gems; i++) {
      final t = gems == 1 ? 0.0 : i / (gems - 1);
      final ox = (t - 0.5) * size.x * 0.72;
      final oy = -i * size.y * 0.12;
      final r = size.x * (0.10 + tier * 0.018 + _pulse * 0.04);
      final c = Color.lerp(
        const Color(0xFF4FC3F7),
        const Color(0xFFFFD54F),
        (i / gems).clamp(0.0, 1.0),
      )!;

      _glow.color = c.withValues(alpha: 0.22 + tier * 0.04 + _pulse * 0.2);
      canvas.drawCircle(base + Offset(ox, oy), r * 2.1, _glow);
      _core.color = c.withValues(alpha: 0.85);
      canvas.drawCircle(base + Offset(ox, oy), r * 0.72, _core);
      _core.color = const Color(0xFFFFFFFF).withValues(alpha: 0.55);
      canvas.drawCircle(
        base + Offset(ox - r * 0.15, oy - r * 0.2),
        r * 0.22,
        _core,
      );
    }
    canvas.restore();
  }
}
