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
  /// Lane the last coin trail trained the player into (for bait bombs).
  int _lastBaitLane = 1;

  void reset() {
    _queue.clear();
    _patternCooldown = 0;
    _magnetCooldown = 14 + _rng.nextDouble() * 10;
    _pitCooldown = 6 + _rng.nextDouble() * 6;
    _lastBaitLane = 1;
    _enqueueBreathing();
  }

  void update(double dt, {double progress = 0}) {
    _magnetCooldown = max(0, _magnetCooldown - dt);
    _pitCooldown = max(0, _pitCooldown - dt);
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

    // Black pits — rare but lethal.
    if (_pitCooldown <= 0 && _rng.nextDouble() < GameConfig.pitSpawnChance) {
      _enqueuePitTrap();
      return;
    }

    final roll = _rng.nextDouble();
    final p = progress.clamp(0.0, 1.0);

    // Trap bands ~+10% denser (bombs + pits eat more of the roll).
    if (roll < 0.16 + p * 0.03) {
      _coinColumn();
    } else if (roll < 0.27 + p * 0.03) {
      _coinArc();
    } else if (roll < 0.36) {
      _coinZigzag();
    } else if (roll < 0.42) {
      _coinRow();
    } else if (roll < 0.52 + p * 0.03) {
      _jewelPocket();
    } else if (roll < 0.63 + p * 0.04) {
      _laneBaitBomb();
    } else if (roll < 0.72 + p * 0.04) {
      _switchGateBomb();
    } else if (roll < 0.80 + p * 0.03) {
      _dodgePunishStagger();
    } else if (roll < 0.87 + p * 0.03) {
      _jewelTrapBomb();
    } else if (roll < 0.93) {
      _bombGateWithSilence();
    } else if (roll < 0.97) {
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
    if (_rng.nextBool()) {
      final side = (lane + (_rng.nextBool() ? 1 : 2)) % 3;
      _queue.add(SpawnBeat(type: _rollRare(), lane: side, gapMult: 0.75));
    }
    _queue.add(SpawnBeat(type: ItemType.gold, lane: lane, gapMult: 0.85));
  }

  /// Classic trap: train the lane with coins, then bomb THAT lane (short warn).
  void _laneBaitBomb() {
    final lane = _rng.nextInt(3);
    _lastBaitLane = lane;
    final n = 3 + _rng.nextInt(3); // 3–5
    for (var i = 0; i < n; i++) {
      _queue.add(
        SpawnBeat(
          type: ItemType.gold,
          lane: lane,
          fixedGap: 0.17 + _rng.nextDouble() * 0.04,
        ),
      );
    }
    // Short hush — not a long telegraph.
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: 0.22 + _rng.nextDouble() * 0.12,
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
    _queue.add(
      SpawnBeat(
        type: ItemType.bomb,
        bombPattern: true,
        forceDual: _rng.nextDouble() < 0.55 ? true : null,
        bombLane: punish && _rng.nextBool() ? _lastBaitLane : null,
        bombFreeLane: punish && _rng.nextBool()
            ? (_lastBaitLane + 1 + _rng.nextInt(2)) % 3
            : null,
      ),
    );
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

  /// Coins bait into a lane, then a black pit on that lane (instant fail).
  void _enqueuePitTrap() {
    final lane = _rng.nextBool() ? _lastBaitLane.clamp(0, 2) : _rng.nextInt(3);
    _lastBaitLane = lane;
    final n = 2 + _rng.nextInt(2);
    for (var i = 0; i < n; i++) {
      _queue.add(
        SpawnBeat(
          type: ItemType.gold,
          lane: lane,
          fixedGap: 0.18,
        ),
      );
    }
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: 0.2 + _rng.nextDouble() * 0.12,
      ),
    );
    _queue.add(SpawnBeat(type: ItemType.pit, lane: lane, gapMult: 1.0));
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
