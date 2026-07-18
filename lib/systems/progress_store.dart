import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/player_skins.dart';
import 'game_settings.dart';

/// Persisted unlocks, daily mission state, and settings.
class ProgressStore {
  ProgressStore._();
  static final ProgressStore instance = ProgressStore._();

  static const _kSkin = 'selected_skin';
  static const _kUnlocked = 'unlocked_skins';
  static const _kDayKey = 'daily_day';
  static const _kDone = 'daily_done';
  static const _kProgress = 'daily_progress';
  static const _kStreak = 'mission_streak';
  static const _kLastPerfect = 'last_perfect_day';
  static const _kSound = 'sound_enabled';
  static const _kShake = 'shake_enabled';

  SharedPreferences? _prefs;

  /// Free skins — always available.
  static const Set<String> freeSkins = {'player', 'woman'};

  /// Consecutive perfect-mission days → unlock that skin.
  static const Map<int, String> streakUnlocks = {
    7: 'ninja',
    14: 'robot',
    21: 'monkey',
    28: 'pingvin',
    35: 'mag',
  };

  final Set<String> unlockedSkins = {...freeSkins};
  int missionStreak = 0;
  String dailyDayKey = '';
  final Set<String> dailyDoneIds = {};
  final Map<String, int> dailyProgress = {};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;

    GameSettings.instance.soundEnabled = p.getBool(_kSound) ?? true;
    GameSettings.instance.shakeEnabled = p.getBool(_kShake) ?? true;

    unlockedSkins
      ..clear()
      ..addAll(freeSkins);
    final saved = p.getStringList(_kUnlocked) ?? const [];
    unlockedSkins.addAll(saved);

    missionStreak = p.getInt(_kStreak) ?? 0;

    var skin = p.getString(_kSkin) ?? PlayerSkins.defaultId;
    if (!unlockedSkins.contains(skin)) skin = PlayerSkins.defaultId;
    GameSettings.instance.selectedSkinId = skin;

