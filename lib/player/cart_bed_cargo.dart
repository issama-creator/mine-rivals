import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../game/asset_library.dart';
import '../game/mine_rivals_game.dart';
import '../items/item_type.dart';

/// Crystals glued to the cart bed — Y synced per walk frame (p5 / vor sheets).
class CartBedCargoLayer {
  CartBedCargoLayer({required this.forThief});

  final bool forThief;
  double pulse = 0;

  /// Dark cart interior centroids — measured from p5 / vor row-0 walk frames.
  static const List<double> _p5Cx = [
    0.474,
    0.479,
    0.474,
    0.481,
    0.477,
    0.477,
  ];
  static const List<double> _p5Cy = [
    0.379,
    0.362,
    0.371,
    0.358,
    0.371,
    0.365,
  ];

  static const List<double> _vorCx = [
    0.467,
    0.469,
    0.471,
    0.475,
    0.475,
    0.477,
  ];
  static const List<double> _vorCy = [
    0.389,
    0.389,
    0.393,
    0.389,
    0.395,
    0.391,
  ];

  static const double _bedWFrac = 0.32;
  static const double _bedHFrac = 0.10;

  /// Extra drop into the hollow (normalized sprite height).
  static const double _paintDropFrac = 0.034;

  /// Feet anchor → bed center for fly FX (p5 average cy + drop).
  static const double bedYFracFromFeet = 1 - (0.368 + _paintDropFrac);

  /// Pile slots in bed-local space (x × bedW, y × bedH from bed center).
  static const List<Offset> _pileSlots = [
    Offset(-0.20, 0.38),
    Offset(0.12, 0.48),
    Offset(-0.06, 0.58),
    Offset(0.16, 0.44),
  ];

  static const List<int> _slotsForCount = [
    1, // 1 gem
    0, // 2 gems → slots 0,1
    1,
    0, // 3 gems → 0,1,3
    1,
    3,
    0, // 4 gems → all
    1,
    2,
    3,
  ];

  static int visibleGemCount(int total) {
    if (total <= 0) return 0;
    if (total == 1) return 1;
    if (total <= 4) return 2;
    if (total <= 10) return 3;
    return 4;
  }

  void paint(Canvas canvas, PositionComponent parent, MineRivalsGame game, int animFrame) {
    final n = forThief ? game.stats.thief.rareTotal : game.stats.player.rareTotal;
    if (n <= 0) return;

    final gem = AssetLibrary.items[ItemType.diamond];
    if (gem == null) return;

    final ps = parent.size;
    if (ps.x <= 0 || ps.y <= 0) return;

    final i = animFrame % 6;
    final cx = forThief ? _vorCx[i] : _p5Cx[i];
    final cy = forThief ? _vorCy[i] : _p5Cy[i];
    final bedW = ps.x * _bedWFrac;
    final bedH = ps.y * _bedHFrac;
    final centerX = ps.x * cx;
    final centerY = ps.y * (cy + _paintDropFrac);

    canvas.save();
    canvas.translate(centerX, centerY);

    if (pulse > 0) {
      final s = 1.0 + 0.07 * Curves.easeOutBack.transform(pulse);
      canvas.scale(s);
    }

    final shown = visibleGemCount(n);
    final gemW = bedW * 0.19;
    final gemH = gemW;
    final slotBase = (shown - 1) * shown ~/ 2;

    for (var j = 0; j < shown; j++) {
      final slot = _slotsForCount[slotBase + j];
      final pile = _pileSlots[slot];
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
}
