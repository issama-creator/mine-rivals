import '../game/game_config.dart';
import '../items/item_type.dart';

class CollectorStats {
  int gold = 0;
  int coal = 0;
  int diamond = 0;
  int ruby = 0;
  int emerald = 0;
  int amethyst = 0;
  int legendary = 0;
  int bombHits = 0;
  int missed = 0;
  int combo = 0;
  int bestCombo = 0;
  int currentStreak = 0;

  int get rareTotal => diamond + ruby + emerald + amethyst + legendary;

  void addGold(int amount) {
    if (amount > 0) gold += amount;
  }

  void addItem(ItemType type, {int amount = 1}) {
    final n = amount < 1 ? 1 : amount;
    switch (type) {
      case ItemType.gold:
        gold += n;
      case ItemType.coal:
        coal += n;
      case ItemType.diamond:
        diamond++;
      case ItemType.ruby:
        ruby++;
      case ItemType.emerald:
        emerald++;
      case ItemType.amethyst:
        amethyst++;
      case ItemType.legendary:
        legendary++;
      case ItemType.bomb:
      case ItemType.dynamiteCart:
        bombHits++;
      case ItemType.web:
      case ItemType.magnet:
      case ItemType.pit:
      case ItemType.spikes:
      case ItemType.heart:
      case ItemType.potion:
        break;
    }
  }

  void registerCatch({required bool isBomb}) {
    if (isBomb) {
      currentStreak = 0;
      combo = 0;
      bombHits++;
      return;
    }
    currentStreak++;
    if (currentStreak > 0 &&
        currentStreak % GameConfig.comboThreshold == 0) {
      combo++;
      if (combo > bestCombo) bestCombo = combo;
    }
  }

  void registerMiss() {
    missed++;
    currentStreak = 0;
  }

  /// Bomb / cart-steal penalty — remove one rare crystal if any.
  bool loseOneRare() => loseOneRareTyped() != null;

  /// Same as [loseOneRare], but returns the type removed (for thief transfer).
  ItemType? loseOneRareTyped() {
    if (legendary > 0) {
      legendary--;
      return ItemType.legendary;
    }
    if (amethyst > 0) {
      amethyst--;
      return ItemType.amethyst;
    }
    if (emerald > 0) {
      emerald--;
      return ItemType.emerald;
    }
    if (ruby > 0) {
      ruby--;
      return ItemType.ruby;
    }
    if (diamond > 0) {
      diamond--;
      return ItemType.diamond;
    }
    return null;
  }
}

class MatchStats {
  final CollectorStats player = CollectorStats();
  final CollectorStats thief = CollectorStats();

  bool get playerWins => player.rareTotal >= thief.rareTotal;
}
