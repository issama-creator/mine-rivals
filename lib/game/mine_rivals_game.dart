import 'dart:async';
import 'dart:math';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../effects/chase_arrow.dart';
import '../effects/corridor_title.dart';
import '../effects/floating_text.dart';
import '../effects/gold_trail.dart';
import '../effects/particle_burst.dart';
import '../effects/screen_flash.dart';
import '../effects/screen_shake.dart';
import '../items/falling_item.dart';
import '../items/item_pool.dart';
import '../items/item_type.dart';
import '../items/spawn_director.dart';
import '../player/player_component.dart';
import '../systems/audio_manager.dart';
import '../systems/game_settings.dart';
import '../systems/lead_system.dart';
import '../systems/progress_store.dart';
import '../systems/stats_system.dart';
import '../thief/thief_component.dart';
import '../world/parallax_background.dart';
import 'asset_library.dart';
import 'game_config.dart';

class MineRivalsGame extends FlameGame with DragCallbacks, TapCallbacks {
  MineRivalsGame({this.onFinished, this.onQuitToMenu});

  final void Function(MatchStats stats)? onFinished;
  final VoidCallback? onQuitToMenu;

  final LeadSystem lead = LeadSystem();
  final MatchStats stats = MatchStats();
  final ItemPool pool = ItemPool();
  final SpawnDirector spawns = SpawnDirector();
  final AudioManager audio = AudioManager();
  final Random _rng = Random();

  /// Active falling loot — avoids walking the whole component tree each frame.
  final List<FallingItem> liveItems = [];
  int _dustLive = 0;
  final List<ThiefComponent> _packCache = [];
  /// Scratch buffers — no per-frame Vector2 alloc in magnet/steal/draw-order.
  final Vector2 _scratch = Vector2.zero();
  final List<ThiefComponent> _packOrder = [];
  final Vector2 _shakeScratch = Vector2.zero();

  late PlayerComponent player;
  late ThiefComponent thief;
  ThiefComponent? thiefBlue;
  late ParallaxBackground background;
  late ChaseArrow chaseArrow;

  double distance = 0;
  double spawnTimer = 0;
  double cleanTimer = 0;
  double dustTimer = 0;

  /// Consecutive misses/bombs — each one adds chase pressure.
  int mistakeStreak = 0;

  /// Lead meters still draining after mistakes (thief approaches over time).
  double _leadDebt = 0;

  /// Thief sprint window — closes hard, readable rivalry wave.
  double _thiefBurstTimer = 0;
  double _thiefBurstCooldown = 0;
  double _nextBurstAt = 90;

  bool get isThiefBursting => _thiefBurstTimer > 0;

  /// Gap under [GameConfig.thiefBreathLeadMax] while you still lead.
  bool get isThiefBreathing =>
      !finished &&
      !inChaseIntro &&
      lead.playerLeads &&
      lead.leadDistance.abs() <= GameConfig.thiefBreathLeadMax;

  double _breathFlashTimer = 0;
  double _breathBannerCd = 0;
  bool _wasBreathing = false;

  /// Time left stuck in a spider web (player sluggish, thief gains).
  double _webSnareTimer = 0;

  bool get isWebSnared => _webSnareTimer > 0;

  /// Subway-style magnet power-up — pulls loot (not bomb/web).
  double _magnetPowerTimer = 0;

  bool get hasMagnetPower => _magnetPowerTimer > 0;

  double get magnetPowerSeconds => _magnetPowerTimer;

  /// Stackable shields (0–[GameConfig.maxHearts]) vs pit / spikes / bomb.
  int hearts = 0;
  bool get hasHeart => hearts > 0;
  /// Answer the thief — tap HUD when he leads / breathes.
  bool hasPotion = false;
  double _potionBoostTimer = 0;
  double _heartIFrame = 0;

  bool get isPotionBoosting => _potionBoostTimer > 0;

  bool get canUsePotion =>
      hasPotion &&
      !isPotionBoosting &&
      !finished &&
      !_finishBeat &&
      !inChaseIntro &&
      (!lead.playerLeads ||
          lead.leadDistance.abs() <= GameConfig.potionUseLeadMax);

  int playerOvertakes = 0;
  int thiefOvertakes = 0;
  /// Crystals caught while the player leads (daily race mission).
  int raresWhileLeading = 0;
  bool newDistanceRecord = false;
  bool newRaresRecord = false;
  /// First jewel of the run — stronger juice once.
  bool _firstJewelJuiced = false;

  /// Coin streak for catch pitch-up / ×2×3 mult / gold trail.
  int _goldStreak = 0;
  int _lastCoinMult = 1;

  int get goldStreak => _goldStreak;

  /// Unbroken crystal catches — HUD combo (coins don't count / don't break).
  int _jewelStreak = 0;

  int get jewelStreak => _jewelStreak;

  /// Subway-style coin multiplier from unbroken streak.
  int get coinMultiplier {
    if (_goldStreak >= GameConfig.coinMult3At) return 3;
    if (_goldStreak >= GameConfig.coinMult2At) return 2;
    return 1;
  }

  /// Consecutive clean catches — you pull further ahead of the thief.
  int successStreak = 0;
  Vector2 shakeOffset = Vector2.zero();

  /// Extra Y (px) when fast — lowers the “camera” for look-ahead.
  double _cameraDipY = 0;
  bool finished = false;
  bool started = false;
  bool _finishBeat = false;
  double _finishBeatTimer = 0;

  /// Manual slow-mo (FlameGame has no built-in timeScale here).
  double _playRate = 1;
  double? dragX;

  /// Last bomb lane / last free lane after a dual gate.
  int _lastBombLane = -1;

  /// Countdown until another bomb pattern is allowed.
  double _bombCooldown = 0;

  /// Keeps web / spikes from stacking in the same 2–3s window.
  double _laneTrapCooldown = 0;

  /// Corridor theme sync — apply once per index (no per-frame Future spam).
  int _corridorDesired = -1;
  int _corridorApplied = -1;
  int _corridorFxAt = -1;
  int _corridorGen = 0;

  /// Short HUD banner (steal / finale / etc).
  String? bannerText;
  Color bannerColor = const Color(0xFFEF5350);
  double bannerTimer = 0;

  /// Instant-fail (pit / spikes / thief escape) — results show loss, not jewel win.
  bool failedRun = false;
  /// Pit suck vs thief ran off with crystals.
  bool failedByThiefEscape = false;
  /// Lethal floor was spikes (not pit) — results copy differs.
  bool failedBySpikes = false;
  /// Player claimed win via Финиш while leading crystals.
  bool finishedByChoice = false;
  /// Thief claimed finish at a checkpoint while leading crystals.
  bool finishedByThiefChoice = false;
  /// Won by clearing the full series (final round), not early cash-out.
  bool finishedSeriesComplete = false;
  /// XP earned last commit (results / menu meta).
  int lastRunXpGain = 0;
  /// Crystals banked into the shop wallet last commit (0 if risk burned).
  int lastRunCrystalsGain = 0;
  /// Had a crystal pot but didn't cash out (death / thief / forfeit).
  bool lastRunCrystalsBurned = false;
  /// Gap banners while thief is far ahead.
  int _lastGapBannerAt = 0;
  /// Current series round (1-based) while racing toward its checkpoint.
  int seriesRound = 1;
  /// Next distance where Finish vs Risk is offered (or thief claims).
  double _nextCheckpointM = GameConfig.seriesRoundMeters;
  bool _checkpointOpen = false;
  /// Soft start after checkpoint risk (3–2–1).
  bool _roundCountdownOpen = false;
  double _roundGraceTimer = 0;
  bool _taughtMagnet = false;
  bool _taughtHeart = false;
  bool _taughtPotion = false;
  bool _taughtCatchUp = false;

  /// Counts up while primary thief is off-screen ahead.
  double _thiefEscapeTimer = 0;
  double _thiefEscapeBannerCd = 0;

  List<DailyMissionDef> _dailyMissions = const [];
  final Set<String> _missionToasted = {};
  bool _dailyCommitted = false;

  /// Opening chase reveal — thief close, then settles back.
  double _introT = 0;
  bool get inChaseIntro => _introT < GameConfig.chaseIntroSec;

  /// Pit suck cinematic before results.
  bool _pitSucking = false;
  double _pitSuckT = 0;
  Vector2? _pitSuckAt;

  double get playRate => _playRate;

  /// Spawn / hazard difficulty 0–1 from meters (endless — no finish line).
  double get progress => GameConfig.difficultyFromDistance(distance);

  double get remainingMeters => 0;

  bool get inFinale => false;

  List<ThiefComponent> get _pack {
    _packCache
      ..clear()
      ..add(thief);
    if (thiefBlue != null) _packCache.add(thiefBlue!);
    return _packCache;
  }

  @override
  Color backgroundColor() => const Color(0xFF1A120B);

  @override
  Future<void> onLoad() async {
    // Audio must not block the run.
    unawaited(audio.init());
    // Core only during loading screen — corridor prefetch waits until started
    // (competing PNG decode was an intermittent hang).
    try {
      await AssetLibrary.ensureLoaded(prefetchRest: false);
    } catch (e, st) {
      // ignore: avoid_print
      print('Asset boot retry: $e\n$st');
      try {
        await AssetLibrary.ensureLoaded(prefetchRest: false);
      } catch (e2, st2) {
        // ignore: avoid_print
        print('Asset boot failed: $e2\n$st2');
        // Stay on loading rather than an unhandled zone throw / debugger pause.
        return;
      }
    }
    _dailyMissions = DailyMissions.forToday();
    _missionToasted.clear();
    _dailyCommitted = false;

    background = ParallaxBackground(size: size);
    await add(background);

    player = PlayerComponent();
    thief = ThiefComponent();
    chaseArrow = ChaseArrow();
    await add(thief);
    await add(player);
    await add(chaseArrow);
    await add(GoldTrail());

    lead.onOvertakeStarted = (leader) {
      final preferRight = player.position.x <= size.x * 0.5;
      thief.passSide = preferRight ? 1.0 : -1.0;
      audio.play('overtake');
      final mid = Vector2(
        (player.position.x + thief.position.x) * 0.5,
        (player.position.y + thief.position.y) * 0.5,
      );
      add(DustPuff(position: mid.clone()));
      add(DustPuff(position: mid + Vector2(16 * thief.passSide, 8)));
      if (leader == Leader.thief) {
        thiefOvertakes++;
        _pulseBanner('Вор впереди', const Color(0xFFEF5350));
        add(
          ScreenFlash(
            color: const Color(0xFFEF5350),
            peakAlpha: 0.18,
            duration: 0.34,
          ),
        );
        _shake(14);
      } else {
        playerOvertakes++;
        _pulseBanner('Ты впереди', const Color(0xFF66BB6A));
        add(
          ScreenFlash(
            color: const Color(0xFF66BB6A),
            peakAlpha: 0.12,
            duration: 0.28,
          ),
        );
        _shake(8);
      }
    };

    _layoutActors();
    _introT = 0;
    // Start with thief almost on your heels so the chase is obvious.
    lead.leadDistance = 0.85;
    lead.visualLead = 0.85;
    _layoutActors();
    _pulseBanner('Вор за тобой!', const Color(0xFFEF5350));
    started = true;
    unawaited(_applyShopLoadout());
    // Heavy corridor decode after the first frame is up.
    AssetLibrary.startBackgroundPrefetch();
    if (GameSettings.instance.runMode.thiefCount >= 2) {
      unawaited(AssetLibrary.ensureThiefBlueLoadedSafe());
    }
    if (!ProgressStore.instance.tutorialSeen) {
      overlays.add('tutorial');
      pauseEngine();
    }
  }

