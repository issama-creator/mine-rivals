import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/mine_rivals_game.dart';

/// Tension checkpoint every 500 m — lead read, cash out or risk.
class CheckpointOverlay extends StatefulWidget {
  const CheckpointOverlay({super.key, required this.game});

  final MineRivalsGame game;

  @override
  State<CheckpointOverlay> createState() => _CheckpointOverlayState();
}

class _CheckpointOverlayState extends State<CheckpointOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  Timer? _thiefAuto;

  MineRivalsGame get game => widget.game;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();

    final you = game.stats.player.rareTotal;
    final thief = game.stats.thief.rareTotal;
    if (thief > you) {
      _thiefAuto = Timer(const Duration(milliseconds: 2800), () {
        if (!mounted) return;
        game.confirmThiefCheckpointDefeat();
      });
    }
  }

  @override
  void dispose() {
    _thiefAuto?.cancel();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final you = game.stats.player.rareTotal;
    final thief = game.stats.thief.rareTotal;
    final round = game.seriesRound;
    final meters = (round * game.checkpointStepMeters).round();
    final delta = you - thief;
    final thiefLeads = thief > you;
    final youLead = you > thief;
    final tied = you == thief;
    final closeFight = youLead && delta >= 1 && delta <= 5;
    final canRisk = !game.isFinalSeriesRound;
    final canCashOut = youLead || (tied && !canRisk) || (tied && canRisk);

    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      child: SafeArea(
        child: FadeTransition(
          opacity: _enter,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1).animate(
                    CurvedAnimation(parent: _enter, curve: Curves.easeOutBack),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: thiefLeads
                            ? const [Color(0xFF5D1F1A), Color(0xFF1A0A08)]
                            : const [Color(0xFF4E342E), Color(0xFF1A100A)],
                      ),
                      border: Border.all(
                        color: thiefLeads
                            ? const Color(0xFFEF5350).withValues(alpha: 0.85)
                            : const Color(0xFFFFB300).withValues(alpha: 0.75),
                        width: 2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'CHECKPOINT $round · $meters М',
                            style: TextStyle(
                              color: const Color(0xFFFFCA28)
                                  .withValues(alpha: 0.92),
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 1.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            thiefLeads ? 'ВОР ВПЕРЕДИ' : 'CHECKPOINT',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: thiefLeads
                                  ? const Color(0xFFEF5350)
                                  : const Color(0xFFFFE082),
                              fontWeight: FontWeight.w900,
                              fontSize: 28,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _ScoreRow(you: you, thief: thief),
                          const SizedBox(height: 14),
                          if (thiefLeads) ...[
                            Text(
                              'У вора больше кристаллов!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Ха-ха!',
                              style: TextStyle(
                                color: Color(0xFFFF8A65),
                                fontWeight: FontWeight.w900,
                                fontSize: 26,
                              ),
                            ),
                            const Text(
                              'Лузер!',
                              style: TextStyle(
                                color: Color(0xFFEF5350),
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _btn(
                              label: 'ПОРАЖЕНИЕ',
                              color: const Color(0xFFEF5350),
                              onTap: () {
                                _thiefAuto?.cancel();
                                HapticFeedback.heavyImpact();
                                game.confirmThiefCheckpointDefeat();
                              },
                            ),
                          ] else ...[
                            Text(
                              youLead
                                  ? (closeFight
                                      ? 'Всего +$delta'
                                      : 'Ты впереди!')
                                  : 'Ничья',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: youLead
                                    ? (closeFight
                                        ? const Color(0xFFFFB300)
                                        : const Color(0xFF81C784))
                                    : const Color(0xFFFFE082),
                                fontWeight: FontWeight.w900,
                                fontSize: closeFight ? 28 : 22,
                              ),
                            ),
                            if (youLead && !closeFight) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Лидерство: +$delta крист.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            if (closeFight) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Следующий участок будет очень опасным…',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            if (tied && canRisk) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Рискни дальше — победит тот, у кого больше на следующем чекпоинте.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            if (canCashOut && (youLead || !canRisk)) ...[
                              _btn(
                                label: canRisk
                                    ? 'ЗАБРАТЬ · $you ◆'
                                    : 'ЗАБРАТЬ · $you ◆ — ФИНИШ',
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
                                    ? 'РИСКНУТЬ ДАЛЬШЕ'
                                    : 'ПРОДОЛЖИТЬ',
                                color: const Color(0xFFFF5252),
                                foreground: Colors.white,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  game.riskCheckpointContinue();
                                },
                              ),
                            if (canRisk && youLead) ...[
                              const SizedBox(height: 8),
                              Text(
                                'При проигрыше весь банк сгорит',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
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
    Color foreground = const Color(0xFF3E2723),
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.you, required this.thief});

  final int you;
  final int thief;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ScoreCard(
            label: 'ТЫ',
            value: you,
            accent: const Color(0xFF4FC3F7),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ScoreCard(
            label: 'ВОР',
            value: thief,
            accent: const Color(0xFFFF8A65),
          ),
        ),
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: accent.withValues(alpha: 0.9),
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 32,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '◆',
              style: TextStyle(
                color: accent.withValues(alpha: 0.85),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
