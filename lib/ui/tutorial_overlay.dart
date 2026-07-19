import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/mine_rivals_game.dart';

/// One-time intro matching real rules: crystals → gap → coins → heart → finish.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.game});

  final MineRivalsGame game;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  int _step = 0;

  static const _steps = [
    (
      icon: Icons.swipe_rounded,
      title: 'Уклоняйся',
      body: 'Веди пальцем влево и вправо — обходи бомбы, ямы и шипы.',
    ),
    (
      icon: Icons.diamond_rounded,
      title: 'Кристаллы — приз',
      body:
          'Цветные камни решают гонку. У кого больше в конце — тот победил. Вор крадёт только их.',
    ),
    (
      icon: Icons.speed_rounded,
      title: 'Догоняй монетами',
      body:
          'Ошибка — вор уходит (+м вверху). Собирай монеты без промахов — сокращаешь дистанцию.',
    ),
    (
      icon: Icons.favorite_rounded,
      title: 'Сердце — щит',
      body: 'До 3 сердец. Каждое спасает от ямы или шипов. Лови их по пути.',
    ),
    (
      icon: Icons.flag_rounded,
      title: 'Серия раундов',
      body:
          'Каждые 500 м: забери банк кристаллов в магазин или рискни дальше. Умрёшь / вор закроет серию — весь банк сгорит. Цель — пройти все раунды.',
    ),
  ];

  void _next() {
    HapticFeedback.selectionClick();
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      return;
    }
    widget.game.finishTutorial();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final last = _step >= _steps.length - 1;

    return Material(
      color: Colors.black.withValues(alpha: 0.72),
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
                    color: const Color(0xFFFFB300).withValues(alpha: 0.7),
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'КАК ИГРАТЬ',
                        style: TextStyle(
                          color: const Color(0xFFFFCA28).withValues(alpha: 0.9),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Icon(step.icon, color: const Color(0xFFFFB300), size: 44),
                      const SizedBox(height: 14),
                      Text(
                        step.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFE082),
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        step.body,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _steps.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: i == _step ? 16 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: i == _step
                                    ? const Color(0xFFFFB300)
                                    : Colors.white24,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFB300),
                            foregroundColor: const Color(0xFF3E2723),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            last ? 'ПОГНАЛИ!' : 'ДАЛЬШЕ',
                            style: const TextStyle(
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
    );
  }
}
