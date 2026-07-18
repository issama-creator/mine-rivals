import '../systems/game_settings.dart';

/// Tunable balance + world constants for Mine Rivals.
class GameConfig {
  /// Length of one shaft; theme swaps every segment.
  static const double corridorSegmentMeters = 700;

  /// How many corridor PNGs ship in assets (always load all).
  static const int corridorAssetCount = 10;

  /// Active run length — from [GameSettings.runMode].
  static int get corridorCount => GameSettings.instance.runMode.corridors;

  static double get levelLengthMeters =>
      corridorSegmentMeters * corridorCount;

  /// Subway-style pace: starts calm, steps up every [speedStepMeters].
  static const double runSpeedStart = 11.9;

  /// Speed jumps every this many meters.
  static const double speedStepMeters = 200;

  /// +25% of start every 200 m (was +15%, +10% more on top).
  static const double speedStepBoost = 0.25;

  /// HUD/corridor meters still say 700 — but they tick this fraction of pace
  /// (lower = longer shafts). 0.62 ≈ +17% duration vs previous 0.75.
  static const double distanceMeterRate = 0.62;

  /// World run speed — +25% of start every 200 m (both modes).
  static double runSpeedAt(double progress) {
    final distance = (progress.clamp(0.0, 1.0)) * levelLengthMeters;
    final step = (distance / speedStepMeters).floor();
    // 0m → start, 200m → ×1.25, 400m → ×1.50, …
    return runSpeedStart * (1.0 + speedStepBoost * step);
  }

  /// How fast run-cycle anim plays vs base (matches world pace).
  static double runAnimRateAt(double progress) {
    final pace = runSpeedAt(progress);
    return (pace / runSpeedStart).clamp(1.0, 2.9);
  }

  /// Spawn density — late shafts throw loot much denser.
  static double spawnTempoAt(double progress) {
    final t = progress.clamp(0.0, 1.0);
    return 1.0 + t * 1.25;
  }

  /// Hot chase — ~15% easier than first rivalry pass (thief less oppressive).
  static const double startLeadDistance = 3.7;
  static const double maxLeadDistance = 4.0;
  /// Thief can pull up to ~10 m ahead on a long mistake streak.
  static const double minLeadDistance = -10.0;

  /// Coins never push lead (columns are free score). Lead is jewel/mistake based.
  static const double leadGainOnCatch = 0.0;
  /// Jewels are the contested prize — catching them opens the gap.
  static const double leadGainOnRare = 2.07;
  static const double leadGainOnCombo = 1.38;
  /// Extra lead meters added for each jewel catch in a success streak.
  static const double successStreakLeadBonus = 0.46;
  /// Miss a coin — thief closes in (the real chase pressure).
  static const double leadLossOnMiss = 1.06;
  static const double leadLossOnMissRare = 1.49;
  static const double leadLossOnBomb = 1.23;
  static const double leadLossPerMistakeStreak = 0.47;
  /// How fast pending chase debt drains into real lead (m/s).
  static const double leadDebtPerSec = 1.40;
  /// Enough debt to push thief toward the full −10 m gap.
  static const double leadDebtMax = 7.2;
  /// Slow recover only while playing clean (no misses).
  static const double leadRecoverPerSec = 0.092;
  /// How fast the thief eases when you pull ahead (goes back).
  static const double leadVisualFollow = 1.35;
  /// How fast he eases when closing after your mistakes (slow approach).
  static const double leadVisualFollowMistake = 0.81;
  /// Extra smoothing on thief screen Y (kills leftover hops).
  static const double thiefYSmooth = 4.2;
  static const double thiefScaleSmooth = 5.0;

  static const double overtakeDuration = 1.55;
  /// Thief takes the lead after a blunder — slow glide past you.
  static const double overtakeSprintDuration = 1.9;
  /// Show faint chase arrow once the thief is this far behind.
  static const double chaseArrowLeadMin = 2.2;
  static const int comboThreshold = 8;

  // ── Thief momentum bursts (rivalry waves) — ~15% softer / rarer ───────────
  static const double thiefBurstDuration = 2.2;
  static const double thiefBurstMetersMin = 98;
  static const double thiefBurstMetersMax = 138;
  /// Extra closing speed while bursting (on top of debt drain).
  static const double thiefBurstClosePerSec = 1.15;
  /// Debt drain multiplier during a burst.
  static const double thiefBurstDebtMult = 1.45;
  /// Mistake streak that can trigger an early burst.
  static const int thiefBurstFromMistakes = 2;
  static const double thiefBurstCooldown = 16;
  /// Stronger steal vacuum while bursting.
  static const double thiefBurstMagnetRadius = 128;
  static const double thiefBurstMagnetPullSpeed = 264;

