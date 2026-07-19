import 'dart:math' as math;

import '../systems/game_settings.dart';

/// Tunable balance + world constants for Mine Rivals.
class GameConfig {
  /// Theme / shaft art swaps every kilometer (endless).
  static const double corridorSegmentMeters = 1000;

  /// How many corridor PNGs ship in assets (cycle forever).
  static const int corridorAssetCount = 10;

  /// Visual shaft cycle length (not a finish line).
  static int get corridorCount => corridorAssetCount;

  /// Subway-style pace: starts calm, steps up every [speedStepMeters],
  /// then soft-caps so late run stays readable (top-runner style).
  static const double runSpeedStart = 11.9;

  /// Speed jumps every this many meters.
  static const double speedStepMeters = 200;

  /// Full +25% bumps until [speedSoftCapStep], then tiny steps.
  static const double speedStepBoost = 0.25;

  /// After this many 200 m steps (~1200 m) pace rises much slower.
  static const int speedSoftCapStep = 6;

  /// Post-cap bump per step (keeps late run tense, not unreadable).
  static const double speedSoftStepBoost = 0.07;

  /// Hard ceiling ≈ ×2.85 start (~34 m/s world) — was uncapped ~×5+.
  static const double speedHardCapMult = 2.85;

  /// HUD meters tick this fraction of world pace.
  static const double distanceMeterRate = 0.62;

  /// Long mode — slightly denser loot / pressure.
  static double get modeSpawnTempoMult =>
      GameSettings.instance.runMode.isLong ? 1.14 : 1.0;

  /// Difficulty 0→1 from meters (asymptote — no hard finish).
  static double difficultyFromDistance(double meters) {
    final m = meters.clamp(0.0, 100000.0);
    return (1.0 - math.exp(-m / 1800.0)).clamp(0.0, 1.0);
  }

  /// World run speed from meters traveled.
  static double runSpeedAt(double meters) {
    final step = (meters.clamp(0.0, 100000.0) / speedStepMeters).floor();
    final double mult;
    if (step <= speedSoftCapStep) {
      mult = 1.0 + speedStepBoost * step;
    } else {
      final soft = step - speedSoftCapStep;
      mult = 1.0 +
          speedStepBoost * speedSoftCapStep +
          speedSoftStepBoost * soft;
    }
    return runSpeedStart * mult.clamp(1.0, speedHardCapMult);
  }

  /// How fast run-cycle anim plays vs base (matches world pace).
  static double runAnimRateAt(double meters) {
    final pace = runSpeedAt(meters);
    return (pace / runSpeedStart).clamp(1.0, 2.9);
  }

  /// Spawn density from difficulty 0–1 (+ mode mult).
  static double spawnTempoAt(double progress) {
    final t = progress.clamp(0.0, 1.0);
    final shaped = t < 0.66 ? t : 0.66 + (t - 0.66) * 0.55;
    return (1.0 + shaped * 0.9) * modeSpawnTempoMult;
  }

  /// Hot chase — player lead stays tight; thief gap uses meters (see min).
  static const double startLeadDistance = 3.7;
  static const double maxLeadDistance = 4.0;
  /// Thief can bolt up to this many meters ahead (HUD shows the gap).
  static const double minLeadDistance = -200.0;
  /// Soft banner when he is far enough to leave the screen (no lose).
  static const double thiefEscapeLead = -32.0;
  /// Legacy — escape no longer ends the run.
  static const double thiefEscapeSeconds = 10.0;
  /// Visual: beyond this gap he stays off the top (gap lives in HUD).
  static const double thiefOffScreenLead = -40.0;

  /// Coins while YOU lead — score only. Catch-up uses [leadGainOnCoinCatchUp].
  static const double leadGainOnCatch = 0.0;
  /// Jewels are the contested prize — catching them opens the gap.
  static const double leadGainOnRare = 2.07;
  static const double leadGainOnCombo = 1.38;
  /// Extra lead meters added for each jewel catch in a success streak.
  static const double successStreakLeadBonus = 0.46;