  /// Equip bought hearts / potion from the shop stock.
  Future<void> _applyShopLoadout() async {
    final load = await ProgressStore.instance.consumeLoadoutForRun(
      maxHearts: GameConfig.maxHearts,
    );
    if (load.hearts > 0) hearts = load.hearts;
    if (load.potion) hasPotion = true;
    if (load.hearts > 0 || load.potion) {
      final parts = <String>[
        if (load.hearts > 0) '${load.hearts}♥',
        if (load.potion) 'зелье',
      ];
      _pulseBanner('Старт: ${parts.join(' · ')}', const Color(0xFF4FC3F7));
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!started) return;
    background.size = size;
    _layoutActors();
  }

  void _layoutActors() {
    final depth = lead.depthPositions(screenHeight: size.y);
    player.position = Vector2(size.x * 0.5, depth.playerY);
    player.applyDepthScale(depth.playerScale);
    for (final t in _pack) {
      t.position.setValues(
        size.x * 0.5 + t.laneBias,
        depth.thiefY + t.depthBias,
      );
      t.applyDepthScale(depth.thiefScale);
    }
    _updateDrawOrder();
  }

  void _updateDrawOrder() {
    var prio = 10;
    final pack = _pack;
    _packOrder
      ..clear()
      ..addAll(pack)
      ..sort((a, b) => a.position.y.compareTo(b.position.y));
    var frontThiefY = 0.0;
    for (final t in _packOrder) {
      t.priority = prio;
      prio += 2;
      if (t.position.y > frontThiefY) frontThiefY = t.position.y;
    }
    if (player.position.y >= frontThiefY) {
      player.priority = prio + 4;
    } else {
      player.priority = 8;
    }
  }

  void _updateChaseArrow() {
    if (lead.isOvertaking) {
      chaseArrow.setActive(false);
      return;
    }
    // You ahead: arrow at bottom when thief is a speck.
    final farBehind =
        lead.playerLeads &&
        lead.leadDistance >= GameConfig.chaseArrowLeadMin &&
        (thief.position.y > size.y * 0.92 ||
            thief.size.y < GameConfig.thiefHeight * 0.55);
    // Thief ahead / off-top: arrow at top so chase never becomes “only a number”.
    final farAhead = !lead.playerLeads && thiefGapMeters >= 28;
    chaseArrow.setActive(farBehind || farAhead);
    chaseArrow.pointUp = farAhead;
    chaseArrow.laneX = thief.position.x.clamp(48.0, size.x - 48.0);
    chaseArrow.position.y = farAhead ? 36 : size.y - 28;
  }

  void _updateFarGapBanners(double dt) {
    if (lead.playerLeads || finished || _finishBeat || inChaseIntro) {
      _lastGapBannerAt = 0;
      return;
    }
    final gap = thiefGapMeters;
    // Pulse every ~30 m of lead once he is clearly ahead.
    final bucket = (gap / 30).floor();
    if (bucket >= 1 && bucket > _lastGapBannerAt) {
      _lastGapBannerAt = bucket;
      _pulseBanner('Вор +$gap м', const Color(0xFFFF8A65));
    }
  }

  double get checkpointStepMeters => GameConfig.seriesRoundMeters;

  int get seriesRounds => GameSettings.instance.runMode.seriesRounds;

  bool get isFinalSeriesRound => seriesRound >= seriesRounds;

  /// Meters left until the next cash-out / risk gate.
  int get metersToCheckpoint =>
      max(0, (_nextCheckpointM - distance).ceil());

  /// 0 early → 1 on final round — drives thief steal pressure.
  double get seriesPressure =>
      GameConfig.thiefSeriesPressure(seriesRound, seriesRounds);

  @override
  void update(double dt) {
    super.update(dt);
    if (!started) return;

    if (bannerTimer > 0) {
      bannerTimer -= dt;
      if (bannerTimer <= 0) bannerText = null;
    }

    if (_pitSucking) {
      _updatePitSuck(dt);
      return;
    }

    if (_finishBeat) {
      _finishBeatTimer -= dt;
      if (_finishBeatTimer <= 0) {
        _finishBeat = false;
        _playRate = 1;
        pauseEngine();
        unawaited(_commitDailyProgress());
        onFinished?.call(stats);
        overlays.add('results');
      }
      return;
    }

    if (finished) return;

    if (_webSnareTimer > 0) _webSnareTimer -= dt;
    if (_magnetPowerTimer > 0) _magnetPowerTimer -= dt;
    if (_heartIFrame > 0) _heartIFrame -= dt;
    if (_roundGraceTimer > 0) _roundGraceTimer -= dt;
    if (_potionBoostTimer > 0) {
      _potionBoostTimer -= dt;
      // Keep pushing the gap open for the boost window.
      if (lead.leadDistance < GameConfig.maxLeadDistance) {
        lead.applyDelta(GameConfig.potionLeadGain * 0.35 * dt);
      }
    }

    var targetRate = inFinale ? GameConfig.finalePlayRate : 1.0;
    // Soft ramp after checkpoint countdown — don't slam into full pace.
    if (_roundGraceTimer > 0) {
      final t = 1.0 -
          (_roundGraceTimer / GameConfig.roundResumeGraceSec).clamp(0.0, 1.0);
      final soft = GameConfig.roundResumePlayRate +
          (1.0 - GameConfig.roundResumePlayRate) * Curves.easeOutCubic.transform(t);
      targetRate = min(targetRate, soft);
    }
    // Whole snare window: world slows so the thief visibly closes in.
    if (_webSnareTimer > 0) {
      targetRate = min(targetRate, GameConfig.webSnarePlayRate);
    }
    _playRate += (targetRate - _playRate) * (1 - (1 / (1 + 8 * dt)));
    final step = dt * _playRate;
    final pace = GameConfig.runSpeedAt(distance);
    final animRate =
        GameConfig.runAnimRateAt(distance) *
        (_webSnareTimer > 0 ? GameConfig.webSnarePlayRate : 1.0);

    distance += pace * step * GameConfig.distanceMeterRate;
    background.setWorldSpeed(pace * _playRate);
    player.setRunAnimRate(animRate);
    for (final t in _pack) {
      t.setRunAnimRate(animRate);
    }
    _syncCorridorTheme();
    _syncExtraThieves();
    _updateFinishCheckpoints();
    if (_checkpointOpen || _roundCountdownOpen || finished) return;

    _updateThiefBurst(step);
    _updateLeadDebt(step);
    _updateThiefBreath(step);
    final playingClean = cleanTimer > 2.5 && _leadDebt <= 0 && !isThiefBursting;
    lead.update(step, playingClean: playingClean && !inChaseIntro);
    cleanTimer += step;
    _updateThiefEscape(step);

    // Chase intro: thief starts on your heels, then drifts to normal lead.
    if (inChaseIntro) {
      _introT += step;
      final t = Curves.easeInOutCubic.transform(
        (_introT / GameConfig.chaseIntroSec).clamp(0.0, 1.0),
      );
      final introLead = 0.85 + (GameConfig.startLeadDistance - 0.85) * t;
      lead.leadDistance = introLead;
      lead.visualLead = introLead;
    }

    final depth = lead.depthPositions(screenHeight: size.y, dt: step);
    // Fast shafts: drop the band so traps read earlier (look-ahead).
    final paceRatio =
        GameConfig.runSpeedAt(distance) / GameConfig.runSpeedStart;
    final dipSpan =
        (GameConfig.cameraSpeedDipFull - GameConfig.cameraSpeedDipFrom).clamp(
          0.05,
          10.0,
        );
    final dipT = ((paceRatio - GameConfig.cameraSpeedDipFrom) / dipSpan).clamp(
      0.0,
      1.0,
    );
    final dipTarget =
        size.y *
        GameConfig.cameraSpeedDipMax *
        Curves.easeOutCubic.transform(dipT);
    final dipFollow = 1 - (1 / (1 + GameConfig.cameraSpeedDipFollow * step));
    _cameraDipY += (dipTarget - _cameraDipY) * dipFollow;
    // Keep feet on-screen even at full look-ahead.
    final maxDip = size.y * 0.94 - depth.playerY;
    if (_cameraDipY > maxDip) _cameraDipY = max(0, maxDip);

    // Straight run — no idle bob; only screen-shake + speed look-ahead.
    player.position.y = depth.playerY + _cameraDipY + shakeOffset.y * 0.35;
    player.applyDepthScale(depth.playerScale, step);
    for (final t in _pack) {
      t.position.y =
          depth.thiefY + t.depthBias + _cameraDipY + shakeOffset.y * 0.2;
      t.applyDepthScale(depth.thiefScale, step);
    }

    final minX = _pathMinX;
    final maxX = _pathMaxX;
    final desiredX = dragX ?? player.position.x;
    // Spider web makes the miner sticky/slow to steer.
    final moveFactor = _webSnareTimer > 0 ? GameConfig.webSnareMoveFactor : 1.0;
    // Finale / late shaft — snappier finger exits from dense trap lines.
    final lateBoost = (progress > 0.72)
        ? GameConfig.steerFinaleBoost
        : 1.0;
    player.moveToward(
      desiredX,
      minX,
      maxX,
      step * moveFactor,
      speed: GameConfig.steerSpeed * lateBoost,
    );
    final closeBehind =
        isThiefBreathing ||
        (lead.playerLeads &&
            lead.leadDistance.abs() < GameConfig.thiefBreathLeadMax + 0.4);
    final sprinting = isPotionBoosting ||
        isThiefBursting ||
        (lead.isOvertaking && lead.sprintOvertake);
    for (final t in _pack) {
      t.runLane(
        screenCenterX: size.x * 0.5,
        playerX: player.position.x,
        dt: step,
        overtaking: lead.isOvertaking,
        overtakeT: lead.overtakeT,
        breathingDownNeck:
            inChaseIntro ||
            closeBehind ||
            isThiefBursting ||
            (!lead.playerLeads && lead.leadDistance.abs() < 2.2),
        sprinting: sprinting && t.kind == ThiefKind.primary,
      );
    }

    _updateChaseArrow();
    _updateFarGapBanners(step);
    _updateDrawOrder();

    dustTimer += step;
    if (dustTimer > 0.45) {
      dustTimer = 0;
      if (_dustLive < 3) {
        _dustLive++;
        add(
          DustPuff(
            position: player.position + Vector2(0, -6),
            onDone: () => _dustLive = max(0, _dustLive - 1),
          ),
        );
      }
    }

    // No loot during the chase reveal — let the thief read first.
    if (!inChaseIntro) {
      spawns.update(step, progress: progress, distance: distance);
      _spawnUpdate(step);
      _magnetAndCatchUpdate(step);
      _stealUpdate(step);
      _missUpdate();
      _pollDailyMissions();
    }

    // Endless — no distance finish; ends on pit / escape / forfeit.
  }

