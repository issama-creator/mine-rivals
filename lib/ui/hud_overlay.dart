import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/game_config.dart';
import '../game/mine_rivals_game.dart';
import '../systems/lead_system.dart';

/// Runner-style HUD — big distance up front (Subway-like), light rivalry chips.
class HudOverlay extends StatefulWidget {
  const HudOverlay({super.key, required this.game});

  final MineRivalsGame game;

  @override
  State<HudOverlay> createState() => _HudOverlayState();
}

class _HudOverlayState extends State<HudOverlay> {
  Timer? _timer;

  static const _gemYou = 'assets/images/kristales/crops/c1_0.png';
  static const _gemThief = 'assets/images/kristales/crops/c1_1.png';

  int _lastYou = -1;
  int _lastThief = -1;
  int _lastRun = -1;
  int _lastGold = -1;
  int _lastMult = -1;
  int _lastJewelCombo = -1;
  int _lastShaft = -1;
  int _lastMagnetSec = -1;
  bool _lastYouLead = true;
  bool _lastBurst = false;
  bool _lastBreath = false;
  bool _lastHeart = false;
  bool _lastPotion = false;
  bool _lastCanPotion = false;
  bool _lastPotionBoost = false;
  String? _lastBanner;

  @override
  void initState() {
    super.initState();
    // Faster poll so the big meter ticks feel alive.
    _timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      final g = widget.game;
      final you = g.stats.player.rareTotal;
      final thief = g.stats.thief.rareTotal;
      final run = g.distance.round();
      final gold = g.stats.player.gold;
      final mult = g.coinMultiplier;
      final jewelCombo = g.jewelStreak;
      final shaft = (g.distance / GameConfig.corridorSegmentMeters)
          .floor()
          .clamp(0, GameConfig.corridorCount - 1);
      final lead = g.lead.logicalLeader == Leader.player;
      final banner = g.bannerText;
      final magnetSec = g.magnetPowerSeconds.ceil();
      final burst = g.isThiefBursting;
      final breath = g.isThiefBreathing;
      final heart = g.hasHeart;
      final potion = g.hasPotion;
      final canPotion = g.canUsePotion;
      final potionBoost = g.isPotionBoosting;
      if (you == _lastYou &&
          thief == _lastThief &&
          run == _lastRun &&
          gold == _lastGold &&
          mult == _lastMult &&
          jewelCombo == _lastJewelCombo &&
          shaft == _lastShaft &&
          lead == _lastYouLead &&
          banner == _lastBanner &&
          magnetSec == _lastMagnetSec &&
          burst == _lastBurst &&
          breath == _lastBreath &&
          heart == _lastHeart &&
          potion == _lastPotion &&
          canPotion == _lastCanPotion &&
          potionBoost == _lastPotionBoost) {
        return;
      }
      _lastYou = you;
      _lastThief = thief;
      _lastRun = run;
      _lastGold = gold;
      _lastMult = mult;
      _lastJewelCombo = jewelCombo;
      _lastShaft = shaft;
      _lastYouLead = lead;
      _lastBanner = banner;
      _lastMagnetSec = magnetSec;
      _lastBurst = burst;
      _lastBreath = breath;
      _lastHeart = heart;
      _lastPotion = potion;
      _lastCanPotion = canPotion;
      _lastPotionBoost = potionBoost;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _openPauseMenu() async {
    final game = widget.game;
    if (game.finished) return;
    HapticFeedback.selectionClick();
    game.pauseForMenu();

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3E2723), Color(0xFF1B120C)],
              ),
              border: Border.all(
                color: const Color(0xFFFFB300).withValues(alpha: 0.55),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Меню',
                      style: TextStyle(
                        color: Color(0xFFFFE082),
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PauseAction(
                      label: 'Продолжить',
                      icon: Icons.play_arrow_rounded,
                      filled: true,
                      onTap: () => Navigator.pop(context, 'resume'),
                    ),
                    const SizedBox(height: 10),
                    _PauseAction(
                      label: 'Закончить игру',
                      icon: Icons.flag_rounded,
                      filled: false,
                      onTap: () => Navigator.pop(context, 'end'),
                    ),
                    const SizedBox(height: 10),
                    _PauseAction(
                      label: 'В главное меню',
                      icon: Icons.home_rounded,
                      filled: false,
                      onTap: () => Navigator.pop(context, 'menu'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    switch (action) {
      case 'end':
        game.endRunEarly();
      case 'menu':
        game.onQuitToMenu?.call();
      case 'resume':
      default:
        game.resumeFromMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final runM = math.max(0, game.distance.round());
    final gold = game.stats.player.gold;
    final playerRare = game.stats.player.rareTotal;
    final thiefRare = game.stats.thief.rareTotal;
    final youLead = game.lead.logicalLeader == Leader.player;
    final shaft = (game.distance / GameConfig.corridorSegmentMeters)
            .floor()
            .clamp(0, GameConfig.corridorCount - 1) +
        1;
    final shafts = GameConfig.corridorCount;
    final runLabel = _formatMeters(runM);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: coins · big distance · pause
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IgnorePointer(
                  child: _CoinChip(
                    value: gold,
                    multiplier: game.coinMultiplier,
                  ),
                ),
                Expanded(
                  child: IgnorePointer(
                    child: Column(
                      children: [
                        // Hero distance — the Subway score read.
                        Text(
                          runLabel,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFFFFF8E1),
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            letterSpacing: -0.5,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.75),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                              Shadow(
                                color: const Color(0xFFFFB300)
                                    .withValues(alpha: 0.35),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'м',
                          style: TextStyle(
                            color: const Color(0xFFFFE082)
                                .withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            height: 1,
                            shadows: const [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        _ShaftDots(
                          current: shaft,
                          total: shafts,
                          progressInShaft: (game.distance %
                                  GameConfig.corridorSegmentMeters) /
                              GameConfig.corridorSegmentMeters,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          youLead ? 'Ты впереди' : 'Вор впереди',
                          style: TextStyle(
                            color: youLead
                                ? const Color(0xFF81C784)
                                : const Color(0xFFFF8A65),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 3),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Column(
                  children: [
                    Material(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color:
                              const Color(0xFFFFB300).withValues(alpha: 0.45),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _openPauseMenu,
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.pause_rounded,
                            size: 22,
                            color: Color(0xFFFFE082),
                          ),
                        ),
                      ),
                    ),
                    if (game.hasHeart || game.hasPotion) ...[
                      const SizedBox(height: 6),
                      if (game.hasHeart)
                        IgnorePointer(
                          child: _PowerChip(
                            icon: Icons.favorite_rounded,
                            color: const Color(0xFFFF5252),
                            active: true,
                          ),
                        ),
                      if (game.hasHeart && game.hasPotion)
                        const SizedBox(height: 6),
                      if (game.hasPotion)
                        Material(
                          color: Colors.black.withValues(
                            alpha: game.canUsePotion ? 0.5 : 0.28,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: const Color(0xFFAB47BC).withValues(
                                alpha: game.canUsePotion ? 0.9 : 0.35,
                              ),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: game.canUsePotion
                                ? () {
                                    HapticFeedback.mediumImpact();
                                    game.tryUsePotion();
                                  }
                                : null,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(
                                Icons.science_rounded,
                                size: 22,
                                color: Color(0xFFE1BEE7).withValues(
                                  alpha: game.canUsePotion ? 1 : 0.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ],
            ),
            // Crystals on the edges — keep the center path clear.
            const SizedBox(height: 4),
            IgnorePointer(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CrystalScore(
                        asset: _gemYou,
                        value: playerRare,
                        accent: const Color(0xFF4FC3F7),
                        label: 'ты',
                      ),
                      if (game.jewelStreak >= 2) ...[
                        const SizedBox(height: 4),
                        _JewelComboHint(streak: game.jewelStreak),
                      ],
                    ],
                  ),
                  const Spacer(),
                  _CrystalScore(
                    asset: _gemThief,
                    value: thiefRare,
                    accent: const Color(0xFFEF5350),
                    label: 'вор',
                  ),
                ],
              ),
            ),
            if (game.isPotionBoosting) ...[
              const SizedBox(height: 6),
              IgnorePointer(
                child: _toast('Рывок!', const Color(0xFFCE93D8)),
              ),
            ] else if (game.hasMagnetPower) ...[
              const SizedBox(height: 6),
              IgnorePointer(
                child: _toast(
                  'Магнит ${game.magnetPowerSeconds.ceil()}с',
                  const Color(0xFF29B6F6),
                ),
              ),
            ] else if (game.isThiefBursting) ...[
              const SizedBox(height: 6),
              IgnorePointer(
                child: _toast('Вор рванул!', const Color(0xFFEF5350)),
              ),
            ] else if (game.isThiefBreathing) ...[
              const SizedBox(height: 6),
              IgnorePointer(
                child: _toast(
                  'Вор дышит в спину!',
                  const Color(0xFFFF8A65),
                ),
              ),
            ] else if (game.bannerText != null) ...[
              const SizedBox(height: 6),
              IgnorePointer(
                child: _toast(game.bannerText!, game.bannerColor),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatMeters(int m) {
    if (m < 1000) return '$m';
    // 1 247 style — readable mid-run.
    final s = m.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(' ');
    }
    return buf.toString();
  }

  /// Subway-style floating toast — text + shadow only, no pill frame.
  Widget _toast(String text, Color color) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w900,
        fontSize: 16,
        letterSpacing: 0.2,
        height: 1.1,
        shadows: const [
          Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 2)),
          Shadow(color: Colors.black54, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

class _CoinChip extends StatelessWidget {
  const _CoinChip({required this.value, this.multiplier = 1});

  final int value;
  final int multiplier;

  @override
  Widget build(BuildContext context) {
    final hot = multiplier > 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.4),
        border: Border.all(
          color: (hot ? const Color(0xFFFF8F00) : const Color(0xFFFFC107))
              .withValues(alpha: hot ? 0.85 : 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xFFFFF59D), Color(0xFFFFB300)],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$value',
              style: const TextStyle(
                color: Color(0xFFFFE082),
                fontWeight: FontWeight.w900,
                fontSize: 16,
                height: 1,
              ),
            ),
            if (hot) ...[
              const SizedBox(width: 5),
              Text(
                '×$multiplier',
                style: const TextStyle(
                  color: Color(0xFFFF8F00),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  height: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shaft pips — light progress without a heavy slider bar.
class _ShaftDots extends StatelessWidget {
  const _ShaftDots({
    required this.current,
    required this.total,
    required this.progressInShaft,
  });

  final int current;
  final int total;
  final double progressInShaft;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: 5),
          _pip(i),
        ],
      ],
    );
  }

  Widget _pip(int i) {
    final done = i < current;
    final active = i == current;
    final t = progressInShaft.clamp(0.0, 1.0);
    final size = active ? 9.0 : 6.0;
    Color color;
    if (done) {
      color = const Color(0xFFFFB300);
    } else if (active) {
      color = Color.lerp(
        const Color(0xFF5D4037),
        const Color(0xFFFFE082),
        0.35 + t * 0.65,
      )!;
    } else {
      color = Colors.white.withValues(alpha: 0.22);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: active
            ? [
                BoxShadow(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.45),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
    );
  }
}

class _PauseAction extends StatelessWidget {
  const _PauseAction({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: filled
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFB300),
                foregroundColor: const Color(0xFF3E2723),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFE082),
                side: BorderSide(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
    );
  }
}

class _CrystalScore extends StatelessWidget {
  const _CrystalScore({
    required this.asset,
    required this.value,
    required this.accent,
    required this.label,
  });

  final String asset;
  final int value;
  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.38),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              asset,
              width: 20,
              height: 20,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => Icon(
                Icons.diamond_rounded,
                size: 16,
                color: accent,
              ),
            ),
            const SizedBox(width: 5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: accent.withValues(alpha: 0.75),
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$value',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    height: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerChip extends StatelessWidget {
  const _PowerChip({
    required this.icon,
    required this.color,
    required this.active,
  });

  final IconData icon;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: active ? 0.85 : 0.35)),
      ),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

/// Soft crystal-combo read — edge of HUD, no frame, doesn't cover the path.
class _JewelComboHint extends StatelessWidget {
  const _JewelComboHint({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final hot = streak >= 5;
    final color = hot
        ? const Color(0xFFE1F5FE)
        : const Color(0xFF81D4FA);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      child: Text(
        key: ValueKey(streak),
        'комбо ×$streak',
        style: TextStyle(
          color: color.withValues(alpha: hot ? 0.92 : 0.78),
          fontSize: hot ? 13 : 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          height: 1,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 5,
              offset: const Offset(0, 1),
            ),
            Shadow(
              color: const Color(0xFF29B6F6).withValues(alpha: 0.28),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}
