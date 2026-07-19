import 'dart:collection';
import 'dart:math';

import '../game/game_config.dart';
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
  /// Absolute pause override (seconds), used for silence / tight columns.
  final double? fixedGap;
  /// Multiplier on the normal spawn interval.
  final double gapMult;

  /// Trick: force a single bomb onto this lane.
  final int? bombLane;
  /// Trick: dual gate with this escape lane.
  final int? bombFreeLane;
  /// null = roll [GameConfig.bombDualChance]; true/false overrides.
  final bool? forceDual;
  /// Second bomb a beat later (dodge-punish) — other lane.
  final int? staggerBombLane;
}

/// Cycles readable Subway-style patterns: columns, arcs, gates, rare magnet.
class SpawnDirector {
  final Random _rng = Random();
  final Queue<SpawnBeat> _queue = Queue<SpawnBeat>();
  int _patternCooldown = 0;
  double _magnetCooldown = 18;
  double _pitCooldown = 8;
  double _webPitCooldown = 16;
  double _heartCooldown = 20;
  double _potionCooldown = 28;
  bool _heartSpawned = false;
  bool _potionSpawned = false;
  /// Lane the last coin trail trained the player into (for bait bombs).
  int _lastBaitLane = 1;

  void reset() {
    _queue.clear();
    _patternCooldown = 0;
    _magnetCooldown = 14 + _rng.nextDouble() * 10;
    _pitCooldown = 6 + _rng.nextDouble() * 6;
    _webPitCooldown = 12 + _rng.nextDouble() * 10;
    _heartCooldown = 18 + _rng.nextDouble() * 10;
    _potionCooldown = 26 + _rng.nextDouble() * 12;
    _heartSpawned = false;
    _potionSpawned = false;
    _lastBaitLane = 1;
    _enqueueBreathing();
  }

  void update(double dt, {double progress = 0}) {
    _magnetCooldown = max(0, _magnetCooldown - dt);
    _pitCooldown = max(0, _pitCooldown - dt);
    _webPitCooldown = max(0, _webPitCooldown - dt);
    _heartCooldown = max(0, _heartCooldown - dt);
    _potionCooldown = max(0, _potionCooldown - dt);
  }

  SpawnBeat nextBeat({required double progress}) {
    if (_queue.isEmpty) {
      _enqueuePattern(progress);
    }
    return _queue.removeFirst();
  }

  double gapFor(SpawnBeat beat, {required double progress}) {
    if (beat.fixedGap != null) return beat.fixedGap!;
    final base = (GameConfig.spawnIntervalStart -
            progress *
                (GameConfig.spawnIntervalStart - GameConfig.spawnIntervalMin))
        .clamp(GameConfig.spawnIntervalMin, GameConfig.spawnIntervalStart);
    final tempo = GameConfig.spawnTempoAt(progress);
    final trail = _queue.isNotEmpty;
    final mult = beat.gapMult * (trail ? 0.72 : 1.05);
    return (base * mult * (0.9 + _rng.nextDouble() * 0.18)) / tempo;
  }

  double rollFallSpeed({required double progress}) {
    final min = GameConfig.itemFallSpeedMin + progress * 40;
    final max = GameConfig.itemFallSpeedMax + progress * 70;
    return min + _rng.nextDouble() * (max - min);
  }