  void _pollDailyMissions() {
    if (_dailyMissions.isEmpty || finished) return;
    final just = ProgressStore.instance.peekJustCompleted(
      distance: distance,
      gold: stats.player.gold,
      rares: stats.player.rareTotal,
      overtakes: playerOvertakes,
      raresWhileLeading: raresWhileLeading,
      won: false, // win only resolves at run end
      missions: _dailyMissions,
      alreadyToasted: _missionToasted,
    );
    for (final m in just) {
      _missionToasted.add(m.id);
      _pulseBanner('✓ ${m.titleRu}', const Color(0xFF81C784));
      audio.play('combo');
    }
  }

  Future<void> _commitDailyProgress() async {
    if (_dailyCommitted) return;
    _dailyCommitted = true;
    final distM = distance.round();
    final rares = stats.player.rareTotal;
    final store = ProgressStore.instance;
    // Flags + in-memory bests update before first await (ResultsOverlay).
    final mode = GameSettings.instance.runMode;
    newDistanceRecord = distM > store.bestDistanceFor(mode);
    newRaresRecord = rares > store.bestRares;
    if (newDistanceRecord || newRaresRecord) {
      final parts = <String>[
        if (newDistanceRecord) 'дистанция',
        if (newRaresRecord) 'кристаллы',
      ];
      _pulseBanner('Рекорд: ${parts.join(' · ')}!', const Color(0xFFFFD54F));
    }
    // Crystal rivalry “win” for missions — survive isn’t possible forever.
    final won = stats.playerWins;
    // Shop wallet: only checkpoint cash-out / series clear banks the pot.
    // Risk further then die / thief finish / forfeit → pot burns.
    final cashOut = finishedByChoice &&
        !failedRun &&
        !finishedByThiefChoice &&
        !failedByThiefEscape;
    final records = await store.considerRecords(
      distanceMeters: distM,
      rares: rares,
      mode: mode,
    );
    final result = await store.applyRunProgress(
      distance: distance,
      gold: stats.player.gold,
      rares: rares,
      overtakes: playerOvertakes,
      raresWhileLeading: raresWhileLeading,
      won: won,
      bankCrystals: cashOut,
      missions: _dailyMissions,
    );
    lastRunXpGain = result.xp;
    lastRunCrystalsGain = result.crystals;
    lastRunCrystalsBurned = !cashOut && rares > 0;
    for (final m in _dailyMissions) {
      if (result.missions.contains(m.titleRu) &&
          !_missionToasted.contains(m.id)) {
        _missionToasted.add(m.id);
        _pulseBanner('✓ ${m.titleRu}', const Color(0xFF81C784));
      }
    }
    if (result.weekly) {
      _pulseBanner('Неделя закрыта!', const Color(0xFFFFD54F));
    }
    for (final skinName in {...records.skins, ...result.skins}) {
      _pulseBanner('Новый скин: $skinName!', const Color(0xFFFFD54F));
      audio.play('rare');
    }
  }

  void _pulseBanner(String text, Color color) {
    bannerText = text;
    bannerColor = color;
    bannerTimer = 1.6;
  }

  void _breakCoinCombo() {
    _goldStreak = 0;
    _lastCoinMult = 1;
  }

  void _breakJewelCombo() {
    _jewelStreak = 0;
  }

  void _shake(double intensity) {
    if (!GameSettings.instance.shakeEnabled) return;
    add(
      ScreenShake(
        onOffset: (o) {
          shakeOffset.setFrom(o);
        },
        intensity: intensity,
        scratch: _shakeScratch,
      ),
    );
  }

  void _magnetAndCatchUpdate(double dt) {
    player.refreshBasketCenter();
    final basket = player.basketCenter;
    final powered = hasMagnetPower;

    for (var i = liveItems.length - 1; i >= 0; i--) {
      // Pit/spikes fail clears the list mid-loop — bail before List.[] blows up.
      if (i >= liveItems.length || _pitSucking || finished) return;
      final item = liveItems[i];
      if (item.collected || item.stolen) continue;

      // Hazards never magnetize — strict touch only.
      if (item.type.isHazard) {
        item.setPlayerMagnet(false);
        // Brief invuln after heart save / round resume (explosives / floor traps).
        if ((_heartIFrame > 0 || _roundGraceTimer > 0) &&
            (item.type.isExplosive || item.type.isLethalFloor)) {
          continue;
        }
        if (item.type.isLethalFloor) {
          // Pit / spikes — feet only (tight). No fat side box.
          final radius = item.type.isSpikes
              ? GameConfig.spikesCatchRadius
              : GameConfig.pitCatchRadius;
          final fdx = player.position.x - item.hitX;
          final fdy = (player.position.y - 10) - item.hitY;
          if (fdx * fdx + fdy * fdy <= radius * radius) {
            onItemCaught(item);
            if (_pitSucking || finished) return;
          }
        } else {
          final dx = basket.x - item.hitX;
          final dy = basket.y - item.hitY;
          final radius = item.type.isExplosive
              ? GameConfig.bombCatchRadius
              : GameConfig.webCatchRadius;
          // Tight: basket circle OR almost-overlapping body (no near-miss).
          if (dx * dx + dy * dy <= radius * radius ||
              _bodyTouchesItem(
                item,
                halfW: GameConfig.bodyCatchHazardHalfW,
                halfH: GameConfig.bodyCatchHazardHalfH,
              )) {
            onItemCaught(item);
            if (_pitSucking || finished) return;
          }
        }
        continue;
      }

      // Power magnet: vacuum all loot (incl. jewels / magnet pickup).
      if (powered && item.type.isMagnetizable) {
        _powerMagnetPull(item, basket, dt);
        if (_pitSucking || finished) return;
        continue;
      }

      // Non-jewels (coin, bar, magnet): player only.
      if (!item.type.isJewel) {
        _playerMagnetOrCatch(item, basket, dt);
        if (_pitSucking || finished) return;
        continue;
      }

      // Jewels: player magnets only while leading (unless powered — above).
      if (!lead.playerLeads) continue;

      _playerMagnetOrCatch(item, basket, dt);
      if (_pitSucking || finished) return;
    }
  }

  void _pullToward(FallingItem item, Vector2 target, double pull) {
    // Aim so the body center (hit) reaches the basket; feet follow for grounded items.
    final feetTargetY = item.standsOnGround
        ? target.y + item.size.y * 0.52
        : target.y;
    _scratch.setValues(
      target.x - item.position.x,
      feetTargetY - item.position.y,
    );
    final dist = _scratch.length;
    if (dist <= 0.001) return;
    _scratch.scale(pull / dist);
    item.position.add(_scratch);
  }

  void _powerMagnetPull(FallingItem item, Vector2 basket, double dt) {
    final dx = basket.x - item.hitX;
    final dy = basket.y - item.hitY;
    final distSq = dx * dx + dy * dy;
    final r = GameConfig.powerMagnetRadius;
    if (distSq > r * r) {
      item.setPlayerMagnet(false);
      return;
    }
    item.setPlayerMagnet(true);
    final dist = sqrt(distSq);
    final pull = min(GameConfig.powerMagnetPullSpeed * dt, dist);
    if (dist > 0.001) {
      _pullToward(item, basket, pull);
    }
    if (dist <= GameConfig.catchRadius * 0.85) {
      onItemCaught(item);
    }
  }

  void _playerMagnetOrCatch(FallingItem item, Vector2 basket, double dt) {
    final dx = basket.x - item.hitX;
    final dy = basket.y - item.hitY;
    final distSq = dx * dx + dy * dy;
    final adx = dx.abs();
    final itemDy = item.hitY - basket.y;

    final gold = item.type == ItemType.gold;
    final assistR = gold ? GameConfig.goldSnapRadius : GameConfig.magnetRadius;
    final pullSp = gold
        ? GameConfig.goldSnapPullSpeed
        : GameConfig.magnetPullSpeed;
    final laneSlack = gold ? 28.0 : 18.0;

    final canAssist =
        adx < laneSlack && itemDy > -10 && itemDy < 22 && distSq < assistR * assistR;
    if (canAssist) {
      item.setPlayerMagnet(true);
      final dist = sqrt(distSq);
      final pull = min(pullSp * dt, dist);
      if (dist > 0.001) {
        _pullToward(item, basket, pull);
      }
    } else {
      item.setPlayerMagnet(false);
    }

    // Basket scoop (front) or tight body brush (side strafe into coin).
    if ((adx <= 24 && itemDy.abs() <= GameConfig.catchRadius) ||
        _bodyTouchesItem(
          item,
          halfW: GameConfig.bodyCatchLootHalfW,
          halfH: GameConfig.bodyCatchLootHalfH,
        )) {
      onItemCaught(item);
    }
  }

  /// Torso overlap — [halfW]/[halfH] kept small for hazards.
  bool _bodyTouchesItem(
    FallingItem item, {
    required double halfW,
    required double halfH,
  }) {
    final bodyY = player.position.y - player.size.y * 0.48;
    final dx = (player.position.x - item.hitX).abs();
    final dy = (bodyY - item.hitY).abs();
    return dx <= halfW && dy <= halfH;
  }

