import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/asset_library.dart';
import '../game/mine_rivals_game.dart';
import '../game/player_skins.dart';
import '../items/item_type.dart';
import '../systems/game_settings.dart';

/// Crystals glued to the cart floor — track helmet so they don't slide on run.
class CartBedCargoLayer {
  CartBedCargoLayer({required this.forThief});

  final bool forThief;
  double pulse = 0;

  /// Helmet top Y per walk frame (player.png 6×3) — cargo sits just above it.
  static const List<double> _playerHatTop = [
    0.557,
    0.548,
    0.543,
    0.566,
    0.551,
    0.575,
    0.566,
    0.554,
    0.584,
    0.572,
    0.560,
    0.572,
    0.578,
    0.575,
    0.578,
    0.563,
    0.563,
    0.578,
  ];

  /// How far above the helmet the cart floor sits (дно вагонетки).
  static const double _playerFloorAboveHat = 0.026;

  static const double _p5Cx = 0.477;
  static const double _p5Cy = 0.385;
  static const double _vorCx = 0.472;
  static const double _vorCy = 0.405;

  static const double _bedWFrac = 0.28;
  static const double _bedHFrac = 0.085;

  /// Feet → bed for fly FX (avg floor).
  static double get bedYFracFromFeet {
    final skin = PlayerSkins.byId(GameSettings.instance.selectedSkinId);
    if (skin.id == 'player') {
      const avgHat = 0.565;
      return 1 - (avgHat - _playerFloorAboveHat);
    }
    return 1 - _p5Cy;
  }

  /// Tight scatter on the cart floor (small Y — stay against the back wall).
  static const List<Offset> _pileSlots = [
    Offset(0.00, 0.08),
    Offset(-0.26, 0.02),
    Offset(0.24, 0.12),
    Offset(-0.10, 0.16),
    Offset(0.12, -0.02),
    Offset(-0.20, 0.14),
    Offset(0.06, 0.18),
    Offset(0.18, 0.08),
  ];

  static int visibleGemCount(int total) {
    if (total <= 0) return 0;
    if (total == 1) return 1;
    if (total <= 3) return 2;
    if (total <= 6) return 3;
    if (total <= 10) return 4;
    if (total <= 16) return 5;
    if (total <= 24) return 6;
    if (total <= 35) return 7;
    return 8;
  }

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
    final bedW = ps.x * _bedWFrac;
    final bedH = ps.y * _bedHFrac;
    final centerX = ps.x * cx;
    final centerY = ps.y * cy;

    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.clipRect(
      Rect.fromCenter(
        center: const Offset(0, 0.05),
        width: bedW * 1.08,
        height: bedH * 1.2,
      ),
    );

    // No scale pulse — that made cargo look like it was wobbling.
    final shown = visibleGemCount(n);
    final gemW = bedW * (0.24 - (shown - 1) * 0.009).clamp(0.16, 0.24);
    final gemH = gemW * 0.88;

    for (var j = 0; j < shown; j++) {
      final pile = _pileSlots[j];
      gem.render(
        canvas,
        position: Vector2(
          pile.dx * bedW - gemW * 0.5,
          pile.dy * bedH - gemH * 0.5,
        ),
        size: Vector2(gemW, gemH),
      );
    }

    canvas.restore();
  }

  (double, double) _bedCenter(int animFrame) {
    if (forThief) return (_vorCx, _vorCy);
    final skin = PlayerSkins.byId(GameSettings.instance.selectedSkinId);
    if (skin.id == 'player') {
      final i = animFrame % _playerHatTop.length;
      // Floor glued just above the helmet — moves with the sprite, no slide.
      return (0.50, _playerHatTop[i] - _playerFloorAboveHat);
    }
    return (_p5Cx, _p5Cy);
  }
}
