import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';

class FloatingText extends TextComponent with HasPaint {
  FloatingText({
    required String text,
    required Vector2 position,
    Color color = Colors.white,
    double fontSize = 22,
  }) : super(
          text: text,
          position: position,
          anchor: Anchor.center,
          textRenderer: TextPaint(
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              shadows: const [
                Shadow(blurRadius: 4, color: Colors.black54),
              ],
            ),
          ),
        );

  double _life = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(
      MoveByEffect(
        Vector2(0, -56),
        EffectController(duration: 0.85, curve: Curves.easeOutCubic),
      ),
    );
    add(
      OpacityEffect.fadeOut(
        EffectController(duration: 0.85, curve: Curves.easeIn),
        onComplete: removeFromParent,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    _life += dt;
    // Safety: never leave popup text stuck on screen.
    if (_life > 1.4 && isMounted) {
      removeFromParent();
    }
  }
}
