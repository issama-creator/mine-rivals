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
    this.walkFrameIndices,
    this.cartStyle = false,
    this.topDown = false,
  });

  final String id;
  final String nameRu;
  final String sheetAsset;
  final String previewAsset;
  final Color accent;
  final int columns;
  final int rows;
  final int? walkRows;

  /// Optional subset of walk-row frame indices (0-based). Skips hop / bad poses.
  final List<int>? walkFrameIndices;
  final bool cartStyle;
  final bool topDown;

  int get frameCount =>
      walkFrameIndices?.length ?? columns * (walkRows ?? rows);
}

class PlayerSkins {
  PlayerSkins._();

  static const String defaultId = 'p5';

  static const List<PlayerSkin> all = [
    PlayerSkin(
      id: 'p5',
      nameRu: 'Шахтёр',
      sheetAsset: 'assets/images/skins/p5.png',
      previewAsset: 'assets/images/skins/preview/p5.png',
      accent: Color(0xFFFF8F00),
      columns: 6,
      rows: 4,
      walkRows: 1,
      // Drop hop-on-one-leg poses (#2,#4,#6) — keep planted / mild stride.
      walkFrameIndices: [0, 2, 4],
      cartStyle: true,
      topDown: true,
    ),
  ];

  static List<PlayerSkin> get paradeSkins =>
      all.where((s) => s.topDown && s.cartStyle).toList(growable: false);

  static PlayerSkin byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return all.first;
  }
}