  /// Thief phases through everything except jewels (magnet + steal when ahead).
  void _stealUpdate(double dt) {
    // During a burst he snatches even while trailing — rivalry heat.
    final thiefHuntsJewels =
        !lead.playerLeads ||
        isThiefBursting ||
        (lead.isOvertaking && lead.pendingLeader == Leader.thief);

    if (!thiefHuntsJewels) {
      for (final item in liveItems) {
        item.setThiefMagnet(false);
      }
      return;
    }

    for (var i = liveItems.length - 1; i >= 0; i--) {
      if (i >= liveItems.length || _pitSucking || finished) return;
      final item = liveItems[i];
      if (item.collected || item.stolen) continue;

      // Same rule as coins: phase through ALL non-jewels (bars, bombs, junk).
      if (!item.type.isJewel) {
        item.setThiefMagnet(false);
        continue;
      }

      ThiefComponent? nearest;
      var bestDistSq = double.infinity;
      var stealX = 0.0;
      var stealY = 0.0;
      for (final t in _pack) {
        final sx = t.position.x;
        final sy = t.position.y - t.size.y * 0.72;
        final ddx = sx - item.hitX;
        final ddy = sy - item.hitY;
        final dSq = ddx * ddx + ddy * ddy;
        if (dSq < bestDistSq) {
          bestDistSq = dSq;
          nearest = t;
          stealX = sx;
          stealY = sy;
        }
      }
      if (nearest == null) continue;

      final dist = sqrt(bestDistSq);
      final revenge = !lead.playerLeads;
      final bursting = isThiefBursting;
      final stealPow = GameConfig.thiefStealPowerMult(seriesPressure);
      final radius = (revenge
              ? GameConfig.thiefRevengeMagnetRadius
              : (bursting
                    ? GameConfig.thiefBurstMagnetRadius
                    : GameConfig.thiefMagnetRadius)) *
          stealPow;
      final pullSp = (revenge
              ? GameConfig.thiefRevengeMagnetPullSpeed
              : (bursting
                    ? GameConfig.thiefBurstMagnetPullSpeed
                    : GameConfig.thiefMagnetPullSpeed)) *
          stealPow;
      final stealAt = (revenge
              ? GameConfig.thiefRevengeStealDist
              : (bursting ? 26.0 : 22.0)) *
          (0.92 + 0.16 * seriesPressure);

      // Standing items use feet Y; jewels still need a vertical window vs thief.
      final itemY = item.standsOnGround ? item.hitY : item.position.y;
      final inRange =
          dist < radius &&
          itemY > nearest.position.y - nearest.size.y * 1.15 &&
          itemY < nearest.position.y + 48;

      if (inRange) {
        item.setThiefMagnet(true);
        final pull = min(pullSp * dt, dist);
        if (dist > 0.001) {
          _scratch.setValues(stealX, stealY);
          _pullToward(item, _scratch, pull);
        }
      } else {
        item.setThiefMagnet(false);
      }

      if (dist < stealAt) {
        _thiefSteal(item);
      }
    }
  }

  void _spawnUpdate(double dt) {
    _bombCooldown = max(0, _bombCooldown - dt);
    _laneTrapCooldown = max(0, _laneTrapCooldown - dt);

    spawnTimer -= dt;
    if (spawnTimer > 0) return;

    final beat = spawns.nextBeat(progress: progress);
    spawnTimer = spawns.gapFor(beat, progress: progress);
    if (inFinale) {
      spawnTimer *= GameConfig.finaleSpawnGapMult;
    }

    // Empty corridor beat — teach “challenge incoming” before bomb gates.
    if (beat.silence) return;

    if (beat.bombPattern || beat.type.isExplosive) {
      final bombLive = liveItems.any((e) => e.type.isExplosive);
      if (bombLive || _bombCooldown > 0) {
        final lane = beat.lane ?? _rng.nextInt(GameConfig.bombLaneCount);
        _spawnLiveItem(
          type: ItemType.gold,
          position: Vector2(_laneX(lane), -40),
          fallSpeed: background.speed,
        );
      } else {
        _spawnBombPattern(beat);
      }
      return;
    }

    // Pit / spikes — separate types. Pits stay out of chase intro; spikes OK.
    if (beat.type.isLethalFloor) {
      if (inChaseIntro && beat.type.isPit) {
        final lane = beat.lane ?? 1;
        _spawnLiveItem(
          type: ItemType.gold,
          position: Vector2(_laneX(lane), -40),
          fallSpeed: background.speed,
        );
        return;
      }
      final lane = beat.lane ?? _rng.nextInt(GameConfig.bombLaneCount);
      // Never swap pit↔spikes — each has its own art and spawn track.
      final type = beat.type.isSpikes ? ItemType.spikes : ItemType.pit;
      final item = _spawnLiveItem(
        type: type,
        position: Vector2(_laneX(lane), -48),
        fallSpeed: background.speed,
      );
      if (type.isSpikes) item.refreshSprite();
      return;
    }

    if (beat.type.isHeart || beat.type.isPotion) {
      final lane = beat.lane ?? _rng.nextInt(GameConfig.bombLaneCount);
      _spawnLiveItem(
        type: beat.type,
        position: Vector2(_laneX(lane), -40),
        fallSpeed: background.speed,
      );
      return;
    }

    // Designed web beat (e.g. double-web → pit combo) — allow stacked webs.
    if (beat.type.isWeb) {
      final lane = beat.lane ?? _rng.nextInt(GameConfig.bombLaneCount);
      _spawnLiveItem(
        type: ItemType.web,
        position: Vector2(_laneX(lane), -40),
        fallSpeed: background.speed,
      );
      return;
    }

    // Lane traps — spikes / web. Pit on screen does NOT block spikes.
    final level = background.corridorIndex + 1;
    final laneTrapBusy = _laneTrapCooldown > 0 ||
        liveItems.any((e) => e.type.isWeb || e.type.isSpikes);
    final canLaneTrap = !inChaseIntro &&
        !laneTrapBusy &&
        !beat.type.isMagnet &&
        !beat.type.isLethalFloor &&
        !beat.type.isWeb &&
        !beat.type.isHeart &&
        !beat.type.isPotion &&
        !beat.row;

    if (canLaneTrap &&
        level >= GameConfig.spikesFromCorridor &&
        _rng.nextDouble() < GameConfig.spikesSpawnChance) {
      final lane = beat.lane ?? _rng.nextInt(GameConfig.bombLaneCount);
      final spikes = _spawnLiveItem(
        type: ItemType.spikes,
        position: Vector2(_laneX(lane), -48),
        fallSpeed: background.speed,
      );
      spikes.refreshSprite();
      _laneTrapCooldown = GameConfig.laneTrapSpacingSec;
      return;
    }

    if (canLaneTrap &&
        level >= GameConfig.webFromCorridor &&
        _rng.nextDouble() < GameConfig.webSpawnChance) {
      final lane = beat.lane ?? _rng.nextInt(GameConfig.bombLaneCount);
      _spawnLiveItem(
        type: ItemType.web,
        position: Vector2(_laneX(lane), -40),
        fallSpeed: background.speed,
      );
      _laneTrapCooldown = GameConfig.laneTrapSpacingSec;
      return;
    }

    if (beat.row) {
      for (var lane = 0; lane < GameConfig.bombLaneCount; lane++) {
        _spawnLiveItem(
          type: beat.type,
          position: Vector2(_laneX(lane), -40),
          fallSpeed: background.speed,
        );
      }
      return;
    }

    final x = beat.lane != null ? _laneX(beat.lane!) : _pickLootX();
    _spawnLiveItem(
      type: beat.type,
      position: Vector2(x, -40),
      fallSpeed: background.speed,
    );
  }

  FallingItem _spawnLiveItem({
    required ItemType type,
    required Vector2 position,
    required double fallSpeed,
  }) {
    final item = pool.acquire(
      type: type,
      position: position,
      fallSpeed: fallSpeed,
    );
    liveItems.add(item);
    add(item);
    return item;
  }

  void _releaseLiveItem(FallingItem item) {
    liveItems.remove(item);
    pool.release(item);
  }

  /// Single / dual / stagger — always at least one free row (never a full wall).
  void _spawnBombPattern(SpawnBeat beat) {
    // Opening chase: only single bombs — teach the dodge, no dual walls.
    final dual = inChaseIntro
        ? false
        : (beat.forceDual ?? (_rng.nextDouble() < GameConfig.bombDualChance));
    // Ground-style bombs — no sky lead. Cart only on single-lane slots.
    const y = -40.0;
    final speed = background.speed;

    if (dual) {
      var freeLane =
          beat.bombFreeLane ?? _rng.nextInt(GameConfig.bombLaneCount);
      // Don't repeat the same escape twice in a row (unless pattern forced it).
      if (beat.bombFreeLane == null &&
          freeLane == _lastBombLane &&
          GameConfig.bombLaneCount > 1) {
        freeLane =
            (freeLane + 1 + _rng.nextInt(GameConfig.bombLaneCount - 1)) %
            GameConfig.bombLaneCount;
      }
      for (var lane = 0; lane < GameConfig.bombLaneCount; lane++) {
        if (lane == freeLane) continue;
        _spawnBombAt(_laneX(lane), y, speed, allowCart: false);
      }
      _lastBombLane = freeLane;
    } else {
      var lane = beat.bombLane;
      if (lane == null) {
        final lanes = List<int>.generate(GameConfig.bombLaneCount, (i) => i)
          ..removeWhere((l) => l == _lastBombLane)
          ..shuffle(_rng);
        lane = lanes.isEmpty
            ? _rng.nextInt(GameConfig.bombLaneCount)
            : lanes.first;
      }
      _lastBombLane = lane;
      _spawnBombAt(_laneX(lane), y, speed, allowCart: true);

      // Dodge-punish: second bomb arrives a beat later on the escape lane.
      final follow = beat.staggerBombLane;
      if (follow != null && follow != lane) {
        final delayY = -(speed * 0.34).clamp(48.0, 130.0);
        _spawnBombAt(_laneX(follow), y + delayY, speed, allowCart: false);
        _lastBombLane = follow;
      }
    }

    _bombCooldown =
        GameConfig.bombCooldownMin +
        _rng.nextDouble() *
            (GameConfig.bombCooldownMax - GameConfig.bombCooldownMin);
    spawnTimer = max(spawnTimer, _bombCooldown * 0.5);
  }

  void _spawnBombAt(
    double x,
    double y,
    double speed, {
    bool allowCart = false,
  }) {
    final cart = allowCart &&
        !inChaseIntro &&
        _rng.nextDouble() < GameConfig.dynamiteCartChance;
    final type = cart ? ItemType.dynamiteCart : ItemType.bomb;
    final fall = cart ? speed * GameConfig.dynamiteCartSpeedMult : speed;
    final item = _spawnLiveItem(
      type: type,
      position: Vector2(x, y),
      fallSpeed: fall,
    );
    // Cart must show hazards/dynamite_cart.png — never a stale bomb crop.
    if (type.isDynamiteCart) item.refreshSprite();
  }

