import 'dart:ui';

enum ItemType {
  gold,
  coal,
  diamond,
  ruby,
  emerald,
  amethyst,
  legendary,
  bomb,
  dynamiteCart,
  web,
  magnet,
  pit,
  spikes,
  heart,
  potion,
}

extension ItemTypeX on ItemType {
  bool get isRare =>
      this == ItemType.diamond ||
      this == ItemType.ruby ||
      this == ItemType.emerald ||
      this == ItemType.amethyst ||
      this == ItemType.legendary;

  bool get isCommon => this == ItemType.gold || this == ItemType.coal;

  bool get isBomb => this == ItemType.bomb;

  bool get isDynamiteCart => this == ItemType.dynamiteCart;

  /// Bomb + dynamite cart — explode, crystal loss, heart can save.
  bool get isExplosive => isBomb || isDynamiteCart;

  bool get isWeb => this == ItemType.web;

  bool get isMagnet => this == ItemType.magnet;

  bool get isPit => this == ItemType.pit;

  bool get isSpikes => this == ItemType.spikes;

  /// Pit + spikes — feet check, instant fail (heart can save).
  bool get isLethalFloor => isPit || isSpikes;

  bool get isHeart => this == ItemType.heart;

  bool get isPotion => this == ItemType.potion;

  /// Hazards use a strict circular touch gate (no fat hitbox).
  bool get isHazard => isExplosive || isWeb || isLethalFloor;

  /// Pulled by the Subway-style magnet power-up (never hazards).
  bool get isMagnetizable => !isHazard;

  /// Explicit jewel set — commons / hazards / pickups are NEVER in here.
  bool get isJewel {
    switch (this) {
      case ItemType.diamond:
      case ItemType.ruby:
      case ItemType.emerald:
      case ItemType.amethyst:
      case ItemType.legendary:
        return true;
      case ItemType.gold:
      case ItemType.coal:
      case ItemType.bomb:
      case ItemType.dynamiteCart:
      case ItemType.web:
      case ItemType.magnet:
      case ItemType.pit:
      case ItemType.spikes:
      case ItemType.heart:
      case ItemType.potion:
        return false;
    }
  }

  /// Thief only snatches jewels — never coins or bombs.
  bool get thiefCanCollect => isJewel;

  String get label {
    switch (this) {
      case ItemType.gold:
        return 'Gold';
      case ItemType.coal:
        return 'Coal';
      case ItemType.diamond:
        return 'Diamond';
      case ItemType.ruby:
        return 'Ruby';
      case ItemType.emerald:
        return 'Emerald';
      case ItemType.amethyst:
        return 'Amethyst';
      case ItemType.legendary:
        return 'Legendary';
      case ItemType.bomb:
        return 'Bomb';
      case ItemType.dynamiteCart:
        return 'Dynamite cart';
      case ItemType.web:
        return 'Web';
      case ItemType.magnet:
        return 'Magnet';
      case ItemType.pit:
        return 'Pit';
      case ItemType.spikes:
        return 'Spikes';
      case ItemType.heart:
        return 'Heart';
      case ItemType.potion:
        return 'Potion';
    }
  }

  String get popupLabel {
    switch (this) {
      case ItemType.bomb:
        return '−1';
      case ItemType.dynamiteCart:
        return 'Бум!';
      case ItemType.web:
        return 'Липко!';
      case ItemType.magnet:
        return 'Магнит!';
      case ItemType.pit:
        return 'Яма!';
      case ItemType.spikes:
        return 'Шипы!';
      case ItemType.heart:
        return 'Сердце!';
      case ItemType.potion:
        return 'Зелье!';
      case ItemType.coal:
        return '+2';
      default:
        return '+1';
    }
  }

  Color get color {
    switch (this) {
      case ItemType.gold:
        return const Color(0xFFFFC107);
      case ItemType.coal:
        return const Color(0xFF5D4037);
      case ItemType.diamond:
        return const Color(0xFF80DEEA);
      case ItemType.ruby:
        return const Color(0xFFE53935);
      case ItemType.emerald:
        return const Color(0xFF43A047);
      case ItemType.amethyst:
        return const Color(0xFF8E24AA);
      case ItemType.legendary:
        return const Color(0xFFFF8F00);
      case ItemType.bomb:
        return const Color(0xFFFF1744);
      case ItemType.dynamiteCart:
        return const Color(0xFFFF6D00);
      case ItemType.web:
        return const Color(0xFFECEFF1);
      case ItemType.magnet:
        return const Color(0xFF29B6F6);
      case ItemType.pit:
        return const Color(0xFF212121);
      case ItemType.spikes:
        return const Color(0xFFFF8A65);
      case ItemType.heart:
        return const Color(0xFFFF5252);
      case ItemType.potion:
        return const Color(0xFFAB47BC);
    }
  }
}
