import 'dart:math';

import 'package:flame/components.dart';

import '../effects/ground_shadow.dart';
import '../game/asset_library.dart';
import '../game/game_config.dart';

/// Single black thief (vor.png) — no blue twin.
class ThiefComponent extends SpriteAnimationComponent {
  ThiefComponent()
      : super(
          size: Vector2(GameConfig.thiefWidth, GameConfig.thiefHeight),
          anchor: Anchor.bottomCenter,
          priority: 10,
        );

  double _displayScale = 1;
  double _animRate = 1;
  double _animRateTarget = 1;
  final Random _rng = Random();
  GroundShadow? _shadow;

  double passSide = 1;

  /// Shadow under boots — sheet pad below feet would otherwise float them.
  double get _shadowY => size.y * 0.92;
  double get _shadowH => size.y * 0.085;

  void setRunAnimRate(double rate) {
    // Pace barely speeds the walk — keeps a calm step.
    _animRateTarget =
        (0.72 + rate * 0.18).clamp(0.72, GameConfig.minerCartAnimRateMax);
  }

  @override
  void update(double dt) {
    final follow = 1 - (1 / (1 + 6.5 * dt));
    _animRate += (_animRateTarget - _animRate) * follow;
    super.update(dt * _animRate);
  }

  @override
  Future<void> onLoad() async {
    if (!AssetLibrary.ready) {
      await AssetLibrary.ensureLoaded(prefetchRest: false);
    }
    animation = AssetLibrary.thiefRun;
    playing = true;
    passSide = _rng.nextBool() ? 1.0 : -1.0;

    final shadow = GroundShadow();
    shadow.size = Vector2(size.x * 0.72, _shadowH);
    shadow.position = Vector2(size.x * 0.5, _shadowY);
    _shadow = shadow;
    await add(shadow);
  }

  /// Follow / press the cart — no overtake side-pass.
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
      lane = playerX + 14 * passSide;
    } else if (breathingDownNeck) {
      lane = screenCenterX + GameConfig.thiefLaneOffsetX * passSide;
    }

    if (!pressingCart) {
      final minClear = GameConfig.thiefMinClearanceX;
      if ((lane - playerX).abs() < minClear) {
        lane = playerX + minClear * passSide;
      }
    }

    // Soft lateral follow — no snap/rock between lane targets.
    final speed = pressingCart ? 5.5 : (sprinting ? 3.2 : 4.0);
    position.x += (lane - position.x) * (1 - (1 / (1 + speed * dt)));
  }

  void applyDepthScale(double scale, [double dt = 1 / 60]) {
    final target = scale;
    if (dt >= 0.2) {
      _displayScale = target;
    } else {
      _displayScale += (target - _displayScale) * (1 - (1 / (1 + 5.5 * dt)));
    }
    size.setValues(
      GameConfig.thiefWidth * _displayScale,
      GameConfig.thiefHeight * _displayScale,
    );
    final shadow = _shadow;
    if (shadow == null) return;
    shadow.size.setValues(size.x * 0.72, _shadowH);
    shadow.position.setValues(size.x * 0.5, _shadowY);
  }
}