  /// Loot: mostly the 3 center rows; sometimes a “bush” near the wall.
  double _pickLootX() {
    final bush = _rng.nextDouble() < GameConfig.bushSpawnChance;
    final minX = _spawnMinX(bush: bush);
    final maxX = _spawnMaxX(bush: bush);

    // Bias toward the middle row.
    final roll = _rng.nextDouble();
    final lane = roll < 0.44 ? 1 : (roll < 0.72 ? 0 : 2);

    final t = (lane + 0.5) / GameConfig.bombLaneCount;
    final jitter = (_rng.nextDouble() - 0.5) * (bush ? 12.0 : 7.0);
    return (minX + (maxX - minX) * t + jitter).clamp(minX, maxX);
  }

  /// Bombs/webs stay on clear center lanes (never in bushes).
  double _laneX(int lane) {
    final minX = _spawnMinX(bush: false);
    final maxX = _spawnMaxX(bush: false);
    final t = (lane + 0.5) / GameConfig.bombLaneCount;
    return minX + (maxX - minX) * t;
  }

  double _spawnMinX({required bool bush}) {
    final inset = bush ? GameConfig.bushInsetFrac : GameConfig.spawnInsetFrac;
    return size.x * inset + GameConfig.pathPadPx;
  }

  double _spawnMaxX({required bool bush}) {
    final inset = bush ? GameConfig.bushInsetFrac : GameConfig.spawnInsetFrac;
    return size.x * (1.0 - inset) - GameConfig.pathPadPx;
  }

  /// Clamp by body edges — center alone still let the sprite clip into bushes.
  double get _playerHalfW =>
      (started ? player.size.x : GameConfig.playerWidth) * 0.45;

  double get _pathMinX =>
      size.x * GameConfig.pathInsetFrac + GameConfig.pathPadPx + _playerHalfW;

  double get _pathMaxX =>
      size.x * (1.0 - GameConfig.pathInsetFrac) -
      GameConfig.pathPadPx -
      _playerHalfW;

  void _missUpdate() {
    final basket = player.basketWorldCenter;
    for (var i = liveItems.length - 1; i >= 0; i--) {
      if (i >= liveItems.length || _pitSucking || finished) return;
      final item = liveItems[i];
      if (item.collected || item.stolen) continue;

      // Grounded items: position = feet. Lethal floor: position = center.
      final pastBottom = item.position.y > size.y + 60;
      final pastFeet = item.position.y > player.position.y +
          (item.standsOnGround ? 12 : 36);
      final stuck = item.life > 7.5;
      if (!pastBottom && !pastFeet && !stuck) continue;

      if (!item.type.isHazard && (pastFeet || pastBottom)) {
        // Magnet pickup miss — no chase penalty.
        if (item.type.isMagnet) {
          item.magnetBy = ItemMagnet.none;
          _releaseLiveItem(item);
          continue;
        }
        // While trailing, jewels belong to the thief — don't punish a miss.
        if (item.type.isJewel && !lead.playerLeads) {
          _thiefSteal(item);
          continue;
        }
        _breakCoinCombo();
        final nearMiss = (item.position.x - basket.x).abs() < 36;
        stats.player.registerMiss();
        cleanTimer = 0;
        audio.play('miss');
        if (nearMiss) {
          add(
            FloatingText(
              text: '−1',
              position: item.position.clone(),
              color: const Color(0xFFFFCC80),
              fontSize: 18,
            ),
          );
        }
        if (item.type.isJewel) {
          _breakJewelCombo();
          _punishMistake(GameConfig.leadLossOnMissRare);
        } else {
          _punishMistake(GameConfig.leadLossOnMiss);
        }
      }
      item.magnetBy = ItemMagnet.none;
      _releaseLiveItem(item);
    }
  }

  /// Mistakes queue chase debt — thief eases closer over time (no rocket pass).
  void _punishMistake(double baseLoss) {
    successStreak = 0;
    mistakeStreak = (mistakeStreak + 1).clamp(1, 6);
    final extra = (mistakeStreak - 1) * GameConfig.leadLossPerMistakeStreak;
    // First miss is soft; stacked mistakes still hurt, but capped lower.
    final add = (baseLoss + extra).clamp(0.0, 1.55);
    _leadDebt = (_leadDebt + add).clamp(0.0, GameConfig.leadDebtMax);
    if (mistakeStreak <= 1) {
      _pulseBanner('Промах! Вор ближе', const Color(0xFFFF7043));
    }
    // Sprint only after a real streak — one slip shouldn't launch him.
    if (mistakeStreak >= GameConfig.thiefBurstFromMistakes) {
      _tryStartThiefBurst(fromMistakes: true);
    }
  }

  void _scheduleNextBurst() {
    _nextBurstAt =
        distance +
        GameConfig.thiefBurstMetersMin +
        _rng.nextDouble() *
            (GameConfig.thiefBurstMetersMax - GameConfig.thiefBurstMetersMin);
  }

  void _tryStartThiefBurst({bool fromMistakes = false}) {
    if (finished || inChaseIntro || isThiefBursting) return;
    if (_thiefBurstCooldown > 0) return;
    _thiefBurstTimer = GameConfig.thiefBurstDuration;
    _thiefBurstCooldown = GameConfig.thiefBurstCooldownAt(seriesPressure);
    _scheduleNextBurst();
    // Small seed only — burst should feel like a push, not a teleport.
    if (_leadDebt < 0.6 && lead.playerLeads) {
      _leadDebt = min(GameConfig.leadDebtMax, _leadDebt + 0.55);
    }
    _pulseBanner(
      fromMistakes ? 'Вор прибавил!' : 'Вор ускорился!',
      const Color(0xFFEF5350),
    );
    add(
      ScreenFlash(
        color: const Color(0xFFEF5350),
        peakAlpha: 0.10,
        duration: 0.28,
      ),
    );
    _shake(6);
    audio.play('overtake');
  }

  void _updateThiefBurst(double dt) {
    if (_thiefBurstCooldown > 0) {
      _thiefBurstCooldown = max(0, _thiefBurstCooldown - dt);
    }
    if (!inChaseIntro &&
        !isThiefBursting &&
        _thiefBurstCooldown <= 0 &&
        distance >= _nextBurstAt) {
      _tryStartThiefBurst();
    }
    if (_thiefBurstTimer <= 0) return;
    final total = GameConfig.thiefBurstDuration;
    final elapsed = total - _thiefBurstTimer;
    _thiefBurstTimer = max(0, _thiefBurstTimer - dt);
    // Ease-in close — first beats soft, peak mid-burst (less "yeet").
    final t = (elapsed / total).clamp(0.0, 1.0);
    final ease = Curves.easeInOut.transform(t);
    final closeRate = GameConfig.thiefBurstClosePerSec * (0.45 + ease * 0.70);
    if (lead.playerLeads && !lead.isOvertaking) {
      lead.applyDelta(-closeRate * dt);
    }
  }

  void _updateThiefBreath(double dt) {
    if (_breathBannerCd > 0) {
      _breathBannerCd = max(0, _breathBannerCd - dt);
    }
    final breathing = isThiefBreathing;
    if (breathing && !_wasBreathing && _breathBannerCd <= 0) {
      _pulseBanner('Вор дышит в спину!', const Color(0xFFFF8A65));
      _breathBannerCd = GameConfig.thiefBreathBannerCooldown;
      _breathFlashTimer = 0;
    }
    _wasBreathing = breathing;
    if (!breathing && !isThiefBursting) return;

    _breathFlashTimer += dt;
    if (_breathFlashTimer >= GameConfig.thiefBreathFlashEvery) {
      _breathFlashTimer = 0;
      add(
        ScreenFlash(
          color: const Color(0xFFEF5350),
          peakAlpha: isThiefBursting ? 0.1 : 0.07,
          duration: 0.22,
        ),
      );
    }
  }

  /// Player ran into a spider web — bomb-like hitch: slow + thief closes in.
  /// (No crystal loss — that's bombs only.)
  void _triggerWebSnare() {
    _webSnareTimer = GameConfig.webSnareDuration;
    // Same chase pipeline as a bomb / miss so the thief actually gains.
    _punishMistake(GameConfig.leadLossOnWeb);
    audio.play('miss');
    _pulseBanner('Паутина!', const Color(0xFFB0BEC5));
    add(
      ScreenFlash(
        color: const Color(0xFFECEFF1),
        peakAlpha: 0.16,
        duration: 0.34,
      ),
    );
    _shake(10);
  }

  void _updateLeadDebt(double dt) {
    if (_leadDebt <= 0) return;
    final burst = isThiefBursting ? GameConfig.thiefBurstDebtMult : 1.0;
    final rate =
        GameConfig.leadDebtPerSec * (1 + (mistakeStreak - 1) * 0.12) * burst;
    final step = min(_leadDebt, rate * dt);
    _leadDebt -= step;
    lead.applyDelta(-step);
  }

  /// While thief leads: clean coins reel the gap in. No effect when you lead.
  void _applyCoinCatchUp(int coinAmount) {
    if (coinAmount <= 0 || lead.playerLeads || inChaseIntro) return;
    if (finished || _finishBeat || _pitSucking) return;

    final n = coinAmount.clamp(1, 6);
    if (_leadDebt > 0) {
      _leadDebt = (_leadDebt - GameConfig.catchUpDebtBurnPerCoin * n)
          .clamp(0.0, GameConfig.leadDebtMax);
    }

    final streakBonus = min(
      2.4,
      max(0, _goldStreak - 1) * GameConfig.leadGainOnCoinCatchUpStreak,
    );
    final base = (GameConfig.leadGainOnCoinCatchUp + streakBonus) * n;
    final gain = (base * GameConfig.catchUpDepthMult(lead.leadDistance))
        .clamp(0.0, GameConfig.catchUpLeadMaxPerCoin * n);
    if (gain <= 0) return;
    lead.applyDelta(gain);
    // Show the close — player sees the gap shrink on clean coins.
    final left = (-lead.leadDistance).clamp(0.0, -GameConfig.minLeadDistance);
    final closed = gain.round().clamp(1, 99);
    if (!_taughtCatchUp) {
      _taughtCatchUp = true;
      _pulseBanner('Монеты догоняют вора!', const Color(0xFF66BB6A));
    } else if (_goldStreak >= 2 || closed >= 3) {
      _pulseBanner(
        '−$closed м → вор ${left.round()} м',
        const Color(0xFF66BB6A),
      );
    }
  }

  /// Gap to the thief in meters (positive = he is ahead). 0 if you lead.
  int get thiefGapMeters {
    if (lead.playerLeads) return 0;
    return (-lead.leadDistance)
        .clamp(0.0, -GameConfig.minLeadDistance)
        .round();
  }

