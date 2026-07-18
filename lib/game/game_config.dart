/// Tunable balance + world constants for Mine Rivals.
class GameConfig {
  /// 10 corridors × 700 m = 7000 m run; theme swaps every shaft.
  static const double corridorSegmentMeters = 700;
  static const int corridorCount = 10;
  static const double levelLengthMeters =
      corridorSegmentMeters * corridorCount;

  /// Pace climbs each corridor (level) — clear bump shaft to shaft.
  static const double runSpeedStart = 15;
  static const double runSpeedPerCorridor = 1.55;
  static const double runSpeedEnd = 31;

  /// World run speed from overall progress (0..1).
  static double runSpeedAt(double progress) {
    final t = progress.clamp(0.0, 1.0);
    // Corridor index 0..9 plus soft blend inside the shaft.
    final corridorF = t * corridorCount;
    final corridor = corridorF.floor().clamp(0, corridorCount - 1);
    final within = (corridorF - corridor).clamp(0.0, 1.0);
    final base = runSpeedStart + corridor * runSpeedPerCorridor;
    final next = runSpeedStart +
        (corridor + 1).clamp(0, corridorCount) * runSpeedPerCorridor;
    final speed = base + (next - base) * within * 0.55;
    return speed.clamp(runSpeedStart, runSpeedEnd);
  }

  /// How fast run-cycle anim plays vs base (matches world pace).
  static double runAnimRateAt(double progress) {
    final pace = runSpeedAt(progress);
    return (pace / runSpeedStart).clamp(0.95, 2.05);
  }

  /// Spawn density grows gently toward the end.
  static double spawnTempoAt(double progress) {
    final t = progress.clamp(0.0, 1.0);
    return 1.0 + t * 0.55;
  }

  /// Start with a clear ~5 m gap; clean play caps around there.
  static const double startLeadDistance = 4.0;
  static const double maxLeadDistance = 5.0;
  /// Thief can pull up to ~10 m ahead on a long mistake streak (was 5).
  static const double minLeadDistance = -10.0;

  /// Success — you pull ahead; streak makes the gap even bigger.
  static const double leadGainOnCatch = 0.8;
  static const double leadGainOnRare = 2.4;
  static const double leadGainOnCombo = 1.5;
  /// Extra lead meters added for each catch in a success streak.
  static const double successStreakLeadBonus = 0.55;
  /// Mistakes add chase debt — thief closes gradually, not in one jump.
  static const double leadLossOnMiss = 0.7;
  static const double leadLossOnMissRare = 1.0;
  static const double leadLossOnBomb = 1.1;
  static const double leadLossPerMistakeStreak = 0.4;
  /// How fast pending chase debt drains into real lead (m/s).
  static const double leadDebtPerSec = 1.05;
  /// Enough debt to push thief toward the full −10 m gap.
  static const double leadDebtMax = 9.0;
  static const double leadRecoverPerSec = 0.1;
  /// How fast the thief eases when you pull ahead (goes back).
  static const double leadVisualFollow = 1.35;
  /// How fast he eases when closing after your mistakes (slow approach).
  static const double leadVisualFollowMistake = 0.72;
  /// Extra smoothing on thief screen Y (kills leftover hops).
  static const double thiefYSmooth = 4.2;
  static const double thiefScaleSmooth = 5.0;

  static const double overtakeDuration = 1.55;
  /// Thief takes the lead after a blunder — slow glide past you.
  static const double overtakeSprintDuration = 1.9;
  /// Show faint chase arrow once the thief is this far behind.
  static const double chaseArrowLeadMin = 2.6;
  static const int comboThreshold = 8;

  static const double itemFallSpeedMin = 140;
  static const double itemFallSpeedMax = 220;
  static const double spawnIntervalStart = 1.05;
  static const double spawnIntervalMin = 0.55;

  static const double playerWidth = 66;
  static const double playerHeight = 128;
  /// Slightly smaller than the miner so the rivalry reads clearer.
  static const double thiefWidth = 60;
  static const double thiefHeight = 118;
  /// Slight boost over depth scale — keep the miner readable, not oversized.
  static const double playerHeroScale = 0.98;

  /// Soft depth for the trailing thief only — hero never uses far shrink.
  static const double depthScaleNear = 1.0;
  static const double depthScaleFar = 0.72;
  /// At full 5 m lead the thief is small, but the miner stays full size.
  static const double thiefMaxLeadScale = 0.42;
  static const double basketWidth = 58;
  static const double basketHeight = 32;

  /// Last meters: slow-mo + finish beat.
  static const double finaleMeters = 40;

  /// Falling loot sizes — jewels share one square so corridor crops look even.
  static const double jewelDisplaySize = 48;
  static const double lootDisplaySize = 38;
  static const double bombDisplaySize = 34;

  static const double magnetRadius = 16;
  static const double magnetPullSpeed = 45;
  static const double catchRadius = 26;
  /// Bombs: circular center-to-center touch only — near misses never explode.
  static const double bombCatchRadius = 11;

  /// Three dodge lanes — always at least one clear row to slip through.
  static const int bombLaneCount = 3;
  /// Chance a bomb beat is a 2-lane gate (one free lane) instead of a single.
  static const double bombDualChance = 0.42;
  /// Min/max pause before the next bomb pattern.
  static const double bombCooldownMin = 1.5;
  static const double bombCooldownMax = 2.9;

  static const double thiefMagnetRadius = 118;
  static const double thiefMagnetPullSpeed = 240;

  /// Player always stays in the runner band — never vanishes up/back.
  /// Thief slides down when you lead, or up the corridor when he leads.
  static const double cameraRunnerYFactor = 0.82;
  static const double cameraThiefFarYFactor = 1.05;
  /// How high up the shaft the thief can go when crushing you.
  static const double cameraThiefAheadYFactor = 0.56;
  static const double leadCloseGapPx = 48;
  /// Mild shrink when thief is deep ahead up the corridor.
  static const double thiefAheadScale = 0.72;

  /// 1-based shaft: blue thief joins from this corridor onward (after 6).
  static const int blueThiefFromCorridor = 7;
  static const double thiefLaneOffsetX = 44;
  static const double thiefPassExtraX = 58;
  static const double thiefMinClearanceX = 56;

  static const int runFps = 7;
  /// Softer stride — frames hold a bit longer, less snappy.
  static const int minerRunFps = 7;
  static const int runFrames = 18;
}
