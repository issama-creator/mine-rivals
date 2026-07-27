import 'dart:ui';

import '../game/game_config.dart';

enum Leader { player, thief }

/// Gap behind the cart — thief creeps closer on mistakes, falls back on
/// ideal line. Never overtakes / runs past the player.
class LeadSystem {
  double leadDistance = GameConfig.startLeadDistance;

  /// Smoothed lead used for camera depth — no teleports on bomb/miss.
  double visualLead = GameConfig.startLeadDistance;

  /// Legacy stubs — overtake pass removed (thief only bumps the cart).
  bool get isOvertaking => false;
  double get overtakeT => 0;
  bool get sprintOvertake => false;
  Leader visualLeader = Leader.player;
  Leader pendingLeader = Leader.player;

  /// Display pose — always eases toward target so he never hops.
  double _smoothThiefY = 0;
  double _smoothThiefScale = 1;
  bool _hasSmoothPose = false;

  /// Always true — thief stays behind / on the cart, never ahead.
  bool get playerLeads => true;

  Leader get logicalLeader => Leader.player;

  void reset() {
    leadDistance = GameConfig.startLeadDistance;
    visualLead = GameConfig.startLeadDistance;
    visualLeader = Leader.player;
    pendingLeader = Leader.player;
    _hasSmoothPose = false;
  }

  void applyDelta(double delta) {
    leadDistance = (leadDistance + delta).clamp(
      GameConfig.minLeadDistance,
      GameConfig.maxLeadDistance,
    );
  }

  void update(
    double dt, {
    required bool playingClean,
    double idealFactor = 1,
  }) {
    if (playingClean && idealFactor > 0) {
      final f = idealFactor.clamp(0.0, 1.0);
      if (leadDistance < GameConfig.maxLeadDistance) {
        // Ideal line opens the gap (thief falls back from the cart).
        applyDelta(GameConfig.leadRecoverPerSec * f * dt);
      }
    }

    final fallingBehind = leadDistance < visualLead;
    final rate = fallingBehind
        ? GameConfig.leadVisualFollowMistake
        : GameConfig.leadVisualFollow;
    final follow = 1 - (1 / (1 + rate * dt));
    visualLead += (leadDistance - visualLead) * follow;
  }

  /// Steady-state Y for a given lead — thief always behind the runner.
  ({double playerY, double thiefY}) _steadyDepth({
    required double screenHeight,
    required double lead,
  }) {
    final runnerY = screenHeight * GameConfig.cameraRunnerYFactor;
    final farY = screenHeight * GameConfig.cameraThiefFarYFactor;
    final closeY = runnerY + GameConfig.leadCloseGapPx;

    final t = (lead / GameConfig.maxLeadDistance).clamp(0.0, 1.0);
    return (
      playerY: runnerY,
      thiefY: lerpDouble(closeY, farY, t)!,
    );
  }

  ({double playerY, double thiefY, double playerScale, double thiefScale})
      depthPositions({required double screenHeight, double dt = 1 / 60}) {
    final runnerY = screenHeight * GameConfig.cameraRunnerYFactor;
    final farY = screenHeight * GameConfig.cameraThiefFarYFactor;

    final steady = _steadyDepth(screenHeight: screenHeight, lead: visualLead);
    final playerY = steady.playerY;
    final targetThiefY = steady.thiefY;

    if (!_hasSmoothPose || dt >= 0.2) {
      _smoothThiefY = targetThiefY;
      _hasSmoothPose = true;
    } else {
      final k = 1 - (1 / (1 + GameConfig.thiefYSmooth * dt));
      _smoothThiefY += (targetThiefY - _smoothThiefY) * k;
    }
    final thiefY = _smoothThiefY;

    final playerScale = GameConfig.playerHeroScale;

    double thiefDepthScale(double y) {
      final t = ((y - runnerY) / (farY - runnerY)).clamp(0.0, 1.0);
      return lerpDouble(
        GameConfig.depthScaleNear,
        GameConfig.depthScaleFar,
        t,
      )!;
    }

    var targetScale = thiefDepthScale(thiefY);
    final t = (visualLead / GameConfig.maxLeadDistance).clamp(0.0, 1.0);
    targetScale *= lerpDouble(1.0, GameConfig.thiefMaxLeadScale, t)!;

    if (dt >= 0.2) {
      _smoothThiefScale = targetScale;
    } else {
      final k = 1 - (1 / (1 + GameConfig.thiefScaleSmooth * dt));
      _smoothThiefScale += (targetScale - _smoothThiefScale) * k;
    }

    return (
      playerY: playerY,
      thiefY: thiefY,
      playerScale: playerScale,
      thiefScale: _smoothThiefScale,
    );
  }
}