  /// While thief leads: each clean coin chips the gap (readable meters).
  static const double leadGainOnCoinCatchUp = 2.8;
  /// Extra per unbroken coin in the streak (soft, capped in-game).
  static const double leadGainOnCoinCatchUpStreak = 0.35;
  static const double catchUpLeadMaxPerCoin = 6.5;
  /// Coins also burn chase debt so recover can kick in.
  static const double catchUpDebtBurnPerCoin = 2.2;
  /// Steady close while clean AND thief ahead (m/s) — no mistakes.
  static const double catchUpRecoverPerSec = 4.2;

  /// How hard catch-up hits by gap depth (0 at even → stronger when he bolted).
  static double catchUpDepthMult(double leadDistance) {
    if (leadDistance >= 0) return 0;
    final depth = (-leadDistance / -minLeadDistance).clamp(0.0, 1.0);
    return 0.75 + depth * 0.85;
  }

  /// Miss a coin — thief opens the meter gap.
  static const double leadLossOnMiss = 5.5;
  static const double leadLossOnMissRare = 7.5;
  static const double leadLossOnBomb = 8.5;
  static const double leadLossPerMistakeStreak = 2.2;
  /// How fast pending chase debt drains into real lead (m/s) — smoother.
  static const double leadDebtPerSec = 6.5;
  /// Cap so one bad streak can't dump the full 200 m instantly.
  static const double leadDebtMax = 55.0;
  /// Slow recover toward start lead while you already lead (clean play).
  static const double leadRecoverPerSec = 0.092;
  /// How fast the thief eases when you pull ahead (goes back).
  static const double leadVisualFollow = 1.35;
  /// How fast he eases when closing after your mistakes (slow approach).
  static const double leadVisualFollowMistake = 0.62;
  /// Extra smoothing on thief screen Y (kills leftover hops).
  static const double thiefYSmooth = 4.2;
  static const double thiefScaleSmooth = 5.0;

  static const double overtakeDuration = 1.75;
  /// Thief takes the lead after a blunder — longer glide, less snap.
  static const double overtakeSprintDuration = 2.45;
  /// Show faint chase arrow once the thief is this far behind.
  static const double chaseArrowLeadMin = 2.2;
  static const int comboThreshold = 8;

  // ── Thief momentum bursts — softer / rarer, less "rocket" ─────────────────
  static const double thiefBurstDuration = 1.85;
  static const double thiefBurstMetersMin = 110;
  static const double thiefBurstMetersMax = 155;
  /// Extra closing speed while bursting (on top of debt drain).
  static const double thiefBurstClosePerSec = 4.8;
  /// Debt drain multiplier during a burst.
  static const double thiefBurstDebtMult = 1.10;
  /// Mistake streak that can trigger an early burst (1 miss = no sprint).
  static const int thiefBurstFromMistakes = 3;
  static const double thiefBurstCooldown = 20;
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

  /// Legacy finale knobs — unused in endless (kept for spawn refs).
  static const double finaleMeters = 0;
  static const double finaleSpawnGapMult = 0.72;
  static const double finalePlayRate = 1.0;

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
  /// One size for every bomb (square crop → square draw, no squash).
  static const double bombDisplaySize = 48;
  /// Unused — pace no longer scales bombs.
  static const double bombSpeedScaleMax = 1.0;
  /// Dynamite minecart — larger readable hazard, same explosive rules as bomb.
  static const double dynamiteCartDisplaySize = 64;
  /// Single-lane bomb slot → slow minecart (readable, not every gate).
  static const double dynamiteCartChance = 0.14;
  /// Cart drifts slower than normal fall so it reads as “rolling in”.
  static const double dynamiteCartSpeedMult = 0.72;
  /// Slightly harsher chase hit than a plain bomb.
  static const double leadLossOnDynamiteCart = 10.0;

  static const double magnetRadius = 16;
  static const double magnetPullSpeed = 45;
  /// Gold snap — short “sucks into basket” assist (~80–120 ms feel).
  static const double goldSnapRadius = 38;
  static const double goldSnapPullSpeed = 460;