  // ── “Breathing down your neck” juice ─────────────────────────────────────
  static const double thiefBreathLeadMax = 1.28;
  static const double thiefBreathFlashEvery = 1.35;
  static const double thiefBreathBannerCooldown = 5.2;

  static const double itemFallSpeedMin = 160;
  static const double itemFallSpeedMax = 280;
  static const double spawnIntervalStart = 1.0;
  static const double spawnIntervalMin = 0.38;

  static const double playerWidth = 66;
  static const double playerHeight = 128;
  /// Slightly smaller than the miner so the rivalry reads clearer.
  static const double thiefWidth = 60;
  static const double thiefHeight = 118;
  /// Slight boost over depth scale — keep the miner readable, not oversized.
  static const double playerHeroScale = 0.98;

  /// Soft lane steer (velocity follow, not a hard snap).
  static const double playerSteerSpeed = 13;
  /// How quickly steer velocity eases toward the finger intent.
  static const double playerSteerAccel = 8.5;
  /// Max lateral speed (px/s) — keeps dodges readable.
  static const double playerSteerMaxSpeed = 600;
  /// Finger drag slightly longer than 1:1 for comfortable lane swaps.
  static const double playerDragGain = 1.08;
  /// Late run — a bit more bite without losing the smooth arc.
  static const double playerSteerFinaleBoost = 1.06;
  /// Body lean while strafing (radians at full speed).
  static const double playerSteerLean = 0.08;

  /// 0 = очень плавно, 1 = резко ([GameSettings.controlSensitivity]).
  static double get steerFeel =>
      GameSettings.instance.controlSensitivity.clamp(0.0, 1.0);

  /// Lerp from soft floor → sharp ceiling (left end is softer than old “base”).
  static double _steerLerp(double soft, double sharp) =>
      soft + (sharp - soft) * steerFeel;

  static double get steerSpeed =>
      playerSteerSpeed * _steerLerp(0.55, 1.45);
  static double get steerAccel =>
      playerSteerAccel * _steerLerp(0.48, 1.7);
  static double get steerMaxSpeed =>
      playerSteerMaxSpeed * _steerLerp(0.62, 1.35);
  static double get steerDragGain =>
      playerDragGain * _steerLerp(0.82, 1.22);
  static double get steerFinaleBoost =>
      playerSteerFinaleBoost * _steerLerp(0.92, 1.12);
  static double get steerLean =>
      playerSteerLean * _steerLerp(0.7, 1.35);

  /// Soft depth for the trailing thief only — hero never uses far shrink.
  static const double depthScaleNear = 1.0;
  static const double depthScaleFar = 0.72;
  /// At full 5 m lead the thief is small, but the miner stays full size.
  static const double thiefMaxLeadScale = 0.42;
  static const double basketWidth = 58;
  static const double basketHeight = 32;

  /// Last meters: sprint denser loot + finish beat.
  static const double finaleMeters = 100;
  /// Spawn gaps shrink in the final sprint.
  static const double finaleSpawnGapMult = 0.58;
  /// Slight world rush (not slow-mo) for the last push.
  static const double finalePlayRate = 1.08;

  // ── Coin combo multiplier (Subway-style) ─────────────────────────────────
  /// Unbroken gold streak for ×2.
  static const int coinMult2At = 8;
  /// Unbroken gold streak for ×3.
  static const int coinMult3At = 16;
  /// Trail sparks while streak is at least this.
  static const int coinTrailFromStreak = 3;

  /// Falling loot sizes — jewels share one square so corridor crops look even.
  static const double jewelDisplaySize = 48;
  static const double lootDisplaySize = 38;
  /// Base bomb size — scaled up further at high run pace in-game.
  static const double bombDisplaySize = 54;
  /// Extra bomb scale at full pace (1 = base, 1.22 = +22% when fast).
  static const double bombSpeedScaleMax = 1.22;

  static const double magnetRadius = 16;
  static const double magnetPullSpeed = 45;
  /// Gold snap — short “sucks into basket” assist (~80–120 ms feel).
  static const double goldSnapRadius = 38;
  static const double goldSnapPullSpeed = 460;

  // ── Subway-style magnet power-up ─────────────────────────────────────────
  static const double magnetDisplaySize = 44;
  static const double magnetPowerDuration = 15;
  /// Wide vacuum while the power-up is active (skips bomb/web).
  static const double powerMagnetRadius = 210;
  static const double powerMagnetPullSpeed = 560;
  /// Chance a pattern slot becomes a magnet pickup (still gated by cooldown).
  static const double magnetSpawnChance = 0.04;
  static const double magnetRespawnMin = 22;
  static const double magnetRespawnMax = 38;
  static const double catchRadius = 26;
  /// Bombs: circular center-to-center touch only — near misses never explode.
  static const double bombCatchRadius = 15;

