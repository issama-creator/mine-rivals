import 'package:flame/components.dart';

import '../effects/ground_shadow.dart';
import '../game/asset_library.dart';
import '../game/game_config.dart';
import '../game/player_skins.dart';
import '../systems/game_settings.dart';
import 'cart_cargo_glow.dart';

class PlayerComponent extends SpriteAnimationComponent {
  PlayerComponent()
      : super(
          size: Vector2(GameConfig.playerWidth, GameConfig.playerHeight),
          anchor: Anchor.bottomCenter,
          priority: 20,
        );

  late GroundShadow _shadow;
  CartCargoGlow? _cargo;
  double targetX = 0;
  double _displayScale = 1;
  double _animRate = 1;
  double _animRateTarget = 1;

  /// Lateral velocity — makes left/right feel smooth and responsive.
  double _steerVx = 0;

  /// Cached basket point — refreshed once per catch tick (no alloc).
  final Vector2 basketCenter = Vector2.zero();

  bool get _cartStyle =>
      PlayerSkins.byId(GameSettings.instance.selectedSkinId).cartStyle;

  bool get _topDown =>
      PlayerSkins.byId(GameSettings.instance.selectedSkinId).topDown;

  double get baseWidth =>
      _cartStyle ? GameConfig.playerCartWidth : GameConfig.playerWidth;

  double get baseHeight =>
      _cartStyle ? GameConfig.playerCartHeight : GameConfig.playerHeight;

  /// Shadow sits under the boots (sheet has empty pad below feet).
  double get _shadowY =>
      _topDown ? size.y * 0.90 : size.y - 2;

  double get _shadowH =>
      _topDown ? size.y * 0.085 : size.y * 0.11;

  /// Approx catch focus in world space.
  void refreshBasketCenter() {
    // Top-down: cart ahead (upper on sprite). Back-view cart: mid bed.
    // Upright skins: head basket.
    final yFrac = _cartStyle ? (_topDown ? 0.68 : 0.42) : 0.88;
    basketCenter.setValues(position.x, position.y - size.y * yFrac);
  }

  Vector2 get basketWorldCenter {
    refreshBasketCenter();
    return basketCenter;
  }

  void setRunAnimRate(double rate) {
    if (_topDown || _cartStyle) {
      // Pace barely speeds the walk — keeps a calm step.
      _animRateTarget =
          (0.72 + rate * 0.18).clamp(0.72, GameConfig.minerCartAnimRateMax);
      return;
    }
    _animRateTarget = rate.clamp(0.95, 3.0);
  }

  /// Clear lateral inertia (restart / pit suck).
  void resetSteer() {
    _steerVx = 0;
    angle = 0;
  }

  @override
  void update(double dt) {
    // Ease stride rate — kills choppy jumps when pace steps up.
    final follow = 1 - (1 / (1 + 6.5 * dt));
    _animRate += (_animRateTarget - _animRate) * follow;
    super.update(dt * _animRate);
  }

  @override
  Future<void> onLoad() async {
    if (!AssetLibrary.ready) {
      await AssetLibrary.ensureLoaded(prefetchRest: false);
    }
    animation = AssetLibrary.minerRunForSelected();
    playing = true;
    size.setValues(baseWidth, baseHeight);

    _shadow = GroundShadow();
    _shadow.size = Vector2(size.x * (_cartStyle ? 0.78 : 0.78), _shadowH);
    _shadow.position = Vector2(size.x * 0.5, _shadowY);
    await add(_shadow);

    if (_cartStyle) {
      _cargo = CartCargoGlow();
      await add(_cargo!);
    }
  }

  /// Smooth velocity follow toward finger X — pleasant arc, still dodge-ready.
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

    // Top-down sheets stay upright — lean reads as “колбасит”.
    if (_topDown) {
      angle = 0;
      return;
    }
    final leanTarget = (_steerVx / maxSp) * GameConfig.steerLean;
    final leanFollow = 5.2 + 6.8 * feel;
    angle += (leanTarget - angle) * (1 - (1 / (1 + leanFollow * dt)));
  }

  void applyDepthScale(double scale, [double dt = 1 / 60]) {
    if (dt >= 0.2) {
      _displayScale = scale;
    } else {
      _displayScale += (scale - _displayScale) * (1 - (1 / (1 + 10 * dt)));
    }
    size.setValues(baseWidth * _displayScale, baseHeight * _displayScale);
    _shadow.size.setValues(
      size.x * (_topDown ? 0.72 : (_cartStyle ? 0.88 : 0.78)),
      _shadowH,
    );
    _shadow.position.setValues(size.x * 0.5, _shadowY);
  }

  /// Cargo bed bounce when a crystal lands.
  void pulseCargo() => _cargo?.pulse();
}
