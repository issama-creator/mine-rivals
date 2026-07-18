import 'dart:async';

import 'package:flutter/material.dart';

import '../game/mine_rivals_game.dart';
import '../systems/lead_system.dart';

class HudOverlay extends StatefulWidget {
  const HudOverlay({super.key, required this.game});

  final MineRivalsGame game;

  @override
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay> {
  Timer? _timer;

  static const _gemYou = 'assets/images/kristales/crops/c1_0.png';
  static const _gemThief = 'assets/images/kristales/crops/c1_1.png';

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final playerRare = game.stats.player.rareTotal;
    final thiefRare = game.stats.thief.rareTotal;
    final youLead = game.lead.logicalLeader == Leader.player;
    final metersLeft = game.remainingMeters.round();
    final progress = game.progress;

    return IgnorePointer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // One slim row — doesn't cover the shaft ahead.
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xCC3E2723),
                      const Color(0xD91A100A),
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.55),
                    width: 1.2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                  child: Row(
                    children: [
                      _CrystalScore(
                        asset: _gemYou,
                        value: playerRare,
                        accent: const Color(0xFF4FC3F7),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ShaftProgress(progress: progress),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$metersLeft м',
                                  style: TextStyle(
                                    color: const Color(0xFFFFE082)
                                        .withValues(alpha: 0.9),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '  ·  ',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.3),
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  youLead ? 'впереди' : 'вор впереди',
                                  style: TextStyle(
                                    color: youLead
                                        ? const Color(0xFF81C784)
                                        : const Color(0xFFFF8A65),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CrystalScore(
                        asset: _gemThief,
                        value: thiefRare,
                        accent: const Color(0xFFEF5350),
                      ),
                    ],
                  ),
                ),
              ),
              if (game.bannerText != null) ...[
                const SizedBox(height: 6),
                _banner(game.bannerText!, game.bannerColor),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(String text, Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.black.withValues(alpha: 0.45),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _CrystalScore extends StatelessWidget {
  const _CrystalScore({
    required this.asset,
    required this.value,
    required this.accent,
  });

  final String asset;
  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 3, 8, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              asset,
              width: 22,
              height: 22,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => Icon(
                Icons.diamond_rounded,
                size: 18,
                color: accent,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$value',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShaftProgress extends StatelessWidget {
  const _ShaftProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 10,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final fill = progress.clamp(0.0, 1.0) * w;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.black.withValues(alpha: 0.5),
                  border: Border.all(
                    color: const Color(0xFFFFE082).withValues(alpha: 0.2),
                  ),
                ),
              ),
              Container(
                width: fill.clamp(0, w),
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB300), Color(0xFFFFECB3)],
                  ),
                ),
              ),
              Positioned(
                left: (fill - 5).clamp(0, w - 10),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFFFFF8E1), Color(0xFFFFB300)],
                    ),
                    border: Border.all(
                      color: const Color(0xFFFFECB3),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
