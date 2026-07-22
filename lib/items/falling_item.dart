import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../effects/ground_shadow.dart';
import '../game/asset_library.dart';
import '../game/game_config.dart';
import '../game/mine_rivals_game.dart';
import 'item_type.dart';

enum ItemMagnet { none, player, thief }

Vector2 _displaySizeFor(ItemType type) {
  if (type.isJewel) {
    // Universal diamond PNG ~316×395 — keep aspect so it doesn't squash.
    final h = type == ItemType.legendary
        ? GameConfig.jewelDisplaySize * 1.12
        : GameConfig.jewelDisplaySize;
    return Vector2(h * (316 / 395), h);
  }
  if (type.isDynamiteCart) {
    // Crop is ~320×298 — keep aspect so wheels don't squash.
    const h = GameConfig.dynamiteCartDisplaySize;
    return Vector2(h * (320 / 298), h);
  }
  // Square sheet crop — always the same on-screen size.
  if (type.isBomb) return Vector2.all(GameConfig.bombDisplaySize);
  if (type.isWeb) return Vector2.all(GameConfig.webDisplaySize);
  if (type.isMagnet) return Vector2.all(GameConfig.magnetDisplaySize);
  if (type.isSpikes) {
    // Art ~3:2 — taller draw so spikes read as sticking up.
    const w = GameConfig.spikesDisplaySize;
    return Vector2(w, w * GameConfig.spikesAspect);
  }
  if (type.isPit) return Vector2.all(GameConfig.pitDisplaySize);
  if (type.isHeart) return Vector2.all(GameConfig.heartDisplaySize);
  if (type.isPotion) return Vector2.all(GameConfig.potionDisplaySize);
  return Vector2.all(GameConfig.lootDisplaySize);
}

class FallingItem extends SpriteComponent {
  FallingItem({
    required this.type,
    required Vector2 position,
    required this.fallSpeed,
  }) : super(
          position: position,
          size: _displaySizeFor(type),
          // Pit/spikes: center on the hole. Everything else: feet on the path.
          anchor: type.isLethalFloor ? Anchor.center : Anchor.bottomCenter,
          priority: type.isSpikes ? 34 : 30,
        );

  final ItemType type;
  double fallSpeed;
  bool collected = false;
  bool stolen = false;
  ItemMagnet magnetBy = ItemMagnet.none;
  double life = 0;
  double _pulse = Random().nextDouble() * pi * 2;
  /// Slow Subway-style tumble for jewels (radians).
  double _jewelSpin = Random().nextDouble() * pi * 2;
  MineRivalsGame? _game;
  GroundShadow? _groundShadow;
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
  final Paint _pitHole = Paint();
  final Paint _magnetSteel = Paint()..color = const Color(0xFFCFD8DC);
  final Paint _magnetSteelEdge = Paint()
    ..color = const Color(0xFF78909C)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final Paint _magnetLeft = Paint()
    ..color = const Color(0xFFE53935)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;
  final Paint _magnetRight = Paint()
    ..color = const Color(0xFF1E88E5)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;
  final Paint _heartPaint = Paint()..color = const Color(0xFFFF1744);
  final Paint _potionGlass = Paint()..color = const Color(0xFF8E24AA);
  final Paint _potionNeck = Paint()..color = const Color(0xFFCE93D8);
  final Paint _potionCork = Paint()..color = const Color(0xFFFFD54F);
  /// 0–1 danger warning as the hazard approaches the catch line.
  double telegraph = 0;
  final Paint _telePaint = Paint();
  final Paint _teleRing = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4;
  double _pitShaderW = -1;
  double _pitShaderH = -1;

  bool get magnetized => magnetBy != ItemMagnet.none;

  /// Pit/spikes sit by center; loot/bombs/cart stand on the path (feet = position).
  bool get standsOnGround => !type.isLethalFloor;

  /// Body center for catch / magnet (world Y).
  double get hitY =>
      standsOnGround ? position.y - size.y * 0.52 : position.y;

