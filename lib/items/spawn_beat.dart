import 'item_type.dart';

/// One beat of loot / hazard placement (lane-locked like top runners).
class SpawnBeat {
  const SpawnBeat({
    required this.type,
    this.lane,
    this.bombPattern = false,
    this.row = false,
    this.silence = false,
    this.fixedGap,
    this.gapMult = 1,
    this.bombLane,
    this.bombFreeLane,
    this.forceDual,
    this.staggerBombLane,
  });

  final ItemType type;

  /// 0..2 lane; null = soft random (bush-biased loot pick).
  final int? lane;

  /// Dual/single bomb gate handled by the game.
  final bool bombPattern;

  /// Spawn the same type across all three lanes on one beat.
  final bool row;

  /// Wait only — no item (empty beat before a gate).
  final bool silence;

  /// Absolute pause override (seconds).
  final double? fixedGap;

  /// Multiplier on the normal spawn interval.
  final double gapMult;

  /// Force a single bomb onto this lane.
  final int? bombLane;

  /// Dual gate with this escape lane.
  final int? bombFreeLane;

  /// null = roll dual chance; true/false overrides.
  final bool? forceDual;

  /// Second bomb a beat later (dodge-punish).
  final int? staggerBombLane;

  /// Mirror left/right lanes (0 ↔ 2). Mid stays mid.
  SpawnBeat mirrored() {
    int? flip(int? l) {
      if (l == null) return null;
      if (l == 1) return 1;
      return 2 - l;
    }

    return SpawnBeat(
      type: type,
      lane: flip(lane),
      bombPattern: bombPattern,
      row: row,
      silence: silence,
      fixedGap: fixedGap,
      gapMult: gapMult,
      bombLane: flip(bombLane),
      bombFreeLane: flip(bombFreeLane),
      forceDual: forceDual,
      staggerBombLane: flip(staggerBombLane),
    );
  }

  /// Tighten / loosen timing (distance pressure). Keeps a readable floor.
  SpawnBeat withScaledGap(double mult) {
    if (fixedGap == null) {
      return SpawnBeat(
        type: type,
        lane: lane,
        bombPattern: bombPattern,
        row: row,
        silence: silence,
        gapMult: gapMult * mult,
        bombLane: bombLane,
        bombFreeLane: bombFreeLane,
        forceDual: forceDual,
        staggerBombLane: staggerBombLane,
      );
    }
    return SpawnBeat(
      type: type,
      lane: lane,
      bombPattern: bombPattern,
      row: row,
      silence: silence,
      fixedGap: (fixedGap! * mult).clamp(0.12, 2.2),
      gapMult: gapMult,
      bombLane: bombLane,
      bombFreeLane: bombFreeLane,
      forceDual: forceDual,
      staggerBombLane: staggerBombLane,
    );
  }
}
