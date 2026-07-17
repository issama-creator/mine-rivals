import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/animation.dart';

import '../effects/ground_shadow.dart';
import '../game/asset_library.dart';
import '../game/game_config.dart';

class ThiefComponent extends SpriteAnimationComponent {
  ThiefComponent()
      : super(
          size: Vector2(GameConfig.thiefWidth, GameConfig.thiefHeight),
          anchor: Anchor.bottomCenter,
          priority: 10,
        );

  double _swayT = 0;
  double _displayScale = 1;
  final Random _rng = Random();
  late GroundShadow _shadow;

  double passSide = 1;

  @override
  Future<void> onLoad() async {
    await AssetLibrary.ensureLoaded();
    animation = AssetLibrary.thiefRun;
    playing = true;
    _swayT = _rng.nextDouble() * pi * 2;
    passSide = _rng.nextBool() ? 1.0 : -1.0;

    _shadow = GroundShadow();
    _shadow.size = Vector2(size.x * 0.78, size.y * 0.11);
    _shadow.position = Vector2(size.x * 0.5, size.y - 2);
    await add(_shadow);
  }

  void runLane({
    required double screenCenterX,
    required double playerX,
    required double dt,
    required bool overtaking,
    required double overtakeT,
    required bool breathingDownNeck,
    bool sprinting = false,
  }) {
    _swayT += dt * 1.5;
    final sway = sin(_swayT) * 8;

    var lane = screenCenterX + GameConfig.thiefLaneOffsetX * passSide + sway;

    if (overtaking) {
      // Peak sideways in the middle of the pass — classic runner lane swap.
      final arc = sin(Curves.easeInOut.transform(overtakeT.clamp(0.0, 1.0)) * pi);
      lane = screenCenterX +
          (GameConfig.thiefLaneOffsetX + GameConfig.thiefPassExtraX * arc) *
              passSide +
          sway * 0.25;
    } else if (breathingDownNeck) {
      lane = screenCenterX +
          (GameConfig.thiefLaneOffsetX + 14) * passSide +
          sway;
    }

    final minClear = GameConfig.thiefMinClearanceX;
    if ((lane - playerX).abs() < minClear) {
      lane = playerX + minClear * passSide;
    }

    // Softer X on mistake-pass so he doesn't hop sideways.
    final speed = sprinting ? 5.5 : (overtaking ? 7.5 : 8.0);
    position.x += (lane - position.x) * (1 - (1 / (1 + speed * dt)));
  }

  void applyDepthScale(double scale, [double dt = 1 / 60]) {
    if (dt >= 0.2) {
      _displayScale = scale;
    } else {
      // Gentle size ease — matches soft Y glide.
      _displayScale += (scale - _displayScale) * (1 - (1 / (1 + 5.5 * dt)));
    }
    size = Vector2(
      GameConfig.thiefWidth * _displayScale,
      GameConfig.thiefHeight * _displayScale,
    );
    _shadow.size = Vector2(size.x * 0.78, size.y * 0.11);
    _shadow.position = Vector2(size.x * 0.5, size.y - 2);
  }
}
