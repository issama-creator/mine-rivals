import 'dart:async';

import 'package:flutter/material.dart';

import '../game/game_config.dart';
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

    return IgnorePointer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Column(
            children: [
              // Thin finish bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: game.progress,
                  minHeight: 6,
                  backgroundColor: Colors.black38,
                  color: const Color(0xFFFFB300),
                ),
              ),
              const SizedBox(height: 6),
              // Compact single row: ТЫ · финиш · ВОР
              Row(
                children: [
                  _pill(
                    'ТЫ $playerRare',
                    const Color(0xFF4FC3F7),
                  ),
                  const Spacer(),
                  Text(
                    '${GameConfig.levelLengthMeters.toInt()} м',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  _pill(
                    'ВОР $thiefRare',
                    const Color(0xFFEF5350),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                youLead ? 'Ты впереди' : 'Вор впереди — догоняй!',
                style: TextStyle(
                  color: youLead
                      ? const Color(0xFF81C784).withValues(alpha: 0.9)
                      : const Color(0xFFFF8A65).withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
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

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _banner(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}