  /// Clean jewel catches stack — you open a bigger gap behind you.
  void _rewardSuccess(double baseGain, {bool showPullAway = false}) {
    mistakeStreak = 0;
    _leadDebt = 0;
    // Crystal answer cuts a thief sprint short.
    if (isThiefBursting) {
      _thiefBurstTimer = max(0, _thiefBurstTimer - 1.0);
    }
    successStreak = (successStreak + 1).clamp(1, 8);
    final extra = (successStreak - 1) * GameConfig.successStreakLeadBonus;
    final total = (baseGain + extra).clamp(0.0, 8.0);
    lead.applyDelta(total);
    if (showPullAway || successStreak >= 3) {
      _pulseBanner('+${total.toStringAsFixed(0)} м', const Color(0xFF66BB6A));
    }
  }

  void onItemCaught(FallingItem item) {
    if (item.collected || item.stolen || finished || _finishBeat) return;

    // Non-jewels always go to the player — never redirected to thief.
    if (!item.type.isJewel) {
      item.collected = true;
      if (item.type.isExplosive) {
        _breakCoinCombo();
        _breakJewelCombo();
        if (_tryConsumeHeart(item.position.clone())) {
          _releaseLiveItem(item);
          return;
        }
        stats.player.registerCatch(isBomb: true);
        final lostCrystal = stats.player.loseOneRare();
        cleanTimer = 0;
        final leadLoss = item.type.isDynamiteCart
            ? GameConfig.leadLossOnDynamiteCart
            : GameConfig.leadLossOnBomb;
        _punishMistake(leadLoss);
        audio.play('bomb');
        add(
          ParticleBurst(
            position: item.position.clone(),
            color: item.type.isDynamiteCart
                ? const Color(0xFFFF6D00)
                : Colors.orange,
            count: item.type.isDynamiteCart ? 16 : 10,
          ),
        );
        add(
          ScreenFlash(
            color: const Color(0xFFFF6D00),
            peakAlpha: item.type.isDynamiteCart ? 0.22 : 0.16,
            duration: 0.32,
          ),
        );
        _shake(item.type.isDynamiteCart ? 18 : 14);
        add(
          FloatingText(
            text: lostCrystal
                ? '−1'
                : (item.type.isDynamiteCart ? 'Вагонетка!' : 'Бум!'),
            position: item.position.clone(),
            color: lostCrystal ? const Color(0xFFFF5252) : Colors.orangeAccent,
          ),
        );
        _releaseLiveItem(item);
        return;
      }

      if (item.type.isWeb) {
        _breakCoinCombo();
        _breakJewelCombo();
        _triggerWebSnare();
        add(
          ParticleBurst(
            position: item.position.clone(),
            color: const Color(0xFFECEFF1),
            count: 8,
          ),
        );
        add(
          FloatingText(
            text: item.type.popupLabel,
            position: item.position.clone(),
            color: const Color(0xFFB0BEC5),
          ),
        );
        _releaseLiveItem(item);
        return;
      }

      if (item.type.isLethalFloor) {
        final at = item.position.clone();
        final spikes = item.type.isSpikes;
        _releaseLiveItem(item);
        if (_tryConsumeHeart(at)) return;
        _failRunPit(at, fromSpikes: spikes);
        return;
      }

      if (item.type.isHeart) {
        if (hearts < GameConfig.maxHearts) {
          hearts++;
          if (!_taughtHeart) {
            _taughtHeart = true;
            _pulseBanner('Щит от ямы и шипов!', const Color(0xFFFF5252));
          } else {
            _pulseBanner(
              'Сердце $hearts/${GameConfig.maxHearts}',
              const Color(0xFFFF5252),
            );
          }
          audio.play('rare');
        } else {
          _pulseBanner('Макс ${GameConfig.maxHearts}!', const Color(0xFFFFAB91));
        }
        add(
          ParticleBurst(
            position: item.position.clone(),
            color: item.type.color,
            count: 12,
          ),
        );
        add(
          FloatingText(
            text: item.type.popupLabel,
            position: item.position.clone(),
            color: item.type.color,
            fontSize: 24,
          ),
        );
        add(BasketSpark(position: player.basketWorldCenter.clone()));
        _releaseLiveItem(item);
        return;
      }

      if (item.type.isPotion) {
        if (!hasPotion) {
          hasPotion = true;
          if (!_taughtPotion) {
            _taughtPotion = true;
            _pulseBanner('Зелье: рывок, когда вор впереди!', const Color(0xFFAB47BC));
          } else {
            _pulseBanner('Зелье рывка!', const Color(0xFFAB47BC));
          }
          audio.play('rare');
        } else {
          _pulseBanner('Уже есть!', const Color(0xFFE1BEE7));
        }
        add(
          ParticleBurst(
            position: item.position.clone(),
            color: item.type.color,
            count: 12,
          ),
        );
        add(
          FloatingText(
            text: item.type.popupLabel,
            position: item.position.clone(),
            color: item.type.color,
            fontSize: 24,
          ),
        );
        add(BasketSpark(position: player.basketWorldCenter.clone()));
        _releaseLiveItem(item);
        return;
      }

      if (item.type.isMagnet) {
        _activateMagnetPower();
        if (!_taughtMagnet) {
          _taughtMagnet = true;
          _pulseBanner('Магнит тянет лут!', const Color(0xFF29B6F6));
        }
        add(
          ParticleBurst(
            position: item.position.clone(),
            color: item.type.color,
            count: 14,
          ),
        );
        add(
          FloatingText(
            text: item.type.popupLabel,
            position: item.position.clone(),
            color: item.type.color,
            fontSize: 26,
          ),
        );
        add(BasketSpark(position: player.basketWorldCenter.clone()));
        audio.play('rare');
        _releaseLiveItem(item);
        return;
      }

      // Gold / coal — score + catch-up when the thief is ahead.
      _goldStreak++;
      final mult = coinMultiplier;
      if (mult > _lastCoinMult) {
        _lastCoinMult = mult;
        _pulseBanner('×$mult', const Color(0xFFFFD54F));
        audio.play('combo');
      }
      final base = item.type == ItemType.coal ? 2 : 1;
      final gained = base * mult;
      stats.player.addItem(item.type, amount: gained);
      stats.player.registerCatch(isBomb: false);
      mistakeStreak = 0;
      _applyCoinCatchUp(gained);

      final pitch = 1.0 + min(0.48, (_goldStreak - 1) * 0.055);
      audio.playCatchPitched(pitch);

      final popup = mult > 1 ? '+$gained' : _lootPopupFor(item.type);
      add(
        ParticleBurst(
          position: item.position.clone(),
          color: item.type.color,
          count: 6 + mult * 3,
        ),
      );
      add(
        FloatingText(
          text: popup,
          position: item.position.clone(),
          color: mult >= 3 ? const Color(0xFFFF8F00) : const Color(0xFFFFD54F),
          fontSize: mult > 1 ? 26 : 22,
        ),
      );
      if (mult > 1) {
        add(
          FloatingText(
            text: '×$mult',
            position: item.position.clone() - Vector2(0, 26),
            color: const Color(0xFFFFECB3),
            fontSize: 16,
          ),
        );
      }
      add(BasketSpark(position: player.basketWorldCenter.clone()));
      _releaseLiveItem(item);
      return;
    }

    item.collected = true;

    // Power magnet claims jewels even when the thief leads.
    final thiefOwnsJewel =
        !hasMagnetPower &&
        (!lead.playerLeads ||
            (lead.isOvertaking && lead.pendingLeader == Leader.thief));
    if (thiefOwnsJewel) {
      item.collected = false;
      _thiefSteal(item);
      return;
    }

    stats.player.addItem(item.type);
    stats.player.registerCatch(isBomb: false);
    if (lead.playerLeads && item.type.isRare) {
      raresWhileLeading += ProgressStore.weekendLeadRareMult;
    }
    _jewelStreak++;
    _rewardSuccess(GameConfig.leadGainOnRare);
    audio.play('rare');
    add(BasketSpark(position: player.basketWorldCenter.clone()));

    if (!_firstJewelJuiced) {
      _firstJewelJuiced = true;
      _pulseBanner('Кристалл!', const Color(0xFF81D4FA));
      add(
        ScreenFlash(
          color: const Color(0xFF4FC3F7),
          peakAlpha: 0.18,
          duration: 0.36,
        ),
      );
      _shake(6);
      HapticFeedback.mediumImpact();
    }

    // Soft crystal-combo juice — readable, not a screen takeover.
    if (_jewelStreak >= 2) {
      add(
        FloatingText(
          text: '×$_jewelStreak',
          position: item.position.clone() - Vector2(0, 30),
          color: const Color(0xFFB3E5FC),
          fontSize: _jewelStreak >= 5 ? 22 : 18,
        ),
      );
    }
    if (_jewelStreak > 0 && _jewelStreak % GameConfig.comboThreshold == 0) {
      _rewardSuccess(GameConfig.leadGainOnCombo, showPullAway: true);
      audio.play('combo');
      add(
        FloatingText(
          text: 'Комбо $_jewelStreak',
          position: item.position.clone() - Vector2(0, 48),
          color: const Color(0xFF81D4FA),
          fontSize: 20,
        ),
      );
    }

    add(
      ParticleBurst(
        position: item.position.clone(),
        color: item.type.color,
        count: 12,
      ),
    );
    add(
      FloatingText(
        text: item.type.popupLabel,
        position: item.position.clone(),
        color: item.type.color,
      ),
    );
    _releaseLiveItem(item);
  }

  void _activateMagnetPower() {
    _magnetPowerTimer = GameConfig.magnetPowerDuration;
    _pulseBanner('Магнит 15с!', const Color(0xFF29B6F6));
    add(
      ScreenFlash(
        color: const Color(0xFF29B6F6),
        peakAlpha: 0.14,
        duration: 0.28,
      ),
    );
  }

  /// Spend one heart — save from pit / spikes / bomb. Returns true if absorbed.
  bool _tryConsumeHeart(Vector2 at) {
    if (hearts <= 0 || _heartIFrame > 0) return false;
    hearts--;
    _heartIFrame = GameConfig.heartIFrameSec;
    audio.play('combo');
    final left = hearts > 0 ? ' ($hearts)' : '';
    _pulseBanner('Спасён!$left', const Color(0xFFFF8A80));
    add(
      ScreenFlash(
        color: const Color(0xFFFF5252),
        peakAlpha: 0.2,
        duration: 0.35,
      ),
    );
    add(
      ParticleBurst(
        position: at,
        color: const Color(0xFFFF5252),
        count: 16,
      ),
    );
    add(
      FloatingText(
        text: 'Спасён!',
        position: at.clone(),
        color: const Color(0xFFFF8A80),
        fontSize: 26,
      ),
    );
    _shake(8);
    return true;
  }

