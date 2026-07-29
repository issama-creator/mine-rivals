import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../effects/wheel_dust.dart';
import '../game/asset_library.dart';
import '../game/game_config.dart';
import '../game/mine_rivals_game.dart';
import '../game/player_skins.dart';
import '../systems/game_settings.dart';
import 'cart_bed_cargo.dart';
import 'cart_cargo_glow.dart';

class PlayerComponent extends SpriteAnimationComponent {
  PlayerComponent()
      : super(
          size: Vector2(GameConfig.playerWidth, GameConfig.playerHeight),
          anchor: Anchor.bottomCenter,
          priority: 20,
        );

  CartCargoGlow? _cargo;
  CartBedCargoLayer? _bedCargo;
  double targetX = 0;
  double _displayScale = 1;
  double _animRate = 1;
  double _animRateTarget = 1;
  double _wheelDustCd = 0;
  int _wheelDustLive = 0;

  double _steerVx = 0;

  final Vector2 basketCenter = Vector2.zero();

  static final Paint _shadowOuter =
      Paint()..color = Colors.black.withValues(alpha: 0.38);
  static final Paint _shadowInner =
      Paint()..color = Colors.black.withValues(alpha: 0.20);

  PlayerSkin get _skin =>
      PlayerSkins.byId(GameSettings.instance.selectedSkinId);

  bool get _cartStyle => _skin.cartStyle;

  bool get _topDown => _skin.topDown;

  /// Public for camera plant (top-down locks Y shake/dip).
  bool get topDown => _topDown;

  double get baseWidth => _skin.width;

  double get baseHeight => _skin.height;

  void refreshBasketCenter() {
    final yFrac =
        _cartStyle ? (_topDown ? CartBedCargoLayer.bedYFracFromFeet : 0.42) : 0.88;
    basketCenter.setValues(position.x, position.y - size.y * yFrac);
  }

  Vector2 get cartBedWorldCenter {
    if (!_topDown || !_cartStyle) {
      refreshBasketCenter();
      return basketCenter;
    }
    return Vector2(
      position.x,
      position.y - size.y * CartBedCargoLayer.bedYFracFromFeet,
    );
  }

  Vector2 get basketWorldCenter {
    refreshBasketCenter();
    return basketCenter;
  }

  void setRunAnimRate(double rate) {
    if (_topDown || _cartStyle) {
      // Steady stride — no speed wobble (that read as sideways shake).
      _animRateTarget = 1.0;
      return;
    }
    _animRateTarget = rate.clamp(0.95, 3.0);
  }

  void resetSteer() {
    _steerVx = 0;
    angle = 0;
  }

  @override
  void render(Canvas canvas) {
    _paintFeetShadow(canvas);
    super.render(canvas);
    final bed = _bedCargo;
    final game = findGame();
    if (bed != null && game is MineRivalsGame) {
      bed.paint(canvas, this, game, animationTicker?.currentIndex ?? 0);
    }
  }

  void _paintFeetShadow(Canvas canvas) {
    final w = size.x * (_topDown ? 0.42 : (_cartStyle ? 0.88 : 0.78));
    final h = _topDown ? size.y * 0.055 : size.y * 0.11;
    // Flush with boots (sprite feet are at the bottom edge of the cell).
    final cy = _topDown ? size.y - 1.0 : size.y - 2;
    final cx = size.x * 0.5;
    final c = Offset(cx, cy);
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
    if (!_topDown) return;
    final parent = this.parent;
    if (parent == null) return;
    _wheelDustCd -= dt;
    if (_wheelDustCd > 0 || _wheelDustLive >= 2) return;
    _wheelDustCd = 0.20;
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
    animation = AssetLibrary.minerRunForSelected();
    playing = true;
    size.setValues(baseWidth, baseHeight);

    if (_cartStyle && _topDown) {
      _bedCargo = CartBedCargoLayer(forThief: false);
    } else if (_cartStyle && !_topDown) {
      _cargo = CartCargoGlow();
      await add(_cargo!);
    }
  }

  void moveToward(
    double x,
    double minX,
    double maxX,
    double dt, {
    double? speed,
  }) {
    final steerSp = speed ?? GameConfig.steerSpeed;
    targetX = x.clamp(minX, maxX);
    final err = targetX - position.x;
    final gap = err.abs();
    final feel = GameConfig.steerFeel;

    final farIntent = 0.92 + 0.36 * feel;
    final midIntent = 0.78 + 0.32 * feel;
    final nearIntent = 0.52 + 0.36 * feel;
    final intent = steerSp *
        (gap > 48 ? farIntent : (gap > 18 ? midIntent : nearIntent));
    final desiredVx = err * intent;
    final maxSp = GameConfig.steerMaxSpeed * (gap > 56 ? 1.05 : 1.0);

    final blend = 1 - (1 / (1 + GameConfig.steerAccel * dt));
    _steerVx += (desiredVx - _steerVx) * blend;
    _steerVx = _steerVx.clamp(-maxSp, maxSp);

    position.x += _steerVx * dt;

    if (position.x < minX) {
      position.x = minX;
      if (_steerVx < 0) _steerVx = 0;
    } else if (position.x > maxX) {
      position.x = maxX;
      if (_steerVx > 0) _steerVx = 0;
    }

    final settleGap = 2.8 - 1.6 * feel;
    final settleVx = 14.0 + 14.0 * feel;
    if (gap < settleGap && _steerVx.abs() < settleVx) {
      position.x = targetX;
      _steerVx *= 0.18 + 0.27 * feel;
    }

    if (_topDown) {
      angle = 0;
      return;
    }
    final leanTarget = (_steerVx / maxSp) * GameConfig.steerLean;
    final leanFollow = 5.2 + 6.8 * feel;
    angle += (leanTarget - angle) * (1 - (1 / (1 + leanFollow * dt)));
  }

  void applyDepthScale(double scale, [double dt = 1 / 60]) {
    if (_topDown) {
      _displayScale = scale;
    } else if (dt >= 0.2) {
      _displayScale = scale;
    } else {
      _displayScale += (scale - _displayScale) * (1 - (1 / (1 + 10 * dt)));
    }
    size.setValues(baseWidth * _displayScale, baseHeight * _displayScale);
  }

  void pulseCargo() {
    _cargo?.pulse();
    _bedCargo?.pulse = 1;
  }
}
