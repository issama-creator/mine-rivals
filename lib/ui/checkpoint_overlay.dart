import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/mine_rivals_game.dart';

/// End of a series round: cash out crystal pot or risk — lose pot on failure.
class CheckpointOverlay extends StatelessWidget {
  const CheckpointOverlay({super.key, required this.game});

  final MineRivalsGame game;

  @override
  Widget build(BuildContext context) {
    final you = game.stats.player.rareTotal;
    final thief = game.stats.thief.rareTotal;
    final round = game.seriesRound;
    final total = game.seriesRounds;
    final stepM = game.checkpointStepMeters.round();
    final youLead = you > thief;
    final tied = you == thief;
    final canRisk = !game.isFinalSeriesRound;

    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
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
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'РАУНД $round / $total · $stepM М',
                        style: TextStyle(
                          color: const Color(0xFFFFCA28).withValues(alpha: 0.9),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        canRisk ? 'ЗАБРАТЬ ИЛИ РИСК?' : 'ФИНАЛ СЕРИИ',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFE082),
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: const Color(0xFF0277BD).withValues(alpha: 0.28),
                          border: Border.all(
                            color: const Color(0xFF4FC3F7).withValues(alpha: 0.55),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Text(
                            'Банк забега: $you ◆',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFE1F5FE),
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ты $you · Вор $thief',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        youLead
                            ? (canRisk
                                ? 'Забери $you ◆ в магазин сейчас — или рискни раунд ${round + 1}/$total. Умрёшь или вор закроет серию — весь банк сгорит.'
                                : 'Последний раунд. Забери $you ◆ в магазин — серия пройдена!')
                            : (tied
                                ? (canRisk
                                    ? 'Ничья. Рискни дальше — при проигрыше банк ($you ◆) сгорит.'
                                    : 'Ничья на финале — можно забрать $you ◆.')
                                : 'Вор ведёт. Беги дальше — если не обгонишь, банк сгорит.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (youLead || (tied && !canRisk)) ...[
                        _btn(
                          label: canRisk
                              ? 'ЗАБРАТЬ $you ◆'
                              : 'ЗАБРАТЬ $you ◆ — СЕРИЯ',
                          color: const Color(0xFF66BB6A),
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            game.acceptCheckpointFinish();
                          },
                        ),
                        if (canRisk) const SizedBox(height: 10),
                      ],
                      if (canRisk)
                        _btn(
                          label: youLead
                              ? 'РИСКНУТЬ — БАНК ГОРИТ ПРИ ПРОИГРЫШЕ'
                              : 'БЕГУ ДАЛЬШЕ',
                          color: const Color(0xFFFFB300),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            game.riskCheckpointContinue();
                          },
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

  Widget _btn({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: const Color(0xFF3E2723),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
      ),
    );
  }
}
