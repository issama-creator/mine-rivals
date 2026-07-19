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

Vector2 _displaySizeFor(ItemType type) {
  if (type.isJewel) {
    final side = type == ItemType.legendary
        ? GameConfig.jewelDisplaySize * 1.12
        : GameConfig.jewelDisplaySize;
    return Vector2.all(side);
  }
  if (type.isDynamiteCart) {
    // Crop is ~320×298 — keep aspect so wheels don't squash.
    const h = GameConfig.dynamiteCartDisplaySize;
    return Vector2(h * (320 / 298), h);
  }
  if (type.isBomb) return Vector2.all(GameConfig.bombDisplaySize);
  if (type.isWeb) return Vector2.all(GameConfig.webDisplaySize);
  if (type.isMagnet) return Vector2.all(GameConfig.magnetDisplaySize);
  if (type.isSpikes) {
    // Crop is ~320×183 — wide floor trap.
    const w = GameConfig.spikesDisplaySize;
    return Vector2(w, w * (183 / 320));
  }
  if (type.isPit) return Vector2.all(GameConfig.pitDisplaySize);
  if (type.isHeart) return Vector2.all(GameConfig.heartDisplaySize);
  if (type.isPotion) return Vector2.all(GameConfig.potionDisplaySize);
  return Vector2.all(GameConfig.lootDisplaySize);
}

class FallingItem extends SpriteComponent with CollisionCallbacks {
  FallingItem({
    required this.type,
    required Vector2 position,
    required this.fallSpeed,
  }) : super(
          position: position,
          size: _displaySizeFor(type),
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
    size = _displaySizeFor(type);
  }

  void refreshSprite() {
    sprite = _spriteForType(type);
    size = _displaySizeFor(type);
  }

  void applyBombSpeedScale(double paceRatio) {
    if (!type.isExplosive) return;
    final t = ((paceRatio - 1.0) / 0.9).clamp(0.0, 1.0);
    final scale = 1.0 +
        (GameConfig.bombSpeedScaleMax - 1.0) * t;
    size = _displaySizeFor(type) * scale;
  }

  /// Web/magnet drawn procedurally but Flame still requires a non-null sprite.
  static Sprite? _spriteForType(ItemType type) {
    final direct = AssetLibrary.items[type];
    if (direct != null) return direct;
    if (type.isWeb ||
        type.isMagnet ||
        type.isPit ||
        type.isHeart ||
        type.isPotion) {
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
          radius: size.x * (type.isExplosive ? 0.38 : 0.55),
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

    if (type.isHeart) {
      _renderHeart(canvas);
      return;
    }

    if (type.isPotion) {
      _renderPotion(canvas);
      return;
    }

    if (type.isPit) {
      _renderPit(canvas);
      return;
    }

    if (type.isExplosive) {
      // Hotter pulse so explosives read at high scroll speed.
      final warn = 0.55 + 0.45 * sin(_pulse * 2.1);
      final c = Offset(size.x / 2, size.y / 2);
      final hot = type.isDynamiteCart
          ? const Color(0xFFFF6D00)
          : const Color(0xFFFF1744);
      _glowPaint.color = hot.withValues(alpha: 0.22 + warn * 0.32);
      canvas.drawCircle(c, size.x * (0.48 + warn * 0.12), _glowPaint);
      _glowPaint.color =
          const Color(0xFFFF9100).withValues(alpha: 0.14 + warn * 0.2);
      canvas.drawCircle(c, size.x * (0.28 + warn * 0.06), _glowPaint);
    }

    if (type.isSpikes) {
      final warn = 0.5 + 0.35 * sin(_pulse * 1.7);
      final c = Offset(size.x / 2, size.y * 0.62);
      _glowPaint.color =
          const Color(0xFFFF6D00).withValues(alpha: 0.16 + warn * 0.22);
      canvas.drawCircle(c, size.x * (0.36 + warn * 0.06), _glowPaint);
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

  void _renderHeart(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final pulse = 0.55 + 0.2 * sin(_pulse * 1.6);
    _glowPaint.color =
        const Color(0xFFFF5252).withValues(alpha: 0.2 + pulse * 0.2);
    canvas.drawCircle(c, size.x * 0.46, _glowPaint);

    final paint = Paint()..color = const Color(0xFFFF1744);
    final path = Path();
    final s = size.x * 0.38;
    path.moveTo(c.dx, c.dy + s * 0.35);
    path.cubicTo(
      c.dx - s,
      c.dy - s * 0.05,
      c.dx - s * 0.85,
      c.dy - s * 0.85,
      c.dx,
      c.dy - s * 0.35,
    );
    path.cubicTo(
      c.dx + s * 0.85,
      c.dy - s * 0.85,
      c.dx + s,
      c.dy - s * 0.05,
      c.dx,
      c.dy + s * 0.35,
    );
    canvas.drawPath(path, paint);
  }

  void _renderPotion(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final pulse = 0.55 + 0.2 * sin(_pulse * 1.5);
    _glowPaint.color =
        const Color(0xFFAB47BC).withValues(alpha: 0.22 + pulse * 0.18);
    canvas.drawCircle(c, size.x * 0.46, _glowPaint);

    final glass = Paint()..color = const Color(0xFF8E24AA);
    final neck = Paint()..color = const Color(0xFFCE93D8);
    final cork = Paint()..color = const Color(0xFFFFD54F);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: c + Offset(0, size.y * 0.06),
          width: size.x * 0.42,
          height: size.y * 0.48,
        ),
        const Radius.circular(10),
      ),
      glass,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: c - Offset(0, size.y * 0.22),
          width: size.x * 0.18,
          height: size.y * 0.2,
        ),
        const Radius.circular(4),
      ),
      neck,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: c - Offset(0, size.y * 0.34),
          width: size.x * 0.22,
          height: size.y * 0.1,
        ),
        const Radius.circular(3),
      ),
      cork,
    );
  }
}
