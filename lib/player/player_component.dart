import 'package:flame/components.dart';

import '../effects/ground_shadow.dart';
import '../game/asset_library.dart';
import '../game/game_config.dart';

class PlayerComponent extends SpriteAnimationComponent {
  PlayerComponent()
    : super(
          size: Vector2(GameConfig.playerWidth, GameConfig.playerHeight),
          anchor: Anchor.bottomCenter,
          priority: 20,
        );

  late GroundShadow _shadow;
  double targetX = 0;
  double _displayScale = 1;
  double _animRate = 1;
  /// Lateral velocity — makes left/right feel smooth and responsive.
  double _steerVx = 0;

  /// Cached basket point — refreshed once per catch tick (no alloc).
  final Vector2 basketCenter = Vector2.zero();

  /// Approx basket in world space (lean ignored — tiny for catch gates).
  void refreshBasketCenter() {
    basketCenter.setValues(position.x, position.y - size.y * 0.88);
  }

  Vector2 get basketWorldCenter {
    refreshBasketCenter();
    return basketCenter;
  }

  void setRunAnimRate(double rate) {
    _animRate = rate.clamp(0.95, 3.0);
  }

  /// Clear lateral inertia (restart / pit suck).
  void resetSteer() {
    _steerVx = 0;
    angle = 0;
  }

  @override
  void update(double dt) {
    // Faster stride as corridors get quicker.
    super.update(dt * _animRate);
  }

  @override
  Future<void> onLoad() async {
    if (!AssetLibrary.ready) {
      await AssetLibrary.ensureLoaded(prefetchRest: false);
    }
    animation = AssetLibrary.minerRunForSelected();
    playing = true;

    _shadow = GroundShadow();
    _shadow.size = Vector2(size.x * 0.78, size.y * 0.11);
    _shadow.position = Vector2(size.x * 0.5, size.y - 2);
    await add(_shadow);
    // Catch is distance-driven in MineRivalsGame — no Flame hitboxes.
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

    // Near target: settle gently. Far: a bit more intent for escapes.
    // Low feel = softer glide (slider left goes below old “плавно”).
    final farIntent = 0.92 + 0.36 * feel;
    final midIntent = 0.78 + 0.32 * feel;
    final nearIntent = 0.52 + 0.36 * feel;
    final intent = steerSp *
        (gap > 48 ? farIntent : (gap > 18 ? midIntent : nearIntent));
    final desiredVx = err * intent;
    final maxSp = GameConfig.steerMaxSpeed * (gap > 56 ? 1.05 : 1.0);

    // Ease velocity — this is what makes strafes feel “nice”.
    final blend = 1 - (1 / (1 + GameConfig.steerAccel * dt));
    _steerVx += (desiredVx - _steerVx) * blend;
    _steerVx = _steerVx.clamp(-maxSp, maxSp);

    position.x += _steerVx * dt;

    // Soft edges — no bounce, kill speed into the wall.
    if (position.x < minX) {
      position.x = minX;
      if (_steerVx < 0) _steerVx = 0;
    } else if (position.x > maxX) {
      position.x = maxX;
      if (_steerVx > 0) _steerVx = 0;
    }

    // Micro-settle so he doesn't jitter on the finger.
    final settleGap = 2.8 - 1.6 * feel;
    final settleVx = 14.0 + 14.0 * feel;
    if (gap < settleGap && _steerVx.abs() < settleVx) {
      position.x = targetX;
      _steerVx *= 0.18 + 0.27 * feel;
    }

    // Light lean into the dodge — sells the left/right move.
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
    size.setValues(
      GameConfig.playerWidth * _displayScale,
      GameConfig.playerHeight * _displayScale,
    );
    _shadow.size.setValues(size.x * 0.78, size.y * 0.11);
    _shadow.position.setValues(size.x * 0.5, size.y - 2);
  }
}
