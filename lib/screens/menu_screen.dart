import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/mine_rivals_game.dart';
import '../game/player_skins.dart';
import '../systems/game_settings.dart';
import '../ui/game_loading_screen.dart';
import '../ui/hud_overlay.dart';
import '../ui/results_overlay.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen>
    with TickerProviderStateMixin {
  late final AnimationController _glow;
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _glow.dispose();
    _enter.dispose();
    super.dispose();
  }

  void _startGame() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: const GameScreen(),
          );
        },
      ),
    );
  }

  void _openSettings() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _SettingsSheet(),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openSkins() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _SkinPickerSheet(),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final slide = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
    final fade = CurvedAnimation(parent: _enter, curve: Curves.easeOut);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed mine tunnel
          Image.asset(
            'assets/tunnel.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.25),
                  const Color(0xFF1A0E08).withValues(alpha: 0.82),
                  const Color(0xFF0D0704).withValues(alpha: 0.92),
                ],
                stops: const [0, 0.35, 0.72, 1],
              ),
            ),
          ),
          // Warm lantern wash
          AnimatedBuilder(
            animation: _glow,
            builder: (context, _) {
              final t = _glow.value;
              return IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.35),
                      radius: 0.95,
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
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: FadeTransition(
                      opacity: fade,
                      child: IconButton(
                        onPressed: _openSettings,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.35),
                          foregroundColor: const Color(0xFFFFE082),
                        ),
                        icon: const Icon(Icons.settings_rounded),
                      ),
                    ),
                  ),
                  const Spacer(flex: 2),
                  FadeTransition(
                    opacity: fade,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.18),
                        end: Offset.zero,
                      ).animate(slide),
                      child: Column(
                        children: [
                          Text(
                            'MINE',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFFFFE082).withValues(alpha: 0.92),
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 14,
                              height: 1,
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _glow,
                            builder: (context, child) {
                              final glow = 8 + _glow.value * 16;
                              return Text(
                                'RIVALS',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0xFFFFCA28),
                                  fontSize: 58,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                  height: 1.05,
                                  shadows: [
                                    Shadow(
                                      color: const Color(0xFFFFB300)
                                          .withValues(alpha: 0.75),
                                      blurRadius: glow,
                                    ),
                                    const Shadow(
                                      color: Colors.black87,
                                      blurRadius: 12,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Лови цветные камни!\nВор крадёт только их',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 18,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(flex: 3),
                  FadeTransition(
                    opacity: fade,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(slide),
                      child: Column(
                        children: [
                          _MenuButton(
                            label: 'НАЧАТЬ ИГРУ',
                            icon: Icons.play_arrow_rounded,
                            filled: true,
                            onTap: _startGame,
                          ),
                          const SizedBox(height: 12),
                          _MenuButton(
                            label: 'ГЕРОЙ',
                            icon: Icons.person_rounded,
                            filled: false,
                            onTap: _openSkins,
                          ),
                          const SizedBox(height: 12),
                          _MenuButton(
                            label: 'НАСТРОЙКИ',
                            icon: Icons.tune_rounded,
                            filled: false,
                            onTap: _openSettings,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Выбран: ${PlayerSkins.byId(GameSettings.instance.selectedSkinId).nameRu}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color(0xFFFFE082).withValues(alpha: 0.75),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Лови цветные камни — не дай вору!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _MenuButton extends StatelessWidget {
  const _MenuButton({
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
    final radius = BorderRadius.circular(18);
    if (filled) {
      return SizedBox(
        width: double.infinity,
        height: 58,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD54F), Color(0xFFFFB300), Color(0xFFF57C00)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB300).withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: const Color(0xFF3E2723), size: 28),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF3E2723),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: const Color(0xFFFFE082)),
        label: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFFFE082),
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: 1,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: const Color(0xFFFFCA28).withValues(alpha: 0.55),
            width: 1.4,
          ),
          backgroundColor: Colors.black.withValues(alpha: 0.28),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  final settings = GameSettings.instance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3E2723), Color(0xFF1B120C)],
          ),
          border: Border.all(
            color: const Color(0xFFFFB300).withValues(alpha: 0.55),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Настройки',
                  style: TextStyle(
                    color: Color(0xFFFFCA28),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Подстрой звук и эффекты под себя',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 18),
                _SettingTile(
                  icon: Icons.volume_up_rounded,
                  title: 'Звук',
                  subtitle: 'Ловля, бомбы, смена лидера',
                  value: settings.soundEnabled,
                  onChanged: (v) => setState(() => settings.soundEnabled = v),
                ),
                const SizedBox(height: 10),
                _SettingTile(
                  icon: Icons.vibration,
                  title: 'Тряска экрана',
                  subtitle: 'При попадании в бомбу',
                  value: settings.shakeEnabled,
                  onChanged: (v) => setState(() => settings.shakeEnabled = v),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB300),
                      foregroundColor: const Color(0xFF3E2723),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'ГОТОВО',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
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

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: Icon(icon, color: const Color(0xFFFFE082)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
        ),
        value: value,
        activeThumbColor: const Color(0xFF3E2723),
        activeTrackColor: const Color(0xFFFFB300),
        onChanged: onChanged,
      ),
    );
  }
}

class _SkinPickerSheet extends StatefulWidget {
  const _SkinPickerSheet();

  @override
  State<_SkinPickerSheet> createState() => _SkinPickerSheetState();
}

class _SkinPickerSheetState extends State<_SkinPickerSheet> {
  late String _selected;
  late final PageController _page;

  @override
  void initState() {
    super.initState();
    _selected = GameSettings.instance.selectedSkinId;
    final idx = PlayerSkins.all.indexWhere((s) => s.id == _selected);
    _page = PageController(viewportFraction: 0.72, initialPage: idx < 0 ? 0 : idx);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _pick(PlayerSkin skin) {
    HapticFeedback.selectionClick();
    setState(() => _selected = skin.id);
    GameSettings.instance.selectedSkinId = skin.id;
  }

  @override
  Widget build(BuildContext context) {
    final skin = PlayerSkins.byId(_selected);
    final h = MediaQuery.sizeOf(context).height;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
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
          child: SizedBox(
            height: h * 0.62,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
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
                    'Выбери героя',
                    style: TextStyle(
                      color: Color(0xFFFFE082),
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    skin.nameRu,
                    style: TextStyle(
                      color: skin.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: PageView.builder(
                      controller: _page,
                      itemCount: PlayerSkins.all.length,
                      onPageChanged: (i) => _pick(PlayerSkins.all[i]),
                      itemBuilder: (context, i) {
                        final s = PlayerSkins.all[i];
                        final on = s.id == _selected;
                        final borderColor = on
                            ? s.accent
                            : s.accent.withValues(alpha: 0.35);
                        return AnimatedScale(
                          scale: on ? 1 : 0.9,
                          duration: const Duration(milliseconds: 220),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                color: Colors.black.withValues(alpha: 0.35),
                                border: Border.all(
                                  color: borderColor,
                                  width: on ? 2.4 : 1.4,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(22),
                                onTap: () {
                                  _page.animateToPage(
                                    i,
                                    duration: const Duration(milliseconds: 280),
                                    curve: Curves.easeOutCubic,
                                  );
                                  _pick(s);
                                },
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          16,
                                          12,
                                          4,
                                        ),
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            final side = constraints
                                                .biggest
                                                .shortestSide;
                                            return Center(
                                              child: SizedBox(
                                                width: side,
                                                height: side,
                                                child: Image.asset(
                                                  s.previewAsset,
                                                  fit: BoxFit.contain,
                                                  alignment: Alignment.center,
                                                  filterQuality:
                                                      FilterQuality.high,
                                                  errorBuilder:
                                                      (_, __, ___) => Icon(
                                                    Icons.person_rounded,
                                                    size: 96,
                                                    color: s.accent
                                                        .withValues(alpha: 0.7),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 14),
                                      child: Text(
                                        s.nameRu,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: on
                                              ? s.accent
                                              : Colors.white70,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB300),
                        foregroundColor: const Color(0xFF3E2723),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Выбрать',
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
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final MineRivalsGame game;

  @override
  void initState() {
    super.initState();
    game = MineRivalsGame(
      onQuitToMenu: () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const MenuScreen(),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A120B),
      body: GameWidget(
        game: game,
        loadingBuilder: (_) => const GameLoadingScreen(),
        overlayBuilderMap: {
          'hud': (context, MineRivalsGame g) => HudOverlay(game: g),
          'results': (context, MineRivalsGame g) => ResultsOverlay(game: g),
        },
        initialActiveOverlays: const ['hud'],
      ),
    );
  }
}
