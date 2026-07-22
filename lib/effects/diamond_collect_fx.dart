import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';

import '../game/asset_library.dart';
import '../items/item_type.dart';

/// Subway-style: diamond pops and flies toward the top HUD after a catch.
class DiamondCollectFx extends SpriteComponent {
  DiamondCollectFx({
    required Vector2 from,
    required Vector2 to,
  }) : super(
          position: from.clone(),
          size: Vector2(28, 35),
          anchor: Anchor.center,
          priority: 120,
        ) {
    _to = to.clone();
  }

  late final Vector2 _to;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    sprite = AssetLibrary.items[ItemType.diamond];
    scale = Vector2.all(0.55);
    add(
      ScaleEffect.to(
        Vector2.all(1.15),
        EffectController(duration: 0.12, curve: Curves.easeOutBack),
      ),
    );
    add(
      MoveToEffect(
        _to,
        EffectController(duration: 0.55, curve: Curves.easeInCubic),
      ),
    );
    add(
      ScaleEffect.to(
        Vector2.all(0.35),
        EffectController(duration: 0.55, curve: Curves.easeIn),
      ),
    );
    add(
      OpacityEffect.fadeOut(
        EffectController(startDelay: 0.32, duration: 0.28),
        onComplete: removeFromParent,
      ),
    );
  }
}
