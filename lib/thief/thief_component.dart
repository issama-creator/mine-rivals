import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/animation.dart';

import '../effects/ground_shadow.dart';
import '../game/asset_library.dart';
import '../game/game_config.dart';

enum ThiefKind { primary, blue }

class ThiefComponent extends SpriteAnimationComponent {
  ThiefComponent({this.kind = ThiefKind.primary})
      : super(
          size: Vector2(GameConfig.thiefWidth, GameConfig.thiefHeight),
          anchor: Anchor.bottomCenter,
          priority: kind == ThiefKind.primary ? 10 : 8,
        );

  final ThiefKind kind;

  double _displayScale = 1;
  double _animRate = 1;
  final Random _rng = Random();
  GroundShadow? _shadow;

  double passSide = 1;

  /// Extra world Y (further down the shaft = behind the pack leader).
  double get depthBias => switch (kind) {
        ThiefKind.primary => 0,
        ThiefKind.blue => 36,
      };

  double get laneBias => switch (kind) {
        ThiefKind.primary => 0,
        ThiefKind.blue => -22,
      };

  double get scaleMul => switch (kind) {
        ThiefKind.primary => 1,
        ThiefKind.blue => 0.92,
      };

  void setRunAnimRate(double rate) {
    _animRate = rate.clamp(0.95, 3.0);
  }

  @override
  void update(double dt) {
    super.update(dt * _animRate);
  }

  @override
  Future<void> onLoad() async {
    await AssetLibrary.ensureLoaded();
    if (kind == ThiefKind.blue) {
      await AssetLibrary.ensureThiefBlueLoaded();
    }
    animation = switch (kind) {
      ThiefKind.primary => AssetLibrary.thiefRun,
      ThiefKind.blue => AssetLibrary.thiefRunBlue,
    };
    playing = true;
    passSide = switch (kind) {
      ThiefKind.primary => _rng.nextBool() ? 1.0 : -1.0,
      ThiefKind.blue => -1.0,
    };

    final shadow = GroundShadow();
    shadow.size = Vector2(size.x * 0.78, size.y * 0.11);
    shadow.position = Vector2(size.x * 0.5, size.y - 2);
    _shadow = shadow;
    await add(shadow);
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
    // Straight lane — no side sway; only overtake / clearance nudges X.
    var lane = screenCenterX +
        GameConfig.thiefLaneOffsetX * passSide +
        laneBias;

    if (overtaking && kind == ThiefKind.primary) {
      final arc =
          sin(Curves.easeInOut.transform(overtakeT.clamp(0.0, 1.0)) * pi);
      lane = screenCenterX +
          (GameConfig.thiefLaneOffsetX + GameConfig.thiefPassExtraX * arc) *
              passSide;
    } else if (breathingDownNeck) {
      lane = screenCenterX +
          (GameConfig.thiefLaneOffsetX + 14) * passSide +
          laneBias;
    }

    final minClear = GameConfig.thiefMinClearanceX;
    if ((lane - playerX).abs() < minClear) {
      lane = playerX + minClear * passSide;
    }

    final speed = sprinting
        ? 5.5
        : (overtaking && kind == ThiefKind.primary ? 7.5 : 8.0);
    position.x += (lane - position.x) * (1 - (1 / (1 + speed * dt)));
  }

  void applyDepthScale(double scale, [double dt = 1 / 60]) {
    final target = scale * scaleMul;
    if (dt >= 0.2) {
      _displayScale = target;
    } else {
      _displayScale += (target - _displayScale) * (1 - (1 / (1 + 5.5 * dt)));
    }
    size = Vector2(
      GameConfig.thiefWidth * _displayScale,
      GameConfig.thiefHeight * _displayScale,
    );
    // Shadow is created in onLoad — skip until mounted (blue thief join).
    final shadow = _shadow;
    if (shadow == null) return;
    shadow.size = Vector2(size.x * 0.78, size.y * 0.11);
    shadow.position = Vector2(size.x * 0.5, size.y - 2);
  }
}
