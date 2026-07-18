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
  if (type.isMagnet) return GameConfig.magnetDisplaySize;
  if (type.isPit) return GameConfig.pitDisplaySize;
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
  final Paint _glowPaint = Paint();
  final Paint _webStrand = Paint()
    ..color = Colors.white.withValues(alpha: 0.78)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.15
    ..strokeCap = StrokeCap.round;
  final Paint _webRing = Paint()
    ..color = Colors.white.withValues(alpha: 0.4)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _webHub = Paint()..color = Colors.white.withValues(alpha: 0.85);

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
    sprite = _spriteForType(type);
    if (type.isJewel) {
      final side = type == ItemType.legendary
          ? GameConfig.jewelDisplaySize * 1.12
          : GameConfig.jewelDisplaySize;
      size = Vector2.all(side);
    }
  }

  void refreshSprite() {
    sprite = _spriteForType(type);
    if (type.isJewel) {
      final side = type == ItemType.legendary
          ? GameConfig.jewelDisplaySize * 1.12
          : GameConfig.jewelDisplaySize;
      size = Vector2.all(side);
    }
  }

  /// Web/magnet drawn procedurally but Flame still requires a non-null sprite.
  static Sprite? _spriteForType(ItemType type) {
    final direct = AssetLibrary.items[type];
    if (direct != null) return direct;
    if (type.isWeb || type.isMagnet || type.isPit) {
      return AssetLibrary.items[ItemType.bomb] ??
          AssetLibrary.items[ItemType.gold];
    }
    return AssetLibrary.items[ItemType.gold];
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
    sprite = _spriteForType(type);
    // Flame mounts only after onLoad — never leave sprite null.
    assert(sprite != null, 'Missing sprite for $type');
    if (children.whereType<CircleHitbox>().isEmpty) {
      add(
        CircleHitbox(
          radius: size.x * (type.isBomb ? 0.38 : 0.55),
          // Passive: no loot↔loot pairs — catch is distance/magnet driven.
          collisionType: CollisionType.passive,
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
      final game = findGame();
      final thiefThreat = game is MineRivalsGame &&
          !game.lead.playerLeads &&
          !game.hasMagnetPower;
      if (thiefThreat || magnetBy == ItemMagnet.thief) {
        // Revenge shimmer — jewel is about to be stolen.
        final flash = 0.35 + 0.35 * sin(_pulse * 3.2);
        _glowPaint.color =
            const Color(0xFFFF1744).withValues(alpha: 0.22 + flash * 0.35);
        canvas.drawCircle(c, size.x * (0.52 + flash * 0.08), _glowPaint);
        _glowPaint.color =
            const Color(0xFFFF8A80).withValues(alpha: 0.12 + flash * 0.2);
        canvas.drawCircle(c, size.x * 0.38, _glowPaint);
      } else {
        _glowPaint.color = type.color.withValues(alpha: 0.18 + pulse * 0.12);
        canvas.drawCircle(c, size.x * 0.48, _glowPaint);
      }
    }

    if (type.isWeb) {
      _renderWeb(canvas);
      return;
    }

    if (type.isMagnet) {
      _renderMagnet(canvas);
      return;
    }

    if (type.isPit) {
      _renderPit(canvas);
      return;
    }

    if (type.isBomb) {
      final warn = 0.5 + 0.5 * sin(_pulse * 1.55);
      final c = Offset(size.x / 2, size.y / 2);
      _glowPaint.color =
          const Color(0xFFFF1744).withValues(alpha: 0.12 + warn * 0.22);
      canvas.drawCircle(c, size.x * (0.40 + warn * 0.08), _glowPaint);
    }

    // Plain sprite blit — no ColorFilter saveLayer (FPS).
    super.render(canvas);
  }

  /// Lightweight sticky web (6 spokes, 2 rings).
  void _renderWeb(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final r = size.x * 0.48;
    final breath = 0.9 + 0.1 * sin(_pulse * 0.9);

    const spokes = 6;
    for (var i = 0; i < spokes; i++) {
      final a = (i / spokes) * pi * 2;
      canvas.drawLine(
        c,
        Offset(c.dx + cos(a) * r, c.dy + sin(a) * r),
        _webStrand,
      );
    }
    for (final ring in const [0.4, 0.85]) {
      canvas.drawCircle(c, r * ring * breath, _webRing);
    }
    canvas.drawCircle(c, 2.0, _webHub);
  }

  /// Black sinkhole on the path — static oval, no pulse.
  void _renderPit(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final rx = size.x * 0.48;
    final ry = size.y * 0.34;
    final rim = Paint()
      ..color = const Color(0xFF5D4037).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final hole = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFF000000),
          Color(0xFF1A1A1A),
          Color(0xFF3E2723),
        ],
        stops: const [0.15, 0.55, 1],
      ).createShader(Rect.fromCenter(center: c, width: rx * 2, height: ry * 2));
    canvas.drawOval(Rect.fromCenter(center: c, width: rx * 2, height: ry * 2), hole);
    canvas.drawOval(Rect.fromCenter(center: c, width: rx * 2, height: ry * 2), rim);
    _glowPaint.color = Colors.black.withValues(alpha: 0.35);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: rx * 1.35, height: ry * 1.35),
      _glowPaint,
    );
  }

  /// Simple horseshoe magnet — readable at loot size without a sheet crop.
  void _renderMagnet(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final pulse = 0.55 + 0.2 * sin(_pulse * 1.4);
    _glowPaint.color =
        const Color(0xFF29B6F6).withValues(alpha: 0.22 + pulse * 0.18);
    canvas.drawCircle(c, size.x * 0.46, _glowPaint);

    final body = Paint()
      ..color = const Color(0xFF039BE5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.x * 0.22
      ..strokeCap = StrokeCap.butt;
    final tip = Paint()..color = const Color(0xFFE53935);
    final tipB = Paint()..color = const Color(0xFF1E88E5);

    final r = size.x * 0.28;
    final rect = Rect.fromCircle(center: c - Offset(0, size.y * 0.04), radius: r);
    canvas.drawArc(rect, pi * 0.15, pi * 0.7, false, body);
    // Pole tips
    canvas.drawCircle(
      Offset(c.dx - r * 0.95, c.dy + r * 0.35),
      size.x * 0.11,
      tip,
    );
    canvas.drawCircle(
      Offset(c.dx + r * 0.95, c.dy + r * 0.35),
      size.x * 0.11,
      tipB,
    );
  }
}
