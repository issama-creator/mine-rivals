import 'package:flutter/material.dart';

import 'game_config.dart';

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
    this.displayWidth,
    this.displayHeight,
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

  /// On-screen size override (keeps sheet aspect — avoids stretch-fat sprites).
  final double? displayWidth;
  final double? displayHeight;

  int get frameCount =>
      walkFrameIndices?.length ?? columns * (walkRows ?? rows);

  double get width =>
      displayWidth ??
      (cartStyle ? GameConfig.playerCartWidth : GameConfig.playerWidth);

  double get height =>
      displayHeight ??
      (cartStyle ? GameConfig.playerCartHeight : GameConfig.playerHeight);
}

class PlayerSkins {
  PlayerSkins._();

  static const String defaultId = 'fav';

  static const List<PlayerSkin> all = [
    PlayerSkin(
      id: 'fav',
      nameRu: 'Шахтёр',
      sheetAsset: 'assets/images/skins/fav.png',
      previewAsset: 'assets/images/skins/preview/fav.png',
      accent: Color(0xFFFFCA28),
      columns: 6,
      rows: 1,
      walkRows: 1,
      cartStyle: true,
      topDown: true,
      // Sheet ~132×339 — keep aspect; −30% then −3% more.
      displayWidth: 40,
      displayHeight: 101,
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
