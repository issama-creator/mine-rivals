import 'dart:async';
import 'dart:math';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../effects/chase_arrow.dart';
import '../effects/corridor_title.dart';
import '../effects/diamond_collect_fx.dart';
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
import '../player/skin_parade.dart';
import '../systems/audio_manager.dart';
import '../systems/game_settings.dart';
import '../systems/lead_system.dart';
import '../systems/progress_store.dart';
import '../systems/stats_system.dart';
import '../thief/thief_component.dart';
import '../world/parallax_background.dart';
import 'asset_library.dart';
import 'game_config.dart';
import 'player_skins.dart';

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

  /// Clean streak long enough that the thief is visibly falling back.
  bool get isIdealLine =>
      !finished &&
      !inChaseIntro &&
      _leadDebt <= 0 &&
      !isThiefBursting &&
      cleanTimer >= GameConfig.idealLineSec;

  /// Thief reached the cart — draining bank crystals over time.
  bool get isThiefAtCart =>
      !GameConfig.skinCompareMode &&
      !finished &&
      !inChaseIntro &&
      !_checkpointOpen &&
      lead.leadDistance <= GameConfig.cartTouchLeadMax;

  bool get isThiefStealingCart =>
      isThiefAtCart && stats.player.rareTotal > 0;

  double _breathFlashTimer = 0;
  double _breathBannerCd = 0;
  bool _wasBreathing = false;
  double _cartStealTimer = 0;
  double _floorStunTimer = 0;
  bool _idealLineBannerShown = false;

  /// Time left stuck in a spider web (player sluggish, thief gains).
  double _webSnareTimer = 0;

  bool get isWebSnared => _webSnareTimer > 0;

  bool get _playerTopDown =>
      PlayerSkins.byId(GameSettings.instance.selectedSkinId).topDown;

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
      lead.leadDistance <= GameConfig.potionUseLeadMax;

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

  /// Legacy fail flag (forfeit / rare paths) — pit/spikes no longer end the run.
  bool failedRun = false;
  /// Thief ran off with crystals (legacy escape path).
  bool failedByThiefEscape = false;
  /// Soft floor was spikes (not pit) — results copy if ever used.
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
  bool _biomeTransitionOpen = false;
  double _roundGraceTimer = 0;
  /// Next mine name shown on biome transition after Continue.
  String pendingBiomeName = AssetLibrary.corridorNames.first;
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

  /// Legacy guard — soft-fail floors no longer enter a suck cinematic.
  bool _pitSucking = false;

  double get playRate => _playRate;

  /// Spawn / hazard difficulty 0–1 from meters (endless — no finish line).
  double get progress => GameConfig.difficultyFromDistance(distance);

  double get remainingMeters => 0;

  bool get inFinale => false;

  List<ThiefComponent> get _pack {
    _packCache.clear();
    if (!GameConfig.skinCompareMode) {
      _packCache.add(thief);
    }
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
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await AssetLibrary.ensureLoaded(prefetchRest: false);
    }
    if (!AssetLibrary.ready) {
      // ignore: avoid_print
      print('AssetLibrary not ready after boot — aborting onLoad');
      return;
    }
    _dailyMissions = DailyMissions.forToday();
    _missionToasted.clear();
    _dailyCommitted = false;

    background = ParallaxBackground(size: size);
    await add(background);

    player = PlayerComponent();
    thief = ThiefComponent();
    chaseArrow = ChaseArrow();
    if (!GameConfig.skinCompareMode) {
      await add(thief);
    }
    await add(player);
    // Parade only useful with 2+ skins to compare.
    if (PlayerSkins.paradeSkins.length > 1) {
      await add(SkinParade());
    }
    if (!GameConfig.skinCompareMode) {
      await add(chaseArrow);
    }
    await add(GoldTrail());

    // Overtake pass removed — thief only creeps to the cart and steals.
    _layoutActors();
    _introT = 0;
    // Start with thief almost on your heels so the chase is obvious.
    lead.leadDistance = 0.85;
    lead.visualLead = 0.85;
    _layoutActors();
    _pulseBanner(
      GameConfig.skinCompareMode
          ? 'Тест скинов · вор и ловушки выкл'
          : 'Вор за тобой!',
      GameConfig.skinCompareMode
          ? const Color(0xFF66BB6A)
          : const Color(0xFFEF5350),
    );
    started = true;
    unawaited(_applyShopLoadout());
    // Defer corridor prefetch — right after boot it fights hot restart / GC.
    unawaited(
      Future<void>.delayed(const Duration(seconds: 5), () {
        if (!started || finished) return;
        AssetLibrary.startBackgroundPrefetch();
      }),
    );
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
      t.position.setValues(size.x * 0.5, depth.thiefY);
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
    if (GameConfig.skinCompareMode || !chaseArrow.isMounted) {
      return;
    }
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
      _pitSucking = false;
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
    if (_floorStunTimer > 0) {
      _floorStunTimer = max(0, _floorStunTimer - dt);
      targetRate = min(targetRate, GameConfig.floorSoftStunPlayRate);
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
    _updateFinishCheckpoints();
    if (_checkpointOpen ||
        _roundCountdownOpen ||
        _biomeTransitionOpen ||
        finished) {
      return;
    }

    _updateThiefBurst(step);
    _updateLeadDebt(step);
    _updateThiefBreath(step);
    final cleanReady =
        cleanTimer >= GameConfig.idealLineWarmupSec &&
        _leadDebt <= 0 &&
        !isThiefBursting &&
        !inChaseIntro;
    final idealFactor = GameConfig.idealLineFactor(cleanTimer);
    lead.update(
      step,
      playingClean: cleanReady,
      idealFactor: idealFactor,
    );
    final wasIdeal = _idealLineBannerShown;
    cleanTimer += step;
    if (!wasIdeal &&
        cleanTimer >= GameConfig.idealLineSec &&
        _leadDebt <= 0 &&
        !isThiefBursting) {
      _idealLineBannerShown = true;
      _pulseBanner('Идеальная линия! Вор отстаёт', const Color(0xFF66BB6A));
      bannerTimer = 1.4;
    }
    if (cleanTimer < GameConfig.idealLineWarmupSec) {
      _idealLineBannerShown = false;
    }
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

    // Top-down sprites: keep Y locked — shake/dip on Y reads as hopping.
    final topDownPlant = player.topDown;
    final dipY = topDownPlant ? 0.0 : _cameraDipY;
    final shakeY = topDownPlant ? 0.0 : shakeOffset.y;
    player.position.y = depth.playerY + dipY + shakeY * 0.35;
    player.applyDepthScale(depth.playerScale, step);
    for (final t in _pack) {
      t.position.y = depth.thiefY + dipY + shakeY * 0.2;
      t.applyDepthScale(depth.thiefScale, step);
    }
    if (isThiefAtCart) {
      // Same row as the miner — reads as shoulder-to-shoulder at the cart.
      for (final t in _pack) {
        t.position.y = player.position.y;
      }
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
        isThiefAtCart ||
        lead.leadDistance < GameConfig.thiefBreathLeadMax + 0.4;
    final sprinting = isPotionBoosting || isThiefBursting;
    for (final t in _pack) {
      t.runLane(
        screenCenterX: size.x * 0.5,
        playerX: player.position.x,
        dt: step,
        pressingCart: isThiefAtCart,
        breathingDownNeck:
            inChaseIntro || closeBehind || isThiefBursting,
        sprinting: sprinting,
      );
    }

    _updateChaseArrow();
    _updateFarGapBanners(step);
    _updateDrawOrder();

    // Top-down cart: no foot dust puffs — they read as random flashes.
    dustTimer += step;
    if (!_playerTopDown && dustTimer > 0.45) {
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
      spawns.update(
        step,
        progress: progress,
        distance: distance,
        seriesRound: seriesRound,
      );
      _spawnUpdate(step);
      _magnetAndCatchUpdate(step);
      _clearThiefJewelMagnets();
      _updateCartBankSteal(step);
      _missUpdate();
      _pollDailyMissions();
    }

    // Endless — ends on thief checkpoint claim / forfeit (mistakes don't kill).
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

  void _shake(double intensity, {double duration = 0.28}) {
    if (!GameSettings.instance.shakeEnabled) return;
    add(
      ScreenShake(
        onOffset: (o) {
          shakeOffset.setFrom(o);
        },
        intensity: intensity,
        duration: duration,
        scratch: _shakeScratch,
      ),
    );
  }

  /// Web = soft hitch. Bomb = punch. Pit/spikes = heavy fail (camera weight).
  void _hitJuiceWeb() {
    _pulseBanner('Паутина!', const Color(0xFFB0BEC5));
    add(
      ScreenFlash(
        color: const Color(0xFFECEFF1),
        peakAlpha: 0.11,
        duration: 0.28,
      ),
    );
    _shake(6, duration: 0.2);
    HapticFeedback.lightImpact();
  }

  void _hitJuiceBomb({required bool cart}) {
    add(
      ScreenFlash(
        color: cart ? const Color(0xFFFF6D00) : const Color(0xFFFF9100),
        peakAlpha: cart ? 0.28 : 0.2,
        duration: cart ? 0.42 : 0.34,
      ),
    );
    if (cart) {
      // Second punch — heavier cart impact.
      add(
        ScreenFlash(
          color: const Color(0xFFFF1744),
          peakAlpha: 0.1,
          duration: 0.5,
        ),
      );
    }
    _shake(cart ? 22 : 16, duration: cart ? 0.42 : 0.32);
    HapticFeedback.heavyImpact();
  }

  void _hitJuiceLethal({required bool spikes}) {
    HapticFeedback.heavyImpact();
    _shake(spikes ? 24 : 28, duration: spikes ? 0.48 : 0.55);
    add(
      ScreenFlash(
        color: spikes ? const Color(0xFFFF8A65) : const Color(0xFFB71C1C),
        peakAlpha: spikes ? 0.28 : 0.32,
        duration: 0.4,
      ),
    );
    add(
      ScreenFlash(
        color: Colors.black,
        peakAlpha: spikes ? 0.28 : 0.42,
        duration: spikes ? 0.55 : 0.7,
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

      // Jewels: always yours — thief only steals from the cart bank.
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

  /// Falling jewels are never vacuumed by the thief — only the cart bank is.
  void _clearThiefJewelMagnets() {
    for (final item in liveItems) {
      item.setThiefMagnet(false);
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

    // Skin parade test — only loot/jewels, no thief pressure / traps.
    if (GameConfig.skinCompareMode) {
      if (beat.bombPattern ||
          beat.type.isExplosive ||
          beat.type.isLethalFloor ||
          beat.type.isWeb) {
        final lane = beat.lane ?? _rng.nextInt(GameConfig.bombLaneCount);
        _spawnLiveItem(
          type: ItemType.diamond,
          position: Vector2(_laneX(lane), -40),
          fallSpeed: background.speed,
        );
        return;
      }
    }

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

    // Designed web beat (e.g. pattern combo) — allow stacked webs.
    if (beat.type.isWeb) {
      final lane = beat.lane ?? _rng.nextInt(GameConfig.bombLaneCount);
      _spawnLiveItem(
        type: ItemType.web,
        position: Vector2(_laneX(lane), -40),
        fallSpeed: background.speed,
      );
      return;
    }

    // Hazards only come from handcrafted patterns — no opportunistic inject.

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
      (started ? player.size.x : player.baseWidth) * 0.45;

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

  /// Mistakes queue chase debt — thief creeps toward the cart (no rocket).
  void _punishMistake(double baseLoss) {
    successStreak = 0;
    _idealLineBannerShown = false;
    mistakeStreak = (mistakeStreak + 1).clamp(1, 6);
    final extra = (mistakeStreak - 1) * GameConfig.leadLossPerMistakeStreak;
    final add = (baseLoss + extra).clamp(0.4, 5.5);
    _leadDebt = (_leadDebt + add).clamp(0.0, GameConfig.leadDebtMax);
    if (mistakeStreak == 1) {
      _pulseBanner('Промах! Вор ближе…', const Color(0xFFFF7043));
    } else if (mistakeStreak <= 3) {
      _pulseBanner('Вор подкрадывается к тележке', const Color(0xFFFF7043));
    } else {
      _pulseBanner('Вор почти у тележки!', const Color(0xFFEF5350));
    }
    // Sprint only after a real streak — one slip shouldn't launch him.
    if (mistakeStreak >= GameConfig.thiefBurstFromMistakes) {
      _tryStartThiefBurst(fromMistakes: true);
    }
  }

  /// Heavy soft-fail (pit / spikes) — big debt dump without ending the run.
  void _punishMistakeHeavy(double debt) {
    successStreak = 0;
    _idealLineBannerShown = false;
    mistakeStreak = (mistakeStreak + 1).clamp(1, 6);
    _leadDebt = (_leadDebt + debt).clamp(0.0, GameConfig.leadDebtMax);
    if (mistakeStreak >= GameConfig.thiefBurstFromMistakes) {
      _tryStartThiefBurst(fromMistakes: true);
    }
  }

  /// Thief near the cart — +1 to his score (takes from your bank, no grab).
  void _updateCartBankSteal(double dt) {
    if (!isThiefAtCart) {
      _cartStealTimer = 0;
      return;
    }
    if (stats.player.rareTotal <= 0) {
      _cartStealTimer = 0;
      return;
    }
    _cartStealTimer += dt;
    if (_cartStealTimer < GameConfig.cartStealInterval) return;
    _cartStealTimer = 0;

    final lost = stats.player.loseOneRareTyped();
    if (lost == null) return;
    stats.thief.addItem(lost);

    _breakJewelCombo();
    unawaited(audio.play('steal'));
    HapticFeedback.selectionClick();
    if (thief.isMounted) {
      thief.pulseBedCargo();
    }
    _pulseBanner('Вор рядом · +1', const Color(0xFFEF5350));
    bannerTimer = 1.0;
    // Score ping on the thief — he just benefits by being close.
    if (!thief.isMounted) return;
    final t = thief;
    add(
      FloatingText(
        text: '+1',
        position: t.position.clone() + Vector2(0, -t.size.y * 0.9),
        color: const Color(0xFFFF8A65),
        fontSize: 26,
      ),
    );
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

  /// Player ran into a spider web — soft hitch (no crystal loss).
  void _triggerWebSnare() {
    _webSnareTimer = GameConfig.webSnareDuration;
    _punishMistake(GameConfig.leadLossOnWeb);
    audio.play('miss');
    _hitJuiceWeb();
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

  /// Gap behind you in meters (thief never runs ahead).
  int get thiefBehindMeters =>
      lead.leadDistance.clamp(0.0, GameConfig.maxLeadDistance).round();

  /// Legacy HUD — always 0 (thief can't pass the cart).
  int get thiefGapMeters => 0;

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
        final lostType = stats.player.loseOneRareTyped();
        if (lostType != null) {
          stats.thief.addItem(lostType);
        }
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
            count: item.type.isDynamiteCart ? 18 : 12,
          ),
        );
        _hitJuiceBomb(
          cart: item.type.isDynamiteCart,
        );
        add(
          FloatingText(
            text: lostType != null
                ? '−1 → вор'
                : (item.type.isDynamiteCart ? 'Вагонетка!' : 'Бум!'),
            position: item.position.clone(),
            color: lostType != null
                ? const Color(0xFFFF5252)
                : Colors.orangeAccent,
            fontSize: item.type.isDynamiteCart ? 26 : 22,
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
            count: 10,
          ),
        );
        add(
          FloatingText(
            text: item.type.popupLabel,
            position: item.position.clone(),
            color: const Color(0xFFB0BEC5),
            fontSize: 20,
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
        _softFailFloor(at, fromSpikes: spikes);
        return;
      }

      if (item.type.isHeart) {
        if (hearts < GameConfig.maxHearts) {
          hearts++;
          if (!_taughtHeart) {
            _taughtHeart = true;
            _pulseBanner('Щит смягчает удар у тележки!', const Color(0xFFFF5252));
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

    stats.player.addItem(item.type);
    stats.player.registerCatch(isBomb: false);
    if (item.type.isRare) {
      raresWhileLeading += ProgressStore.weekendLeadRareMult;
    }
    _jewelStreak++;
    _rewardSuccess(GameConfig.leadGainOnRare);
    audio.play('rare');
    HapticFeedback.selectionClick();
    add(BasketSpark(position: player.basketWorldCenter.clone()));

    // Top HUD + cart land juice.
    final youNow = stats.player.rareTotal;
    if (_jewelStreak >= 3) {
      _pulseBanner('◆ ×$_jewelStreak  ·  $youNow', const Color(0xFF81D4FA));
      bannerTimer = 1.15;
    } else {
      _pulseBanner('◆ +1  ·  $youNow', const Color(0xFF4FC3F7));
      bannerTimer = 0.95;
    }

    // Crystal flies into the cart bed (inside the brown box).
    final flyTo = player.cartBedWorldCenter.clone();
    add(
      DiamondCollectFx(
        from: item.position.clone(),
        to: flyTo,
        onArrive: () {
          if (!isMounted || finished) return;
          player.pulseCargo();
          add(
            FloatingText(
              text: '+1',
              position: player.basketWorldCenter.clone() + Vector2(0, -18),
              color: const Color(0xFF81D4FA),
              fontSize: 22,
            ),
          );
        },
      ),
    );

    if (!_firstJewelJuiced) {
      _firstJewelJuiced = true;
      add(
        ScreenFlash(
          color: const Color(0xFF4FC3F7),
          peakAlpha: 0.14,
          duration: 0.28,
        ),
      );
      _shake(5);
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

  /// End of each series round: tension checkpoint (cash out / risk / thief win).
  void _updateFinishCheckpoints() {
    if (finished ||
        _finishBeat ||
        _pitSucking ||
        _checkpointOpen ||
        _biomeTransitionOpen ||
        _roundCountdownOpen ||
        inChaseIntro) {
      return;
    }
    if (distance < _nextCheckpointM) return;

    _checkpointOpen = true;
    pauseEngine();
    overlays.remove('pause');
    unawaited(audio.playCheckpoint());
    HapticFeedback.mediumImpact();

    // Always show the tension screen — including thief-ahead defeat beat.
    // Final-round auto-clear only when player already leads/ties.
    if (isFinalSeriesRound &&
        stats.playerWins &&
        stats.thief.rareTotal <= stats.player.rareTotal) {
      _checkpointOpen = false;
      finishedSeriesComplete = true;
      _pulseBanner('Серия пройдена!', const Color(0xFF81C784));
      endRunEarly(asVictory: true);
      return;
    }

    overlays.add('checkpoint');
    // Prefetch next shaft while the player decides Cash Out / Continue.
    if (!isFinalSeriesRound) {
      final nextIdx = seriesRound % GameConfig.corridorAssetCount;
      unawaited(AssetLibrary.ensureCorridorReady(nextIdx));
    }
  }

  /// Player cashes out the series at the checkpoint (must lead or tie).
  void acceptCheckpointFinish() {
    if (!_checkpointOpen || finished || !stats.playerWins) return;
    if (stats.thief.rareTotal > stats.player.rareTotal) return;
    overlays.remove('checkpoint');
    _checkpointOpen = false;
    finishedSeriesComplete = isFinalSeriesRound;
    _pulseBanner(
      finishedSeriesComplete ? 'Серия пройдена!' : 'Забрал камни!',
      const Color(0xFF81C784),
    );
    endRunEarly(asVictory: true);
  }

  /// Risk the next round — swap mine first, then biome card → 3–2–1.
  void riskCheckpointContinue() {
    if (!_checkpointOpen || finished || isFinalSeriesRound) return;
    if (stats.thief.rareTotal > stats.player.rareTotal) return;
    overlays.remove('checkpoint');
    _checkpointOpen = false;
    seriesRound += 1;
    _nextCheckpointM += GameConfig.seriesRoundMeters;
    unawaited(_beginBiomeTransition());
  }

  void confirmThiefCheckpointDefeat() {
    if (!_checkpointOpen || finished) return;
    overlays.remove('checkpoint');
    _checkpointOpen = false;
    _claimThiefCheckpointFinish();
  }

  Future<void> _beginBiomeTransition() async {
    final idx = (seriesRound - 1) % GameConfig.corridorAssetCount;
    pendingBiomeName = AssetLibrary.corridorNames[
        idx.clamp(0, AssetLibrary.corridorNames.length - 1)];
    _biomeTransitionOpen = true;
    pauseEngine();
    // Mine must be live BEFORE the “Entering…” card / 3–2–1.
    await _applyCheckpointBiome(idx);
    if (!isMounted || finished || !_biomeTransitionOpen) return;
    overlays.add('biome');
  }

  Future<void> _applyCheckpointBiome(int idx) async {
    try {
      await AssetLibrary.ensureCorridorReady(idx);
    } catch (_) {
      // Still mark desired so sync won't yank us back to the old shaft.
      _corridorDesired = idx;
      _corridorApplied = idx;
      _corridorFxAt = idx;
      return;
    }
    if (!isMounted || finished) return;
    background.setCorridorIndex(idx);
    AssetLibrary.applyCorridorJewels(idx);
    for (final item in liveItems) {
      if (item.type.isJewel) item.refreshSprite();
    }
    _corridorApplied = idx;
    _corridorDesired = idx;
    _corridorFxAt = idx;
    children.whereType<CorridorTitle>().toList().forEach(
      (e) => e.removeFromParent(),
    );
  }

  /// Called by biome overlay when the “Entering …” beat ends.
  void finishBiomeTransition() {
    if (!_biomeTransitionOpen || finished) return;
    overlays.remove('biome');
    _biomeTransitionOpen = false;
    // Guarantee art is on the next shaft before 3–2–1 (reload race).
    final idx = (seriesRound - 1) % GameConfig.corridorAssetCount;
    if (_corridorApplied != idx) {
      unawaited(_applyCheckpointBiome(idx).then((_) {
        if (!isMounted || finished) return;
        _startRoundCountdown();
      }));
      return;
    }
    _startRoundCountdown();
  }

  void _startRoundCountdown() {
    if (finished || _roundCountdownOpen) return;
    _roundCountdownOpen = true;
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
      pendingBiomeName,
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
    overlays.remove('biome');
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

  /// Pit / spikes — soft fail: thief surges toward the cart, crystals spill.
  void _softFailFloor(Vector2 pitAt, {bool fromSpikes = false}) {
    if (finished || _finishBeat || _floorStunTimer > 0) return;
    _floorStunTimer = GameConfig.floorSoftStunSec;
    _heartIFrame = GameConfig.heartIFrameSec;
    _breakCoinCombo();
    _breakJewelCombo();
    cleanTimer = 0;
    _punishMistakeHeavy(
      fromSpikes ? GameConfig.leadLossOnSpikes : GameConfig.leadLossOnPit,
    );

    // Spill into the thief's pocket — the fight is over the cart bank.
    final spills = fromSpikes ? 1 : 2;
    var taken = 0;
    for (var i = 0; i < spills; i++) {
      final lost = stats.player.loseOneRareTyped();
      if (lost == null) break;
      stats.thief.addItem(lost);
      taken++;
    }

    audio.play('bomb');
    _hitJuiceLethal(spikes: fromSpikes);
    _pulseBanner(
      taken > 0
          ? (fromSpikes
              ? 'Шипы! −$taken ◆ · вор у тележки'
              : 'Яма! −$taken ◆ · вор рвётся к тележке')
          : (fromSpikes
              ? 'Шипы! Вор ближе к тележке'
              : 'Яма! Вор рвётся к тележке'),
      fromSpikes ? const Color(0xFFFF8A65) : const Color(0xFFEF5350),
    );
    bannerTimer = 1.4;
    add(
      FloatingText(
        text: taken > 0 ? '−$taken ◆' : '!',
        position: pitAt.clone(),
        color: const Color(0xFFFF5252),
        fontSize: 26,
      ),
    );
    add(
      ParticleBurst(
        position: pitAt.clone(),
        color: fromSpikes ? const Color(0xFFFF8A65) : const Color(0xFFB71C1C),
        count: 14,
      ),
    );
  }

  /// +1 normally; every 10th gold in a streak pops +10 (Subway juice).
  String _lootPopupFor(ItemType type) {
    if (type == ItemType.gold) {
      final next = _goldStreak + 1;
      return next > 0 && next % 10 == 0 ? '+10' : '+1';
    }
    return type.popupLabel;
  }

  /// Pause for in-run menu sheet.
  void pauseForMenu() {
    if (finished ||
        _finishBeat ||
        _checkpointOpen ||
        _biomeTransitionOpen ||
        _roundCountdownOpen) {
      return;
    }
    pauseEngine();
  }

  void resumeFromMenu() {
    if (finished ||
        _finishBeat ||
        _checkpointOpen ||
        _biomeTransitionOpen ||
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
    _biomeTransitionOpen = false;
    _roundGraceTimer = 0;
    overlays.remove('checkpoint');
    overlays.remove('countdown');
    overlays.remove('biome');
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
    overlays.remove('biome');
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
    _cartStealTimer = 0;
    _floorStunTimer = 0;
    _idealLineBannerShown = false;
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
    _biomeTransitionOpen = false;
    _roundGraceTimer = 0;
    pendingBiomeName = AssetLibrary.corridorNames.first;
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
    player.scale = Vector2.all(1);
    player.angle = 0;
    player.opacity = 1;
    player.resetSteer();
    // Re-show chase intro so “вор за тобой” reads every run.
    lead.leadDistance = 0.85;
    lead.visualLead = 0.85;
    _layoutActors();
    _pulseBanner(
      GameConfig.skinCompareMode
          ? 'Тест скинов · вор и ловушки выкл'
          : 'Вор за тобой!',
      GameConfig.skinCompareMode
          ? const Color(0xFF66BB6A)
          : const Color(0xFFEF5350),
    );
    resumeEngine();
  }

  void _syncCorridorTheme() {
    // Series rounds own the shaft art (each Continue = next mine).
    // Don't fall back to distance — that snapped the old mine back after 3–2–1.
    final idx = (seriesRound - 1) % GameConfig.corridorAssetCount;
    if (idx == _corridorApplied && idx == _corridorDesired) return;
    if (idx == _corridorDesired && idx != _corridorApplied) return;

    _corridorDesired = idx;
    final gen = ++_corridorGen;

    if (idx != _corridorFxAt && distance > 1 && !_biomeTransitionOpen && !_roundCountdownOpen) {
      _corridorFxAt = idx;
      children.whereType<CorridorTitle>().toList().forEach(
        (e) => e.removeFromParent(),
      );
      add(
        CorridorTitle(
          label: pendingBiomeName.isNotEmpty
              ? pendingBiomeName
              : AssetLibrary.corridorNames[
                  idx.clamp(0, AssetLibrary.corridorNames.length - 1)],
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
