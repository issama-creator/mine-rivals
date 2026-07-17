import 'package:flutter/material.dart';

import '../game/mine_rivals_game.dart';

class ResultsOverlay extends StatelessWidget {
  const ResultsOverlay({super.key, required this.game});

  final MineRivalsGame game;

  @override
  Widget build(BuildContext context) {
    final s = game.stats;
    final win = s.playerWins;
    final you = s.player.rareTotal;
    final thief = s.thief.rareTotal;

    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4E342E), Color(0xFF1A100A)],
                  ),
                  border: Border.all(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.75),
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        win ? 'ТЫ ПОБЕДИЛ!' : 'ВОР ПОБЕДИЛ!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: win
                              ? const Color(0xFF81C784)
                              : const Color(0xFFFF7043),
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        win
                            ? 'У тебя больше красивых камней'
                            : 'Вор унёс больше красивых камней',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _scoreBox(
                              'ТЫ',
                              you,
                              const Color(0xFF4FC3F7),
                              win,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'против',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _scoreBox(
                              'ВОР',
                              thief,
                              const Color(0xFFEF5350),
                              !win,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Лови цветные камни — не дай вору!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFFFFE082).withValues(alpha: 0.9),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFFD54F),
                                Color(0xFFFFB300),
                              ],
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: game.restart,
                              child: const Center(
                                child: Text(
                                  'ИГРАТЬ СНОВА',
                                  style: TextStyle(
                                    color: Color(0xFF3E2723),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scoreBox(String title, int value, Color color, bool highlight) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: highlight ? 0.4 : 0.22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: highlight ? 0.9 : 0.4),
          width: highlight ? 2.5 : 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 44,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'камни',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
