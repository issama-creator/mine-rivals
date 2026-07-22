import 'spawn_beat.dart';
import 'item_type.dart';

enum PatternDifficulty { easy, medium, hard, extreme }

/// Handcrafted obstacle + crystal sequence (Subway / Temple Run style).
class SpawnPattern {
  const SpawnPattern({
    required this.id,
    required this.difficulty,
    required this.beats,
    this.breathBeats = 1,
  });

  final String id;
  final PatternDifficulty difficulty;
  final List<SpawnBeat> beats;

  /// Soft gold beats after this pattern (breathing room).
  final int breathBeats;
}

/// Compact beat builders — fixed gaps, never random crystal picks.
class _B {
  static SpawnBeat gold(int lane, [double gap = 0.2]) =>
      SpawnBeat(type: ItemType.gold, lane: lane, fixedGap: gap);

  static SpawnBeat silence([double gap = 0.5]) => SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: gap,
      );

  static SpawnBeat gem(
    int lane,
    ItemType type, [
    double gap = 0.28,
  ]) =>
      SpawnBeat(type: type, lane: lane, fixedGap: gap);

  static SpawnBeat spikes(int lane, [double gap = 0.42]) =>
      SpawnBeat(type: ItemType.spikes, lane: lane, fixedGap: gap);

  static SpawnBeat pit(int lane, [double gap = 0.45]) =>
      SpawnBeat(type: ItemType.pit, lane: lane, fixedGap: gap);

  static SpawnBeat web(int lane, [double gap = 0.4]) =>
      SpawnBeat(type: ItemType.web, lane: lane, fixedGap: gap);

  static SpawnBeat bombSingle(int lane, [double gap = 0.42]) => SpawnBeat(
        type: ItemType.bomb,
        bombPattern: true,
        forceDual: false,
        bombLane: lane,
        fixedGap: gap,
      );

  static int other(int lane, [int prefer = 1]) {
    if (prefer != lane) return prefer;
    return (lane + 1) % 3;
  }

  static int side(int lane) => lane == 0 ? 2 : (lane == 2 ? 0 : 0);
}

/// Catalog of handcrafted patterns (~80). Extend by appending to lists.
class PatternCatalog {
  PatternCatalog._();

  static final List<SpawnPattern> easy = _buildEasy();
  static final List<SpawnPattern> medium = _buildMedium();
  static final List<SpawnPattern> hard = _buildHard();
  static final List<SpawnPattern> extreme = _buildExtreme();

  static List<SpawnPattern> pool(PatternDifficulty d) {
    switch (d) {
      case PatternDifficulty.easy:
        return easy;
      case PatternDifficulty.medium:
        return medium;
      case PatternDifficulty.hard:
        return hard;
      case PatternDifficulty.extreme:
        return extreme;
    }
  }

  /// Round-based pacing (Standard & Hardcore share the same curve).
  /// R1–R2: packed doubles — exciting, finger-fast decisions.
  /// R3: ~10% easier breather.
  /// R4+: gradual climb — denser, still readable (no unfair walls).
  static Map<PatternDifficulty, double> weightsAtRound(int seriesRound) {
    final r = seriesRound < 1 ? 1 : seriesRound;
    if (r <= 2) {
      return const {
        PatternDifficulty.easy: 0.08,
        PatternDifficulty.medium: 0.70,
        PatternDifficulty.hard: 0.22,
        PatternDifficulty.extreme: 0.0,
      };
    }
    if (r == 3) {
      // ~10% easier than the packed opener.
      return const {
        PatternDifficulty.easy: 0.22,
        PatternDifficulty.medium: 0.68,
        PatternDifficulty.hard: 0.10,
        PatternDifficulty.extreme: 0.0,
      };
    }
    // Gradual after the breather (t → 1 over ~12 more rounds).
    final t = ((r - 3) / 12.0).clamp(0.0, 1.0);
    final easy = 0.10 * (1.0 - t);
    final medium = 0.58 - t * 0.36;
    final hard = 0.27 + t * 0.20;
    final extreme = 0.05 + t * 0.26;
    final sum = easy + medium + hard + extreme;
    return {
      PatternDifficulty.easy: easy / sum,
      PatternDifficulty.medium: medium / sum,
      PatternDifficulty.hard: hard / sum,
      PatternDifficulty.extreme: extreme / sum,
    };
  }

  /// How hard gaps squeeze (0 = loose, 1 = snappy). Cap keeps it fair.
  static double pressureAtRound(int seriesRound) {
    final r = seriesRound < 1 ? 1 : seriesRound;
    if (r <= 2) return 0.48; // packed & fun
    if (r == 3) return 0.28; // breather
    return (0.34 + (r - 3) * 0.04).clamp(0.34, 0.70);
  }

