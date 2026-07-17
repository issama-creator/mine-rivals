import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/asset_library.dart';
import '../game/mine_rivals_game.dart';
import '../player/player_component.dart';
import 'item_type.dart';

enum ItemMagnet { none, player, thief }

class FallingItem extends SpriteComponent with CollisionCallbacks {
  FallingItem({
    required this.type,
    required Vector2 position,
    required this.fallSpeed,
  }) : super(
          position: position,
          size: Vector2.all(
            type.isJewel ? 44 : type.isBomb ? 38 * 0.9 : 38,
          ),
          anchor: Anchor.center,
          priority: 30,
        );

  final ItemType type;
  double fallSpeed;
  bool collected = false;
  bool stolen = false;
  ItemMagnet magnetBy = ItemMagnet.none;
  double life = 0;
  double _pulse = Random().nextDouble() * pi * 2;

  bool get magnetized => magnetBy != ItemMagnet.none;

  ColorFilter? get _tint {
    switch (type) {
      case ItemType.ruby:
        return const ColorFilter.mode(Color(0xFFFF5252), BlendMode.modulate);
      case ItemType.emerald:
        return const ColorFilter.mode(Color(0xFF69F0AE), BlendMode.modulate);
      case ItemType.amethyst:
        return const ColorFilter.mode(Color(0xFFE040FB), BlendMode.modulate);
      case ItemType.legendary:
        return const ColorFilter.mode(Color(0xFFFF8F00), BlendMode.modulate);
      default:
        return null;
    }
  }

  void recycle({
    required Vector2 newPosition,
    required double newSpeed,
  }) {
    collected = false;
    stolen = false;
    magnetBy = ItemMagnet.none;
    life = 0;
    position.setFrom(newPosition);
    fallSpeed = newSpeed;
    _pulse = Random().nextDouble() * pi * 2;
  }

  /// Player may magnet anything they can catch.
  void setPlayerMagnet(bool on) {
    if (on) {
      magnetBy = ItemMagnet.player;
    } else if (magnetBy == ItemMagnet.player) {
      magnetBy = ItemMagnet.none;
    }
  }

  /// Thief may magnet JEWELS only — coins/bars/bombs always phase through.
  void setThiefMagnet(bool on) {
    if (!type.isJewel) {
      if (magnetBy == ItemMagnet.thief) magnetBy = ItemMagnet.none;
      return;
    }
    if (on) {
      magnetBy = ItemMagnet.thief;
    } else if (magnetBy == ItemMagnet.thief) {
      magnetBy = ItemMagnet.none;
    }
  }

  @override
  Future<void> onLoad() async {
    await AssetLibrary.ensureLoaded();
    sprite = AssetLibrary.items[type];
    if (children.whereType<CircleHitbox>().isEmpty) {
      add(
        CircleHitbox(
          radius: size.x * (type.isBomb ? 0.38 : 0.55),
          collisionType: CollisionType.active,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (collected || stolen) return;
    // Safety: thief magnet can never stick on non-jewels.
    if (!type.isJewel && magnetBy == ItemMagnet.thief) {
      magnetBy = ItemMagnet.none;
    }
    life += dt;
    final game = findGame();
    final rate = game is MineRivalsGame ? game.playRate : 1.0;
    final worldSpeed =
        game is MineRivalsGame ? game.background.speed : fallSpeed;
    if (!magnetized) {
      position.y += worldSpeed * dt * rate;
    } else {
      position.y += worldSpeed * 0.35 * dt * rate;
    }
    _pulse += dt * 4;
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    // Only the player basket collects via collision — thief has no hitbox.
    final owner = other is PlayerComponent ? other : other.parent;
    if (owner is PlayerComponent) {
      final game = findGame();
      if (game is MineRivalsGame) {
        game.onItemCaught(this);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (type.isJewel) {
      final glow = 0.22 + 0.12 * sin(_pulse);
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        size.x * 0.5,
        Paint()..color = type.color.withValues(alpha: glow * 0.28),
      );
    }

    final tint = _tint;
    if (tint != null) {
      canvas.saveLayer(size.toRect(), Paint()..colorFilter = tint);
      super.render(canvas);
      canvas.restore();
      return;
    }
    super.render(canvas);
  }
}
