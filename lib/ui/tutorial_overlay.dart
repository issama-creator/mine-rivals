import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/mine_rivals_game.dart';

/// One-time 2-beat intro: dodge → crystals vs thief.
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
      body: 'Веди пальцем влево и вправо — обходи бомбы и ямы.',
    ),
    (
      icon: Icons.diamond_rounded,
      title: 'Кристаллы и вор',
      body:
          'Цветные камни решают гонку. Если вор впереди — он их крадёт. Не дай удрать!',
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
                            if (i > 0) const SizedBox(width: 8),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: i == _step ? 18 : 8,
                              height: 8,
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
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFB300),
                            foregroundColor: const Color(0xFF3E2723),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            last ? 'ПОГНАЛИ!' : 'ДАЛЬШЕ',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
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
