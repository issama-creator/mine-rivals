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
  static const _kControlFeel = 'control_feel'; // legacy string
  static const _kControlSensitivity = 'control_sensitivity';
  static const _kTutorialSeen = 'tutorial_seen';
  static const _kBestDistance = 'best_distance_m';
  static const _kBestRares = 'best_rares';
  static const _kWeekKey = 'weekly_key';
  static const _kWeekProgress = 'weekly_progress';
  static const _kWeekDone = 'weekly_done';
  static const _kTotalWins = 'total_wins';

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

  /// Alternate path — beat a personal distance PB threshold (no streak needed).
  static const Map<int, String> careerDistanceUnlocks = {
    1800: 'ninja',
    2800: 'robot',
    4000: 'monkey',
    5500: 'pingvin',
    7000: 'mag',
  };

  final Set<String> unlockedSkins = {...freeSkins};
  int missionStreak = 0;
  String dailyDayKey = '';
  final Set<String> dailyDoneIds = {};
  final Map<String, int> dailyProgress = {};
  bool tutorialSeen = false;
  int bestDistanceMeters = 0;
  int bestRares = 0;
  int totalWins = 0;
  String weeklyKey = '';
  int weeklyProgress = 0;
  bool weeklyDone = false;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;

    GameSettings.instance.soundEnabled = p.getBool(_kSound) ?? true;
    GameSettings.instance.shakeEnabled = p.getBool(_kShake) ?? true;
    GameSettings.instance.controlSensitivity =
        _loadControlSensitivity(p);
    tutorialSeen = p.getBool(_kTutorialSeen) ?? false;
    bestDistanceMeters = p.getInt(_kBestDistance) ?? 0;
    bestRares = p.getInt(_kBestRares) ?? 0;
    totalWins = p.getInt(_kTotalWins) ?? 0;

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

    _loadWeekly(p);
  }

  static String todayKey() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  /// ISO-ish week key (Mon-based) for weekly challenge rotation.
  static String weekKey() {
    final n = DateTime.now();
    final monday = n.subtract(Duration(days: n.weekday - 1));
    final m = monday.month.toString().padLeft(2, '0');
    final d = monday.day.toString().padLeft(2, '0');
    return '${monday.year}-W$m-$d';
  }

  void _loadWeekly(SharedPreferences p) {
    weeklyKey = weekKey();
    final saved = p.getString(_kWeekKey) ?? '';
    if (saved == weeklyKey) {
      weeklyProgress = p.getInt(_kWeekProgress) ?? 0;
      weeklyDone = p.getBool(_kWeekDone) ?? false;
    } else {
      weeklyProgress = 0;
      weeklyDone = false;
    }
  }

  Future<void> _saveWeekly() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString(_kWeekKey, weeklyKey);
    await p.setInt(_kWeekProgress, weeklyProgress);
    await p.setBool(_kWeekDone, weeklyDone);
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
    await p.setDouble(
      _kControlSensitivity,
      GameSettings.instance.controlSensitivity.clamp(0.0, 1.0),
    );
  }

  Future<void> markTutorialSeen() async {
    tutorialSeen = true;
    await _prefs?.setBool(_kTutorialSeen, true);
  }

  double _loadControlSensitivity(SharedPreferences p) {
    final saved = p.getDouble(_kControlSensitivity);
    if (saved != null) return saved.clamp(0.0, 1.0);
    // Migrate old Плавно/Резко chips.
    switch (p.getString(_kControlFeel)) {
      case 'sharp':
        return 1.0;
      case 'smooth':
        return 0.0;
      default:
        return 0.35;
    }
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

  int _runAdd(
    DailyMissionDef m, {
    required double distance,
    required int gold,
    required int rares,
    required int overtakes,
    required int raresWhileLeading,
    required bool won,
  }) {
    return switch (m.kind) {
      DailyKind.runMeters => distance.round(),
      DailyKind.collectGold => gold,
      DailyKind.collectRares => rares,
      DailyKind.overtakeThief => overtakes,
      DailyKind.raresWhileLeading => raresWhileLeading,
      DailyKind.winRun => won ? 1 : 0,
    };
  }

  int _weeklyAdd(
    WeeklyMissionDef w, {
    required int gold,
    required int rares,
    required int overtakes,
    required int raresWhileLeading,
    required bool won,
  }) {
    return switch (w.kind) {
      DailyKind.runMeters => 0,
      DailyKind.collectGold => gold,
      DailyKind.collectRares => rares,
      DailyKind.overtakeThief => overtakes,
      DailyKind.raresWhileLeading => raresWhileLeading,
      DailyKind.winRun => won ? 1 : 0,
    };
  }

  /// Apply run stats. Returns newly completed mission titles + new skin names.
  Future<({List<String> missions, List<String> skins, bool weekly})>
      applyRunProgress({
    required double distance,
    required int gold,
    required int rares,
    required int overtakes,
    required int raresWhileLeading,
    required bool won,
    required List<DailyMissionDef> missions,
  }) async {
    _rollDayIfNeeded();
    if (weeklyKey != weekKey()) {
      weeklyKey = weekKey();
      weeklyProgress = 0;
      weeklyDone = false;
    }

    if (won) {
      totalWins += 1;
      await _prefs?.setInt(_kTotalWins, totalWins);
    }

    final newly = <String>[];
    for (final m in missions) {
      if (dailyDoneIds.contains(m.id)) continue;
      final prev = dailyProgress[m.id] ?? 0;
      final add = _runAdd(
        m,
        distance: distance,
        gold: gold,
        rares: rares,
        overtakes: overtakes,
        raresWhileLeading: raresWhileLeading,
        won: won,
      );
      final value = (prev + add).clamp(0, m.target);
      dailyProgress[m.id] = value;
      if (value >= m.target) {
        dailyDoneIds.add(m.id);
        newly.add(m.titleRu);
      }
    }

    await _saveDaily();

    var weeklyJust = false;
    final week = WeeklyMissions.forThisWeek();
    if (!weeklyDone) {
      weeklyProgress = (weeklyProgress +
              _weeklyAdd(
                week,
                gold: gold,
                rares: rares,
                overtakes: overtakes,
                raresWhileLeading: raresWhileLeading,
                won: won,
              ))
          .clamp(0, week.target);
      if (weeklyProgress >= week.target) {
        weeklyDone = true;
        weeklyJust = true;
        newly.add('Неделя: ${week.titleRu}');
      }
      await _saveWeekly();
    }

    final skins = <String>[];
    if (_allMissionsDone(missions)) {
      skins.addAll(await _onPerfectDay());
    }
    if (weeklyJust) {
      skins.addAll(await _tryUnlockFromWeekly());
    }

    return (missions: newly, skins: skins, weekly: weeklyJust);
  }

  /// Live peek during a run (no persist).
  List<DailyMissionDef> peekJustCompleted({
    required double distance,
    required int gold,
    required int rares,
    required int overtakes,
    required int raresWhileLeading,
    required bool won,
    required List<DailyMissionDef> missions,
    required Set<String> alreadyToasted,
  }) {
    final out = <DailyMissionDef>[];
    for (final m in missions) {
      if (dailyDoneIds.contains(m.id) || alreadyToasted.contains(m.id)) {
        continue;
      }
      final base = dailyProgress[m.id] ?? 0;
      final add = _runAdd(
        m,
        distance: distance,
        gold: gold,
        rares: rares,
        overtakes: overtakes,
        raresWhileLeading: raresWhileLeading,
        won: won,
      );
      if (base + add >= m.target) out.add(m);
    }
    return out;
  }

  /// Persist personal bests. Returns which records were broken this run.
  /// Memory fields update synchronously so UI can read them before await.
  Future<({bool distance, bool rares, List<String> skins})> considerRecords({
    required int distanceMeters,
    required int rares,
  }) async {
    var beatDistance = false;
    var beatRares = false;
    if (distanceMeters > bestDistanceMeters) {
      bestDistanceMeters = distanceMeters;
      beatDistance = true;
    }
    if (rares > bestRares) {
      bestRares = rares;
      beatRares = true;
    }
    if (beatDistance || beatRares) {
      final p = _prefs;
      if (p != null) {
        await p.setInt(_kBestDistance, bestDistanceMeters);
        await p.setInt(_kBestRares, bestRares);
      }
    }
    final skins = await _tryUnlockFromCareerDistance();
    return (distance: beatDistance, rares: beatRares, skins: skins);
  }

  Future<List<String>> _tryUnlockFromCareerDistance() async {
    final unlockedNow = <String>[];
    for (final e in careerDistanceUnlocks.entries) {
      if (bestDistanceMeters >= e.key && !unlockedSkins.contains(e.value)) {
        unlockedSkins.add(e.value);
        unlockedNow.add(PlayerSkins.byId(e.value).nameRu);
      }
    }
    if (unlockedNow.isNotEmpty) await _saveUnlocks();
    return unlockedNow;
  }

  /// Completing the weekly challenge unlocks the next locked streak skin early.
  Future<List<String>> _tryUnlockFromWeekly() async {
    for (final e in streakUnlocks.entries) {
      if (!unlockedSkins.contains(e.value)) {
        unlockedSkins.add(e.value);
        await _saveUnlocks();
        return [PlayerSkins.byId(e.value).nameRu];
      }
    }
    return const [];
  }

  /// Next career distance unlock hint for menu UI.
  ({int meters, String skinName})? nextCareerUnlock() {
    for (final e in careerDistanceUnlocks.entries) {
      if (!unlockedSkins.contains(e.value)) {
        return (meters: e.key, skinName: PlayerSkins.byId(e.value).nameRu);
      }
    }
    return null;
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
  int liveProgress(
    DailyMissionDef m, {
    required double distance,
    required int gold,
    required int rares,
    int overtakes = 0,
    int raresWhileLeading = 0,
    bool won = false,
  }) {
    final base = progressOf(m.id);
    if (isDone(m.id)) return m.target;
    final add = _runAdd(
      m,
      distance: distance,
      gold: gold,
      rares: rares,
      overtakes: overtakes,
      raresWhileLeading: raresWhileLeading,
      won: won,
    );
    return (base + add).clamp(0, m.target);
  }

  int liveWeeklyProgress({
    required int gold,
    required int rares,
    required int overtakes,
    required int raresWhileLeading,
    required bool won,
  }) {
    final week = WeeklyMissions.forThisWeek();
    if (weeklyDone) return week.target;
    final add = _weeklyAdd(
      week,
      gold: gold,
      rares: rares,
      overtakes: overtakes,
      raresWhileLeading: raresWhileLeading,
      won: won,
    );
    return (weeklyProgress + add).clamp(0, week.target);
  }
}

enum DailyKind {
  runMeters,
  collectGold,
  collectRares,
  overtakeThief,
  raresWhileLeading,
  winRun,
}

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

class WeeklyMissionDef {
  const WeeklyMissionDef({
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
    final overtakeTargets = [2, 3, 3, 4];
    final leadRareTargets = [3, 4, 5, 6];
    final rareTargets = [6, 8, 10, 12];
    final winTargets = [1, 1, 2, 2];
    final meters = meterTargets[seed % meterTargets.length];
    final overtakes = overtakeTargets[(seed ~/ 7) % overtakeTargets.length];
    final leadRares =
        leadRareTargets[(seed ~/ 13) % leadRareTargets.length];
    // Rotating 4th mission — dopamine on rivalry / jewels / finish.
    final bonusRoll = (seed ~/ 19) % 3;
    final DailyMissionDef bonus;
    if (bonusRoll == 0) {
      final wins = winTargets[(seed ~/ 23) % winTargets.length];
      bonus = DailyMissionDef(
        id: 'wins',
        kind: DailyKind.winRun,
        target: wins,
        titleRu: wins == 1 ? 'Выиграй забег у вора' : 'Выиграй $wins забега',
      );
    } else if (bonusRoll == 1) {
      final rares = rareTargets[(seed ~/ 29) % rareTargets.length];
      bonus = DailyMissionDef(
        id: 'rares',
        kind: DailyKind.collectRares,
        target: rares,
        titleRu: 'Собери $rares кристаллов',
      );
    } else {
      bonus = DailyMissionDef(
        id: 'wins',
        kind: DailyKind.winRun,
        target: 1,
        titleRu: 'Финишируй впереди вора',
      );
    }

    return [
      DailyMissionDef(
        id: 'overtakes',
        kind: DailyKind.overtakeThief,
        target: overtakes,
        titleRu: 'Обогнать вора $overtakes раз',
      ),
      DailyMissionDef(
        id: 'lead_rares',
        kind: DailyKind.raresWhileLeading,
        target: leadRares,
        titleRu: 'Кристаллы, пока ты впереди: $leadRares',
      ),
      DailyMissionDef(
        id: 'run',
        kind: DailyKind.runMeters,
        target: meters,
        titleRu: 'Пробеги $meters м',
      ),
      bonus,
    ];
  }

  static String unlockHint(String skinId) {
    String? streak;
    for (final e in ProgressStore.streakUnlocks.entries) {
      if (e.value == skinId) streak = '${e.key} дн.';
    }
    String? career;
    for (final e in ProgressStore.careerDistanceUnlocks.entries) {
      if (e.value == skinId) career = 'рекорд ${e.key} м';
    }
    if (streak != null && career != null) return '$streak или $career';
    return streak ?? career ?? 'Закрыто';
  }
}

/// One hard weekly goal — completes for a skin unlock (next locked).
class WeeklyMissions {
  WeeklyMissions._();

  static WeeklyMissionDef forThisWeek() {
    final key = ProgressStore.weekKey();
    final seed = key.hashCode & 0x7fffffff;
    final roll = seed % 4;
    switch (roll) {
      case 0:
        final n = [8, 10, 12, 14][(seed ~/ 5) % 4];
        return WeeklyMissionDef(
          id: 'w_overtakes',
          kind: DailyKind.overtakeThief,
          target: n,
          titleRu: 'Обгони вора $n раз за неделю',
        );
      case 1:
        final n = [12, 15, 18, 20][(seed ~/ 7) % 4];
        return WeeklyMissionDef(
          id: 'w_lead',
          kind: DailyKind.raresWhileLeading,
          target: n,
          titleRu: 'Кристаллы впереди: $n за неделю',
        );
      case 2:
        final n = [3, 4, 5, 5][(seed ~/ 11) % 4];
        return WeeklyMissionDef(
          id: 'w_wins',
          kind: DailyKind.winRun,
          target: n,
          titleRu: 'Выиграй $n забегов на этой неделе',
        );
      default:
        final n = [25, 30, 35, 40][(seed ~/ 13) % 4];
        return WeeklyMissionDef(
          id: 'w_rares',
          kind: DailyKind.collectRares,
          target: n,
          titleRu: 'Собери $n кристаллов за неделю',
        );
    }
  }
}