  void _enqueuePattern(double progress) {
    if (_patternCooldown > 0) {
      _patternCooldown--;
      _enqueueBreathing();
      return;
    }

    if (_magnetCooldown <= 0 &&
        _rng.nextDouble() < GameConfig.magnetSpawnChance) {
      _enqueueMagnet();
      return;
    }

    // One heart / potion per run — rare Subway-style pickups.
    if (!_heartSpawned &&
        _heartCooldown <= 0 &&
        _rng.nextDouble() < GameConfig.heartSpawnChance) {
      _enqueueHeart();
      return;
    }
    if (!_potionSpawned &&
        _potionCooldown <= 0 &&
        progress > 0.18 &&
        _rng.nextDouble() < GameConfig.potionSpawnChance) {
      _enqueuePotion();
      return;
    }

    // Rare: two webs to snare, then a pit while sticky (~2–3 m later).
    if (_webPitCooldown <= 0 &&
        _pitCooldown <= 0 &&
        _rng.nextDouble() < GameConfig.webPitComboChanceAt(progress)) {
      _enqueueWebPitCombo(progress);
      return;
    }

    // Black pits — unlock mid-run, rarer than before.
    if (_pitCooldown <= 0 &&
        _rng.nextDouble() < GameConfig.pitSpawnChanceAt(progress)) {
      _enqueuePitTrap();
      return;
    }

    final roll = _rng.nextDouble();
    final p = progress.clamp(0.0, 1.0);

    // Early: more loot air. Late: bombs stay sharp, lethal floors gated.
    if (roll < 0.14 + p * 0.02) {
      _coinColumn();
    } else if (roll < 0.23 + p * 0.02) {
      _coinArc();
    } else if (roll < 0.31) {
      _coinZigzag();
    } else if (roll < 0.36) {
      _coinRow();
    } else if (roll < 0.48 + p * 0.02) {
      _jewelPocket();
    } else if (roll < 0.55 + p * 0.025) {
      _laneBaitBomb(); // coins → bomb same lane (tight)
    } else if (roll < 0.62 + p * 0.025) {
      _switchGateBomb();
    } else if (roll < 0.68 + p * 0.02) {
      _dodgePunishStagger();
    } else if (roll < 0.75 + p * 0.015) {
      _jewelTrapBomb();
    } else if (roll < 0.80 + p * 0.015) {
      _timingSnapBomb(); // almost no telegraph — pure timing
    } else if (roll < 0.85 + p * 0.015) {
      _fakeSafeThenBomb(); // long hush, then snap bomb
    } else if (roll < 0.91) {
      _bombGateWithSilence();
    } else if (p >= GameConfig.pitUnlockProgress && roll < 0.95) {
      _enqueuePitTrap();
    } else {
      _mixedSweep();
    }
  }

  void _enqueueBreathing() {
    final lane = _rng.nextDouble() < 0.5 ? 1 : _rng.nextInt(3);
    final type = _rng.nextDouble() < 0.62 ? ItemType.gold : ItemType.coal;
    _queue.add(SpawnBeat(type: type, lane: lane, gapMult: 1.15));
  }

  void _coinColumn() {
    final lane = _rng.nextInt(3);
    _lastBaitLane = lane;
    final n = 6 + _rng.nextInt(3);
    for (var i = 0; i < n; i++) {
      _queue.add(
        SpawnBeat(
          type: ItemType.gold,
          lane: lane,
          fixedGap: 0.16 + _rng.nextDouble() * 0.04,
        ),
      );
    }
  }

  void _coinArc() {
    final lanes = _rng.nextBool()
        ? const [0, 1, 2, 1, 0]
        : const [2, 1, 0, 1, 2];
    _lastBaitLane = lanes[lanes.length ~/ 2];
    for (final lane in lanes) {
      _queue.add(
        SpawnBeat(
          type: ItemType.gold,
          lane: lane,
          fixedGap: 0.20 + _rng.nextDouble() * 0.05,
        ),
      );
    }
  }

  void _coinZigzag() {
    final n = 5 + _rng.nextInt(2);
    var lane = _rng.nextInt(3);
    var step = _rng.nextBool() ? 1 : -1;
    for (var i = 0; i < n; i++) {
      _queue.add(
        SpawnBeat(
          type: ItemType.gold,
          lane: lane,
          fixedGap: 0.22,
        ),
      );
      _lastBaitLane = lane;
      final next = lane + step;
      if (next < 0 || next > 2) {
        step = -step;
        lane = (lane + step).clamp(0, 2);
      } else {
        lane = next;
      }
    }
  }

  void _coinRow() {
    _queue.add(
      const SpawnBeat(
        type: ItemType.gold,
        row: true,
        gapMult: 0.85,
      ),
    );
    _queue.add(
      SpawnBeat(type: ItemType.gold, lane: _rng.nextInt(3), gapMult: 0.9),
    );
  }

  void _jewelPocket() {
    final lane = _rng.nextInt(3);
    _lastBaitLane = lane;
    _queue.add(SpawnBeat(type: ItemType.gold, lane: lane, gapMult: 0.7));
    _queue.add(SpawnBeat(type: ItemType.gold, lane: lane, gapMult: 0.65));
    _queue.add(SpawnBeat(type: _rollRare(), lane: lane, gapMult: 0.7));
    // ~+20% denser pockets — side crystal more often, sometimes a third.
    if (_rng.nextDouble() < 0.72) {
      final side = (lane + (_rng.nextBool() ? 1 : 2)) % 3;
      _queue.add(SpawnBeat(type: _rollRare(), lane: side, gapMult: 0.75));
    }
    if (_rng.nextDouble() < 0.28) {
      _queue.add(SpawnBeat(type: _rollRare(), lane: lane, gapMult: 0.7));
    }
    _queue.add(SpawnBeat(type: ItemType.gold, lane: lane, gapMult: 0.85));
  }

