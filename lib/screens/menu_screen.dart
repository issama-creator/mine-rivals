import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/mine_rivals_game.dart';
import '../game/player_skins.dart';
import '../systems/game_settings.dart';
import '../systems/progress_store.dart';
import '../systems/shop_catalog.dart';
import '../ui/game_loading_screen.dart';
import '../ui/hud_overlay.dart';
import '../ui/biome_transition_overlay.dart';
import '../ui/checkpoint_overlay.dart';
import '../ui/countdown_overlay.dart';
import '../ui/results_overlay.dart';
import '../ui/shop_sheet.dart';
import '../ui/tutorial_overlay.dart';

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
    // No AssetLibrary warm-up on menu — heavy decode caused ANR.
    // GameScreen / loadingBuilder loads assets when a run starts.
  }

  @override
  void dispose() {
    _glow.dispose();
    _enter.dispose();
    super.dispose();
  }

  void _startGame() {
    HapticFeedback.mediumImpact();
    // Opaque + short fade — a long fade kept the menu under a stuck loader.
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => const GameScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
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
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _SkinPickerSheet(),
    ).then((result) {
      if (!mounted) return;
      setState(() {});
      if (result == 'shop') _openShop();
    });
  }

  void _openShop() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const ShopSheet(),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openMissions() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _DailyMissionsSheet(),
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
          // Full-bleed mine tunnel (decode at screen width — full PNG is ~1.8MB)
          Image.asset(
            'assets/tunnel.png',
            fit: BoxFit.cover,
            cacheWidth: (MediaQuery.sizeOf(context).width *
                    MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(480, 1440),
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
                  FadeTransition(
                    opacity: fade,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PlayerMetaChip(onWalletTap: _openShop),
                            const SizedBox(height: 8),
                            _MissionSticker(onTap: _openMissions),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _openSettings,
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.35),
                            foregroundColor: const Color(0xFFFFE082),
                          ),
                          icon: const Icon(Icons.settings_rounded),
                        ),
                      ],
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
                            'Забери банк — или рискни\nи потеряй всё!',
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
                          _LocalRecordsStrip(),
                          const SizedBox(height: 12),
                          _RunModePicker(
                            selected: GameSettings.instance.runMode,
                            onChanged: (mode) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                GameSettings.instance.runMode = mode;
                              });
                            },
                          ),
                          const SizedBox(height: 14),
                          _MenuButton(
                            label: 'НАЧАТЬ ИГРУ',
                            icon: Icons.play_arrow_rounded,
                            filled: true,
                            onTap: _startGame,
                          ),
                          const SizedBox(height: 12),
                          _MenuButton(
                            label: 'МАГАЗИН',
                            icon: Icons.storefront_rounded,
                            filled: false,
                            onTap: _openShop,
                          ),
                          const SizedBox(height: 12),
                          _MenuButton(
                            label: 'ПЕРСОНАЖИ',
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

class _RunModePicker extends StatelessWidget {
  const _RunModePicker({
    required this.selected,
    required this.onChanged,
  });

  final RunMode selected;
  final ValueChanged<RunMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'РЕЖИМ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final mode in RunMode.values) ...[
              if (mode != RunMode.values.first) const SizedBox(width: 10),
              Expanded(
                child: _ModeChip(
                  mode: mode,
                  selected: selected == mode,
                  onTap: () => onChanged(mode),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final RunMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final record = ProgressStore.instance.bestDistanceFor(mode);
    final recordLine = record > 0
        ? '${mode.blurbRu} · $record м'
        : mode.blurbRu;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? const Color(0xFFFFB300).withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.32),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFCA28)
                  : Colors.white.withValues(alpha: 0.12),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                mode.titleRu,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFFFE082)
                      : Colors.white.withValues(alpha: 0.78),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                recordLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFFFE082).withValues(alpha: 0.75)
                      : Colors.white.withValues(alpha: 0.42),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
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
                  'Подстрой звук, эффекты и управление',
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
                  onChanged: (v) {
                    setState(() => settings.soundEnabled = v);
                    unawaited(ProgressStore.instance.saveSettings());
                  },
                ),
                const SizedBox(height: 10),
                _SettingTile(
                  icon: Icons.vibration,
                  title: 'Тряска экрана',
                  subtitle: 'При попадании в бомбу',
                  value: settings.shakeEnabled,
                  onChanged: (v) {
                    setState(() => settings.shakeEnabled = v);
                    unawaited(ProgressStore.instance.saveSettings());
                  },
                ),
                const SizedBox(height: 10),
                _ControlSensitivityTile(
                  value: settings.controlSensitivity,
                  onChanged: (v) {
                    setState(() => settings.controlSensitivity = v);
                  },
                  onChangeEnd: (v) {
                    settings.controlSensitivity = v;
                    unawaited(ProgressStore.instance.saveSettings());
                  },
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

class _ControlSensitivityTile extends StatelessWidget {
  const _ControlSensitivityTile({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  String get _label {
    if (value < 0.2) return 'Очень плавно';
    if (value < 0.4) return 'Плавно';
    if (value < 0.7) return 'Нормально';
    return 'Резко';
  }

  String get _valueText =>
      value.clamp(0.0, 1.0).toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swipe_rounded, color: Color(0xFFFFE082)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Чувствительность',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_label · $_valueText',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _valueText,
                style: const TextStyle(
                  color: Color(0xFFFFE082),
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFFFFB300),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              thumbColor: const Color(0xFFFFE082),
              overlayColor: const Color(0xFFFFB300).withValues(alpha: 0.18),
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              divisions: 20,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
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

  @override
  void initState() {
    super.initState();
    _selected = GameSettings.instance.selectedSkinId;
  }

  void _pick(PlayerSkin skin) {
    HapticFeedback.selectionClick();
    setState(() => _selected = skin.id);
    if (!ProgressStore.instance.isSkinUnlocked(skin.id)) {
      HapticFeedback.heavyImpact();
      return;
    }
    unawaited(ProgressStore.instance.selectSkin(skin.id));
  }

  @override
  Widget build(BuildContext context) {
    final skin = PlayerSkins.byId(_selected);
    final unlocked = ProgressStore.instance.isSkinUnlocked(skin.id);
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
            height: h * 0.68,
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
                    'Выбери персонажа',
                    style: TextStyle(
                      color: Color(0xFFFFE082),
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    unlocked
                        ? skin.nameRu
                        : '${skin.nameRu} · ${_skinLockHint(skin.id)}',
                    style: TextStyle(
                      color: unlocked ? skin.accent : Colors.white54,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: PlayerSkins.all.length,
                      itemBuilder: (context, i) {
                        final s = PlayerSkins.all[i];
                        final open =
                            ProgressStore.instance.isSkinUnlocked(s.id);
                        final on = s.id == _selected;
                        final borderColor = on && open
                            ? s.accent
                            : s.accent.withValues(alpha: open ? 0.4 : 0.22);

                        return Material(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _pick(s),
                            child: Ink(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: borderColor,
                                  width: on ? 2.2 : 1.3,
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      8,
                                      10,
                                      8,
                                      8,
                                    ),
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: Opacity(
                                            opacity: open ? 1 : 0.3,
                                            child: Image.asset(
                                              s.previewAsset,
                                              fit: BoxFit.contain,
                                              filterQuality: FilterQuality.high,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(
                                                Icons.person_rounded,
                                                size: 56,
                                                color: s.accent,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          s.nameRu,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: open
                                                ? (on
                                                    ? s.accent
                                                    : Colors.white70)
                                                : Colors.white54,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (!open)
                                          Text(
                                            _skinLockHint(s.id),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: const Color(0xFFFFE082)
                                                  .withValues(alpha: 0.8),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 10,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (!open)
                                    const Icon(
                                      Icons.lock_rounded,
                                      color: Color(0xFFFFE082),
                                      size: 28,
                                    ),
                                  if (on && open)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: s.accent,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'ON',
                                          style: TextStyle(
                                            color: Color(0xFF1A100A),
                                            fontWeight: FontWeight.w900,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
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
                      onPressed: () => Navigator.pop(
                        context,
                        unlocked ? null : 'shop',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: unlocked
                            ? const Color(0xFFFFB300)
                            : const Color(0xFF4FC3F7),
                        foregroundColor: unlocked
                            ? const Color(0xFF3E2723)
                            : const Color(0xFF0D47A1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        unlocked ? 'Готово' : 'В магазин',
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
    );
  }
}

String _skinLockHint(String skinId) {
  final price = ShopCatalog.skinPrice(skinId);
  if (price != null) return 'Замок · $price ◆';
  return DailyMissions.unlockHint(skinId);
}

/// Top-left: level + wallet (tap wallet → shop).
class _PlayerMetaChip extends StatelessWidget {
  const _PlayerMetaChip({required this.onWalletTap});

  final VoidCallback onWalletTap;

  static const _gemAsset = 'assets/images/items/diamond.png';

  @override
  Widget build(BuildContext context) {
    final store = ProgressStore.instance;
    final lvl = store.minerLevel;
    final wallet = store.crystalBalance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ур. $lvl · ${store.minerTitle}',
          style: TextStyle(
            color: const Color(0xFFFFCA28).withValues(alpha: 0.95),
            fontSize: 13,
            fontWeight: FontWeight.w900,
            shadows: const [
              Shadow(color: Colors.black87, blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onWalletTap,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0277BD).withValues(alpha: 0.42),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFF4FC3F7).withValues(alpha: 0.7),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      _gemAsset,
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.diamond_rounded,
                        size: 18,
                        color: Color(0xFF4FC3F7),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '$wallet',
                      style: const TextStyle(
                        color: Color(0xFFE1F5FE),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'кошелёк',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalRecordsStrip extends StatelessWidget {
  const _LocalRecordsStrip();

  @override
  Widget build(BuildContext context) {
    final store = ProgressStore.instance;
    final dist = store.bestDistanceMeters;
    final rares = store.bestRares;
    final record = dist <= 0 && rares <= 0
        ? 'Рекорд появится после первого забега'
        : 'Рекорд: $dist м · $rares крист.';
    return Text(
      record,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: const Color(0xFFFFE082).withValues(alpha: 0.85),
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

/// Top-left daily missions sticker with unread/remaining badge.
class _MissionSticker extends StatelessWidget {
  const _MissionSticker({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final missions = DailyMissions.forToday();
    final store = ProgressStore.instance;
    final left = missions.where((m) => !store.isDone(m.id)).length;
    final allDone = left == 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.black.withValues(alpha: 0.4),
            border: Border.all(
              color: (allDone
                      ? const Color(0xFF81C784)
                      : const Color(0xFFFFB300))
                  .withValues(alpha: 0.75),
              width: 1.4,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  allDone ? Icons.check_rounded : Icons.flag_rounded,
                  size: 20,
                  color: allDone
                      ? const Color(0xFF81C784)
                      : const Color(0xFFFFE082),
                ),
                const SizedBox(width: 6),
                Text(
                  'Задания',
                  style: TextStyle(
                    color: allDone
                        ? const Color(0xFF81C784)
                        : const Color(0xFFFFE082),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                if (!allDone) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE53935),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$left',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyMissionsSheet extends StatelessWidget {
  const _DailyMissionsSheet();

  @override
  Widget build(BuildContext context) {
    final store = ProgressStore.instance;
    final missions = DailyMissions.forToday();
    final doneCount = missions.where((m) => store.isDone(m.id)).length;
    final streakGoal = store.nextStreakUnlock();
    final prizeName = streakGoal?.skinName ?? 'скин';
    final day = store.missionStreak.clamp(0, streakGoal?.atStreak ?? 7);
    final need = streakGoal?.atStreak ?? 7;

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
                  'Задания',
                  style: TextStyle(
                    color: Color(0xFFFFE082),
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 12),
                // One prize block — like Subway challenge reward.
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFFFFB300).withValues(alpha: 0.12),
                    border: Border.all(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.card_giftcard_rounded,
                          color: Color(0xFFFFE082),
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prizeName,
                                style: const TextStyle(
                                  color: Color(0xFFFFE082),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                streakGoal == null
                                    ? 'Все скины открыты'
                                    : 'Закрой все задания $need дней подряд',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (streakGoal != null)
                          Text(
                            '$day/$need',
                            style: const TextStyle(
                              color: Color(0xFFFFB300),
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Сегодня  $doneCount/${missions.length}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final m in missions) ...[
                  _MissionRow(mission: m),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'На неделе',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const _WeeklyMissionRow(),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB300),
                      foregroundColor: const Color(0xFF3E2723),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Понятно',
                      style: TextStyle(fontWeight: FontWeight.w900),
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

class _WeeklyMissionRow extends StatelessWidget {
  const _WeeklyMissionRow();

  @override
  Widget build(BuildContext context) {
    final store = ProgressStore.instance;
    final week = WeeklyMissions.forThisWeek();
    final done = store.weeklyDone;
    final prog = store.weeklyProgress.clamp(0, week.target);
    final t = done ? 1.0 : prog / week.target;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(
          color: done
              ? const Color(0xFF81C784).withValues(alpha: 0.7)
              : const Color(0xFFFFB300).withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              color: done
                  ? const Color(0xFF81C784)
                  : const Color(0xFFFFE082).withValues(alpha: 0.55),
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    week.titleRu,
                    style: TextStyle(
                      color: done
                          ? const Color(0xFF81C784)
                          : Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: t,
                      minHeight: 7,
                      backgroundColor: Colors.white12,
                      color: done
                          ? const Color(0xFF81C784)
                          : const Color(0xFFFFB300),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              done ? '✓' : '$prog/${week.target}',
              style: TextStyle(
                color: done
                    ? const Color(0xFF81C784)
                    : const Color(0xFFFFE082),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({required this.mission});

  final DailyMissionDef mission;

  @override
  Widget build(BuildContext context) {
    final store = ProgressStore.instance;
    final done = store.isDone(mission.id);
    final prog = store.progressOf(mission.id).clamp(0, mission.target);
    final t = done ? 1.0 : prog / mission.target;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(
          color: done
              ? const Color(0xFF81C784).withValues(alpha: 0.7)
              : const Color(0xFFFFB300).withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              color: done
                  ? const Color(0xFF81C784)
                  : const Color(0xFFFFE082).withValues(alpha: 0.55),
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mission.titleRu,
                    style: TextStyle(
                      color: done
                          ? const Color(0xFF81C784)
                          : Colors.white.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: t,
                      minHeight: 7,
                      backgroundColor: Colors.white12,
                      color: done
                          ? const Color(0xFF81C784)
                          : const Color(0xFFFFB300),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              done ? '✓' : '$prog/${mission.target}',
              style: TextStyle(
                color: done
                    ? const Color(0xFF81C784)
                    : const Color(0xFFFFE082),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
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
          'tutorial': (context, MineRivalsGame g) => TutorialOverlay(game: g),
          'checkpoint': (context, MineRivalsGame g) =>
              CheckpointOverlay(game: g),
          'biome': (context, MineRivalsGame g) =>
              BiomeTransitionOverlay(game: g),
          'countdown': (context, MineRivalsGame g) =>
              CountdownOverlay(game: g),
        },
        initialActiveOverlays: const ['hud'],
      ),
    );
  }
}
