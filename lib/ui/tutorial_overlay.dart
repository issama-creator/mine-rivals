import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/mine_rivals_game.dart';

/// One-time intro — cart bank, thief pressure, checkpoint cash-out.
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
      body:
          'Веди пальцем влево и вправо — обходи бомбы, ямы и шипы. Ошибки не убивают, но подпускают вора к тележке.',
    ),
    (
      icon: Icons.shopping_cart_rounded,
      title: 'Тележка — центр',
      body:
          'Кристаллы падают в тележку. Чем больше добычи — тем богаче она выглядит. Защищай её до чекпоинта.',
    ),
    (
      icon: Icons.dangerous_rounded,
      title: 'Вор у тележки',
      body:
          'Если вор догнал тележку — он тащит кристаллы по одному. Играй чисто, чтобы снова оторваться.',
    ),
    (
      icon: Icons.favorite_rounded,
      title: 'Сердце — щит',
      body:
          'До 3 сердец. Каждое смягчает удар ямы или шипов и не даёт вору сразу прорваться к добыче.',
    ),
    (
      icon: Icons.flag_rounded,
      title: 'Чекпоинт 500 м',
      body:
          'Если у тебя больше кристаллов — забери банк или рискни дальше. Если у вора больше — конец серии.',
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
                    color: const Color(0xFFFFB300).withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        step.icon,
                        size: 44,
                        color: const Color(0xFFFFB300),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        step.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFFF8E1),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        step.body,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFFFFE082).withValues(alpha: 0.9),
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_steps.length, (i) {
                          final on = i == _step;
                          return Container(
                            width: on ? 18 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: on
                                  ? const Color(0xFFFFB300)
                                  : const Color(0xFFFFB300)
                                      .withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFB300),
                            foregroundColor: const Color(0xFF1A100A),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            last ? 'В шахту!' : 'Дальше',
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
