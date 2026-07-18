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

  ColorFilter? get _tint => null;

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
      // Soft halo so gems don't vanish into corridor art.
      canvas.drawCircle(
        c,
        size.x * 0.52,
        Paint()..color = type.color.withValues(alpha: 0.16 + pulse * 0.10),
      );
      canvas.drawCircle(
        c,
        size.x * 0.38,
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.10 + pulse * 0.06),
      );
      // Thin colored rim — light outline, not a heavy frame.
      canvas.drawCircle(
        c,
        size.x * 0.46,
        Paint()
          ..color = type.color.withValues(alpha: 0.45 + pulse * 0.20)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.35,
      );
    }

    if (type.isWeb) {
      _renderWeb(canvas);
      return;
    }

    if (type.isBomb) {
      final warn = 0.5 + 0.5 * sin(_pulse * 1.55);
      final c = Offset(size.x / 2, size.y / 2);
      // Soft pulsing red — no hard permanent ring.
      canvas.drawCircle(
        c,
        size.x * (0.42 + warn * 0.10),
        Paint()
          ..color = const Color(0xFFFF1744).withValues(alpha: 0.10 + warn * 0.28),
      );
      canvas.drawCircle(
        c,
        size.x * (0.28 + warn * 0.06),
        Paint()
          ..color = const Color(0xFFFF5252).withValues(alpha: 0.06 + warn * 0.18),
      );
    }

    final tint = type.isBomb
        ? const ColorFilter.matrix(<double>[
            // Boost red / lift midtones so the bomb pops on brown corridors.
            1.35, 0.05, 0.05, 0, 18,
            0.05, 1.05, 0.05, 0, 8,
            0.00, 0.00, 1.00, 0, 4,
            0, 0, 0, 1, 0,
          ])
        : _tint;
    if (tint != null) {
      canvas.saveLayer(size.toRect(), Paint()..colorFilter = tint);
      super.render(canvas);
      canvas.restore();
      return;
    }
    super.render(canvas);
  }

  /// Procedural sticky spider web — no sprite asset needed.
  void _renderWeb(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final r = size.x * 0.48;
    final breath = 0.85 + 0.15 * sin(_pulse * 0.9);

    // Soft sticky halo.
    canvas.drawCircle(
      c,
      r * breath,
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );

    const spokes = 8;
    final strand = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final strandSoft = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Radial spokes.
    for (var i = 0; i < spokes; i++) {
      final a = (i / spokes) * pi * 2;
      final p = Offset(c.dx + cos(a) * r, c.dy + sin(a) * r);
      canvas.drawLine(c, p, strand);
    }

    // Concentric rings connecting the spokes.
    for (final ring in const [0.32, 0.62, 0.92]) {
      final rr = r * ring * breath;
      final path = Path();
      for (var i = 0; i <= spokes; i++) {
        final a = (i / spokes) * pi * 2;
        final p = Offset(c.dx + cos(a) * rr, c.dy + sin(a) * rr);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          // Slight inward sag between spokes for a woven look.
          final aPrev = ((i - 1) / spokes) * pi * 2;
          final mid = (a + aPrev) / 2;
          final sag = rr * 0.82;
          final cp = Offset(c.dx + cos(mid) * sag, c.dy + sin(mid) * sag);
          path.quadraticBezierTo(cp.dx, cp.dy, p.dx, p.dy);
        }
      }
      canvas.drawPath(path, strandSoft);
    }

    // Center knot.
    canvas.drawCircle(
      c,
      2.2,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }
}
