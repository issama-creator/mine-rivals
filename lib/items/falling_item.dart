import 'dart:math';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/asset_library.dart';
import '../game/game_config.dart';
import '../game/mine_rivals_game.dart';
import '../player/player_component.dart';
import 'item_type.dart';

enum ItemMagnet { none, player, thief }

double _displaySizeFor(ItemType type) {
  if (type.isJewel) {
    return type == ItemType.legendary
        ? GameConfig.jewelDisplaySize * 1.12
        : GameConfig.jewelDisplaySize;
  }
  if (type.isBomb) return GameConfig.bombDisplaySize;
  if (type.isWeb) return GameConfig.webDisplaySize;
  return GameConfig.lootDisplaySize;
}

class FallingItem extends SpriteComponent with CollisionCallbacks {
  FallingItem({
    required this.type,
    required Vector2 position,
    required this.fallSpeed,
  }) : super(
          position: position,
          size: Vector2.all(_displaySizeFor(type)),
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
    // Corridor may have swapped jewel art since this instance was pooled.
    final s = AssetLibrary.items[type];
    if (s != null) sprite = s;
    if (type.isJewel) {
      final side = type == ItemType.legendary
          ? GameConfig.jewelDisplaySize * 1.12
          : GameConfig.jewelDisplaySize;
      size = Vector2.all(side);
    }
  }

  void refreshSprite() {
    final s = AssetLibrary.items[type];
    if (s != null) sprite = s;
    if (type.isJewel) {
      final side = type == ItemType.legendary
          ? GameConfig.jewelDisplaySize * 1.12
          : GameConfig.jewelDisplaySize;
      size = Vector2.all(side);
    }
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
    // background.speed already includes playRate — don't multiply again.
    final worldSpeed =
        game is MineRivalsGame ? game.background.speed : fallSpeed;
    if (!magnetized) {
      position.y += worldSpeed * dt;
    } else {
      position.y += worldSpeed * 0.35 * dt;
    }
    _pulse += dt * 4;
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);
    // Hazards (bomb/web) use the tight distance gate — not fat hitboxes.
    if (type.isHazard) return;
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
      final pulse = 0.55 + 0.2 * sin(_pulse);
      final c = Offset(size.x / 2, size.y * 0.52);
      // One soft halo — enough to read gems without heavy overdraw.
      canvas.drawCircle(
        c,
        size.x * 0.48,
        Paint()..color = type.color.withValues(alpha: 0.18 + pulse * 0.12),
      );
    }

    if (type.isWeb) {
      _renderWeb(canvas);
      return;
    }

    if (type.isBomb) {
      final warn = 0.5 + 0.5 * sin(_pulse * 1.55);
      final c = Offset(size.x / 2, size.y / 2);
      canvas.drawCircle(
        c,
        size.x * (0.40 + warn * 0.08),
        Paint()
          ..color = const Color(0xFFFF1744).withValues(alpha: 0.12 + warn * 0.22),
      );
    }

    // Plain sprite blit — no ColorFilter saveLayer (FPS).
    super.render(canvas);
  }

  /// Lightweight sticky web (6 spokes, 2 rings).
  void _renderWeb(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final r = size.x * 0.48;
    final breath = 0.9 + 0.1 * sin(_pulse * 0.9);

    final strand = Paint()
      ..color = Colors.white.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const spokes = 6;
    for (var i = 0; i < spokes; i++) {
      final a = (i / spokes) * pi * 2;
      canvas.drawLine(
        c,
        Offset(c.dx + cos(a) * r, c.dy + sin(a) * r),
        strand,
      );
    }
    for (final ring in const [0.4, 0.85]) {
      canvas.drawCircle(c, r * ring * breath, ringPaint);
    }
    canvas.drawCircle(
      c,
      2.0,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }
}
