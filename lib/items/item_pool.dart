import 'dart:math';

import 'package:flame/components.dart';

import '../game/game_config.dart';
import 'falling_item.dart';
import 'item_type.dart';

/// Reuses FallingItem instances by type to keep GC pressure low.
class ItemPool {
  final Map<ItemType, List<FallingItem>> _inactive = {
    for (final t in ItemType.values) t: <FallingItem>[],
  };
  final Random _rng = Random();

  FallingItem acquire({
    required ItemType type,
    required Vector2 position,
    required double fallSpeed,
  }) {
    final bucket = _inactive[type]!;
    if (bucket.isNotEmpty) {
      final item = bucket.removeLast();
      item.recycle(newPosition: position, newSpeed: fallSpeed);
      return item;
    }
    return FallingItem(type: type, position: position, fallSpeed: fallSpeed);
  }

  void release(FallingItem item) {
    if (item.isMounted) {
      item.removeFromParent();
    }
    final bucket = _inactive[item.type]!;
    if (bucket.length < 12) {
      bucket.add(item);
    }
  }

  ItemType rollType({required double progress}) {
    final roll = _rng.nextDouble();
    final bombChance = 0.08 + progress * 0.1;
    final rareChance = (0.18 + progress * 0.08) * 0.9;

    if (roll < bombChance) return ItemType.bomb;
    if (roll < bombChance + rareChance) {
      final rares = [
        ItemType.diamond,
        ItemType.ruby,
        ItemType.emerald,
        ItemType.amethyst,
        ItemType.legendary,
      ];
      final r = _rng.nextDouble();
      if (r > 0.92) return ItemType.legendary;
      return rares[_rng.nextInt(rares.length - 1)];
    }
    return _rng.nextDouble() < 0.55 ? ItemType.gold : ItemType.coal;
  }

  double rollFallSpeed({required double progress}) {
    final min = GameConfig.itemFallSpeedMin + progress * 40;
    final max = GameConfig.itemFallSpeedMax + progress * 70;
    return min + _rng.nextDouble() * (max - min);
  }
}
