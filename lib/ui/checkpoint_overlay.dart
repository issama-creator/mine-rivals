import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/mine_rivals_game.dart';

/// Every 700 m: cash out crystals or risk the next segment (thief may finish).
class CheckpointOverlay extends StatelessWidget {
  const CheckpointOverlay({super.key, required this.game});

  final MineRivalsGame game;

  @override
  Widget build(BuildContext context) {
    final you = game.stats.player.rareTotal;
    final thief = game.stats.thief.rareTotal;
    final meters = game.distance.round();
    final youLead = you > thief;
    final tied = you == thief;

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
                        '$meters М',
                        style: TextStyle(
                          color: const Color(0xFFFFCA28).withValues(alpha: 0.9),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'ЗАБРАТЬ КАМНИ?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFFFE082),
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Ты $you · Вор $thief',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        youLead
                            ? 'Ты впереди — забери победу или рискни ещё ${game.checkpointStepMeters.round()} м. Если у вора станет больше — он нажмёт Финиш.'
                            : (tied
                                ? 'Ничья. Рискни дальше или беги — победит тот, у кого больше на следующем чекпоинте.'
                                : 'Вор ведёт! Если рискнёшь и не обгонишь по камням — он заберёт Финиш.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (youLead) ...[
                        _btn(
                          label: 'ФИНИШ — ЗАБРАТЬ',
                          color: const Color(0xFF66BB6A),
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            game.acceptCheckpointFinish();
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      _btn(
                        label: youLead ? 'РИСКНУТЬ ДАЛЬШЕ' : 'БЕГУ ДАЛЬШЕ',
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
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
      ),
    );
  }
}
