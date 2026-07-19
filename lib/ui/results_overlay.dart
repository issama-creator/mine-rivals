import 'package:flutter/material.dart';

import '../game/mine_rivals_game.dart';
import '../systems/game_settings.dart';
import '../systems/progress_store.dart';

class ResultsOverlay extends StatefulWidget {
  const ResultsOverlay({super.key, required this.game});

  final MineRivalsGame game;

  @override
  State<ResultsOverlay> createState() => _ResultsOverlayState();
}

class _ResultsOverlayState extends State<ResultsOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _enter, curve: Curves.easeOutBack),
    );
    // Finish haptic already fired from the game — keep results visual-only.
    _enter.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final s = game.stats;
    final failed = game.failedRun;
    final win = !failed && s.playerWins;
    final you = s.player.rareTotal;
    final thief = s.thief.rareTotal;
    final title = game.finishHeadline;
    final subtitle = game.finishTagline;
    final titleColor = failed
        ? const Color(0xFFEF5350)
        : (win ? const Color(0xFF81C784) : const Color(0xFFFF7043));

    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      child: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
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
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            subtitle,
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
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
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
                          const SizedBox(height: 14),
                          Text(
                            'Обгоны: ты ${game.playerOvertakes} · вор ${game.thiefOvertakes}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (game.newDistanceRecord || game.newRaresRecord) ...[
                            const SizedBox(height: 12),
                            Text(
                              [
                                if (game.newDistanceRecord)
                                  'Новый рекорд дистанции!',
                                if (game.newRaresRecord)
                                  'Новый рекорд кристаллов!',
                              ].join('\n'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFFD54F),
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                height: 1.25,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            '${game.distance.round()} м · '
                            '${GameSettings.instance.runMode.titleRu}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Рекорд режима: '
                            '${ProgressStore.instance.bestDistanceFor(GameSettings.instance.runMode)} м',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _MetaPull(game: game, win: win, failed: failed),
                          const SizedBox(height: 18),
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
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton(
                              onPressed: () => game.onQuitToMenu?.call(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFFE082),
                                side: BorderSide(
                                  color: const Color(0xFFFFB300)
                                      .withValues(alpha: 0.5),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'В МЕНЮ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
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

/// XP / mission / streak pull into the next run.
class _MetaPull extends StatelessWidget {
  const _MetaPull({
    required this.game,
    required this.win,
    required this.failed,
  });

  final MineRivalsGame game;
  final bool win;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final store = ProgressStore.instance;
    final xp = game.lastRunXpGain;
    final lvl = store.minerLevel;
    final into = store.minerXpIntoLevel;
    final need = store.minerXpForNextLevel;
    final hook = store.comebackHook();
    final tip = failed
        ? 'Сердце спасает · монеты догоняют вора'
        : (win
            ? 'Веди по кристаллам и жми Финиш'
            : 'Собери больше камней, чем вор');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFFB300).withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          children: [
            Text(
              xp > 0
                  ? '+$xp XP · Ур. $lvl · $into/$need'
                  : 'Ур. $lvl · ${store.minerTitle}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFFFE082),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tip,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hook,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF81C784).withValues(alpha: 0.95),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