  // ── Web (spider net) hazard ──────────────────────────────────────────────
  static const double webDisplaySize = 42;
  /// Strict touch like bombs — glancing pass doesn't snare.
  static const double webCatchRadius = 13;
  /// Web appears from this 1-based shaft onward (1 = from the start).
  static const int webFromCorridor = 1;
  /// Chance a normal spawn beat becomes a web (once eligible). +10% traps.
  static const double webSpawnChance = 0.11;
  /// Rare combo: double web → pit a few meters later (also gated by cooldown).
  static const double webPitComboChance = 0.055;
  static const double webPitComboCooldownMin = 22;
  static const double webPitComboCooldownMax = 36;
  /// How long the player stays sticky/slow after touching a web.
  static const double webSnareDuration = 3.0;
  /// Player control sluggishness while snared (1 = normal, lower = slower).
  static const double webSnareMoveFactor = 0.32;
  /// World + stride slow while snared (bomb-like hitch, a bit softer).
  static const double webSnarePlayRate = 0.55;
  /// Chase pressure — close to a bomb, but no crystal loss.
  static const double leadLossOnWeb = 1.02;

  /// Three dodge lanes — always at least one clear row to slip through.
  static const int bombLaneCount = 3;
  /// Chance a bomb beat is a 2-lane gate (one free lane) instead of a single.
  static const double bombDualChance = 0.55;
  /// Min/max pause before the next bomb pattern — denser timing traps.
  static const double bombCooldownMin = 0.95;
  static const double bombCooldownMax = 1.85;

  // ── Pit (black hole) — instant fail ──────────────────────────────────────
  static const double pitDisplaySize = 52;
  /// Touch radius vs player feet / basket — forgiving edge, lethal center.
  static const double pitCatchRadius = 22;
  /// Pattern chance for a pit trap (also gated by cooldown in director).
  static const double pitSpawnChance = 0.16;
  static const double pitRespawnMin = 6.5;
  static const double pitRespawnMax = 12;
  /// Suck-into-pit cinematic length (seconds).
  static const double pitSuckDuration = 0.78;

  /// Opening beat — thief close on camera so the chase reads immediately.
  static const double chaseIntroSec = 2.35;

  /// Walkable stone path inset from each screen edge (player steering).
  /// ~0.27 keeps the miner on the cobbles, out of wall mushrooms/ice.
  static const double pathInsetFrac = 0.27;
  /// Extra padding inside the path so sprites don't kiss the rock edge.
  static const double pathPadPx = 6;

  /// Normal loot/bombs: tighter center band for the 3 rows (~56% width).
  static const double spawnInsetFrac = 0.28;
  /// Rare “in the bushes” spawn near the wall ice (still on path edge).
  static const double bushSpawnChance = 0.14;
  static const double bushInsetFrac = 0.17;

  static const double thiefMagnetRadius = 118;
  static const double thiefMagnetPullSpeed = 240;
  /// When thief leads — wider / faster jewel vacuum (revenge).
  static const double thiefRevengeMagnetRadius = 168;
  static const double thiefRevengeMagnetPullSpeed = 360;
  static const double thiefRevengeStealDist = 30;

  /// Player always stays in the runner band — never vanishes up/back.
  /// Thief slides down when you lead, or up the corridor when he leads.
  static const double cameraRunnerYFactor = 0.82;
  static const double cameraThiefFarYFactor = 1.05;
  /// How high up the shaft the thief can go when crushing you.
  static const double cameraThiefAheadYFactor = 0.56;
  /// At high run speed, drop the runner band so more path is visible ahead.
  /// ~11% of screen — readable look-ahead, still not a hard tilt.
  static const double cameraSpeedDipMax = 0.11;
  /// Pace ratio (vs start) where the dip begins / reaches full.
  static const double cameraSpeedDipFrom = 1.0;
  static const double cameraSpeedDipFull = 1.75;
  /// How fast the camera eases into the speed dip.
  static const double cameraSpeedDipFollow = 4.5;
  /// Spawn bombs this many extra px above the top when pace is high.
  static const double bombSpawnLeadPxMax = 72;
  static const double leadCloseGapPx = 48;
  /// Mild shrink when thief is deep ahead up the corridor.
  static const double thiefAheadScale = 0.72;

  /// 1-based shaft: blue thief joins from this corridor onward (after 6).
  static const int blueThiefFromCorridor = 7;
  static const double thiefLaneOffsetX = 44;
  static const double thiefPassExtraX = 58;
  static const double thiefMinClearanceX = 56;

  static const int runFps = 9;
  /// Slightly snappier stride so airborne feet don't hang a beat.
  static const int minerRunFps = 9;
  static const int runFrames = 18;
}
