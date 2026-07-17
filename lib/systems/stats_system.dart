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

  void addItem(ItemType type) {
    switch (type) {
      case ItemType.gold:
        gold++;
      case ItemType.coal:
        coal++;
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
        bombHits++;
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
    if (currentStreak > 0 && currentStreak % 10 == 0) {
      combo++;
      if (combo > bestCombo) bestCombo = combo;
    }
  }

  void registerMiss() {
    missed++;
    currentStreak = 0;
  }
}

class MatchStats {
  final CollectorStats player = CollectorStats();
  final CollectorStats thief = CollectorStats();

  bool get playerWins => player.rareTotal >= thief.rareTotal;
}
