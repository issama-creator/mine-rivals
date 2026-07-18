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
  web,
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

  bool get isWeb => this == ItemType.web;

  /// Hazards use a strict circular touch gate (no fat hitbox).
  bool get isHazard => this == ItemType.bomb || this == ItemType.web;

  /// Explicit jewel set — gold/coal/bomb/web are NEVER in here.
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
      case ItemType.web:
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
      case ItemType.web:
        return 'Web';
    }
  }

  String get popupLabel {
    switch (this) {
      case ItemType.bomb:
        return '−1';
      case ItemType.web:
        return 'Липко!';
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
      case ItemType.web:
        return const Color(0xFFECEFF1);
    }
  }
}
