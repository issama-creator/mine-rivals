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
    this.walkRows,
    this.cartStyle = false,
    this.topDown = false,
  });

  final String id;
  final String nameRu;
  final String sheetAsset;
  final String previewAsset;

  /// Theme color for skin-picker card border / label.
  final Color accent;

  /// Sprite sheet grid (legacy 9×2; top-down cart pushers 6×N).
  final int columns;
  final int rows;

  /// Limit walk cycle to first N rows (null = all rows).
  final int? walkRows;

  /// Cart runner — cargo bed is the catch / fill focus.
  final bool cartStyle;

  /// True top-down sheet (cart ahead of miner toward top of frame).
  final bool topDown;

  int get frameCount => columns * (walkRows ?? rows);
}

class PlayerSkins {
  PlayerSkins._();

  /// Default = new 18-frame cart pusher (p5 kept for A/B).
  static const String defaultId = 'player';

  static const List<PlayerSkin> all = [
    PlayerSkin(
      id: 'player',
      nameRu: 'Шахтёр',
      sheetAsset: 'assets/images/skins/player.png',
      previewAsset: 'assets/images/skins/preview/player.png',
      accent: Color(0xFFFFB300),
      columns: 6,
      rows: 3,
      cartStyle: true,
      topDown: true,
    ),
    PlayerSkin(
      id: 'p5',
      nameRu: 'Шахтёр (старый)',
      sheetAsset: 'assets/images/skins/p5.png',
      previewAsset: 'assets/images/skins/preview/p5.png',
      accent: Color(0xFFFF8F00),
      columns: 6,
      rows: 4,
      walkRows: 1,
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
