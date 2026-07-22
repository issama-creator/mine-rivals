import 'dart:collection';
import 'dart:math';

import '../game/game_config.dart';
import 'item_type.dart';
import 'spawn_beat.dart';
import 'spawn_pattern.dart';

export 'spawn_beat.dart';
export 'spawn_pattern.dart';

/// Plays handcrafted [SpawnPattern]s from distance-weighted difficulty pools.
class SpawnDirector {
  final Random _rng = Random();
  final Queue<SpawnBeat> _queue = Queue<SpawnBeat>();

  int _seriesRound = 1;
  double _magnetCooldown = 18;
  double _heartCooldown = 20;
  double _potionCooldown = 28;
  bool _potionSpawned = false;
  String? _lastPatternId;
  int _breathLeft = 0;

  void reset() {
    _queue.clear();
    _seriesRound = 1;
    _magnetCooldown = 14 + _rng.nextDouble() * 10;
    _heartCooldown = 14 + _rng.nextDouble() * 8;
    _potionCooldown = 26 + _rng.nextDouble() * 12;
    _potionSpawned = false;
    _lastPatternId = null;
    _breathLeft = 0;
    _enqueueOpeningHook();
  }

  /// Scripted first beats — teach steer → crystal → dodge → reward.
  void _enqueueOpeningHook() {
    const lane = 1;
    for (var i = 0; i < 5; i++) {
      _queue.add(
        const SpawnBeat(type: ItemType.gold, lane: lane, fixedGap: 0.22),
      );
    }
    _queue.add(
      const SpawnBeat(type: ItemType.diamond, lane: lane, fixedGap: 0.38),
    );
    _queue.add(
      const SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: 0.55,
      ),
    );
    _queue.add(
      const SpawnBeat(
        type: ItemType.bomb,
        bombPattern: true,
        bombLane: 0,
        forceDual: false,
        fixedGap: 0.28,
      ),
    );
    _queue.add(
      const SpawnBeat(type: ItemType.emerald, lane: lane, fixedGap: 0.42),
    );
    _queue.add(
      const SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: 0.55,
      ),
    );
    _queue.add(
      const SpawnBeat(type: ItemType.spikes, lane: 2, fixedGap: 0.4),
    );
    _queue.add(
      const SpawnBeat(type: ItemType.gold, lane: lane, fixedGap: 0.35),
    );
    _breathLeft = 1;
  }

  void update(
    double dt, {
    double progress = 0,
    double distance = 0,
    int seriesRound = 1,
  }) {
    _seriesRound = seriesRound < 1 ? 1 : seriesRound;
    _magnetCooldown = max(0, _magnetCooldown - dt);
    _heartCooldown = max(0, _heartCooldown - dt);
    _potionCooldown = max(0, _potionCooldown - dt);
  }

  SpawnBeat nextBeat({required double progress}) {
    if (_queue.isEmpty) {
      _enqueueNext(progress);
    }
    return _queue.removeFirst();
  }

  double gapFor(SpawnBeat beat, {required double progress}) {
    final pressure = PatternCatalog.pressureAtRound(_seriesRound);
    // fixedGap already pressure-scaled when the pattern was enqueued.
    if (beat.fixedGap != null) return beat.fixedGap!;
    final base = (GameConfig.spawnIntervalStart -
            progress *
                (GameConfig.spawnIntervalStart - GameConfig.spawnIntervalMin))
        .clamp(GameConfig.spawnIntervalMin, GameConfig.spawnIntervalStart);
    final tempo = GameConfig.spawnTempoAt(progress) * (1.0 + 0.22 * pressure);
    final trail = _queue.isNotEmpty;
    final mult = beat.gapMult * (trail ? 0.72 : 1.0);
    return (base * mult * (0.94 + _rng.nextDouble() * 0.06)) / tempo;
  }

  double rollFallSpeed({required double progress}) {
    final min = GameConfig.itemFallSpeedMin + progress * 40;
    final max = GameConfig.itemFallSpeedMax + progress * 70;
    return min + _rng.nextDouble() * (max - min);
  }

  void _enqueueNext(double progress) {
    if (_breathLeft > 0) {
      _breathLeft--;
      _enqueueBreathing();
      return;
    }

    if (_magnetCooldown <= 0 &&
        _rng.nextDouble() < GameConfig.magnetSpawnChance) {
      _enqueueMagnet();
      return;
    }
    if (_heartCooldown <= 0 &&
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

    _enqueuePattern();
  }

  void _enqueuePattern() {
    final round = _seriesRound;
    final pressure = PatternCatalog.pressureAtRound(round);
    final gapScale = PatternCatalog.gapScaleAtRound(round);
    final difficulty = _rollDifficulty();
    final pool = PatternCatalog.pool(difficulty);
    if (pool.isEmpty) {
      _enqueueBreathing();
      return;
    }

    var pattern = _pickPattern(pool);
    _lastPatternId = pattern.id;
    _pushPatternBeats(pattern, gapScale);

    // Pack R1–R2 with chained doubles; ease off on R3; climb again later.
    final chainChance = PatternCatalog.chainChanceAtRound(round);
    if (difficulty != PatternDifficulty.easy &&
        _rng.nextDouble() < chainChance) {
      // Prefer another medium (2-trap) for that Temple Run finger-dance.
      PatternDifficulty secondDiff = PatternDifficulty.medium;
      if (round >= 5 && _rng.nextDouble() < 0.35 + pressure * 0.25) {
        secondDiff = round >= 8 && _rng.nextDouble() < 0.4
            ? PatternDifficulty.extreme
            : PatternDifficulty.hard;
      } else if (round <= 2 && _rng.nextDouble() < 0.28) {
        secondDiff = PatternDifficulty.hard;
      }
      final pool2 = PatternCatalog.pool(secondDiff);
      if (pool2.isNotEmpty) {
        final linkGap = (0.36 * gapScale).clamp(0.16, 0.36);
        _queue.add(
          SpawnBeat(
            type: ItemType.gold,
            silence: true,
            fixedGap: linkGap,
          ),
        );
        final p2 = _pickPattern(pool2);
        _lastPatternId = p2.id;
        _pushPatternBeats(p2, gapScale);
      }
    }

    // Breathing: rare in R1–2, generous in R3, then slowly tighten.
    var breath = 0;
    if (round == 3) {
      breath = _rng.nextDouble() < 0.7 ? 1 : 0;
    } else if (round <= 2) {
      breath = _rng.nextDouble() < 0.22 ? 1 : 0;
    } else if (pressure < 0.45) {
      breath = _rng.nextDouble() < 0.4 ? 1 : 0;
    } else if (pressure < 0.6) {
      breath = _rng.nextDouble() < 0.22 ? 1 : 0;
    }
    _breathLeft = breath;

    final tailGap = (0.28 * gapScale).clamp(0.14, 0.28);
    _queue.add(
      SpawnBeat(
        type: ItemType.gold,
        silence: true,
        fixedGap: tailGap,
      ),
    );
  }

  SpawnPattern _pickPattern(List<SpawnPattern> pool) {
    var pattern = pool[_rng.nextInt(pool.length)];
    if (pool.length > 1 && pattern.id == _lastPatternId) {
      pattern = pool[_rng.nextInt(pool.length)];
    }
    return pattern;
  }

  void _pushPatternBeats(SpawnPattern pattern, double gapScale) {
    final mirror = _rng.nextBool();
    for (final beat in pattern.beats) {
      final base = mirror ? beat.mirrored() : beat;
      _queue.add(base.withScaledGap(gapScale));
    }
  }

  PatternDifficulty _rollDifficulty() {
    final weights = PatternCatalog.weightsAtRound(_seriesRound);
    var roll = _rng.nextDouble();
    var acc = 0.0;
    for (final entry in weights.entries) {
      acc += entry.value;
      if (roll <= acc) return entry.key;
    }
    return PatternDifficulty.medium;
  }

  void _enqueueBreathing() {
    final lane = _rng.nextDouble() < 0.55 ? 1 : _rng.nextInt(3);
    final type = _rng.nextDouble() < 0.65 ? ItemType.gold : ItemType.coal;
    _queue.add(SpawnBeat(type: type, lane: lane, fixedGap: 0.32));
  }

  void _enqueueMagnet() {
    const lane = 1;
    _queue.add(const SpawnBeat(type: ItemType.gold, lane: lane, fixedGap: 0.2));
    _queue.add(
      const SpawnBeat(type: ItemType.magnet, lane: lane, fixedGap: 0.4),
    );
    _magnetCooldown = GameConfig.magnetRespawnMin +
        _rng.nextDouble() *
            (GameConfig.magnetRespawnMax - GameConfig.magnetRespawnMin);
    _breathLeft = 1;
  }

  void _enqueueHeart() {
    const lane = 1;
    _queue.add(const SpawnBeat(type: ItemType.gold, lane: lane, fixedGap: 0.18));
    _queue.add(
      const SpawnBeat(type: ItemType.heart, lane: lane, fixedGap: 0.4),
    );
    _heartCooldown = GameConfig.heartRespawnMin +
        _rng.nextDouble() *
            (GameConfig.heartRespawnMax - GameConfig.heartRespawnMin);
    _breathLeft = 1;
  }

  void _enqueuePotion() {
    const lane = 1;
    _queue.add(const SpawnBeat(type: ItemType.gold, lane: lane, fixedGap: 0.18));
    _queue.add(
      const SpawnBeat(type: ItemType.potion, lane: lane, fixedGap: 0.4),
    );
    _potionSpawned = true;
    _potionCooldown = GameConfig.potionRespawnMin;
    _breathLeft = 1;
  }
}
