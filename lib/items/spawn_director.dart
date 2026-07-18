import 'dart:math';

import '../game/game_config.dart';
import 'item_type.dart';

enum SpawnWave { calm, rareRush, bombSpike }

/// Cycles calm → rare pack → light bomb warning so the lane isn't flat noise.
class SpawnDirector {
  SpawnWave wave = SpawnWave.calm;
  double waveLeft = 4.5;
  int _burstLeft = 0;
  final Random _rng = Random();

  void reset() {
    wave = SpawnWave.calm;
    waveLeft = 3.5 + _rng.nextDouble() * 2;
    _burstLeft = 0;
  }

  void update(double dt, {double progress = 0}) {
    final tempo = GameConfig.spawnTempoAt(progress);
    waveLeft -= dt * tempo;
    if (waveLeft > 0 && _burstLeft <= 0) return;
    if (_burstLeft > 0) return;

    switch (wave) {
      case SpawnWave.calm:
        wave = SpawnWave.rareRush;
        // Slightly shorter rare pack — more room for gold/coins.
        _burstLeft = 1 + _rng.nextInt(2);
        waveLeft = (2.4 + _rng.nextDouble()) / tempo;
      case SpawnWave.rareRush:
        wave = SpawnWave.bombSpike;
        // One bomb warning — never a wall of bombs.
        _burstLeft = 1;
        waveLeft = (2.0 + _rng.nextDouble() * 0.8) / tempo;
      case SpawnWave.bombSpike:
        wave = SpawnWave.calm;
        _burstLeft = 0;
        waveLeft = (4.2 + _rng.nextDouble() * 2.2) / tempo;
    }
  }

  ItemType rollType({required double progress}) {
    if (_burstLeft > 0) {
      _burstLeft--;
      if (wave == SpawnWave.rareRush) return _rollRare();
      if (wave == SpawnWave.bombSpike) return ItemType.bomb;
    }

    final roll = _rng.nextDouble();
    // Sparse bombs — one lane at a time, never a wall.
    final bombChance = switch (wave) {
      SpawnWave.calm => 0.04 + progress * 0.03,
      SpawnWave.rareRush => 0.03,
      SpawnWave.bombSpike => 0.55,
    };
    final rareChance = switch (wave) {
      SpawnWave.calm => (0.14 + progress * 0.04) * 0.9,
      SpawnWave.rareRush => 0.4 * 0.9,
      SpawnWave.bombSpike => 0.12 * 0.9,
    };

    if (roll < bombChance) return ItemType.bomb;
    if (roll < bombChance + rareChance) return _rollRare();
    // Commons fill the rest — ~10% more gold/coins vs previous mix.
    return _rng.nextDouble() < 0.55 ? ItemType.gold : ItemType.coal;
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

  double rollFallSpeed({required double progress}) {
    final min = GameConfig.itemFallSpeedMin + progress * 40;
    final max = GameConfig.itemFallSpeedMax + progress * 70;
    final base = min + _rng.nextDouble() * (max - min);
    return switch (wave) {
      SpawnWave.rareRush => base * 1.08,
      SpawnWave.bombSpike => base * 1.05,
      SpawnWave.calm => base * 0.94,
    };
  }

  double nextInterval({required double progress}) {
    final base = (GameConfig.spawnIntervalStart -
            progress *
                (GameConfig.spawnIntervalStart - GameConfig.spawnIntervalMin))
        .clamp(GameConfig.spawnIntervalMin, GameConfig.spawnIntervalStart);
    final mult = switch (wave) {
      SpawnWave.calm => 1.2,
      SpawnWave.rareRush => 0.7,
      // Extra pause after/around bombs so they aren't stacked.
      SpawnWave.bombSpike => 1.35,
    };
    final tempo = GameConfig.spawnTempoAt(progress);
    return (base * mult * (0.85 + _rng.nextDouble() * 0.3)) / tempo;
  }
}
