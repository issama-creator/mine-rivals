import 'package:flutter/material.dart';

/// Catalog of playable miner skins.
class PlayerSkin {
  const PlayerSkin({
    required this.id,
    required this.nameRu,
    required this.sheetAsset,
    required this.previewAsset,
    required this.accent,
    this.columns = 9,
    this.rows = 2,
    this.cartStyle = false,
    this.topDown = false,
  });

  final String id;
  final String nameRu;
  final String sheetAsset;
  final String previewAsset;

  /// Theme color for skin-picker card border / label.
  final Color accent;

  /// Sprite sheet grid (legacy 9×2; top-down cart pushers 6×4).
  final int columns;
  final int rows;

  /// Cart runner — cargo bed is the catch / fill focus.
  final bool cartStyle;

  /// True top-down sheet (cart ahead of miner toward top of frame).
  final bool topDown;
}

class PlayerSkins {
  PlayerSkins._();

  /// Default = p5 (main cart pusher).
  static const String defaultId = 'p5';

  static const List<PlayerSkin> all = [
    PlayerSkin(
      id: 'p5',
      nameRu: 'Шахтёр',
      sheetAsset: 'assets/images/skins/p5.png',
      previewAsset: 'assets/images/skins/preview/p5.png',
      accent: Color(0xFFFFB300),
      columns: 6,
      rows: 4,
      cartStyle: true,
      topDown: true,
    ),
  ];

  static PlayerSkin byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return all.first;
  }
}
