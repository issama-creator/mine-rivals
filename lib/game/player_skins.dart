import 'package:flutter/material.dart';

/// Catalog of playable miner skins (9×2 run sheets).
class PlayerSkin {
  const PlayerSkin({
    required this.id,
    required this.nameRu,
    required this.sheetAsset,
    required this.previewAsset,
    required this.accent,
  });

  final String id;
  final String nameRu;
  final String sheetAsset;
  final String previewAsset;

  /// Theme color for skin-picker card border / label.
  final Color accent;
}

class PlayerSkins {
  PlayerSkins._();

  static const String defaultId = 'player';

  static const List<PlayerSkin> all = [
    PlayerSkin(
      id: 'player',
      nameRu: 'Шахтёр',
      sheetAsset: 'assets/images/skins/player.png',
      previewAsset: 'assets/images/skins/preview/player.png',
      accent: Color(0xFF7CB342), // olive green shirt
    ),
    PlayerSkin(
      id: 'woman',
      nameRu: 'Шахтёрша',
      sheetAsset: 'assets/images/skins/woman.png',
      previewAsset: 'assets/images/skins/preview/woman.png',
      accent: Color(0xFFEC407A), // pink shirt
    ),
    PlayerSkin(
      id: 'ninja',
      nameRu: 'Ниндзя',
      sheetAsset: 'assets/images/skins/ninja.png',
      previewAsset: 'assets/images/skins/preview/ninja.png',
      accent: Color(0xFFE53935), // red sash
    ),
    PlayerSkin(
      id: 'robot',
      nameRu: 'Робот',
      sheetAsset: 'assets/images/skins/robot.png',
      previewAsset: 'assets/images/skins/preview/robot.png',
      accent: Color(0xFF40C4FF), // neon blue glow
    ),
    PlayerSkin(
      id: 'monkey',
      nameRu: 'Обезьяна',
      sheetAsset: 'assets/images/skins/monkey.png',
      previewAsset: 'assets/images/skins/preview/monkey.png',
      accent: Color(0xFFD17A3A), // warm brown fur
    ),
    PlayerSkin(
      id: 'panda',
      nameRu: 'Панда',
      sheetAsset: 'assets/images/skins/panda.png',
      previewAsset: 'assets/images/skins/preview/panda.png',
      accent: Color(0xFF66BB6A), // green scarf
    ),
    PlayerSkin(
      id: 'pingvin',
      nameRu: 'Пингвин',
      sheetAsset: 'assets/images/skins/pingvin.png',
      previewAsset: 'assets/images/skins/preview/pingvin.png',
      accent: Color(0xFF4DD0E1), // icy cyan
    ),
    PlayerSkin(
      id: 'mag',
      nameRu: 'Маг',
      sheetAsset: 'assets/images/skins/mag.png',
      previewAsset: 'assets/images/skins/preview/mag.png',
      accent: Color(0xFF7E57C2), // indigo robe
    ),
  ];

  static PlayerSkin byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return all.first;
  }
}
