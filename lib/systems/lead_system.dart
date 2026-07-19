import 'dart:ui';

import 'package:flutter/animation.dart';

import '../game/game_config.dart';

enum Leader { player, thief }

typedef OvertakeCallback = void Function(Leader newLeader);

/// Hidden momentum / advantage between player and thief.
class LeadSystem {
  double leadDistance = GameConfig.startLeadDistance;
  /// Smoothed lead used for camera depth — no teleports on bomb/miss.
  double visualLead = GameConfig.startLeadDistance;
  bool isOvertaking = false;
  double overtakeT = 0;
  /// True when thief is passing after a mistake (longer glide).
  bool sprintOvertake = false;
  Leader visualLeader = Leader.player;
  Leader pendingLeader = Leader.player;

  OvertakeCallback? onOvertakeStarted;
  OvertakeCallback? onOvertakeFinished;

  double _lastPlayerY = 0;
  double _lastThiefY = 0;
  double _passFromPlayerY = 0;
  double _passFromThiefY = 0;
  double _passToPlayerY = 0;
  double _passToThiefY = 0;
  bool _capturePassPose = false;
  bool _hasLastPose = false;

  /// Display pose — always eases toward target so he never hops.
  double _smoothThiefY = 0;
  double _smoothThiefScale = 1;
  bool _hasSmoothPose = false;

  bool get playerLeads => leadDistance >= 0;

  Leader get logicalLeader => playerLeads ? Leader.player : Leader.thief;

  void reset() {
    leadDistance = GameConfig.startLeadDistance;
    visualLead = GameConfig.startLeadDistance;
    isOvertaking = false;
    overtakeT = 0;
    sprintOvertake = false;
    visualLeader = Leader.player;
    pendingLeader = Leader.player;
    _capturePassPose = false;
    _hasLastPose = false;
    _hasSmoothPose = false;
  }

  void applyDelta(double delta) {
    final before = leadDistance;
    leadDistance = (leadDistance + delta).clamp(
      GameConfig.minLeadDistance,
      GameConfig.maxLeadDistance,
    );
    _checkOvertake(before, leadDistance);
  }

  void update(double dt, {required bool playingClean}) {
    if (playingClean) {
      if (leadDistance < 0) {
        // Thief ahead — clean play slowly reels him back (coins help too).
        applyDelta(GameConfig.catchUpRecoverPerSec * dt);
      } else if (leadDistance < GameConfig.startLeadDistance) {
        applyDelta(GameConfig.leadRecoverPerSec * dt);
      }
    }

    // Always ease visual lead — also during overtake so exit doesn't snap.
    final fallingBehind = leadDistance < visualLead;
    final rate = isOvertaking
        ? 2.4
        : (fallingBehind
            ? GameConfig.leadVisualFollowMistake
            : GameConfig.leadVisualFollow);
    final follow = 1 - (1 / (1 + rate * dt));
    visualLead += (leadDistance - visualLead) * follow;

    if (!isOvertaking) return;

    final duration = sprintOvertake
        ? GameConfig.overtakeSprintDuration
        : GameConfig.overtakeDuration;
    overtakeT += dt / duration;
    if (overtakeT >= 1) {
      overtakeT = 1;
      isOvertaking = false;
      sprintOvertake = false;
      visualLeader = pendingLeader;
      // Land on the correct side of zero so he doesn't bounce back.
      if (pendingLeader == Leader.thief) {
        visualLead = leadDistance < -0.35 ? leadDistance : -0.35;
      } else {
        visualLead = leadDistance > 0.35 ? leadDistance : 0.35;
      }
      onOvertakeFinished?.call(visualLeader);
    }
  }

  void _checkOvertake(double before, double after) {
    if (isOvertaking) return;
    final crossedToThief = before >= 0 && after < 0;
    final crossedToPlayer = before < 0 && after >= 0;
    if (!crossedToThief && !crossedToPlayer) return;

    isOvertaking = true;
    overtakeT = 0;
    pendingLeader = after < 0 ? Leader.thief : Leader.player;
    sprintOvertake = pendingLeader == Leader.thief;
    _capturePassPose = true;
    onOvertakeStarted?.call(pendingLeader);
  }