  // ── Subway-style magnet power-up ─────────────────────────────────────────
  static const double magnetDisplaySize = 50;
  static const double magnetPowerDuration = 15;
  /// Wide vacuum while the power-up is active (skips bomb/web).
  static const double powerMagnetRadius = 210;
  static const double powerMagnetPullSpeed = 560;
  /// Chance a pattern slot becomes a magnet pickup (still gated by cooldown).
  static const double magnetSpawnChance = 0.04;
  static const double magnetRespawnMin = 22;
  static const double magnetRespawnMax = 38;

  // ── Hearts (stack to 3 — shield vs pit / spikes; also absorbs bomb) ─────
  static const double heartDisplaySize = 46;
  static const int maxHearts = 3;
  /// Can drop more than once per run until stack is full (pickup soft-caps).
  static const double heartSpawnChance = 0.12;
  static const double heartRespawnMin = 18;
  static const double heartRespawnMax = 28;
  static const double heartIFrameSec = 0.45;

  // ── Potion boost (1 per run — answer thief lead) ─────────────────────────
  static const double potionDisplaySize = 46;
  static const double potionSpawnChance = 0.05;
  static const double potionRespawnMin = 48;
  static const double potionBoostDuration = 2.5;
  static const double potionLeadGain = 2.6;
  /// Usable when thief leads, or while breathing (gap ≤ this).
  static const double potionUseLeadMax = 1.5;
  static const double catchRadius = 26;
  /// Bombs: circular center-to-center touch only — near misses never explode.
  static const double bombCatchRadius = 15;
  /// Body brush for loot only (coins) — a bit forgiving.
  static const double bodyCatchLootHalfW = 26;
  static const double bodyCatchLootHalfH = 32;
  /// Hazards: must nearly overlap the sprite — no “near miss” side hits.
  static const double bodyCatchHazardHalfW = 15;
  static const double bodyCatchHazardHalfH = 16;

  // ── Web (spider net) hazard ──────────────────────────────────────────────
  static const double webDisplaySize = 42;
  /// Strict touch like bombs — glancing pass doesn't snare.
  static const double webCatchRadius = 13;
  /// Web appears from this 1-based shaft onward (1 = from the start).
  static const int webFromCorridor = 1;
  /// Chance a normal spawn beat becomes a web (once eligible).
  static const double webSpawnChance = 0.105;
  /// Shared spacing so web + spikes don't stack in the same window.
  static const double laneTrapSpacingSec = 2.6;
  /// Combo difficulty steps every N meters (with run tempo).
  static const double trapComboTierMeters = 200;
  /// Soft start: lethal set-piece combos (tier 2+) unlock after this.
  static const double lethalComboUnlockMeters = 380;
  /// Bomb→spikes teaching combo unlock (after opening).
  static const double teachComboUnlockMeters = 200;
  /// Claim victory with Финиш when leading crystals past this distance.
  static const double finishMinMeters = 150;
  /// Rare combo: web → pit (legacy; prefer [webPitComboChanceAt]).
  static const double webPitComboChance = 0.045;
  static const double webPitComboCooldownMin = 18;
  static const double webPitComboCooldownMax = 30;
  /// Bomb dodge → spikes ~5 m later (same / escape lane).
  static const double bombSpikesComboChance = 0.055;
  static const double bombSpikesComboCooldownMin = 16;
  static const double bombSpikesComboCooldownMax = 28;
  static const double bombSpikesGapMeters = 5.0;
  static const double webSpikesComboChance = 0.05;
  static const double spikesPitComboChance = 0.045;
  static const double zigzagBombChance = 0.06;
  /// Dual gate → web on free lane → pit (squeeze the escape).
  static const double gateWebPitChance = 0.05;
  /// Bomb → web on dodge → spikes (sticky punish).
  static const double bombWebSpikesChance = 0.048;
  /// Spikes + pit on two lanes nearly together (split choice).
  static const double splitFloorChance = 0.042;
  /// L/R bomb weave → pit in the middle (classic runner sandwich).
  static const double bombSandwichPitChance = 0.045;
  /// Web → short zigzag bombs while sticky.
  static const double stickyZigzagChance = 0.04;
  /// Dual free lane → pit on free → spikes on bait (double fake-safe).
  static const double fakeSafeDoubleChance = 0.038;
  /// How long the player stays sticky/slow after touching a web.
  static const double webSnareDuration = 3.0;
  /// Player control sluggishness while snared (1 = normal, lower = slower).
  static const double webSnareMoveFactor = 0.32;
  /// World + stride slow while snared (bomb-like hitch, a bit softer).
  static const double webSnarePlayRate = 0.55;
  /// Chase pressure — close to a bomb, but no crystal loss.
  static const double leadLossOnWeb = 6.5;