  /// Survive bomb/pit → crystal reward in a clear lane (not every time).
  void _maybeJewelAfterHazard({
    required int lane,
    double chance = 0.42,
  }) {
    if (_rng.nextDouble() >= chance) return;
    final safe = lane.clamp(0, 2);
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: 0.16 + _rng.nextDouble() * 0.1,
      ),
    );
    _queue.add(
      SpawnBeat(
        type: _rollRare(),
        lane: safe,
        fixedGap: 0.2 + _rng.nextDouble() * 0.06,
      ),
    );
    if (_rng.nextDouble() < 0.3) {
      final side = (safe + 1 + _rng.nextInt(2)) % 3;
      _queue.add(
        SpawnBeat(type: _rollRare(), lane: side, gapMult: 0.72),
      );
    }
    _lastBaitLane = safe;
  }

  /// Classic trap: train the lane with coins, then bomb THAT lane (tight timing).
  void _laneBaitBomb() {
    final lane = _rng.nextInt(3);
    _lastBaitLane = lane;
    final n = 3 + _rng.nextInt(3); // 3–5
    for (var i = 0; i < n; i++) {
      _queue.add(
        SpawnBeat(
          type: ItemType.gold,
          lane: lane,
          fixedGap: 0.15 + _rng.nextDouble() * 0.03,
        ),
      );
    }
    // Very short hush — dodge window is tiny.
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: 0.12 + _rng.nextDouble() * 0.08,
      ),
    );
    _queue.add(
      SpawnBeat(
        type: ItemType.bomb,
        bombPattern: true,
        forceDual: false,
        bombLane: lane,
      ),
    );
    // Reward dodge — crystal in a clear lane.
    final reward = (lane + 1 + _rng.nextInt(2)) % 3;
    _maybeJewelAfterHazard(lane: reward);
    _patternCooldown = 1;
  }

  /// Coin in a lane → bomb almost immediately (reaction / timing check).
  void _timingSnapBomb() {
    final lane = _rng.nextInt(3);
    _lastBaitLane = lane;
    _queue.add(
      SpawnBeat(type: ItemType.gold, lane: lane, fixedGap: 0.16),
    );
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: 0.08 + _rng.nextDouble() * 0.06,
      ),
    );
    final free = (lane + 1 + _rng.nextInt(2)) % 3;
    _queue.add(
      SpawnBeat(
        type: ItemType.bomb,
        bombPattern: true,
        forceDual: _rng.nextDouble() < 0.4,
        bombLane: lane,
        bombFreeLane: free,
      ),
    );
    _maybeJewelAfterHazard(lane: free);
    _patternCooldown = 0;
  }

  /// Long empty beat so the player relaxes — then a sudden bomb/gate.
  void _fakeSafeThenBomb() {
    final lane = _lastBaitLane.clamp(0, 2);
    final free = (lane + 1) % 3;
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: 0.55 + _rng.nextDouble() * 0.25,
      ),
    );
    _queue.add(
      SpawnBeat(
        type: ItemType.bomb,
        bombPattern: true,
        forceDual: _rng.nextBool(),
        bombLane: lane,
        bombFreeLane: free,
      ),
    );
    _maybeJewelAfterHazard(lane: free);
    _patternCooldown = 1;
  }

  /// Coins pull you into a lane; dual gate leaves a DIFFERENT lane free.
  void _switchGateBomb() {
    final bait = _rng.nextInt(3);
    _lastBaitLane = bait;
    final n = 3 + _rng.nextInt(2);
    for (var i = 0; i < n; i++) {
      _queue.add(
        SpawnBeat(
          type: ItemType.gold,
          lane: bait,
          fixedGap: 0.18,
        ),
      );
    }
    var free = (bait + 1 + _rng.nextInt(2)) % 3;
    if (free == bait) free = (bait + 1) % 3;
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: 0.28 + _rng.nextDouble() * 0.12,
      ),
    );
    _queue.add(
      SpawnBeat(
        type: ItemType.bomb,
        bombPattern: true,
        forceDual: true,
        bombFreeLane: free,
      ),
    );
    _maybeJewelAfterHazard(lane: free);
    _patternCooldown = 1;
  }

  /// Bomb in bait lane, then a delayed bomb in a side lane (punish the dodge).
  void _dodgePunishStagger() {
    final first = _lastBaitLane.clamp(0, 2);
    final sides = <int>[0, 1, 2]..remove(first);
    final second = sides[_rng.nextInt(sides.length)];
    // Tiny coin teaser so it doesn't feel random spam.
    _queue.add(
      SpawnBeat(type: ItemType.gold, lane: first, fixedGap: 0.2),
    );
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: 0.2 + _rng.nextDouble() * 0.1,
      ),
    );
    _queue.add(
      SpawnBeat(
        type: ItemType.bomb,
        bombPattern: true,
        forceDual: false,
        bombLane: first,
        staggerBombLane: second,
      ),
    );
    final clear = <int>[0, 1, 2]
      ..remove(first)
      ..remove(second);
    _maybeJewelAfterHazard(
      lane: clear.isNotEmpty ? clear.first : (first + 1) % 3,
      chance: 0.36,
    );
    _patternCooldown = 1;
  }

  /// Crystal in a lane → bomb on the greedy grab.
  void _jewelTrapBomb() {
    final lane = _rng.nextInt(3);
    _lastBaitLane = lane;
    _queue.add(SpawnBeat(type: ItemType.gold, lane: lane, fixedGap: 0.2));
    _queue.add(SpawnBeat(type: _rollRare(), lane: lane, fixedGap: 0.22));
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: 0.18 + _rng.nextDouble() * 0.1,
      ),
    );
    _queue.add(
      SpawnBeat(
        type: ItemType.bomb,
        bombPattern: true,
        forceDual: false,
        bombLane: lane,
      ),
    );
    _maybeJewelAfterHazard(lane: (lane + 1 + _rng.nextInt(2)) % 3);
    _patternCooldown = 1;
  }

  void _bombGateWithSilence() {
    final pause = 0.36 + _rng.nextDouble() * 0.16;
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: pause,
      ),
    );
    // Often block the lane the player was just farming.
    final punish = _rng.nextDouble() < 0.55;
    final free = (_lastBaitLane + 1 + _rng.nextInt(2)) % 3;
    _queue.add(
      SpawnBeat(
        type: ItemType.bomb,
        bombPattern: true,
        forceDual: _rng.nextDouble() < 0.55 ? true : null,
        bombLane: punish && _rng.nextBool() ? _lastBaitLane : null,
        bombFreeLane: punish && _rng.nextBool() ? free : null,
      ),
    );
    _maybeJewelAfterHazard(lane: free);
    _patternCooldown = 1;
  }

  void _enqueueMagnet() {
    final lane = _rng.nextInt(3);
    _queue.add(SpawnBeat(type: ItemType.gold, lane: lane, gapMult: 0.8));
    _queue.add(
      SpawnBeat(
        type: ItemType.magnet,
        lane: lane,
        gapMult: 1.1,
      ),
    );
    _magnetCooldown = GameConfig.magnetRespawnMin +
        _rng.nextDouble() *
            (GameConfig.magnetRespawnMax - GameConfig.magnetRespawnMin);
    _patternCooldown = 1;
  }

  void _enqueueHeart() {
    final lane = _rng.nextInt(3);
    _lastBaitLane = lane;
    _queue.add(SpawnBeat(type: ItemType.gold, lane: lane, fixedGap: 0.18));
    _queue.add(
      SpawnBeat(type: ItemType.heart, lane: lane, gapMult: 1.05),
    );
    _heartSpawned = true;
    _heartCooldown = GameConfig.heartRespawnMin;
    _patternCooldown = 1;
  }

  void _enqueuePotion() {
    final lane = _rng.nextInt(3);
    _lastBaitLane = lane;
    _queue.add(SpawnBeat(type: ItemType.gold, lane: lane, fixedGap: 0.18));
    _queue.add(
      SpawnBeat(type: ItemType.potion, lane: lane, gapMult: 1.05),
    );
    _potionSpawned = true;
    _potionCooldown = GameConfig.potionRespawnMin;
    _patternCooldown = 1;
  }

  /// Double web snare → black pit ~2–3 m later while the miner is sticky.
  void _enqueueWebPitCombo(double progress) {
    final lane = _rng.nextBool() ? _lastBaitLane.clamp(0, 2) : _rng.nextInt(3);
    _lastBaitLane = lane;

    // Light coin bait into the trap lane.
    if (_rng.nextDouble() < 0.6) {
      final n = 2 + _rng.nextInt(2);
      for (var i = 0; i < n; i++) {
        _queue.add(
          SpawnBeat(
            type: ItemType.gold,
            lane: lane,
            fixedGap: 0.15,
          ),
        );
      }
    }

    // Web #1, then a tight follow-up web (same lane, or neighbor to cover dodge).
    _queue.add(
      SpawnBeat(
        type: ItemType.web,
        lane: lane,
        fixedGap: 0.24,
      ),
    );
    final side = _rng.nextBool() ? 1 : -1;
    final lane2 = _rng.nextDouble() < 0.7
        ? lane
        : (lane + side).clamp(0, 2);
    _queue.add(
      SpawnBeat(
        type: ItemType.web,
        lane: lane2,
        fixedGap: 0.26 + _rng.nextDouble() * 0.06,
      ),
    );

    // ~2–3 run meters of empty shaft, then pit on the snare lane.
    final meters = 2.0 + _rng.nextDouble();
    final pace = GameConfig.runSpeedAt(progress.clamp(0.0, 1.0));
    final gapSec = (meters / (pace * GameConfig.distanceMeterRate))
        .clamp(0.28, 0.62);
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: gapSec,
      ),
    );
    _queue.add(SpawnBeat(type: ItemType.pit, lane: lane, gapMult: 1.0));
    // Crystal just past the pit lane — reward for not falling in.
    _maybeJewelAfterHazard(
      lane: (lane + 1 + _rng.nextInt(2)) % 3,
      chance: 0.48,
    );

    _webPitCooldown = GameConfig.webPitComboCooldownMin +
        _rng.nextDouble() *
            (GameConfig.webPitComboCooldownMax -
                GameConfig.webPitComboCooldownMin);
    _pitCooldown = GameConfig.pitRespawnMin +
        _rng.nextDouble() *
            (GameConfig.pitRespawnMax - GameConfig.pitRespawnMin);
    _patternCooldown = 2;
  }

  /// Coins bait into a lane, then a black pit (sometimes after a bomb dodge).
  void _enqueuePitTrap() {
    final lane = _rng.nextBool() ? _lastBaitLane.clamp(0, 2) : _rng.nextInt(3);
    _lastBaitLane = lane;
    final n = 2 + _rng.nextInt(3);
    for (var i = 0; i < n; i++) {
      _queue.add(
        SpawnBeat(
          type: ItemType.gold,
          lane: lane,
          fixedGap: 0.16,
        ),
      );
    }
    // Often: bomb first, then pit in the “safe” escape lane.
    late final int pitLane;
    if (_rng.nextDouble() < 0.55) {
      final free = (lane + 1 + _rng.nextInt(2)) % 3;
      pitLane = free;
      _queue.add(
        SpawnBeat(
          type: ItemType.gold,
          silence: true,
          fixedGap: 0.14 + _rng.nextDouble() * 0.08,
        ),
      );
      _queue.add(
        SpawnBeat(
          type: ItemType.bomb,
          bombPattern: true,
          forceDual: true,
          bombFreeLane: free,
        ),
      );
      _queue.add(
        SpawnBeat(
          type: ItemType.gold,
          silence: true,
          fixedGap: 0.28 + _rng.nextDouble() * 0.12,
        ),
      );
      _queue.add(SpawnBeat(type: ItemType.pit, lane: free, gapMult: 1.0));
    } else {
      pitLane = lane;
      _queue.add(
        SpawnBeat(
          type: ItemType.gold,
          silence: true,
          fixedGap: 0.14 + _rng.nextDouble() * 0.1,
        ),
      );
      _queue.add(SpawnBeat(type: ItemType.pit, lane: lane, gapMult: 1.0));
    }
    _maybeJewelAfterHazard(
      lane: (pitLane + 1 + _rng.nextInt(2)) % 3,
      chance: 0.5,
    );
    _pitCooldown = GameConfig.pitRespawnMin +
        _rng.nextDouble() *
            (GameConfig.pitRespawnMax - GameConfig.pitRespawnMin);
    _patternCooldown = 1;
  }

  void _mixedSweep() {
    var lane = _rng.nextInt(3);
    final types = <ItemType>[
      ItemType.gold,
      ItemType.coal,
      _rollRare(),
      ItemType.gold,
    ];
    // Slightly richer sweep — second crystal sometimes (+20% feel).
    if (_rng.nextDouble() < 0.35) {
      types.insert(2, _rollRare());
    }
    for (final t in types) {
      _queue.add(SpawnBeat(type: t, lane: lane, gapMult: 0.8));
      _lastBaitLane = lane;
      lane = (lane + 1) % 3;
    }
  }

  ItemType _rollRare() {
    final rares = [
      ItemType.diamond,
      ItemType.ruby,
      ItemType.emerald,
      ItemType.amethyst,
      ItemType.legendary,
    ];
    if (_rng.nextDouble() > 0.92) return ItemType.legendary;
    return rares[_rng.nextInt(rares.length - 1)];
  }
}