  double get hitX => position.x;

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
    telegraph = 0;
    _pulse = Random().nextDouble() * pi * 2;
    _jewelSpin = Random().nextDouble() * pi * 2;
    // Corridor may have swapped jewel art since this instance was pooled.
    sprite = _spriteForType(type);
    size = _displaySizeFor(type);
    anchor = type.isLethalFloor ? Anchor.center : Anchor.bottomCenter;
    _syncGroundShadow();
  }

  void refreshSprite() {
    sprite = _spriteForType(type);
    size = _displaySizeFor(type);
    anchor = type.isLethalFloor ? Anchor.center : Anchor.bottomCenter;
    _syncGroundShadow();
  }

  void applyBombSpeedScale(double paceRatio) {
    // Disabled — pace scaling made a second “wrong size” bomb look.
    size = _displaySizeFor(type);
  }

  /// Web/magnet/pit drawn procedurally; Flame still wants a non-null sprite.
  static Sprite? _spriteForType(ItemType type) {
    if (type.isSpikes || type.isDynamiteCart) {
      // Only real hazard PNG — never gold/bomb (that drew spikes as coins).
      if (AssetLibrary.hasRealHazardArt(type)) {
        return AssetLibrary.items[type];
      }
      // Invisible placeholder; render path draws procedural spikes / skips cart.
      return AssetLibrary.items[ItemType.gold];
    }
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
    if (!AssetLibrary.ready) {
      await AssetLibrary.ensureLoaded(prefetchRest: false);
    }
    sprite = _spriteForType(type);
    // Flame mounts only after onLoad — never leave sprite null.
    assert(sprite != null, 'Missing sprite for $type');
    if (standsOnGround) {
      final shadow = GroundShadow();
      _groundShadow = shadow;
      await add(shadow);
      _syncGroundShadow();
    }
    // Catch is distance-driven in MineRivalsGame — no Flame hitboxes.
  }

  void _syncGroundShadow() {
    final shadow = _groundShadow;
    if (shadow == null) return;
    // Feet blob — plants bomb/loot on the cobbles.
    final w = type.isDynamiteCart
        ? size.x * 0.85
        : (type.isBomb ? size.x * 0.72 : size.x * 0.55);
    shadow.size.setValues(w, size.y * 0.14);
    shadow.position.setValues(size.x * 0.5, size.y - 1);
  }

  @override
  void onMount() {
    super.onMount();
    final g = findGame();
    if (g is MineRivalsGame) _game = g;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (collected || stolen) return;
    // Lock bomb size — pooled / hot-reload leftovers must not look different.
    if (type.isBomb) {
      final s = GameConfig.bombDisplaySize;
      if (size.x != s || size.y != s) size.setValues(s, s);
      scale.setValues(1, 1);
    }
    // Safety: thief magnet can never stick on non-jewels.
    if (!type.isJewel && magnetBy == ItemMagnet.thief) {
      magnetBy = ItemMagnet.none;
    }
    life += dt;
    // background.speed already includes playRate — don't multiply again.
    final scroll = _game?.background.speed ?? fallSpeed;
    final worldSpeed = type.isDynamiteCart
        ? scroll * GameConfig.dynamiteCartSpeedMult
        : scroll;
    if (!magnetized) {
      position.y += worldSpeed * dt;
    } else {
      position.y += worldSpeed * 0.35 * dt;
    }
    _updateTelegraph(worldSpeed);
    if (type.isJewel) {
      // Slow Subway-style tumble (~0.28 rev/s).
      _jewelSpin += dt * 1.75;
      _pulse += dt * 2.0;
    } else {
      _pulse += dt * (type.isBomb
          ? 0.22
          : (type.isExplosive || type.isSpikes || type.isHazard ? 2.8 : 4));
    }
  }

  /// ETA to player catch line → readable “danger incoming” window.
  void _updateTelegraph(double scrollSpeed) {
    if (!type.isHazard || collected || stolen) {
      telegraph = 0;
      return;
    }
    final game = _game;
    if (game == null || scrollSpeed < 8) {
      telegraph = 0;
      return;
    }
    // Catch roughly at the miner’s feet / basket band.
    final catchY = game.player.position.y - (type.isLethalFloor ? 10 : 28);
    final dy = catchY - hitY;
    if (dy <= 0) {
      telegraph = 0;
      return;
    }
    final eta = dy / scrollSpeed;
    final start = GameConfig.hazardTelegraphStartSec;
    if (eta > start || eta < 0.04) {
      telegraph = 0;
      return;
    }
    // Ramps up as impact nears (readable ~0.5→0.05s).
    telegraph = ((start - eta) / start).clamp(0.0, 1.0);
    // Soft pulse so it blinks, not a static tint.
    telegraph *= 0.72 + 0.28 * (0.5 + 0.5 * sin(_pulse * 6));
  }

  Color get _telegraphColor {
    if (type.isWeb) return const Color(0xFFECEFF1);
    if (type.isDynamiteCart) return const Color(0xFFFF6D00);
    if (type.isBomb) return const Color(0xFFFF9100);
    if (type.isSpikes) return const Color(0xFFFF8A65);
    if (type.isPit) return const Color(0xFFEF5350);
    return const Color(0xFFFF5252);
  }

  void _renderTelegraph(Canvas canvas) {
    if (telegraph <= 0.04) return;
    final t = telegraph;
    final foot = Offset(size.x / 2, standsOnGround ? size.y - 2 : size.y * 0.55);
    // Ground danger disc — grows as impact nears.
    final rw = size.x * (0.55 + 0.55 * t);
    final rh = size.y * (0.16 + 0.12 * t);
    _telePaint.color = _telegraphColor.withValues(alpha: 0.16 + 0.28 * t);
    canvas.drawOval(
      Rect.fromCenter(center: foot, width: rw * 2, height: rh * 2),
      _telePaint,
    );
    _teleRing
      ..color = _telegraphColor.withValues(alpha: 0.35 + 0.55 * t)
      ..strokeWidth = 1.6 + 2.2 * t;
    canvas.drawOval(
      Rect.fromCenter(center: foot, width: rw * 2.05, height: rh * 2.05),
      _teleRing,
    );
    // Body warning halo.
    final body = Offset(size.x / 2, size.y * (type.isLethalFloor ? 0.5 : 0.42));
    _telePaint.color = _telegraphColor.withValues(alpha: 0.1 + 0.22 * t);
    canvas.drawCircle(body, size.x * (0.42 + 0.2 * t), _telePaint);
  }

  @override
  void render(Canvas canvas) {
    if (type.isHazard) {
      _renderTelegraph(canvas);
    }

    if (type.isJewel) {
      final pulse = 0.55 + 0.2 * sin(_pulse);
      final c = Offset(size.x / 2, size.y * 0.55);
      final game = _game;
      final thiefThreat = game != null &&
          !game.lead.playerLeads &&
          !game.hasMagnetPower;
      if (thiefThreat || magnetBy == ItemMagnet.thief) {
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
      // Vertical-axis tumble — never fully collapses so spin stays readable.
      final flip = cos(_jewelSpin);
      final sx = flip.abs() < 0.22 ? 0.22 * flip.sign : flip;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(sx, 1);
      canvas.translate(-c.dx, -c.dy);
      super.render(canvas);
      canvas.restore();
      return;
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
      // Procedural hole only — never blit the bomb placeholder sprite.
      _renderPit(canvas);
      return;
    }

    if (type.isSpikes) {
      if (AssetLibrary.hasRealHazardArt(ItemType.spikes) &&
          _spriteIs(AssetLibrary.items[ItemType.spikes])) {
        super.render(canvas);
      } else {
        // Never blit coin/bomb placeholder as spikes.
        _renderSpikesFallback(canvas);
      }
      return;
    }

    if (type.isDynamiteCart &&
        !(AssetLibrary.hasRealHazardArt(ItemType.dynamiteCart) &&
            _spriteIs(AssetLibrary.items[ItemType.dynamiteCart]))) {
      // Missing cart art — crate stub, never a coin.
      final body = Paint()..color = const Color(0xFF5D4037);
      final rim = Paint()
        ..color = const Color(0xFFFF7043)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final r = Rect.fromLTWH(size.x * 0.12, size.y * 0.28, size.x * 0.76, size.y * 0.55);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), body);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), rim);
      return;
    }

    // Plain sprite blit — no ColorFilter saveLayer (FPS).
    // Ground shadow (child) plants standing items; no floating red disc.
    super.render(canvas);
  }

  bool _spriteIs(Sprite? other) {
    final s = sprite;
    if (s == null || other == null) return false;
    return identical(s.image, other.image) &&
        s.srcPosition == other.srcPosition &&
        s.srcSize == other.srcSize;
  }

  /// Drawn only if spikes.png failed to load — never show a bomb / lava disc.
  void _renderSpikesFallback(Canvas canvas) {
    final c = Offset(size.x / 2, size.y * 0.68);
    // Dark hole, not a glowing circle.
    _glowPaint.color = const Color(0xFF0D0D0D);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: size.x * 0.42, height: size.y * 0.28),
      _glowPaint,
    );
    final spike = Paint()..color = const Color(0xFF78909C);
    final edge = Paint()
      ..color = const Color(0xFF37474F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 10; i++) {
      final a = (i / 10) * pi * 2 - pi / 2;
      final baseR = size.x * 0.16;
      final tipR = size.x * 0.46;
      final tip = Offset(
        c.dx + cos(a) * tipR * 0.55,
        c.dy + sin(a) * tipR * 0.22 - size.y * 0.42,
      );
      final path = Path()
        ..moveTo(c.dx + cos(a - 0.22) * baseR, c.dy + sin(a - 0.22) * baseR * 0.45)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(c.dx + cos(a + 0.22) * baseR, c.dy + sin(a + 0.22) * baseR * 0.45)
        ..close();
      canvas.drawPath(path, spike);
      canvas.drawPath(path, edge);
    }
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

  /// Soft dark oval sinkhole (approved look) — separate from spikes art.
  void _renderPit(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final rx = size.x * 0.48;
    final ry = size.y * 0.34;
    if (size.x != _pitShaderW || size.y != _pitShaderH) {
      _pitShaderW = size.x;
      _pitShaderH = size.y;
      _pitHole.shader = RadialGradient(
        colors: const [
          Color(0xFF000000),
          Color(0xFF1A1A1A),
          Color(0xFF3E2723),
        ],
        stops: const [0.15, 0.55, 1],
      ).createShader(Rect.fromCenter(center: c, width: rx * 2, height: ry * 2));
    }
    final oval = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
    canvas.drawOval(oval, _pitHole);
    _glowPaint.color = Colors.black.withValues(alpha: 0.28);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: rx * 1.2, height: ry * 1.2),
      _glowPaint,
    );
  }

  /// Classic U horseshoe — red / blue body, steel tips (reads at ~44px).
  void _renderMagnet(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    final cx = w * 0.5;
    final pulse = 0.55 + 0.15 * sin(_pulse * 1.25);
    _glowPaint.color =
        const Color(0xFF64B5F6).withValues(alpha: 0.12 + pulse * 0.1);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.62),
        width: w * 0.78,
        height: h * 0.22,
      ),
      _glowPaint,
    );

    final thick = w * 0.20;
    final midR = w * 0.28;
    final top = h * 0.14;
    final legBot = h * 0.72;
    final arcCy = top + midR;
    _magnetLeft.strokeWidth = thick;
    _magnetRight.strokeWidth = thick;

    final arcRect = Rect.fromCircle(center: Offset(cx, arcCy), radius: midR);
    canvas.drawArc(arcRect, pi, pi * 0.5, false, _magnetLeft);
    canvas.drawArc(arcRect, pi * 1.5, pi * 0.5, false, _magnetRight);
    final lx = cx - midR;
    final rx = cx + midR;
    canvas.drawLine(Offset(lx, arcCy), Offset(lx, legBot), _magnetLeft);
    canvas.drawLine(Offset(rx, arcCy), Offset(rx, legBot), _magnetRight);

    // Steel pole tips — classic magnet feet.
    final tipW = thick * 1.12;
    final tipH = h * 0.16;
    final tipY = legBot + tipH * 0.15;
    for (final x in [lx, rx]) {
      final tip = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, tipY),
          width: tipW,
          height: tipH,
        ),
        const Radius.circular(2.5),
      );
      canvas.drawRRect(tip, _magnetSteel);
      canvas.drawRRect(tip, _magnetSteelEdge);
    }
  }

  void _renderHeart(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final pulse = 0.55 + 0.2 * sin(_pulse * 1.6);
    _glowPaint.color =
        const Color(0xFFFF5252).withValues(alpha: 0.28 + pulse * 0.22);
    canvas.drawCircle(c, size.x * 0.48, _glowPaint);

    final path = Path();
    final s = size.x * 0.42;
    path.moveTo(c.dx, c.dy + s * 0.38);
    path.cubicTo(
      c.dx - s,
      c.dy - s * 0.02,
      c.dx - s * 0.9,
      c.dy - s * 0.9,
      c.dx,
      c.dy - s * 0.32,
    );
    path.cubicTo(
      c.dx + s * 0.9,
      c.dy - s * 0.9,
      c.dx + s,
      c.dy - s * 0.02,
      c.dx,
      c.dy + s * 0.38,
    );
    canvas.drawPath(path, _heartPaint);
    final rim = Paint()
      ..color = const Color(0xFFFFCDD2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawPath(path, rim);
    // Shine — reads as a pickup icon, not a red blob.
    canvas.drawCircle(
      Offset(c.dx - s * 0.22, c.dy - s * 0.28),
      s * 0.12,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  void _renderPotion(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final pulse = 0.55 + 0.2 * sin(_pulse * 1.5);
    _glowPaint.color =
        const Color(0xFFAB47BC).withValues(alpha: 0.28 + pulse * 0.2);
    canvas.drawCircle(c, size.x * 0.48, _glowPaint);

    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: c + Offset(0, size.y * 0.08),
        width: size.x * 0.48,
        height: size.y * 0.52,
      ),
      const Radius.circular(12),
    );
    canvas.drawRRect(body, _potionGlass);
    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0xFFE1BEE7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    // Liquid line.
    canvas.drawLine(
      Offset(c.dx - size.x * 0.16, c.dy + size.y * 0.02),
      Offset(c.dx + size.x * 0.16, c.dy + size.y * 0.02),
      Paint()
        ..color = const Color(0xFFCE93D8).withValues(alpha: 0.85)
        ..strokeWidth = 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: c - Offset(0, size.y * 0.22),
          width: size.x * 0.2,
          height: size.y * 0.2,
        ),
        const Radius.circular(4),
      ),
      _potionNeck,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: c - Offset(0, size.y * 0.36),
          width: size.x * 0.26,
          height: size.y * 0.12,
        ),
        const Radius.circular(3),
      ),
      _potionCork,
    );
  }
}