  /// Three dodge lanes — always at least one clear row to slip through.
  static const int bombLaneCount = 3;
  /// Chance a bomb beat is a 2-lane gate (one free lane) instead of a single.
  static const double bombDualChance = 0.48;
  /// Min/max pause before the next bomb pattern — denser timing traps.
  static const double bombCooldownMin = 0.95;
  static const double bombCooldownMax = 1.85;

  // ── Pit (black hole) — instant fail ──────────────────────────────────────
  static const double pitDisplaySize = 52;
  /// Touch radius vs player feet / basket — forgiving edge, lethal center.
  static const double pitCatchRadius = 22;
  /// Legacy base — prefer [pitSpawnChanceAt].
  static const double pitSpawnChance = 0.10;
  /// No pits until ~250 m (teach jewels / bombs / spikes / heart first).
  static const double pitUnlockProgress = 0.22;
  static const double pitRespawnMin = 12.0;
  static const double pitRespawnMax = 20.0;
  /// Suck-into-pit cinematic length (seconds).
  static const double pitSuckDuration = 0.78;

  /// Direct pit roll scales with progress (0 early → ~0.09 late).
  static double pitSpawnChanceAt(double progress) {
    final t = progress.clamp(0.0, 1.0);
    if (t < pitUnlockProgress) return 0;
    final u = ((t - pitUnlockProgress) / (1.0 - pitUnlockProgress)).clamp(0.0, 1.0);
    return 0.044 + u * 0.044;
  }

  /// Web→pit combo only after the player has learned the chase.
  static double webPitComboChanceAt(double progress) {
    final t = progress.clamp(0.0, 1.0);
    if (t < 0.18) return 0;
    return 0.038 + (t - 0.18) / 0.82 * 0.028;
  }

  /// Bomb→spikes chance — unlock gated by meters tier in SpawnDirector.
  static double bombSpikesComboChanceAt(double progress) {
    final t = progress.clamp(0.0, 1.0);
    return bombSpikesComboChance + t * 0.02;
  }

  // ── Spikes — separate lethal floor (not pits) ─────────────────────────────
  /// Width of spikes sprite on the path.
  static const double spikesDisplaySize = 88;
  /// Height / width for current hazards/spikes.png (1536×1024).
  static const double spikesAspect = 1024 / 1536;
  static const double spikesCatchRadius = 26;
  /// Interrupt chance on a loot beat (own path — not tied to pits).
  static const double spikesSpawnChance = 0.16;
  /// Designed spikes pattern from director (from run start).
  static const double spikesDirectorChance = 0.09;
  static const double spikesRespawnMin = 9.0;
  static const double spikesRespawnMax = 16.0;
  /// Spikes from run start (same as webs) — not gated behind pit unlock.
  static const int spikesFromCorridor = 1;
  /// Legacy — unused (pit beats stay pits).
  static const double spikesChance = 0.32;

  static double spikesChanceAt(double progress) {
    final t = progress.clamp(0.0, 1.0);
    return 0.55 + t * 0.2;
  }

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
  /// @Deprecated — blue thief is mode-based (Long = 2 thieves from start).
  static const int blueThiefFromCorridor = 999;
  static const double thiefLaneOffsetX = 44;
  static const double thiefPassExtraX = 58;
  static const double thiefMinClearanceX = 56;

  static const int runFps = 9;
  /// Slightly snappier stride so airborne feet don't hang a beat.
  static const int minerRunFps = 9;
  static const int runFrames = 18;
}