  /// Steady-state Y for a given lead value (no overtake).
  ({double playerY, double thiefY}) _steadyDepth({
    required double screenHeight,
    required double lead,
  }) {
    final runnerY = screenHeight * GameConfig.cameraRunnerYFactor;
    final farY = screenHeight * GameConfig.cameraThiefFarYFactor;
    final aheadY = screenHeight * GameConfig.cameraThiefAheadYFactor;
    final closeY = runnerY + GameConfig.leadCloseGapPx;

    if (lead >= 0) {
      // Linear — small lead changes move him gently, no cubic jumps.
      final t = (lead / GameConfig.maxLeadDistance).clamp(0.0, 1.0);
      return (
        playerY: runnerY,
        thiefY: lerpDouble(closeY, farY, t)!,
      );
    }
    // Map meters ahead → screen: close on path → far → off-top by ~40 m.
    // Deeper gaps (up to 200 m) stay off-screen; HUD shows the number.
    final gap = (-lead).clamp(0.0, -GameConfig.minLeadDistance);
    final offAt = -GameConfig.thiefOffScreenLead; // positive meters
    final onScreen = aheadY;
    final offTop = -screenHeight * 0.12;
    late final double thiefY;
    if (gap <= 8) {
      thiefY = lerpDouble(runnerY - 20, onScreen, (gap / 8).clamp(0.0, 1.0))!;
    } else if (gap <= offAt) {
      final u = ((gap - 8) / (offAt - 8)).clamp(0.0, 1.0);
      thiefY = lerpDouble(onScreen, offTop, u)!;
    } else {
      thiefY = offTop;
    }
    return (
      playerY: runnerY,
      thiefY: thiefY,
    );
  }

  ({double playerY, double thiefY, double playerScale, double thiefScale})
      depthPositions({required double screenHeight, double dt = 1 / 60}) {
    final runnerY = screenHeight * GameConfig.cameraRunnerYFactor;
    final farY = screenHeight * GameConfig.cameraThiefFarYFactor;
    final aheadY = screenHeight * GameConfig.cameraThiefAheadYFactor;

    late double playerY;
    late double targetThiefY;

    if (isOvertaking) {
      final end = _steadyDepth(screenHeight: screenHeight, lead: leadDistance);

      if (_capturePassPose) {
        _passFromPlayerY = _hasLastPose ? _lastPlayerY : end.playerY;
        _passFromThiefY = _hasLastPose ? _lastThiefY : end.thiefY;
        _passToPlayerY = end.playerY;
        _passToThiefY = end.thiefY;
        // Partial pass only — remaining gap eases via visualLead after.
        if (pendingLeader == Leader.thief) {
          _passToThiefY = lerpDouble(runnerY - 24, aheadY, 0.35)!;
          _passToPlayerY = runnerY;
        } else {
          _passToPlayerY = runnerY;
          _passToThiefY = runnerY + GameConfig.leadCloseGapPx;
        }
        _capturePassPose = false;
      }

      final curve = Curves.easeInOutCubic.transform(overtakeT);
      playerY = lerpDouble(_passFromPlayerY, _passToPlayerY, curve)!;
      targetThiefY = lerpDouble(_passFromThiefY, _passToThiefY, curve)!;
    } else {
      final steady =
          _steadyDepth(screenHeight: screenHeight, lead: visualLead);
      playerY = steady.playerY;
      targetThiefY = steady.thiefY;
    }

    // Smooth thief Y so even target hops become a glide.
    if (!_hasSmoothPose || dt >= 0.2) {
      _smoothThiefY = targetThiefY;
      _hasSmoothPose = true;
    } else {
      final k = 1 - (1 / (1 + GameConfig.thiefYSmooth * dt));
      _smoothThiefY += (targetThiefY - _smoothThiefY) * k;
    }
    final thiefY = _smoothThiefY;

    _lastPlayerY = playerY;
    _lastThiefY = thiefY;
    _hasLastPose = true;

    final playerScale = GameConfig.playerHeroScale;

    double thiefDepthScale(double y) {
      if (y < runnerY) {
        final span = (runnerY - aheadY).clamp(1.0, double.infinity);
        final t = ((runnerY - y) / span).clamp(0.0, 1.0);
        return lerpDouble(
          GameConfig.depthScaleNear,
          GameConfig.thiefAheadScale,
          t,
        )!;
      }
      final t = ((y - runnerY) / (farY - runnerY)).clamp(0.0, 1.0);
      return lerpDouble(
        GameConfig.depthScaleNear,
        GameConfig.depthScaleFar,
        t,
      )!;
    }

    final leadForScale = visualLead;
    var targetScale = thiefDepthScale(thiefY);
    if (leadForScale > 0) {
      final t = (leadForScale / GameConfig.maxLeadDistance).clamp(0.0, 1.0);
      targetScale *= lerpDouble(1.0, GameConfig.thiefMaxLeadScale, t)!;
    }

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