  /// Chance to stack a second 2-trap combo (Temple Run chain).
  static double chainChanceAtRound(int seriesRound) {
    final r = seriesRound < 1 ? 1 : seriesRound;
    if (r <= 2) return 0.68;
    if (r == 3) return 0.30;
    return (0.38 + (r - 3) * 0.028).clamp(0.38, 0.62);
  }

  /// Multiplier on pattern fixedGaps (<1 = less reaction time).
  static double gapScaleAtRound(int seriesRound) {
    final r = seriesRound < 1 ? 1 : seriesRound;
    if (r <= 2) return 0.80;
    if (r == 3) return 0.92; // ~15% more air vs R1–2
    return (0.86 - (r - 3) * 0.018).clamp(0.68, 0.86);
  }

  // ── Easy: one obstacle, crystals guide / reward ──────────────────────────

  static List<SpawnPattern> _buildEasy() {
    final out = <SpawnPattern>[];

    // Spikes × 3 lanes — guide on safe mid, hazard on side/mid.
    for (final lane in [0, 1, 2]) {
      final safe = _B.other(lane);
      out.add(
        SpawnPattern(
          id: 'easy_spikes_$lane',
          difficulty: PatternDifficulty.easy,
          breathBeats: 1,
          beats: [
            _B.gold(safe, 0.2),
            _B.gold(safe, 0.18),
            _B.gem(safe, ItemType.diamond, 0.3),
            _B.silence(0.5),
            _B.spikes(lane),
            _B.silence(0.28),
            _B.gem(safe, ItemType.emerald, 0.32),
          ],
        ),
      );
    }

    // Pit × 3 — bait then clear reward.
    for (final lane in [0, 1, 2]) {
      final safe = _B.other(lane);
      out.add(
        SpawnPattern(
          id: 'easy_pit_$lane',
          difficulty: PatternDifficulty.easy,
          breathBeats: 1,
          beats: [
            _B.gold(lane, 0.18),
            _B.gold(lane, 0.18),
            _B.silence(0.52),
            _B.pit(lane),
            _B.silence(0.3),
            _B.gem(safe, ItemType.ruby, 0.3),
          ],
        ),
      );
    }

    // Bomb × 3 — telegraph + safe crystal arc.
    for (final lane in [0, 1, 2]) {
      final safe = _B.other(lane);
      out.add(
        SpawnPattern(
          id: 'easy_bomb_$lane',
          difficulty: PatternDifficulty.easy,
          breathBeats: 1,
          beats: [
            _B.gold(safe, 0.2),
            _B.gem(safe, ItemType.diamond, 0.28),
            _B.silence(0.48),
            _B.bombSingle(lane),
            _B.silence(0.28),
            _B.gem(safe, ItemType.amethyst, 0.3),
          ],
        ),
      );
    }

    // Web × 3 — sticky warning, crystal shows exit.
    for (final lane in [0, 1, 2]) {
      final safe = _B.other(lane);
      out.add(
        SpawnPattern(
          id: 'easy_web_$lane',
          difficulty: PatternDifficulty.easy,
          breathBeats: 1,
          beats: [
            _B.gold(safe, 0.2),
            _B.gold(safe, 0.18),
            _B.silence(0.45),
            _B.web(lane),
            _B.silence(0.32),
            _B.gem(safe, ItemType.emerald, 0.3),
          ],
        ),
      );
    }

    // Pure reward / guide patterns (still “easy pool” pacing).
    out.add(
      const SpawnPattern(
        id: 'easy_mid_column',
        difficulty: PatternDifficulty.easy,
        breathBeats: 0,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.32),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.22),
        ],
      ),
    );
    out.add(
      const SpawnPattern(
        id: 'easy_arc_gem',
        difficulty: PatternDifficulty.easy,
        breathBeats: 0,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.28),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.22),
        ],
      ),
    );
    out.add(
      const SpawnPattern(
        id: 'easy_zig_gem',
        difficulty: PatternDifficulty.easy,
        breathBeats: 0,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.ruby, lane: 2, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.amethyst, lane: 0, fixedGap: 0.28),
        ],
      ),
    );
    out.add(
      const SpawnPattern(
        id: 'easy_row_diamond',
        difficulty: PatternDifficulty.easy,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, row: true, fixedGap: 0.32),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.34),
        ],
      ),
    );
    out.add(
      const SpawnPattern(
        id: 'easy_pocket',
        difficulty: PatternDifficulty.easy,
        breathBeats: 0,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.26),
          SpawnBeat(type: ItemType.emerald, lane: 0, fixedGap: 0.28),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.22),
        ],
      ),
    );
    out.add(
      const SpawnPattern(
        id: 'easy_jump_timing',
        difficulty: PatternDifficulty.easy,
        breathBeats: 1,
        beats: [
          // Crystals mark “stay mid”, then spikes on a side — jump timing feel.
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.4),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.3),
        ],
      ),
    );
    out.add(
      const SpawnPattern(
        id: 'easy_side_reward',
        difficulty: PatternDifficulty.easy,
        breathBeats: 0,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.35),
          SpawnBeat(type: ItemType.ruby, lane: 2, fixedGap: 0.3),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.22),
        ],
      ),
    );
    out.add(
      const SpawnPattern(
        id: 'easy_dual_safe_bomb',
        difficulty: PatternDifficulty.easy,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.28),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 1,
            fixedGap: 0.42,
          ),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.32),
        ],
      ),
    );

    assert(out.length >= 20, 'need ≥20 easy patterns, got ${out.length}');
    return out;
  }

  // ── Medium: two-obstacle combos, crystals mark safest path ───────────────

  static List<SpawnPattern> _buildMedium() {
    final out = <SpawnPattern>[];

    // Spikes → Pit (classic)
    for (final a in [0, 1, 2]) {
      final b = _B.other(a, a == 1 ? 0 : 1);
      final safe = 3 - a - b;
      out.add(
        SpawnPattern(
          id: 'med_spikes_pit_${a}_$b',
          difficulty: PatternDifficulty.medium,
          breathBeats: 1,
          beats: [
            _B.gold(safe, 0.18),
            _B.gem(safe, ItemType.diamond, 0.26),
            _B.silence(0.48),
            _B.spikes(a, 0.4),
            _B.silence(0.55),
            _B.pit(b, 0.42),
            _B.silence(0.28),
            _B.gem(safe, ItemType.emerald, 0.3),
          ],
        ),
      );
    }

    // Pit → Bomb
    for (final pitLane in [0, 2]) {
      final bombLane = 1;
      final safe = pitLane == 0 ? 2 : 0;
      out.add(
        SpawnPattern(
          id: 'med_pit_bomb_$pitLane',
          difficulty: PatternDifficulty.medium,
          breathBeats: 1,
          beats: [
            _B.gold(pitLane, 0.18),
            _B.gold(pitLane, 0.16),
            _B.silence(0.5),
            _B.pit(pitLane),
            _B.silence(0.55),
            _B.bombSingle(bombLane),
            _B.silence(0.28),
            _B.gem(safe, ItemType.ruby, 0.3),
          ],
        ),
      );
    }
    out.add(
      const SpawnPattern(
        id: 'med_pit_bomb_mid',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.16),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.45),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            fixedGap: 0.42,
          ),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.3),
        ],
      ),
    );

    // Web → Spikes
    for (final lane in [0, 1, 2]) {
      final spikesLane = _B.other(lane);
      final reward = spikesLane == 1 ? 0 : 1;
      out.add(
        SpawnPattern(
          id: 'med_web_spikes_$lane',
          difficulty: PatternDifficulty.medium,
          breathBeats: 1,
          beats: [
            _B.gold(lane, 0.18),
            _B.silence(0.45),
            _B.web(lane, 0.38),
            _B.silence(0.52),
            _B.spikes(spikesLane, 0.4),
            _B.silence(0.28),
            _B.gem(reward, ItemType.amethyst, 0.3),
          ],
        ),
      );
    }

    // Bomb → Pit
    for (final bombLane in [0, 1, 2]) {
      final pitLane = _B.other(bombLane);
      final safe = 3 - bombLane - pitLane;
      out.add(
        SpawnPattern(
          id: 'med_bomb_pit_$bombLane',
          difficulty: PatternDifficulty.medium,
          breathBeats: 1,
          beats: [
            _B.gem(_B.other(bombLane), ItemType.diamond, 0.28),
            _B.silence(0.48),
            _B.bombSingle(bombLane),
            _B.silence(0.58),
            _B.pit(pitLane),
            _B.silence(0.28),
            _B.gem(safe < 0 ? 1 : safe, ItemType.emerald, 0.3),
          ],
        ),
      );
    }

    // Web → Pit
    for (final lane in [0, 2]) {
      out.add(
        SpawnPattern(
          id: 'med_web_pit_$lane',
          difficulty: PatternDifficulty.medium,
          breathBeats: 1,
          beats: [
            _B.gold(lane, 0.18),
            _B.gold(lane, 0.16),
            _B.silence(0.45),
            _B.web(lane),
            _B.silence(0.55),
            _B.pit(lane),
            _B.silence(0.28),
            _B.gem(1, ItemType.ruby, 0.3),
          ],
        ),
      );
    }

    // Spikes → Bomb
    for (final spikesLane in [0, 2]) {
      out.add(
        SpawnPattern(
          id: 'med_spikes_bomb_$spikesLane',
          difficulty: PatternDifficulty.medium,
          breathBeats: 1,
          beats: [
            _B.gold(1, 0.2),
            _B.gem(1, ItemType.diamond, 0.26),
            _B.silence(0.48),
            _B.spikes(spikesLane),
            _B.silence(0.55),
            _B.bombSingle(1),
            _B.silence(0.28),
            _B.gem(_B.side(spikesLane), ItemType.emerald, 0.3),
          ],
        ),
      );
    }

    // Dual bomb → spikes on free (bait escape)
    out.add(
      const SpawnPattern(
        id: 'med_gate_spikes',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 1,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.58),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.42),
          SpawnBeat(type: ItemType.emerald, lane: 0, fixedGap: 0.3),
        ],
      ),
    );

    // Bomb bait same lane → crystal on dodge
    out.add(
      const SpawnPattern(
        id: 'med_bait_bomb',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.16),
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.16),
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.16),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.ruby, lane: 1, fixedGap: 0.3),
        ],
      ),
    );

    // Switch gate: bait mid, free side
    out.add(
      const SpawnPattern(
        id: 'med_switch_gate',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 2,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.diamond, lane: 2, fixedGap: 0.3),
        ],
      ),
    );

    // Spikes mid → web side
    out.add(
      const SpawnPattern(
        id: 'med_spikes_web',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.2),
          SpawnBeat(type: ItemType.diamond, lane: 0, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.52),
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.38),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.3),
        ],
      ),
    );

    // Pit side → web mid
    out.add(
      const SpawnPattern(
        id: 'med_pit_web',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 2, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.45),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.web, lane: 1, fixedGap: 0.4),
          SpawnBeat(type: ItemType.amethyst, lane: 0, fixedGap: 0.3),
        ],
      ),
    );

    // Crystal trail through dual free lane
    out.add(
      const SpawnPattern(
        id: 'med_crystal_gate',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 2, fixedGap: 0.18),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 2,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.ruby, lane: 2, fixedGap: 0.28),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.4),
        ],
      ),
    );

    // Risk crystal beside spikes then pit other side
    out.add(
      const SpawnPattern(
        id: 'med_risk_gem_spikes_pit',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.38),
          // Risky ruby next to spikes lane path
          SpawnBeat(type: ItemType.ruby, lane: 0, fixedGap: 0.22),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.42),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.3),
        ],
      ),
    );

    // Bomb → Web
    out.add(
      const SpawnPattern(
        id: 'med_bomb_web',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.web, lane: 1, fixedGap: 0.38),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.3),
        ],
      ),
    );

    // Spikes → Web (mid→side)
    out.add(
      const SpawnPattern(
        id: 'med_spikes_web_b',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.diamond, lane: 2, fixedGap: 0.28),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.52),
          SpawnBeat(type: ItemType.web, lane: 2, fixedGap: 0.38),
          SpawnBeat(type: ItemType.ruby, lane: 1, fixedGap: 0.3),
        ],
      ),
    );

    // Pit → Spikes
    out.add(
      const SpawnPattern(
        id: 'med_pit_spikes',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.pit, lane: 0, fixedGap: 0.45),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.4),
          SpawnBeat(type: ItemType.amethyst, lane: 1, fixedGap: 0.3),
        ],
      ),
    );

    // Dual free side → pit mid
    out.add(
      const SpawnPattern(
        id: 'med_gate_pit',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 2, fixedGap: 0.18),
          SpawnBeat(type: ItemType.diamond, lane: 2, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 2,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.42),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.3),
        ],
      ),
    );

    // Web → Bomb
    out.add(
      const SpawnPattern(
        id: 'med_web_bomb',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.52),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 2,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.ruby, lane: 1, fixedGap: 0.3),
        ],
      ),
    );

    // Crystal guides left around spikes then bomb
    out.add(
      const SpawnPattern(
        id: 'med_guide_left',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.18),
          SpawnBeat(type: ItemType.diamond, lane: 0, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.4),
          SpawnBeat(type: ItemType.emerald, lane: 0, fixedGap: 0.24),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.52),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 2,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.amethyst, lane: 0, fixedGap: 0.3),
        ],
      ),
    );

    // Timing snap: short hush → bomb → pit
    out.add(
      const SpawnPattern(
        id: 'med_timing_snap',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.16),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.38),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 1,
            fixedGap: 0.38,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.pit, lane: 0, fixedGap: 0.42),
          SpawnBeat(type: ItemType.diamond, lane: 2, fixedGap: 0.3),
        ],
      ),
    );

    // ── One free lane (Temple / Subway gates) ─────────────────────────────
    // Spikes L + pit R → only mid is safe.
    out.add(
      const SpawnPattern(
        id: 'med_one_lane_mid',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.12),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.38),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.3),
        ],
      ),
    );
    // Dual bomb free mid, then spikes on a side — still one clean path if you stay.
    out.add(
      const SpawnPattern(
        id: 'med_gate_one_lane',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.4),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 1,
            fixedGap: 0.36,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.12),
          SpawnBeat(type: ItemType.web, lane: 2, fixedGap: 0.36),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.28),
        ],
      ),
    );
    // Only left free: spikes mid + pit right.
    out.add(
      const SpawnPattern(
        id: 'med_one_lane_left',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.12),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.36),
          SpawnBeat(type: ItemType.diamond, lane: 0, fixedGap: 0.28),
        ],
      ),
    );
    // Only right free.
    out.add(
      const SpawnPattern(
        id: 'med_one_lane_right',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 2, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.12),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.36),
          SpawnBeat(type: ItemType.amethyst, lane: 2, fixedGap: 0.28),
        ],
      ),
    );

    // ── Risk diamonds (grab = commit into danger) ─────────────────────────
    // Diamond on trap lane, then spikes same lane — dodge after grab.
    out.add(
      const SpawnPattern(
        id: 'med_risk_grab_dodge',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.16),
          SpawnBeat(type: ItemType.diamond, lane: 0, fixedGap: 0.22),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.28),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.38),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.28),
        ],
      ),
    );
    // Safe mid gold; risky side diamond then pit on that side.
    out.add(
      const SpawnPattern(
        id: 'med_risk_side_gem',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.16),
          SpawnBeat(type: ItemType.diamond, lane: 2, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.32),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.4),
          SpawnBeat(type: ItemType.ruby, lane: 1, fixedGap: 0.28),
        ],
      ),
    );
    // Risk gem between dual free lane then punish that free lane.
    out.add(
      const SpawnPattern(
        id: 'med_risk_free_lane_gem',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.36),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 2,
            fixedGap: 0.34,
          ),
          SpawnBeat(type: ItemType.diamond, lane: 2, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.4),
          SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.38),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.28),
        ],
      ),
    );
    // Web snare lane with diamond bait — sticky then spikes.
    out.add(
      const SpawnPattern(
        id: 'med_risk_web_gem',
        difficulty: PatternDifficulty.medium,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.22),
          SpawnBeat(type: ItemType.web, lane: 1, fixedGap: 0.28),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.38),
          SpawnBeat(type: ItemType.amethyst, lane: 0, fixedGap: 0.28),
        ],
      ),
    );

    assert(out.length >= 30, 'need ≥30 medium patterns, got ${out.length}');
    return out;
  }

  // ── Hard: three+ linked hazards ──────────────────────────────────────────

  static List<SpawnPattern> _buildHard() {
    final out = <SpawnPattern>[];

    // Spikes → Bomb → Pit
    out.add(
      const SpawnPattern(
        id: 'hard_spikes_bomb_pit',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 2,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.58),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.45),
          SpawnBeat(type: ItemType.emerald, lane: 0, fixedGap: 0.3),
        ],
      ),
    );
    out.add(
      const SpawnPattern(
        id: 'hard_spikes_bomb_pit_b',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.58),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.45),
          SpawnBeat(type: ItemType.ruby, lane: 2, fixedGap: 0.3),
        ],
      ),
    );

    // Web → Spikes → Bomb
    out.add(
      const SpawnPattern(
        id: 'hard_web_spikes_bomb',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.52),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 2,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.amethyst, lane: 0, fixedGap: 0.3),
        ],
      ),
    );
    out.add(
      const SpawnPattern(
        id: 'hard_web_spikes_bomb_b',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 2, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.web, lane: 2, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.52),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.diamond, lane: 2, fixedGap: 0.3),
        ],
      ),
    );

    // Bomb → Web → Pit (squeeze escape)
    out.add(
      const SpawnPattern(
        id: 'hard_bomb_web_pit',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 1,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.web, lane: 1, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.45),
          SpawnBeat(type: ItemType.emerald, lane: 0, fixedGap: 0.28),
          SpawnBeat(type: ItemType.ruby, lane: 2, fixedGap: 0.28),
        ],
      ),
    );

    // Bomb → Web → Spikes
    out.add(
      const SpawnPattern(
        id: 'hard_bomb_web_spikes',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.16),
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.16),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.web, lane: 1, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.52),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.4),
          SpawnBeat(type: ItemType.amethyst, lane: 2, fixedGap: 0.3),
        ],
      ),
    );

    // Web → Pit → Spikes
    out.add(
      const SpawnPattern(
        id: 'hard_web_pit_spikes',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.52),
          SpawnBeat(type: ItemType.pit, lane: 0, fixedGap: 0.45),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.4),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.3),
        ],
      ),
    );

    // Sandwich: bomb L → bomb R → pit mid
    out.add(
      const SpawnPattern(
        id: 'hard_sandwich_pit',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.4),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            fixedGap: 0.4,
          ),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 2,
            fixedGap: 0.42,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.45),
          SpawnBeat(type: ItemType.emerald, lane: 0, fixedGap: 0.3),
        ],
      ),
    );

    // Split floor: spikes + pit, safe lane crystal
    out.add(
      const SpawnPattern(
        id: 'hard_split_floor',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.28),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.28),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.35),
          SpawnBeat(type: ItemType.ruby, lane: 1, fixedGap: 0.3),
        ],
      ),
    );

    // Zigzag bombs (3)
    out.add(
      const SpawnPattern(
        id: 'hard_zigzag_bombs',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.4),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            fixedGap: 0.42,
          ),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 1,
            fixedGap: 0.42,
          ),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 2,
            fixedGap: 0.42,
          ),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.32),
        ],
      ),
    );

    // Fake-safe gate → pit → spikes
    out.add(
      const SpawnPattern(
        id: 'hard_fake_safe',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.16),
          SpawnBeat(type: ItemType.gold, lane: 0, fixedGap: 0.16),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 2,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.42),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.4),
          SpawnBeat(type: ItemType.amethyst, lane: 1, fixedGap: 0.3),
        ],
      ),
    );

    // Sticky zigzag: web then 3 bombs
    out.add(
      const SpawnPattern(
        id: 'hard_sticky_zigzag',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.web, lane: 1, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            fixedGap: 0.4,
          ),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 2,
            fixedGap: 0.4,
          ),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 1,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.diamond, lane: 0, fixedGap: 0.28),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.28),
        ],
      ),
    );

    // Spikes → Pit → Bomb
    out.add(
      const SpawnPattern(
        id: 'hard_spikes_pit_bomb',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.42),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 1,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.ruby, lane: 0, fixedGap: 0.3),
        ],
      ),
    );

    // Pit → Spikes → Web
    out.add(
      const SpawnPattern(
        id: 'hard_pit_spikes_web',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.pit, lane: 0, fixedGap: 0.45),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.52),
          SpawnBeat(type: ItemType.web, lane: 1, fixedGap: 0.38),
          SpawnBeat(type: ItemType.emerald, lane: 0, fixedGap: 0.3),
        ],
      ),
    );

    // Dual gate → spikes → pit other
    out.add(
      const SpawnPattern(
        id: 'hard_gate_spikes_pit',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.28),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 1,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.pit, lane: 0, fixedGap: 0.42),
          SpawnBeat(type: ItemType.ruby, lane: 2, fixedGap: 0.3),
        ],
      ),
    );

    // Risk arc through hazards
    out.add(
      const SpawnPattern(
        id: 'hard_risk_arc',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.4),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.38),
          SpawnBeat(type: ItemType.ruby, lane: 0, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.web, lane: 2, fixedGap: 0.38),
          SpawnBeat(type: ItemType.amethyst, lane: 2, fixedGap: 0.22),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.52),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.42),
          SpawnBeat(type: ItemType.diamond, lane: 0, fixedGap: 0.28),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.28),
        ],
      ),
    );

    // Stagger bomb punish
    out.add(
      const SpawnPattern(
        id: 'hard_stagger_bomb',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 1,
            staggerBombLane: 0,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.4),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.3),
        ],
      ),
    );

    // Web → Spikes → Pit
    out.add(
      const SpawnPattern(
        id: 'hard_web_spikes_pit',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.web, lane: 1, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.42),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.3),
        ],
      ),
    );

    // Bomb → Pit → Spikes
    out.add(
      const SpawnPattern(
        id: 'hard_bomb_pit_spikes',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 2, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.45),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.4),
          SpawnBeat(type: ItemType.ruby, lane: 0, fixedGap: 0.3),
        ],
      ),
    );

    // Four-beat weave
    out.add(
      const SpawnPattern(
        id: 'hard_four_weave',
        difficulty: PatternDifficulty.hard,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.web, lane: 2, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 1,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.55),
          SpawnBeat(type: ItemType.pit, lane: 0, fixedGap: 0.42),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.3),
        ],
      ),
    );

    // One free lane + risk gem on the only safe path then punish it.
    out.add(
      const SpawnPattern(
        id: 'hard_one_lane_risk',
        difficulty: PatternDifficulty.hard,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.36),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.1),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.32),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.4),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 1,
            fixedGap: 0.36,
          ),
          SpawnBeat(type: ItemType.ruby, lane: 0, fixedGap: 0.26),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.26),
        ],
      ),
    );
    // Dual free left → risk diamond left → web+spikes squeeze.
    out.add(
      const SpawnPattern(
        id: 'hard_risk_squeeze',
        difficulty: PatternDifficulty.hard,
        breathBeats: 1,
        beats: [
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 0,
            fixedGap: 0.34,
          ),
          SpawnBeat(type: ItemType.diamond, lane: 0, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.38),
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.28),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.12),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.34),
          SpawnBeat(type: ItemType.amethyst, lane: 0, fixedGap: 0.28),
        ],
      ),
    );
    // Needle lane: only mid open, risk gems on both walls.
    out.add(
      const SpawnPattern(
        id: 'hard_needle_risk_walls',
        difficulty: PatternDifficulty.hard,
        breathBeats: 1,
        beats: [
          SpawnBeat(type: ItemType.diamond, lane: 0, fixedGap: 0.2),
          SpawnBeat(type: ItemType.diamond, lane: 2, fixedGap: 0.18),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.32),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.1),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.32),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.4),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 1,
            fixedGap: 0.36,
          ),
          SpawnBeat(type: ItemType.legendary, lane: 1, fixedGap: 0.3),
        ],
      ),
    );

    assert(out.length >= 20, 'need ≥20 hard patterns, got ${out.length}');
    return out;
  }

  // ── Extreme: dense combos + crystal reward arcs ──────────────────────────

  static List<SpawnPattern> _buildExtreme() {
    final out = <SpawnPattern>[
      const SpawnPattern(
        id: 'ext_gauntlet',
        difficulty: PatternDifficulty.extreme,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.26),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.36),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 2,
            fixedGap: 0.38,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.52),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.42),
          SpawnBeat(type: ItemType.ruby, lane: 0, fixedGap: 0.24),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.24),
          SpawnBeat(type: ItemType.amethyst, lane: 1, fixedGap: 0.28),
        ],
      ),
      const SpawnPattern(
        id: 'ext_crystal_snake',
        difficulty: PatternDifficulty.extreme,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.diamond, lane: 0, fixedGap: 0.22),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.22),
          SpawnBeat(type: ItemType.ruby, lane: 2, fixedGap: 0.22),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.36),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 2,
            fixedGap: 0.38,
          ),
          SpawnBeat(type: ItemType.amethyst, lane: 2, fixedGap: 0.24),
          SpawnBeat(type: ItemType.legendary, lane: 2, fixedGap: 0.3),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.pit, lane: 0, fixedGap: 0.42),
        ],
      ),
      const SpawnPattern(
        id: 'ext_double_squeeze',
        difficulty: PatternDifficulty.extreme,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.16),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.24),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 1,
            fixedGap: 0.38,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.web, lane: 1, fixedGap: 0.36),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.pit, lane: 0, fixedGap: 0.28),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.35),
          SpawnBeat(type: ItemType.ruby, lane: 1, fixedGap: 0.26),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.26),
        ],
      ),
      const SpawnPattern(
        id: 'ext_mirror_hell',
        difficulty: PatternDifficulty.extreme,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.4),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.36),
          SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.36),
          SpawnBeat(type: ItemType.ruby, lane: 1, fixedGap: 0.24),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 1,
            fixedGap: 0.38,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.36),
          SpawnBeat(type: ItemType.web, lane: 2, fixedGap: 0.36),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.24),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.42),
          SpawnBeat(type: ItemType.amethyst, lane: 0, fixedGap: 0.24),
          SpawnBeat(type: ItemType.diamond, lane: 2, fixedGap: 0.24),
        ],
      ),
      const SpawnPattern(
        id: 'ext_legendary_run',
        difficulty: PatternDifficulty.extreme,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.legendary, lane: 1, fixedGap: 0.28),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.4),
          SpawnBeat(type: ItemType.web, lane: 1, fixedGap: 0.36),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            staggerBombLane: 2,
            fixedGap: 0.38,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.38),
          SpawnBeat(type: ItemType.ruby, lane: 0, fixedGap: 0.22),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.22),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.5),
          SpawnBeat(type: ItemType.pit, lane: 0, fixedGap: 0.4),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.24),
          SpawnBeat(type: ItemType.amethyst, lane: 1, fixedGap: 0.24),
          SpawnBeat(type: ItemType.legendary, lane: 1, fixedGap: 0.3),
        ],
      ),
      const SpawnPattern(
        id: 'ext_weave_four',
        difficulty: PatternDifficulty.extreme,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.38),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 0,
            fixedGap: 0.38,
          ),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.2),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 2,
            fixedGap: 0.38,
          ),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.spikes, lane: 1, fixedGap: 0.38),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.36),
          SpawnBeat(type: ItemType.ruby, lane: 2, fixedGap: 0.22),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.4),
          SpawnBeat(type: ItemType.amethyst, lane: 0, fixedGap: 0.24),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.24),
        ],
      ),
      const SpawnPattern(
        id: 'ext_pit_tunnel',
        difficulty: PatternDifficulty.extreme,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.16),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.24),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(type: ItemType.pit, lane: 0, fixedGap: 0.4),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.22),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.4),
          SpawnBeat(type: ItemType.ruby, lane: 1, fixedGap: 0.22),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.36),
          SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.36),
          SpawnBeat(type: ItemType.amethyst, lane: 1, fixedGap: 0.24),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 1,
            fixedGap: 0.4,
          ),
          SpawnBeat(type: ItemType.legendary, lane: 0, fixedGap: 0.26),
          SpawnBeat(type: ItemType.legendary, lane: 2, fixedGap: 0.26),
        ],
      ),
      const SpawnPattern(
        id: 'ext_sticky_gauntlet',
        difficulty: PatternDifficulty.extreme,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.36),
          SpawnBeat(type: ItemType.web, lane: 2, fixedGap: 0.36),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.22),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 1,
            fixedGap: 0.38,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.36),
          SpawnBeat(type: ItemType.ruby, lane: 2, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.4),
          SpawnBeat(type: ItemType.emerald, lane: 0, fixedGap: 0.22),
          SpawnBeat(type: ItemType.amethyst, lane: 1, fixedGap: 0.24),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.24),
        ],
      ),
      const SpawnPattern(
        id: 'ext_false_hope',
        difficulty: PatternDifficulty.extreme,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.16),
          SpawnBeat(type: ItemType.gold, lane: 1, fixedGap: 0.16),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.24),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: true,
            bombFreeLane: 1,
            fixedGap: 0.38,
          ),
          SpawnBeat(type: ItemType.emerald, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.pit, lane: 1, fixedGap: 0.4),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.36),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.45),
          SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.38),
          SpawnBeat(type: ItemType.ruby, lane: 0, fixedGap: 0.22),
          SpawnBeat(type: ItemType.amethyst, lane: 1, fixedGap: 0.22),
          SpawnBeat(type: ItemType.legendary, lane: 1, fixedGap: 0.28),
        ],
      ),
      const SpawnPattern(
        id: 'ext_all_hazards',
        difficulty: PatternDifficulty.extreme,
        breathBeats: 2,
        beats: [
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.24),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.42),
          SpawnBeat(type: ItemType.spikes, lane: 0, fixedGap: 0.36),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.pit, lane: 2, fixedGap: 0.4),
          SpawnBeat(type: ItemType.ruby, lane: 1, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(
            type: ItemType.bomb,
            bombPattern: true,
            forceDual: false,
            bombLane: 1,
            fixedGap: 0.38,
          ),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.web, lane: 0, fixedGap: 0.36),
          SpawnBeat(type: ItemType.emerald, lane: 2, fixedGap: 0.2),
          SpawnBeat(type: ItemType.gold, silence: true, fixedGap: 0.48),
          SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.36),
          SpawnBeat(type: ItemType.amethyst, lane: 0, fixedGap: 0.22),
          SpawnBeat(type: ItemType.diamond, lane: 1, fixedGap: 0.22),
          SpawnBeat(type: ItemType.legendary, lane: 1, fixedGap: 0.28),
        ],
      ),
    ];

    assert(out.length >= 10, 'need ≥10 extreme patterns, got ${out.length}');
    return out;
  }
}