    dailyDayKey = todayKey();
    final day = p.getString(_kDayKey) ?? '';
    if (day == dailyDayKey) {
      dailyDoneIds
        ..clear()
        ..addAll(p.getStringList(_kDone) ?? const []);
      final raw = p.getString(_kProgress);
      dailyProgress.clear();
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        map.forEach((k, v) => dailyProgress[k] = (v as num).toInt());
      }
    } else {
      dailyDoneIds.clear();
      dailyProgress.clear();
      await _saveDaily();
    }
  }

  static String todayKey() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  bool isSkinUnlocked(String id) => unlockedSkins.contains(id);

  Future<void> selectSkin(String id) async {
    if (!isSkinUnlocked(id)) return;
    GameSettings.instance.selectedSkinId = id;
    await _prefs?.setString(_kSkin, id);
  }

  Future<void> saveSettings() async {
    final p = _prefs;
    if (p == null) return;
    await p.setBool(_kSound, GameSettings.instance.soundEnabled);
    await p.setBool(_kShake, GameSettings.instance.shakeEnabled);
  }

  Future<void> _saveUnlocks() async {
    await _prefs?.setStringList(_kUnlocked, unlockedSkins.toList());
  }

  Future<void> _saveDaily() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString(_kDayKey, dailyDayKey);
    await p.setStringList(_kDone, dailyDoneIds.toList());
    await p.setString(_kProgress, jsonEncode(dailyProgress));
    await p.setInt(_kStreak, missionStreak);
  }

  void _rollDayIfNeeded() {
    final today = todayKey();
    if (dailyDayKey == today) return;
    dailyDayKey = today;
    dailyDoneIds.clear();
    dailyProgress.clear();
  }

  /// Apply run stats. Returns newly completed mission titles + new skin names.
  Future<({List<String> missions, List<String> skins})> applyRunProgress({
    required double distance,
    required int gold,
    required int rares,
    required List<DailyMissionDef> missions,
  }) async {
    _rollDayIfNeeded();

    final newly = <String>[];
    for (final m in missions) {
      if (dailyDoneIds.contains(m.id)) continue;
      final prev = dailyProgress[m.id] ?? 0;
      final add = switch (m.kind) {
        DailyKind.runMeters => distance.round(),
        DailyKind.collectGold => gold,
        DailyKind.collectRares => rares,
      };
      final value = (prev + add).clamp(0, m.target);
      dailyProgress[m.id] = value;
      if (value >= m.target) {
        dailyDoneIds.add(m.id);
        newly.add(m.titleRu);
      }
    }

    await _saveDaily();

    final skins = <String>[];
    if (_allMissionsDone(missions)) {
      skins.addAll(await _onPerfectDay());
    }

    return (missions: newly, skins: skins);
  }

  /// Live peek during a run (no persist).
  List<DailyMissionDef> peekJustCompleted({
    required double distance,
    required int gold,
    required int rares,
    required List<DailyMissionDef> missions,
    required Set<String> alreadyToasted,
  }) {
    final out = <DailyMissionDef>[];
    for (final m in missions) {
      if (dailyDoneIds.contains(m.id) || alreadyToasted.contains(m.id)) {
        continue;
      }
      final base = dailyProgress[m.id] ?? 0;
      final add = switch (m.kind) {
        DailyKind.runMeters => distance.round(),
        DailyKind.collectGold => gold,
        DailyKind.collectRares => rares,
      };
      if (base + add >= m.target) out.add(m);
    }
    return out;
  }

  bool _allMissionsDone(List<DailyMissionDef> missions) {
    for (final m in missions) {
      if (!dailyDoneIds.contains(m.id)) return false;
    }
    return missions.isNotEmpty;
  }

  Future<List<String>> _onPerfectDay() async {
    final p = _prefs;
    if (p == null) return const [];
    final last = p.getString(_kLastPerfect) ?? '';
    if (last == dailyDayKey) return const [];

    final yesterday = _dayOffset(-1);
    if (last == yesterday) {
      missionStreak += 1;
    } else {
      missionStreak = 1;
    }
    await p.setString(_kLastPerfect, dailyDayKey);
    await p.setInt(_kStreak, missionStreak);

    final unlockedNow = <String>[];
    for (final e in streakUnlocks.entries) {
      if (missionStreak >= e.key && !unlockedSkins.contains(e.value)) {
        unlockedSkins.add(e.value);
        unlockedNow.add(PlayerSkins.byId(e.value).nameRu);
      }
    }
    if (unlockedNow.isNotEmpty) await _saveUnlocks();
    return unlockedNow;
  }

  static String _dayOffset(int days) {
    final n = DateTime.now().add(Duration(days: days));
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  int progressOf(String id) => dailyProgress[id] ?? 0;

  bool isDone(String id) => dailyDoneIds.contains(id);

  /// Effective progress including the current run (for UI).
  int liveProgress(DailyMissionDef m, {required double distance, required int gold, required int rares}) {
    final base = progressOf(m.id);
    if (isDone(m.id)) return m.target;
    final add = switch (m.kind) {
      DailyKind.runMeters => distance.round(),
      DailyKind.collectGold => gold,
      DailyKind.collectRares => rares,
    };
    return (base + add).clamp(0, m.target);
  }
}

enum DailyKind { runMeters, collectGold, collectRares }

class DailyMissionDef {
  const DailyMissionDef({
    required this.id,
    required this.kind,
    required this.target,
    required this.titleRu,
  });

  final String id;
  final DailyKind kind;
  final int target;
  final String titleRu;
}

/// Deterministic daily set from the calendar date.
class DailyMissions {
  DailyMissions._();

  static List<DailyMissionDef> forToday() {
    final key = ProgressStore.todayKey();
    final seed = key.hashCode & 0x7fffffff;
    final meterTargets = [1200, 1500, 1800, 2000];
    final goldTargets = [40, 55, 70, 90];
    final rareTargets = [4, 6, 8, 10];
    final meters = meterTargets[seed % meterTargets.length];
    final gold = goldTargets[(seed ~/ 7) % goldTargets.length];
    final rares = rareTargets[(seed ~/ 13) % rareTargets.length];
    return [
      DailyMissionDef(
        id: 'run',
        kind: DailyKind.runMeters,
        target: meters,
        titleRu: 'Пробеги $meters м',
      ),
      DailyMissionDef(
        id: 'gold',
        kind: DailyKind.collectGold,
        target: gold,
        titleRu: 'Собери $gold монет',
      ),
      DailyMissionDef(
        id: 'rares',
        kind: DailyKind.collectRares,
        target: rares,
        titleRu: 'Поймай $rares кристаллов',
      ),
    ];
  }

  static String unlockHint(String skinId) {
    for (final e in ProgressStore.streakUnlocks.entries) {
      if (e.value == skinId) {
        return '${e.key} дней миссий';
      }
    }
    return 'Закрыто';
  }
}
