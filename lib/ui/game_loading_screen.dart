import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shown while Flame loads assets / builds the run.
class GameLoadingScreen extends StatefulWidget {
  const GameLoadingScreen({super.key});

  @override
  State<GameLoadingScreen> createState() => _GameLoadingScreenState();
}

class _GameLoadingScreenState extends State<GameLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _glow;
  late final AnimationController _spin;
  late final AnimationController _bar;

  static const _tips = [
    'Лови цветные камни!',
    'Вор крадёт только камни',
    'Бомбы — обходи стороной',
    'Веди в шахте — и магнитишь',
  ];

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _bar = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _glow.dispose();
    _spin.dispose();
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tip = _tips[DateTime.now().second % _tips.length];

    return Material(
      color: const Color(0xFF1A120B),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/tunnel.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFF1A120B),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.28),
                  const Color(0xFF1A0E08).withValues(alpha: 0.85),
                  const Color(0xFF0D0704).withValues(alpha: 0.94),
                ],
                stops: const [0, 0.35, 0.72, 1],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _glow,
            builder: (context, _) {
              final t = _glow.value;
              return IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.2),
                      radius: 0.9,
                      colors: [
                        Color.lerp(
                          const Color(0x55FFB300),
                          const Color(0x33FFECB3),
                          t,
                        )!,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 40),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Text(
                    'MINE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFFFFE082).withValues(alpha: 0.92),
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 12,
                      height: 1,
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _glow,
                    builder: (context, _) {
                      final glow = 8 + _glow.value * 14;
                      return Text(
                        'RIVALS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFFFFCA28),
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                          height: 1.05,
                          shadows: [
                            Shadow(
                              color: const Color(0xFFFFB300)
                                  .withValues(alpha: 0.75),
                              blurRadius: glow,
                            ),
                            const Shadow(
                              color: Colors.black87,
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) {
                      return CustomPaint(
                        size: const Size(72, 72),
                        painter: _GemSpinnerPainter(
                          progress: _spin.value,
                          pulse: _glow.value,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Спускаемся в шахту…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tip,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFFFFE082).withValues(alpha: 0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(flex: 2),
                  AnimatedBuilder(
                    animation: Listenable.merge([_bar, _glow]),
                    builder: (context, _) {
                      // Soft looping sweep — real load time varies.
                      final sweep = (math.sin(_bar.value * math.pi * 2) + 1) / 2;
                      final fill = 0.18 + sweep * 0.62;
                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              height: 10,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(
                                    color: Colors.white.withValues(alpha: 0.12),
                                  ),
                                  FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: fill,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color.lerp(
                                              const Color(0xFFFFB300),
                                              const Color(0xFFFFECB3),
                                              _glow.value,
                                            )!,
                                            const Color(0xFFFFCA28),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFFB300)
                                                .withValues(alpha: 0.45),
                                            blurRadius: 10,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Загрузка',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GemSpinnerPainter extends CustomPainter {
  _GemSpinnerPainter({required this.progress, required this.pulse});

  final double progress;
  final double pulse;

  static const _colors = [
    Color(0xFF80DEEA),
    Color(0xFFE53935),
    Color(0xFF43A047),
    Color(0xFF8E24AA),
    Color(0xFFFF8F00),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.38;
    canvas.drawCircle(
      c,
      r + 6 + pulse * 4,
      Paint()..color = const Color(0xFFFFB300).withValues(alpha: 0.12 + pulse * 0.08),
    );

    for (var i = 0; i < _colors.length; i++) {
      final a = progress * math.pi * 2 + i * (math.pi * 2 / _colors.length);
      final p = Offset(c.dx + math.cos(a) * r, c.dy + math.sin(a) * r);
      final gemR = 7.0 + (i.isEven ? pulse * 2 : (1 - pulse) * 2);
      canvas.drawCircle(
        p,
        gemR + 3,
        Paint()..color = _colors[i].withValues(alpha: 0.28),
      );
      canvas.drawCircle(p, gemR, Paint()..color = _colors[i]);
      canvas.drawCircle(
        p + const Offset(-1.5, -1.5),
        gemR * 0.35,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GemSpinnerPainter old) =>
      old.progress != progress || old.pulse != pulse;
}
