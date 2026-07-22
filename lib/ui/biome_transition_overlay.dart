import 'dart:async';

import 'package:flutter/material.dart';

import '../game/mine_rivals_game.dart';

/// After Continue: brief “entering next mine” beat before 3–2–1.
/// Mine art is already applied underneath before this overlay appears.
class BiomeTransitionOverlay extends StatefulWidget {
  const BiomeTransitionOverlay({super.key, required this.game});

  final MineRivalsGame game;

  @override
  State<BiomeTransitionOverlay> createState() => _BiomeTransitionOverlayState();
}

class _BiomeTransitionOverlayState extends State<BiomeTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  Timer? _done;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    // Shorter card — shaft is already live behind a light veil.
    _done = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      widget.game.finishBiomeTransition();
    });
  }

  @override
  void dispose() {
    _done?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.game.pendingBiomeName;

    return Material(
      // Light enough that the new shaft is already readable underneath.
      color: Colors.black.withValues(alpha: 0.55),
      child: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CHECKPOINT CLEARED',
                  style: TextStyle(
                    color: const Color(0xFF81C784).withValues(alpha: 0.95),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'ВХОД',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFE082),
                    fontWeight: FontWeight.w900,
                    fontSize: 34,
                    height: 1.15,
                    shadows: [
                      Shadow(color: Colors.black87, blurRadius: 16),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Новый этап · новые опасности',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
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
