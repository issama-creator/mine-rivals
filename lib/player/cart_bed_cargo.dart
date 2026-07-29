import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/asset_library.dart';
import '../game/mine_rivals_game.dart';
import '../game/player_skins.dart';
import '../items/item_type.dart';
import '../systems/game_settings.dart';

/// Crystals glued to the cart floor — locked to bed, no run wobble.
class CartBedCargoLayer {
  CartBedCargoLayer({required this.forThief});

  final bool forThief;
  double pulse = 0; // kept for call sites; paint ignores it (no bounce).

  /// Vor walk-row bed centers (sheet cols 0–5).
  static const List<double> _vorBedCx = [
    0.470,
    0.472,
    0.471,
    0.473,
    0.477,
    0.476,
  ];
  static const List<double> _vorBedCy = [
    0.420,
    0.419,
    0.425,
    0.421,
    0.428,
    0.426,
  ];

  /// Fav walk-row bed centers (sheet cols 0–5).
  static const List<double> _favBedCx = [
    0.501,
    0.515,
    0.507,
    0.504,
    0.510,
    0.507,
  ];
  static const List<double> _favBedCy = [
    0.226,
    0.230,
    0.231,
    0.234,
    0.229,
    0.232,
  ];

  static const double _bedWFrac = 0.34;
  static const double _bedHFrac = 0.13;
  static const double _thiefBedWFrac = 0.26;
  static const double _thiefBedHFrac = 0.095;

  /// Feet → bed for fly FX (avg floor).
  static double get bedYFracFromFeet {
    final avg =
        _favBedCy.reduce((a, b) => a + b) / _favBedCy.length;
    return 1 - avg;
  }

  static const int maxVisibleGems = 15;

  /// Messy dump across the bed — looks random, stays fixed (no flicker).
  static const List<Offset> _pileSlots = [
    Offset(-0.28, 0.22),
    Offset(0.32, -0.18),
    Offset(0.06, 0.34),
    Offset(-0.34, -0.26),
    Offset(0.22, 0.10),
    Offset(-0.08, -0.34),
    Offset(0.36, 0.26),
    Offset(-0.30, 0.04),
    Offset(0.14, -0.30),
    Offset(-0.02, 0.00),
    Offset(0.28, 0.36),
    Offset(-0.36, 0.30),
    Offset(0.34, -0.32),
    Offset(-0.18, -0.08),
    Offset(0.10, 0.18),
  ];

  static int visibleGemCount(int total) => total.clamp(0, maxVisibleGems);

  void paint(
    Canvas canvas,
    PositionComponent parent,
    MineRivalsGame game, [
    int animFrame = 0,
  ]) {
    final n =
        forThief ? game.stats.thief.rareTotal : game.stats.player.rareTotal;
    if (n <= 0) return;

    final gem = AssetLibrary.cartGem ?? AssetLibrary.items[ItemType.diamond];
    if (gem == null) return;

    final ps = parent.size;
    if (ps.x <= 0 || ps.y <= 0) return;

    final (cx, cy) = _bedCenter(animFrame);
    final bedW = ps.x * (forThief ? _thiefBedWFrac : _bedWFrac);
    final bedH = ps.y * (forThief ? _thiefBedHFrac : _bedHFrac);
    final centerX = ps.x * cx;
    final centerY = ps.y * cy + bedH * (forThief ? 0.22 : 0.08);

    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.clipRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: bedW * 1.05,
        height: bedH * 1.12,
      ),
    );

    final shown = visibleGemCount(n);
    final base = bedW * 0.24 < bedH * 1.0 ? bedW * 0.24 : bedH * 1.0;
    final gemW = base * (forThief ? 0.85 : 1.08);
    final gemH = gemW * 0.88;
    // Full bed scatter for player; thief a bit tighter so gems stay in rim.
    final scatter = forThief ? 0.78 : 0.95;

    for (var j = 0; j < shown; j++) {
      final pile = _pileSlots[j];
      gem.render(
        canvas,
        position: Vector2(
          pile.dx * bedW * scatter - gemW * 0.5,
          pile.dy * bedH * scatter - gemH * 0.5,
        ),
        size: Vector2(gemW, gemH),
      );
    }

    canvas.restore();
  }

  (double, double) _bedCenter(int animFrame) {
    if (forThief) {
      final i = animFrame % _vorBedCy.length;
      return (_vorBedCx[i], _vorBedCy[i]);
    }
    final skin = PlayerSkins.byId(GameSettings.instance.selectedSkinId);
    if (skin.id == 'fav') {
      final keep = skin.walkFrameIndices;
      final sheetCol = (keep != null && keep.isNotEmpty)
          ? keep[animFrame % keep.length]
          : animFrame % _favBedCy.length;
      final i = sheetCol.clamp(0, _favBedCy.length - 1);
      return (_favBedCx[i], _favBedCy[i]);
    }
    return (_favBedCx[0], _favBedCy[0]);
  }
}
