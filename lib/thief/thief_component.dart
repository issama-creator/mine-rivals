import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../effects/wheel_dust.dart';
import '../game/asset_library.dart';
import '../game/game_config.dart';
import '../game/mine_rivals_game.dart';
import '../player/cart_bed_cargo.dart';

/// Single black thief (vor.png) — no blue twin.
class ThiefComponent extends SpriteAnimationComponent {
  ThiefComponent()
      : super(
          size: Vector2(GameConfig.thiefWidth, GameConfig.thiefHeight),
          anchor: Anchor.bottomCenter,
          priority: 10,
          paint: _silhouettePaint,
        );

  double _displayScale = 1;
  double _animRate = 1;
  double _animRateTarget = 1;
  final Random _rng = Random();
  CartBedCargoLayer? _bedCargo;
  double _wheelDustCd = 0;
  int _wheelDustLive = 0;

  double passSide = 1;

  /// Cooler / slightly darker than the miner so silhouettes don't melt together.
  static final Paint _silhouettePaint = Paint()
    ..colorFilter = const ColorFilter.matrix(<double>[
      0.82, 0.05, 0.05, 0, 0,
      0.04, 0.80, 0.06, 0, 0,
      0.06, 0.08, 1.12, 0, 10,
      0, 0, 0, 1, 0,
    ]);

  static final Paint _shadowOuter =
      Paint()..color = Colors.black.withValues(alpha: 0.38);
  static final Paint _shadowInner =
      Paint()..color = Colors.black.withValues(alpha: 0.20);

  static final Paint _rimPaint = Paint()
    ..color = const Color(0xFF5C6BC0).withValues(alpha: 0.35)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

  void setRunAnimRate(double rate) {
    _animRateTarget =
        (0.62 + rate * 0.14).clamp(0.62, GameConfig.minerCartAnimRateMax);
  }

  @override
  void render(Canvas canvas) {
    _paintFeetShadow(canvas);
    // Soft cool rim — separates dark gear from brown path / miner.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x * 0.5, size.y * 0.52),
        width: size.x * 0.72,
        height: size.y * 0.78,
      ),
      _rimPaint,
    );
    super.render(canvas);
    final bed = _bedCargo;
    final game = findGame();
    if (bed != null && game is MineRivalsGame) {
      bed.paint(canvas, this, game, animationTicker?.currentIndex ?? 0);
    }
  }

  void _paintFeetShadow(Canvas canvas) {
    final w = size.x * 0.50;
    final h = size.y * 0.085;
    final c = Offset(size.x * 0.5, size.y * 0.935);
    canvas.drawOval(Rect.fromCenter(center: c, width: w, height: h), _shadowOuter);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: w * 0.7, height: h * 0.65),
      _shadowInner,
    );
  }

  @override
  void update(double dt) {
    final follow = 1 - (1 / (1 + 6.5 * dt));
    _animRate += (_animRateTarget - _animRate) * follow;
    super.update(dt * _animRate);
    final bed = _bedCargo;
    if (bed != null && bed.pulse > 0) {
      bed.pulse = (bed.pulse - dt * 2.6).clamp(0.0, 1.0);
    }
    _emitWheelDust(dt);
  }

  void _emitWheelDust(double dt) {
    final parent = this.parent;
    if (parent == null) return;
    _wheelDustCd -= dt;
    if (_wheelDustCd > 0 || _wheelDustLive >= 2) return;
    _wheelDustCd = 0.24;
    _wheelDustLive++;
    final ahead = position + Vector2(0, -size.y * 0.58);
    parent.add(
      WheelDust(
        position: ahead,
        onDone: () => _wheelDustLive = (_wheelDustLive - 1).clamp(0, 8),
      ),
    );
  }

  @override
  Future<void> onLoad() async {
    if (!AssetLibrary.ready) {
      await AssetLibrary.ensureLoaded(prefetchRest: false);
    }
    animation = AssetLibrary.thiefRun;
    playing = true;
    passSide = _rng.nextBool() ? 1.0 : -1.0;

    _bedCargo = CartBedCargoLayer(forThief: true);
  }

  void runLane({
    required double screenCenterX,
    required double playerX,
    required double dt,
    required bool pressingCart,
    required bool breathingDownNeck,
    bool sprinting = false,
  }) {
    angle = 0;
    var lane = screenCenterX + GameConfig.thiefLaneOffsetX * passSide;

    if (pressingCart) {
      lane = playerX + GameConfig.thiefCartPressOffsetX * passSide;
    } else if (breathingDownNeck) {
      lane = screenCenterX + GameConfig.thiefLaneOffsetX * passSide;
    }

    if (!pressingCart) {
      final minClear = GameConfig.thiefMinClearanceX;
      if ((lane - playerX).abs() < minClear) {
        lane = playerX + minClear * passSide;
      }
    }

    final speed = pressingCart ? 5.5 : (sprinting ? 3.2 : 4.0);
    position.x += (lane - position.x) * (1 - (1 / (1 + speed * dt)));
  }

  void applyDepthScale(double scale, [double dt = 1 / 60]) {
    _displayScale = scale;
    size.setValues(
      GameConfig.thiefWidth * _displayScale,
      GameConfig.thiefHeight * _displayScale,
    );
  }

  void pulseBedCargo() => _bedCargo?.pulse = 1;
}