  /// HUD tap — answer when thief leads / breathes down your neck.
  void tryUsePotion() {
    if (!canUsePotion) return;
    hasPotion = false;
    _potionBoostTimer = GameConfig.potionBoostDuration;
    _thiefBurstTimer = 0;
    lead.applyDelta(GameConfig.potionLeadGain);
    audio.play('overtake');
    _pulseBanner('Рывок!', const Color(0xFFCE93D8));
    add(
      ScreenFlash(
        color: const Color(0xFFAB47BC),
        peakAlpha: 0.16,
        duration: 0.32,
      ),
    );
    _shake(10);
    add(
      DustPuff(position: player.position.clone() + Vector2(0, -8)),
    );
  }

  void finishTutorial() {
    unawaited(ProgressStore.instance.markTutorialSeen());
    overlays.remove('tutorial');
    if (!finished && !_pitSucking) {
      resumeEngine();
    }
  }

  /// Emotional results copy.
  String get finishHeadline {
    if (failedByThiefEscape) return 'ВОР УШЁЛ!';
    if (finishedByThiefChoice) return 'ВОР ЗАКРЫЛ СЕРИЮ!';
    if (failedRun) {
      return failedBySpikes ? 'УМЕР ОТ ШИПОВ!' : 'УПАЛ В ЯМУ!';
    }
    if (finishedByChoice && finishedSeriesComplete) return 'СЕРИЯ ПРОЙДЕНА!';
    if (finishedByChoice && stats.playerWins) return 'ЗАБРАЛ КАМНИ!';
    if (stats.playerWins) return 'КРИСТАЛЛЫ ТВОИ!';
    return 'ВОР ЗАБРАЛ БОЛЬШЕ!';
  }

  String get finishTagline {
    final you = stats.player.rareTotal;
    final thief = stats.thief.rareTotal;
    final meters = distance.round();
    final roundLabel = 'раунд $seriesRound/$seriesRounds';
    if (failedByThiefEscape) {
      return 'Догоняй, пока его видно — $meters м';
    }
    if (finishedByThiefChoice) {
      return 'У вора больше · $you–$thief · $roundLabel';
    }
    if (failedRun) {
      return failedBySpikes
          ? 'Сердце спасает от шипов — $meters м'
          : 'Сердце спасает от ямы — $meters м';
    }
    if (finishedByChoice && finishedSeriesComplete) {
      return 'Все $seriesRounds раундов · $you–$thief · $meters м';
    }
    if (finishedByChoice && stats.playerWins) {
      return 'Досрочно · $you–$thief · $roundLabel';
    }
    if (stats.playerWins) {
      return 'Кристаллы $you–$thief · $meters м';
    }
    return 'Кристаллы $you–$thief · $meters м';
  }

  /// End of each series round: cash out, risk next, or thief closes the series.
  void _updateFinishCheckpoints() {
    if (finished ||
        _finishBeat ||
        _pitSucking ||
        _checkpointOpen ||
        inChaseIntro) {
      return;
    }
    if (distance < _nextCheckpointM) return;

    _checkpointOpen = true;
    pauseEngine();
    overlays.remove('pause');

    final you = stats.player.rareTotal;
    final thief = stats.thief.rareTotal;
    if (thief > you) {
      _claimThiefCheckpointFinish();
      return;
    }

    // Final round while leading/tied — series cleared.
    if (isFinalSeriesRound && stats.playerWins) {
      _checkpointOpen = false;
      finishedSeriesComplete = true;
      audio.play('combo');
      _pulseBanner('Серия пройдена!', const Color(0xFF81C784));
      endRunEarly(asVictory: true);
      return;
    }

    audio.play('combo');
    overlays.add('checkpoint');
  }

  /// Player cashes out the series at the checkpoint (must lead or tie).
  void acceptCheckpointFinish() {
    if (!_checkpointOpen || finished || !stats.playerWins) return;
    overlays.remove('checkpoint');
    _checkpointOpen = false;
    finishedSeriesComplete = isFinalSeriesRound;
    audio.play('combo');
    _pulseBanner(
      finishedSeriesComplete ? 'Серия пройдена!' : 'Забрал камни!',
      const Color(0xFF81C784),
    );
    endRunEarly(asVictory: true);
  }

  /// Risk the next round — 3–2–1 then soft resume (thief may close later).
  void riskCheckpointContinue() {
    if (!_checkpointOpen || finished || isFinalSeriesRound) return;
    overlays.remove('checkpoint');
    _checkpointOpen = false;
    seriesRound += 1;
    _nextCheckpointM += GameConfig.seriesRoundMeters;
    _roundCountdownOpen = true;
    // Stay paused during countdown overlay.
    pauseEngine();
    overlays.add('countdown');
  }

  /// Called by countdown overlay when 3–2–1 finishes.
  void finishRoundCountdown() {
    if (!_roundCountdownOpen || finished) return;
    overlays.remove('countdown');
    _roundCountdownOpen = false;
    _softResumeAfterCheckpoint();
  }

  /// Clear nearby lethals, brief grace, ease pace back in.
  void _softResumeAfterCheckpoint() {
    _clearHazardsNearPlayer();
    _roundGraceTimer = GameConfig.roundResumeGraceSec;
    _playRate = GameConfig.roundResumePlayRate;
    _pulseBanner(
      'Раунд $seriesRound/$seriesRounds',
      const Color(0xFFFFB300),
    );
    if (!finished && !_pitSucking) {
      resumeEngine();
    }
  }

  void _clearHazardsNearPlayer() {
    final py = player.position.y;
    for (final e in List<FallingItem>.of(liveItems)) {
      if (e.collected || e.stolen) continue;
      if (!e.type.isHazard) continue;
      // Drop traps already underfoot / just ahead so resume isn't a free death.
      if (e.position.y > py - 220 && e.position.y < py + 90) {
        _releaseLiveItem(e);
      }
    }
  }

  void _claimThiefCheckpointFinish() {
    if (finished || _finishBeat) return;
    finished = true;
    failedRun = false;
    failedByThiefEscape = false;
    failedBySpikes = false;
    finishedByChoice = false;
    finishedByThiefChoice = true;
    finishedSeriesComplete = false;
    _checkpointOpen = false;
    _thiefEscapeTimer = 0;
    _finishBeat = false;
    _webSnareTimer = 0;
    _magnetPowerTimer = 0;
    _goldStreak = 0;
    _jewelStreak = 0;
    _playRate = 1;
    audio.play('steal');
    _pulseBanner('Вор закрыл серию!', const Color(0xFFFF7043));
    unawaited(_commitDailyProgress());
    pauseEngine();
    overlays.remove('checkpoint');
    overlays.remove('pause');
    overlays.add('results');
  }

  /// Thief far ahead / off-screen for [GameConfig.thiefEscapeSeconds].
  bool get _thiefEscapedVisually {
    if (lead.playerLeads || lead.isOvertaking) return false;
    if (lead.leadDistance > GameConfig.thiefEscapeLead) return false;
    final top =
        thief.position.y - thief.size.y * thief.scale.y.abs() * 0.9;
    return top < 12;
  }

  void _updateThiefEscape(double dt) {
    if (finished || _finishBeat || _pitSucking || inChaseIntro) {
      _thiefEscapeTimer = 0;
      return;
    }
    if (_thiefEscapeBannerCd > 0) _thiefEscapeBannerCd -= dt;

    if (!_thiefEscapedVisually) {
      _thiefEscapeTimer = 0;
      return;
    }

    // Soft pressure only — thief can leave (up to 200 m), run never ends.
    final was = _thiefEscapeTimer;
    _thiefEscapeTimer += dt;
    final gap = thiefGapMeters;
    if (was <= 0) {
      _pulseBanner('Вор уходит! +$gap м', const Color(0xFFEF5350));
      _thiefEscapeBannerCd = 3.5;
      audio.play('steal');
    } else if (_thiefEscapeBannerCd <= 0 && _thiefEscapeTimer < 8) {
      _pulseBanner('Догоняй! +$gap м', const Color(0xFFFF7043));
      _thiefEscapeBannerCd = 4.0;
    }
  }

  /// Pit / spikes — suck-in cinematic, then results.
  void _failRunPit(Vector2 pitAt, {bool fromSpikes = false}) {
    if (finished || _finishBeat || _pitSucking) return;
    failedRun = true;
    failedByThiefEscape = false;
    failedBySpikes = fromSpikes;
    _pitSucking = true;
    _pitSuckT = 0;
    _pitSuckAt = pitAt;
    _magnetPowerTimer = 0;
    _webSnareTimer = 0;
    _playRate = 0.35;
    _goldStreak = 0;
    _jewelStreak = 0;
    dragX = null;
    player.resetSteer();
    audio.play('bomb');
    HapticFeedback.heavyImpact();
    _shake(16);
    add(ScreenFlash(color: Colors.black, peakAlpha: 0.35, duration: 0.55));
    _pulseBanner(
      fromSpikes ? 'Шипы!' : 'Яма!',
      fromSpikes ? const Color(0xFFFF8A65) : const Color(0xFFEF5350),
    );
    for (final e in List<FallingItem>.of(liveItems)) {
      _releaseLiveItem(e);
    }
    liveItems.clear();
    unawaited(_commitDailyProgress());
  }

  void _updatePitSuck(double dt) {
    _pitSuckT += dt;
    final dur = GameConfig.pitSuckDuration;
    final t = Curves.easeInCubic.transform((_pitSuckT / dur).clamp(0.0, 1.0));
    final pit = _pitSuckAt ?? player.position;
    // Pull toward the hole and shrink — “засос”.
    player.position.x +=
        (pit.x - player.position.x) * (1 - (1 / (1 + 14 * dt)));
    player.position.y += (pit.y + 8 - player.position.y) * (0.08 + t * 0.55);
    final s = (1.0 - t * 0.92).clamp(0.06, 1.0);
    player.scale = Vector2.all(s);
    player.angle = t * 1.15;
    player.opacity = (1.0 - t * 0.85).clamp(0.0, 1.0);
    background.scroll += background.speed * dt * 0.25;

    if (_pitSuckT >= dur) {
      _pitSucking = false;
      finished = true;
      _playRate = 1;
      player.scale = Vector2.all(1);
      player.angle = 0;
      player.opacity = 1;
      pauseEngine();
      overlays.add('results');
    }
  }

