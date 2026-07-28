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

  /// Cart-bed center per p5 sheet column (row 0) — follows hop so gems don't hang.
  static const List<double> _p5BedCx = [
    0.479,
    0.485,
    0.477,
    0.486,
    0.480,
    0.481,
  ];
  static const List<double> _p5BedCy = [
    0.385,
    0.351,
    0.368,
    0.343,
    0.364,
    0.355,
  ];
  static const double _vorCx = 0.470;
  static const double _vorCy = 0.430;

  static const double _bedWFrac = 0.32;
  static const double _bedHFrac = 0.14;

  /// Feet → bed for fly FX (avg floor).
  static double get bedYFracFromFeet {
    final skin = PlayerSkins.byId(GameSettings.instance.selectedSkinId);
    if (skin.id == 'player') {
      const avgHat = 0.565;
      return 1 - (avgHat - _playerFloorAboveHat);
    }
    final avgCy =
        _p5BedCy.reduce((a, b) => a + b) / _p5BedCy.length;
    return 1 - avgCy;
  }

  /// Messy dump across the whole bed — each gem claims its own patch (max 15).
  static const int maxVisibleGems = 15;

  /// Fractions of bedW/bedH; look random, stay fixed (no per-frame flicker).
  static const List<Offset> _pileSlots = [
    Offset(-0.22, 0.18),
    Offset(0.28, -0.12),
    Offset(0.05, 0.30),
    Offset(-0.32, -0.22),
    Offset(0.18, 0.08),
    Offset(-0.08, -0.30),
    Offset(0.34, 0.22),
    Offset(-0.30, 0.06),
    Offset(0.12, -0.28),
    Offset(-0.02, 0.02),
    Offset(0.26, 0.32),
    Offset(-0.36, 0.28),
    Offset(0.32, -0.30),
    Offset(-0.16, -0.06),
    Offset(0.08, 0.20),
  ];

  /// 1 collected → 1 shown … up to [maxVisibleGems] in the cart bed.
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
    final bedW = ps.x * _bedWFrac;
    final bedH = ps.y * _bedHFrac;
    final centerX = ps.x * cx;
    final centerY = ps.y * cy + bedH * 0.12;

    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.clipRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: bedW * 1.08,
        height: bedH * 1.2,
      ),
    );

    final shown = visibleGemCount(n);
    // Readable pile — bigger gems so cargo reads at a glance.
    final base = bedW * 0.24 < bedH * 1.05 ? bedW * 0.24 : bedH * 1.05;
    final gemW = base * (forThief ? 1.08 : 1.05);
    final gemH = gemW * 0.88;

    // Soft glow under the dump so empty vs loaded carts differ instantly.
    final glow = Paint()
      ..color = (forThief ? const Color(0xFFEF5350) : const Color(0xFF4FC3F7))
          .withValues(alpha: 0.22 + 0.02 * shown.clamp(0, 8))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: bedW * 0.85,
        height: bedH * 0.95,
      ),
      glow,
    );

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
    // Map anim index → sheet column (honours walkFrameIndices).
    final keep = skin.walkFrameIndices;
    final sheetCol = (keep != null && keep.isNotEmpty)
        ? keep[animFrame % keep.length]
        : animFrame % _p5BedCy.length;
    final i = sheetCol.clamp(0, _p5BedCy.length - 1);
    return (_p5BedCx[i], _p5BedCy[i]);
  }
}
