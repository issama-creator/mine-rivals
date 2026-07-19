import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/player_skins.dart';
import 'game_settings.dart';
import 'shop_catalog.dart';

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
  static const _kBestDistanceStandard = 'best_distance_standard_m';
  static const _kBestDistanceLong = 'best_distance_long_m';
  static const _kBestRares = 'best_rares';
  static const _kWeekKey = 'weekly_key';
  static const _kWeekProgress = 'weekly_progress';
  static const _kWeekDone = 'weekly_done';
  static const _kTotalWins = 'total_wins';
  static const _kMinerXp = 'miner_xp';
  static const _kWeekBestDist = 'week_best_distance_m';
  static const _kTotalRuns = 'total_runs';
  static const _kCrystals = 'crystal_wallet';
  static const _kStockHearts = 'stock_hearts';
  static const _kStockPotions = 'stock_potions';

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
  /// Best of either mode — career unlocks / menu strip.
  int bestDistanceMeters = 0;
  int bestDistanceStandard = 0;
  int bestDistanceLong = 0;
  int bestRares = 0;
  int totalWins = 0;
  int totalRuns = 0;
  int minerXp = 0;
  String weeklyKey = '';
  int weeklyProgress = 0;
  bool weeklyDone = false;
  int weekBestDistanceMeters = 0;

  /// Spendable crystals banked from runs (shop currency).
  int crystalBalance = 0;
  /// Consumables for the next run(s).
  int stockHearts = 0;
  int stockPotions = 0;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;

    GameSettings.instance.soundEnabled = p.getBool(_kSound) ?? true;
    GameSettings.instance.shakeEnabled = p.getBool(_kShake) ?? true;
    GameSettings.instance.controlSensitivity =
        _loadControlSensitivity(p);
    tutorialSeen = p.getBool(_kTutorialSeen) ?? false;
    bestDistanceMeters = p.getInt(_kBestDistance) ?? 0;
    bestDistanceStandard =
        p.getInt(_kBestDistanceStandard) ?? bestDistanceMeters;
    bestDistanceLong = p.getInt(_kBestDistanceLong) ?? 0;
    // Migrate legacy single best into standard if mode bests empty.
    if (bestDistanceStandard <= 0 && bestDistanceMeters > 0) {
      bestDistanceStandard = bestDistanceMeters;
    }
    if (bestDistanceStandard > bestDistanceMeters) {
      bestDistanceMeters = bestDistanceStandard;
    }
    if (bestDistanceLong > bestDistanceMeters) {
      bestDistanceMeters = bestDistanceLong;
    }
    bestRares = p.getInt(_kBestRares) ?? 0;
    totalWins = p.getInt(_kTotalWins) ?? 0;
    totalRuns = p.getInt(_kTotalRuns) ?? 0;
    minerXp = p.getInt(_kMinerXp) ?? 0;

    if (!p.containsKey(_kCrystals)) {
      crystalBalance = ShopCatalog.starterCrystals;
      await p.setInt(_kCrystals, crystalBalance);
    } else {
      crystalBalance = p.getInt(_kCrystals) ?? 0;
    }
    stockHearts = (p.getInt(_kStockHearts) ?? 0).clamp(0, ShopCatalog.maxStockHearts);
    stockPotions =
        (p.getInt(_kStockPotions) ?? 0).clamp(0, ShopCatalog.maxStockPotions);

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
      weekBestDistanceMeters = p.getInt(_kWeekBestDist) ?? 0;
    } else {
      weeklyProgress = 0;
      weeklyDone = false;
      weekBestDistanceMeters = 0;
    }
  }

  Future<void> _saveWeekly() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString(_kWeekKey, weeklyKey);
    await p.setInt(_kWeekProgress, weeklyProgress);
    await p.setBool(_kWeekDone, weeklyDone);
    await p.setInt(_kWeekBestDist, weekBestDistanceMeters);
  }

  /// Sat/Sun — ×2 crystals while leading (freshness event, no server).
  static bool get weekendEventActive {
    final wd = DateTime.now().weekday;
    return wd == DateTime.saturday || wd == DateTime.sunday;
  }

  static int get weekendLeadRareMult => weekendEventActive ? 2 : 1;

  /// Days left in the Mon–Sun week (1 = last day).
  static int daysLeftInWeek() {
    final left = 8 - DateTime.now().weekday;
    return left.clamp(1, 7);
  }

  /// Miner level from XP — soft endless progression.
  int get minerLevel {
    var lvl = 1;
    var need = 40;
    var xp = minerXp;
    while (xp >= need && lvl < 50) {
      xp -= need;
      lvl++;
      need = 40 + (lvl - 1) * 18;
    }
    return lvl;
  }

  int get minerXpIntoLevel {
    var need = 40;
    var xp = minerXp;
    var lvl = 1;
    while (xp >= need && lvl < 50) {
      xp -= need;
      lvl++;
      need = 40 + (lvl - 1) * 18;
    }
    return xp;
  }

  int get minerXpForNextLevel {
    final lvl = minerLevel;
    return 40 + (lvl - 1) * 18;
  }

  String get minerTitle {
    final l = minerLevel;
    if (l >= 40) return 'Легенда шахты';
    if (l >= 30) return 'Мастер гонки';
    if (l >= 20) return 'Охотник за вором';
    if (l >= 12) return 'Бывалый шахтёр';
    if (l >= 6) return 'Подмастерье';
    return 'Новичок';
  }

  /// Next streak skin FOMO — “2 дн. → Ниндзя”.
  ({int daysLeft, int atStreak, String skinName})? nextStreakUnlock() {
    for (final e in streakUnlocks.entries) {
      if (!unlockedSkins.contains(e.value)) {
        final left = (e.key - missionStreak).clamp(0, 99);
        return (
          daysLeft: left,
          atStreak: e.key,
          skinName: PlayerSkins.byId(e.value).nameRu,
        );
      }
    }
    return null;
  }

  /// Closest incomplete daily — “ещё 1 обгон до миссии”.
  String? nextDailyHook() {
    for (final m in DailyMissions.forToday()) {
      if (isDone(m.id)) continue;
      final left = (m.target - progressOf(m.id)).clamp(1, m.target);
      switch (m.kind) {
        case DailyKind.overtakeThief:
          return left == 1
              ? 'Ещё 1 обгон до миссии'
              : 'Ещё $left обгона до миссии';
        case DailyKind.raresWhileLeading:
          return 'Ещё $left крист. впереди до миссии';
        case DailyKind.runMeters:
          return 'Ещё $left м до миссии';
        case DailyKind.collectRares:
          return 'Ещё $left крист. до миссии';
        case DailyKind.winRun:
          return left == 1
              ? 'Выиграй ещё 1 забег'
              : 'Выиграй ещё $left забега';
        case DailyKind.collectGold:
          return 'Ещё $left монет до миссии';
      }
    }
    return null;
  }

  /// Primary comeback line for results / menu.
  String comebackHook() {
    final daily = nextDailyHook();
    if (daily != null) return daily;
    if (!weeklyDone) {
      final week = WeeklyMissions.forThisWeek();
      final left = (week.target - weeklyProgress).clamp(1, week.target);
      final days = daysLeftInWeek();
      return 'Неделя: ещё $left · осталось $days дн.';
    }
    final streak = nextStreakUnlock();
    if (streak != null) {
      if (streak.daysLeft <= 0) {
        return 'Закрой миссии сегодня → ${streak.skinName}';
      }
      return '${streak.daysLeft} дн. серии → ${streak.skinName}';
    }
    final career = nextCareerUnlock();
    if (career != null) {
      return 'Рекорд ${career.meters} м → ${career.skinName}';
    }
    return 'Новый рекорд — брось вызов себе';
  }

  bool isSkinUnlocked(String id) => unlockedSkins.contains(id);

  Future<void> selectSkin(String id) async {
    if (!isSkinUnlocked(id)) return;
    GameSettings.instance.selectedSkinId = id;
    await _prefs?.setString(_kSkin, id);
  }

  Future<void> _saveWallet() async {
    final p = _prefs;
    if (p == null) return;
    await p.setInt(_kCrystals, crystalBalance);
    await p.setInt(_kStockHearts, stockHearts);
    await p.setInt(_kStockPotions, stockPotions);
  }

  /// Bank crystals only on cash-out (checkpoint / series clear). Risk loss = 0.
  Future<int> bankRunCrystals({
    required int rares,
    required bool cashOut,
  }) async {
    if (!cashOut || rares <= 0) return 0;
    crystalBalance += rares;
    await _saveWallet();
    return rares;
  }

  Future<bool> buyHeart() async {
    if (crystalBalance < ShopCatalog.heartPrice) return false;
    if (stockHearts >= ShopCatalog.maxStockHearts) return false;
    crystalBalance -= ShopCatalog.heartPrice;
    stockHearts += 1;
    await _saveWallet();
    return true;
  }

  Future<bool> buyPotion() async {
    if (crystalBalance < ShopCatalog.potionPrice) return false;
    if (stockPotions >= ShopCatalog.maxStockPotions) return false;
    crystalBalance -= ShopCatalog.potionPrice;
    stockPotions += 1;
    await _saveWallet();
    return true;
  }

  Future<bool> buySkin(String id) async {
    final price = ShopCatalog.skinPrice(id);
    if (price == null) return false;
    if (isSkinUnlocked(id)) return false;
    if (crystalBalance < price) return false;
    crystalBalance -= price;
    unlockedSkins.add(id);
    await _saveUnlocks();
    await _saveWallet();
    await selectSkin(id);
    return true;
  }

  /// Apply bought helpers at run start. Returns what was equipped.
  Future<({int hearts, bool potion})> consumeLoadoutForRun({
    required int maxHearts,
  }) async {
    final h = stockHearts.clamp(0, maxHearts);
    final potion = stockPotions > 0;
    if (h > 0) stockHearts -= h;
    if (potion) stockPotions -= 1;
    if (h > 0 || potion) await _saveWallet();
    return (hearts: h, potion: potion);
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
        return 0.42;
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
  Future<
      ({
        List<String> missions,
        List<String> skins,
        bool weekly,
        int xp,
        int crystals,
      })> applyRunProgress({
    required double distance,
    required int gold,
    required int rares,
    required int overtakes,
    required int raresWhileLeading,
    required bool won,
    /// Only true when player cashed out at a checkpoint / cleared the series.
    required bool bankCrystals,
    required List<DailyMissionDef> missions,
  }) async {
    _rollDayIfNeeded();
    if (weeklyKey != weekKey()) {
      weeklyKey = weekKey();
      weeklyProgress = 0;
      weeklyDone = false;
      weekBestDistanceMeters = 0;
    }

    totalRuns += 1;
    await _prefs?.setInt(_kTotalRuns, totalRuns);

    if (won) {
      totalWins += 1;
      await _prefs?.setInt(_kTotalWins, totalWins);
    }

    final distM = distance.round();
    if (distM > weekBestDistanceMeters) {
      weekBestDistanceMeters = distM;
    }

    final xpGain = (distM ~/ 50) +
        rares * 3 +
        overtakes * 2 +
        (won ? 15 : 0) +
        (raresWhileLeading > 0 ? 4 : 0);
    minerXp += xpGain;
    await _prefs?.setInt(_kMinerXp, minerXp);

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
    }
    await _saveWeekly();

    final skins = <String>[];
    if (_allMissionsDone(missions)) {
      skins.addAll(await _onPerfectDay());
    }
    if (weeklyJust) {
      skins.addAll(await _tryUnlockFromWeekly());
    }

    final crystals = await bankRunCrystals(
      rares: rares,
      cashOut: bankCrystals,
    );

    return (
      missions: newly,
      skins: skins,
      weekly: weeklyJust,
      xp: xpGain,
      crystals: crystals,
    );
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

  int bestDistanceFor(RunMode mode) => switch (mode) {
        RunMode.standard => bestDistanceStandard,
        RunMode.long => bestDistanceLong,
      };

  /// Persist personal bests. Returns which records were broken this run.
  /// Memory fields update synchronously so UI can read them before await.
  Future<({bool distance, bool rares, List<String> skins})> considerRecords({
    required int distanceMeters,
    required int rares,
    RunMode? mode,
  }) async {
    final runMode = mode ?? GameSettings.instance.runMode;
    var beatDistance = false;
    var beatRares = false;

    if (runMode == RunMode.standard &&
        distanceMeters > bestDistanceStandard) {
      bestDistanceStandard = distanceMeters;
      beatDistance = true;
    } else if (runMode == RunMode.long &&
        distanceMeters > bestDistanceLong) {
      bestDistanceLong = distanceMeters;
      beatDistance = true;
    }

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
        await p.setInt(_kBestDistanceStandard, bestDistanceStandard);
        await p.setInt(_kBestDistanceLong, bestDistanceLong);
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
    final meters = meterTargets[seed % meterTargets.length];
    final overtakes = overtakeTargets[(seed ~/ 7) % overtakeTargets.length];
    final leadRares =
        leadRareTargets[(seed ~/ 13) % leadRareTargets.length];

    // Three short goals — Subway-style, no puzzle wording.
    return [
      DailyMissionDef(
        id: 'overtakes',
        kind: DailyKind.overtakeThief,
        target: overtakes,
        titleRu: 'Обгони вора',
      ),
      DailyMissionDef(
        id: 'lead_rares',
        kind: DailyKind.raresWhileLeading,
        target: leadRares,
        titleRu: 'Кристаллы впереди',
      ),
      DailyMissionDef(
        id: 'run',
        kind: DailyKind.runMeters,
        target: meters,
        titleRu: 'Пробеги метры',
      ),
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
          titleRu: 'Обгони вора',
        );
      case 1:
        final n = [12, 15, 18, 20][(seed ~/ 7) % 4];
        return WeeklyMissionDef(
          id: 'w_lead',
          kind: DailyKind.raresWhileLeading,
          target: n,
          titleRu: 'Кристаллы впереди',
        );
      case 2:
        final n = [3, 4, 5, 5][(seed ~/ 11) % 4];
        return WeeklyMissionDef(
          id: 'w_wins',
          kind: DailyKind.winRun,
          target: n,
          titleRu: 'Выиграй забеги',
        );
      default:
        final n = [25, 30, 35, 40][(seed ~/ 13) % 4];
        return WeeklyMissionDef(
          id: 'w_rares',
          kind: DailyKind.collectRares,
          target: n,
          titleRu: 'Собери кристаллы',
        );
    }
  }
}