  /// +1 normally; every 10th gold in a streak pops +10 (Subway juice).
  String _lootPopupFor(ItemType type) {
    if (type == ItemType.gold) {
      final next = _goldStreak + 1;
      return next > 0 && next % 10 == 0 ? '+10' : '+1';
    }
    return type.popupLabel;
  }

  void _thiefSteal(FallingItem item) {
    if (item.stolen || item.collected) return;
    // Only jewels — same phase-through rule as coins for everything else.
    if (!item.type.isJewel) return;
    item.stolen = true;
    stats.thief.addItem(item.type);
    _breakJewelCombo();
    audio.play('steal');
    final revenge = !lead.playerLeads;
    add(
      ScreenFlash(
        color: const Color(0xFFEF5350),
        peakAlpha: revenge ? 0.22 : 0.14,
        duration: revenge ? 0.38 : 0.3,
      ),
    );
    _shake(revenge ? 14.0 : 11.0);
    add(
      ParticleBurst(
        position: item.position.clone(),
        color: const Color(0xFFFF1744),
        count: revenge ? 16 : 12,
      ),
    );
    add(
      FloatingText(
        text: revenge ? 'Украл!' : '+1',
        position: item.position.clone(),
        color: const Color(0xFFFF5252),
        fontSize: revenge ? 24 : 22,
      ),
    );
    if (revenge) {
      _pulseBanner('Вор забирает!', const Color(0xFFEF5350));
    }
    _releaseLiveItem(item);
  }

  /// Pause for in-run menu sheet.
  void pauseForMenu() {
    if (finished ||
        _finishBeat ||
        _checkpointOpen ||
        _roundCountdownOpen) {
      return;
    }
    pauseEngine();
  }

  void resumeFromMenu() {
    if (finished ||
        _finishBeat ||
        _checkpointOpen ||
        _roundCountdownOpen) {
      return;
    }
    resumeEngine();
  }

  /// End the run early and show results (forfeit / checkpoint Финиш / quit).
  void endRunEarly({bool asVictory = false}) {
    if (finished || _finishBeat) return;
    finished = true;
    failedRun = false;
    failedByThiefEscape = false;
    failedBySpikes = false;
    finishedByChoice = asVictory;
    finishedByThiefChoice = false;
    if (!asVictory) finishedSeriesComplete = false;
    _checkpointOpen = false;
    _roundCountdownOpen = false;
    _roundGraceTimer = 0;
    overlays.remove('checkpoint');
    overlays.remove('countdown');
    _thiefEscapeTimer = 0;
    _finishBeat = false;
    _webSnareTimer = 0;
    _magnetPowerTimer = 0;
    _goldStreak = 0;
    _jewelStreak = 0;
    _playRate = 1;
    unawaited(_commitDailyProgress());
    pauseEngine();
    overlays.add('results');
  }

  void restart() {
    overlays.remove('results');
    overlays.remove('pause');
    overlays.remove('checkpoint');
    overlays.remove('countdown');
    for (final e in List<FallingItem>.of(liveItems)) {
      _releaseLiveItem(e);
    }
    liveItems.clear();
    _dustLive = 0;
    children.whereType<FloatingText>().toList().forEach(
      (e) => e.removeFromParent(),
    );
    children.whereType<CorridorTitle>().toList().forEach(
      (e) => e.removeFromParent(),
    );
    children.whereType<DustPuff>().toList().forEach(
      (e) => e.removeFromParent(),
    );
    children.whereType<ParticleBurst>().toList().forEach(
      (e) => e.removeFromParent(),
    );
    children.whereType<ScreenFlash>().toList().forEach(
      (e) => e.removeFromParent(),
    );
    children.whereType<ScreenShake>().toList().forEach(
      (e) => e.removeFromParent(),
    );

    stats.player
      ..gold = 0
      ..coal = 0
      ..diamond = 0
      ..ruby = 0
      ..emerald = 0
      ..amethyst = 0
      ..legendary = 0
      ..bombHits = 0
      ..missed = 0
      ..combo = 0
      ..bestCombo = 0
      ..currentStreak = 0;
    stats.thief
      ..gold = 0
      ..coal = 0
      ..diamond = 0
      ..ruby = 0
      ..emerald = 0
      ..amethyst = 0
      ..legendary = 0
      ..bombHits = 0
      ..missed = 0
      ..combo = 0
      ..bestCombo = 0
      ..currentStreak = 0;

    lead.reset();
    spawns.reset();
    distance = 0;
    spawnTimer = 0;
    cleanTimer = 0;
    mistakeStreak = 0;
    _leadDebt = 0;
    _thiefBurstTimer = 0;
    _thiefBurstCooldown = 0;
    _nextBurstAt =
        GameConfig.thiefBurstMetersMin +
        _rng.nextDouble() *
            (GameConfig.thiefBurstMetersMax - GameConfig.thiefBurstMetersMin);
    _breathFlashTimer = 0;
    _breathBannerCd = 0;
    _wasBreathing = false;
    _webSnareTimer = 0;
    _magnetPowerTimer = 0;
    hearts = 0;
    hasPotion = false;
    _potionBoostTimer = 0;
    _heartIFrame = 0;
    unawaited(_applyShopLoadout());
    playerOvertakes = 0;
    thiefOvertakes = 0;
    raresWhileLeading = 0;
    newDistanceRecord = false;
    newRaresRecord = false;
    _firstJewelJuiced = false;
    _goldStreak = 0;
    _lastCoinMult = 1;
    _jewelStreak = 0;
    successStreak = 0;
    _dailyMissions = DailyMissions.forToday();
    _missionToasted.clear();
    _dailyCommitted = false;
    _lastBombLane = -1;
    _bombCooldown = 0;
    _laneTrapCooldown = 0;
    _corridorDesired = -1;
    _corridorApplied = -1;
    _corridorFxAt = -1;
    _corridorGen = 0;
    finished = false;
    failedRun = false;
    failedByThiefEscape = false;
    failedBySpikes = false;
    finishedByChoice = false;
    finishedByThiefChoice = false;
    finishedSeriesComplete = false;
    seriesRound = 1;
    _nextCheckpointM = GameConfig.seriesRoundMeters;
    _checkpointOpen = false;
    _roundCountdownOpen = false;
    _roundGraceTimer = 0;
    lastRunXpGain = 0;
    lastRunCrystalsGain = 0;
    lastRunCrystalsBurned = false;
    _lastGapBannerAt = 0;
    _taughtMagnet = false;
    _taughtHeart = false;
    _taughtPotion = false;
    _taughtCatchUp = false;
    _thiefEscapeTimer = 0;
    _thiefEscapeBannerCd = 0;
    _pitSucking = false;
    _pitSuckT = 0;
    _pitSuckAt = null;
    _introT = 0;
    _finishBeat = false;
    _finishBeatTimer = 0;
    bannerText = null;
    bannerTimer = 0;
    _playRate = 1;
    shakeOffset.setZero();
    _cameraDipY = 0;
    dragX = null;
    chaseArrow.setActive(false);
    background.resetCorridors();
    AssetLibrary.applyCorridorJewels(0);
    pool.clearJewels();
    pool.clearHazards();
    _clearExtraThieves();
    player.scale = Vector2.all(1);
    player.angle = 0;
    player.opacity = 1;
    player.resetSteer();
    // Re-show chase intro so “вор за тобой” reads every run.
    lead.leadDistance = 0.85;
    lead.visualLead = 0.85;
    _layoutActors();
    _pulseBanner('Вор за тобой!', const Color(0xFFEF5350));
    resumeEngine();
  }

  void _clearExtraThieves() {
    thiefBlue?.removeFromParent();
    thiefBlue = null;
  }

  /// Long mode = 2 thieves from the start; Standard = one.
  void _syncExtraThieves() {
    final wantBlue = GameSettings.instance.runMode.thiefCount >= 2;

    if (wantBlue && thiefBlue == null) {
      final t = ThiefComponent(kind: ThiefKind.blue);
      thiefBlue = t;
      // ignore: discarded_futures
      _mountBlueThief(t);
    } else if (!wantBlue && thiefBlue != null) {
      thiefBlue!.removeFromParent();
      thiefBlue = null;
    }
  }

  Future<void> _mountBlueThief(ThiefComponent t) async {
    await add(t);
    if (!isMounted || thiefBlue != t) return;
    final depth = lead.depthPositions(screenHeight: size.y);
    t.position = Vector2(size.x * 0.5 + t.laneBias, depth.thiefY + t.depthBias);
    t.applyDepthScale(depth.thiefScale);
    if (!inChaseIntro) {
      _pulseBanner('Двое воров!', const Color(0xFF42A5F5));
    }
  }

  void _syncCorridorTheme() {
    // Endless: cycle art every 1 km (0…9, then wrap).
    final idx = (distance / GameConfig.corridorSegmentMeters)
            .floor() %
        GameConfig.corridorAssetCount;
    if (idx == _corridorApplied && idx == _corridorDesired) return;
    if (idx == _corridorDesired && idx != _corridorApplied) return;

    _corridorDesired = idx;
    final gen = ++_corridorGen;
    final km = (distance / GameConfig.corridorSegmentMeters).floor() + 1;

    if (idx != _corridorFxAt && distance > 1) {
      _corridorFxAt = idx;
      children.whereType<CorridorTitle>().toList().forEach(
        (e) => e.removeFromParent(),
      );
      add(
        CorridorTitle(
          label: 'Шахта $km',
          position: Vector2(size.x * 0.5, 52),
        ),
      );
      add(
        ScreenFlash(
          color: const Color(0xFFFFE082),
          peakAlpha: 0.09,
          duration: 0.85,
        ),
      );
      audio.play('overtake');
    }

    // ignore: discarded_futures
    AssetLibrary.ensureCorridorReady(idx).then((_) {
      if (!isMounted || gen != _corridorGen) return;
      if (AssetLibrary.corridors.length <= idx) return;
      background.setCorridorIndex(idx);
      AssetLibrary.applyCorridorJewels(idx);
      for (final item in liveItems) {
        if (item.type.isJewel) item.refreshSprite();
      }
      _corridorApplied = idx;
    }).catchError((Object _) {});
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    dragX = event.localPosition.x.clamp(_pathMinX, _pathMaxX);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    // Amplify finger travel so lane swaps in trap combos feel immediate.
    final gain =
        GameConfig.steerDragGain * ((inFinale || progress > 0.72) ? 1.06 : 1.0);
    dragX = ((dragX ?? player.position.x) + event.localDelta.x * gain).clamp(
      _pathMinX,
      _pathMaxX,
    );
  }

  @override
  void onTapDown(TapDownEvent event) {
    dragX = event.localPosition.x.clamp(_pathMinX, _pathMaxX);
  }
}
