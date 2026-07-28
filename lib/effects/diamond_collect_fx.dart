import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';

import '../game/asset_library.dart';
import '../items/item_type.dart';

/// Crystal pops and flies into the cart bed after a catch.
class DiamondCollectFx extends SpriteComponent {
  DiamondCollectFx({
    required Vector2 from,
    required Vector2 to,
    this.onArrive,
  }) : super(
          position: from.clone(),
          size: Vector2(17.1, 20.9),
          anchor: Anchor.center,
          priority: 120,
        ) {
    _to = to.clone();
  }

  late final Vector2 _to;
  final VoidCallback? onArrive;
  bool _arrived = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = AssetLibrary.cartGem ?? AssetLibrary.items[ItemType.diamond];
    scale = Vector2.all(0.5);
    add(
      ScaleEffect.to(
        Vector2.all(0.85),
        EffectController(duration: 0.12, curve: Curves.easeOutBack),
      ),
    );
    add(
      MoveToEffect(
        _to,
        EffectController(duration: 0.48, curve: Curves.easeInCubic),
        onComplete: () {
          if (_arrived) return;
          _arrived = true;
          onArrive?.call();
        },
      ),
    );
    add(
      ScaleEffect.to(
        Vector2.all(0.22),
        EffectController(duration: 0.48, curve: Curves.easeIn),
      ),
    );
    add(
      OpacityEffect.fadeOut(
        EffectController(startDelay: 0.28, duration: 0.24),
        onComplete: removeFromParent,
      ),
    );
  }
}
