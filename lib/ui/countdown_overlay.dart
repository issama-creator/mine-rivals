import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/mine_rivals_game.dart';

/// 3–2–1 after checkpoint risk — then soft resume.
class CountdownOverlay extends StatefulWidget {
  const CountdownOverlay({super.key, required this.game});

  final MineRivalsGame game;

  @override
  State<CountdownOverlay> createState() => _CountdownOverlayState();
}

class _CountdownOverlayState extends State<CountdownOverlay>
    with SingleTickerProviderStateMixin {
  int _n = 3;
  late final AnimationController _pulse;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _tick = Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (!mounted) return;
      if (_n > 1) {
        HapticFeedback.selectionClick();
        setState(() => _n -= 1);
        _pulse
          ..value = 0
          ..forward();
        return;
      }
      _tick?.cancel();
      HapticFeedback.mediumImpact();
      widget.game.finishRoundCountdown();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.72, end: 1.08).animate(
            CurvedAnimation(parent: _pulse, curve: Curves.easeOutBack),
          ),
          child: FadeTransition(
            opacity: _pulse,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'РАУНД ${widget.game.seriesRound}/${widget.game.seriesRounds}',
                  style: TextStyle(
                    color: const Color(0xFFFFCA28).withValues(alpha: 0.9),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$_n',
                  style: const TextStyle(
                    color: Color(0xFFFFE082),
                    fontWeight: FontWeight.w900,
                    fontSize: 96,
                    height: 1,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Приготовься',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
