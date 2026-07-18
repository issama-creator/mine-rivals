import 'dart:math';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../effects/chase_arrow.dart';
import '../effects/corridor_title.dart';
import '../effects/floating_text.dart';
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
import '../systems/stats_system.dart';
import '../thief/thief_component.dart';
import '../world/parallax_background.dart';
import 'asset_library.dart';
import 'game_config.dart';

class MineRivalsGame extends FlameGame
    with HasCollisionDetection, DragCallbacks, TapCallbacks {
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

  /// Time left stuck in a spider web (player sluggish, thief gains).
  double _webSnareTimer = 0;

  bool get isWebSnared => _webSnareTimer > 0;

  /// Subway-style magnet power-up — pulls loot (not bomb/web).
  double _magnetPowerTimer = 0;

  bool get hasMagnetPower => _magnetPowerTimer > 0;

  double get magnetPowerSeconds => _magnetPowerTimer;

  /// Coin streak for catch pitch-up (+10 popup every 10).
  int _goldStreak = 0;

  /// Consecutive clean catches — you pull further ahead of the thief.
  int successStreak = 0;
  Vector2 shakeOffset = Vector2.zero();
  bool finished = false;
  bool started = false;
  bool _finaleAnnounced = false;
  bool _finishBeat = false;
  double _finishBeatTimer = 0;

  /// Manual slow-mo (FlameGame has no built-in timeScale here).
  double _playRate = 1;
  double? dragX;

  /// Last bomb lane / last free lane after a dual gate.
  int _lastBombLane = -1;

  /// Countdown until another bomb pattern is allowed.
  double _bombCooldown = 0;

  /// Corridor theme sync — apply once per index (no per-frame Future spam).
  int _corridorDesired = -1;
  int _corridorApplied = -1;
  int _corridorFxAt = -1;
  int _corridorGen = 0;

  /// Short HUD banner (steal / finale / etc).
  String? bannerText;
  Color bannerColor = const Color(0xFFEF5350);
  double bannerTimer = 0;

  double get playRate => _playRate;

  double get progress =>
      (distance / GameConfig.levelLengthMeters).clamp(0.0, 1.0);

  double get remainingMeters => (GameConfig.levelLengthMeters - distance).clamp(
    0.0,
    GameConfig.levelLengthMeters,
  );

  bool get inFinale => remainingMeters <= GameConfig.finaleMeters && !finished;

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
    // Assets + audio in parallel; loading overlay keeps animating.
    await Future.wait([AssetLibrary.ensureLoaded(), audio.init()]);

    background = ParallaxBackground(size: size);
    await add(background);

    player = PlayerComponent();
    thief = ThiefComponent();
    chaseArrow = ChaseArrow();
    await add(thief);
    await add(player);
    await add(chaseArrow);

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
        _pulseBanner('Вор впереди', const Color(0xFFEF5350));
        add(
          ScreenFlash(
            color: const Color(0xFFEF5350),
            peakAlpha: 0.12,
            duration: 0.28,
          ),
        );
        _shake(10);
      } else {
        _pulseBanner('Ты впереди', const Color(0xFF66BB6A));
        add(
          ScreenFlash(
            color: const Color(0xFF66BB6A),
            peakAlpha: 0.1,
            duration: 0.26,
          ),
        );
        _shake(6);
      }
    };

    _layoutActors();
    started = true;
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
      t.position = Vector2(
        size.x * 0.5 + t.laneBias,
        depth.thiefY + t.depthBias,
      );
      t.applyDepthScale(depth.thiefScale);
    }
    _updateDrawOrder();
  }

  void _updateDrawOrder() {
    var prio = 10;
    final ordered = _pack.toList()
      ..sort((a, b) => a.position.y.compareTo(b.position.y));
    for (final t in ordered) {
      t.priority = prio;
      prio += 2;
    }
    final frontThiefY = _pack.map((t) => t.position.y).fold<double>(0, max);
    if (player.position.y >= frontThiefY) {
      player.priority = prio + 4;
    } else {
      player.priority = 8;
    }
  }

  void _updateChaseArrow() {
    // Only when you're ahead and the thief is a speck / off the bottom edge.
    final farBehind =
        lead.playerLeads &&
        lead.leadDistance >= GameConfig.chaseArrowLeadMin &&
        !lead.isOvertaking;
    final offish =
        thief.position.y > size.y * 0.92 ||
        thief.size.y < GameConfig.thiefHeight * 0.55;
    chaseArrow.setActive(farBehind && offish);
    chaseArrow.laneX = thief.position.x.clamp(48.0, size.x - 48.0);
    chaseArrow.position.y = size.y - 28;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!started) return;

    if (bannerTimer > 0) {
      bannerTimer -= dt;
      if (bannerTimer <= 0) bannerText = null;
    }

    if (_finishBeat) {
      _finishBeatTimer -= dt;
      if (_finishBeatTimer <= 0) {
        _finishBeat = false;
        _playRate = 1;
        pauseEngine();
        onFinished?.call(stats);
        overlays.add('results');
      }
      return;
    }

    if (finished) return;

    if (_webSnareTimer > 0) _webSnareTimer -= dt;
    if (_magnetPowerTimer > 0) _magnetPowerTimer -= dt;

    var targetRate = inFinale ? 0.62 : 1.0;
    // Whole snare window: world slows so the thief visibly closes in.
    if (_webSnareTimer > 0) {
      targetRate = min(targetRate, GameConfig.webSnarePlayRate);
    }
    _playRate += (targetRate - _playRate) * (1 - (1 / (1 + 8 * dt)));
    final step = dt * _playRate;
    final pace = GameConfig.runSpeedAt(progress);
    final animRate =
        GameConfig.runAnimRateAt(progress) *
        (_webSnareTimer > 0 ? GameConfig.webSnarePlayRate : 1.0);

    distance += pace * step * GameConfig.distanceMeterRate;
    background.setWorldSpeed(pace * _playRate);
    player.setRunAnimRate(animRate);
    for (final t in _pack) {
      t.setRunAnimRate(animRate);
    }
    _syncCorridorTheme();
    _syncExtraThieves();
    _syncFinale();

    _updateLeadDebt(step);
    final playingClean = cleanTimer > 2.5 && _leadDebt <= 0;
    lead.update(step, playingClean: playingClean);
    cleanTimer += step;

    final depth = lead.depthPositions(screenHeight: size.y, dt: step);
    // Straight run — no idle bob; only screen-shake offsets.
    player.position.y = depth.playerY + shakeOffset.y * 0.35;
    player.applyDepthScale(depth.playerScale, step);
    for (final t in _pack) {
      t.position.y = depth.thiefY + t.depthBias + shakeOffset.y * 0.2;
      t.applyDepthScale(depth.thiefScale, step);
    }

    final minX = _pathMinX;
    final maxX = _pathMaxX;
    final desiredX = dragX ?? player.position.x;
    // Spider web makes the miner sticky/slow to steer.
    final moveFactor = _webSnareTimer > 0 ? GameConfig.webSnareMoveFactor : 1.0;
    player.moveToward(desiredX, minX, maxX, step * moveFactor);
    final closeBehind = lead.playerLeads && lead.leadDistance.abs() < 2.2;
    final sprinting = lead.isOvertaking && lead.sprintOvertake;
    for (final t in _pack) {
      t.runLane(
        screenCenterX: size.x * 0.5,
        playerX: player.position.x,
        dt: step,
        overtaking: lead.isOvertaking,
        overtakeT: lead.overtakeT,
        breathingDownNeck:
            closeBehind || (!lead.playerLeads && lead.leadDistance.abs() < 2.2),
        sprinting: sprinting && t.kind == ThiefKind.primary,
      );
    }

    _updateChaseArrow();
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

    spawns.update(step, progress: progress);
    _spawnUpdate(step);
    _magnetAndCatchUpdate(step);
    _stealUpdate(step);
    _missUpdate();

    if (distance >= GameConfig.levelLengthMeters) {
      _beginFinishBeat();
    }
  }

  void _syncFinale() {
    if (!inFinale || _finaleAnnounced) return;
    _finaleAnnounced = true;
    _pulseBanner('Финиш близко!', const Color(0xFFFFE082));
    add(
      FloatingText(
        text: 'Почти финиш!',
        position: Vector2(size.x / 2, size.y * 0.26),
        color: const Color(0xFFFFE082),
        fontSize: 28,
      ),
    );
    audio.play('overtake');
  }

  void _pulseBanner(String text, Color color) {
    bannerText = text;
    bannerColor = color;
    bannerTimer = 1.6;
  }

  void _shake(double intensity) {
    if (!GameSettings.instance.shakeEnabled) return;
    add(ScreenShake(onOffset: (o) => shakeOffset = o, intensity: intensity));
  }

  void _magnetAndCatchUpdate(double dt) {
    final basket = player.basketWorldCenter;
    final powered = hasMagnetPower;

    for (var i = liveItems.length - 1; i >= 0; i--) {
      final item = liveItems[i];
      if (item.collected || item.stolen) continue;

      // Hazards never magnetize — strict touch only.
      if (item.type.isHazard) {
        item.setPlayerMagnet(false);
        final dist = (basket - item.position).length;
        final radius = item.type.isBomb
            ? GameConfig.bombCatchRadius
            : GameConfig.webCatchRadius;
        if (dist <= radius) {
          onItemCaught(item);
        }
        continue;
      }

      // Power magnet: vacuum all loot (incl. jewels / magnet pickup).
      if (powered && item.type.isMagnetizable) {
        _powerMagnetPull(item, basket, dt);
        continue;
      }

      // Non-jewels (coin, bar, magnet): player only.
      if (!item.type.isJewel) {
        _playerMagnetOrCatch(item, basket, dt);
        continue;
      }

      // Jewels: player magnets only while leading (unless powered — above).
      if (!lead.playerLeads) continue;

      _playerMagnetOrCatch(item, basket, dt);
    }
  }

  void _powerMagnetPull(FallingItem item, Vector2 basket, double dt) {
    final delta = basket - item.position;
    final dist = delta.length;
    if (dist > GameConfig.powerMagnetRadius) {
      item.setPlayerMagnet(false);
      return;
    }
    item.setPlayerMagnet(true);
    final pull = min(GameConfig.powerMagnetPullSpeed * dt, dist);
    if (dist > 0.001) {
      item.position += delta.normalized() * pull;
    }
    if (dist <= GameConfig.catchRadius * 0.85) {
      onItemCaught(item);
    }
  }

  void _playerMagnetOrCatch(FallingItem item, Vector2 basket, double dt) {
    final delta = basket - item.position;
    final dist = delta.length;
    final dx = delta.x.abs();
    final dy = item.position.y - basket.y;

    final gold = item.type == ItemType.gold;
    final assistR = gold ? GameConfig.goldSnapRadius : GameConfig.magnetRadius;
    final pullSp = gold
        ? GameConfig.goldSnapPullSpeed
        : GameConfig.magnetPullSpeed;
    final laneSlack = gold ? 22.0 : 12.0;

    final canAssist = dx < laneSlack && dy > -10 && dy < 22 && dist < assistR;
    if (canAssist) {
      item.setPlayerMagnet(true);
      final pull = min(pullSp * dt, dist);
      if (dist > 0.001) {
        item.position += delta.normalized() * pull;
      }
    } else {
      item.setPlayerMagnet(false);
    }

    if (dx <= 18 && dy.abs() <= GameConfig.catchRadius) {
      onItemCaught(item);
    }
  }

  /// Thief phases through everything except jewels (magnet + steal when ahead).
  void _stealUpdate(double dt) {
    final thiefHuntsJewels =
        !lead.playerLeads ||
        (lead.isOvertaking && lead.pendingLeader == Leader.thief);

    if (!thiefHuntsJewels) {
      for (final item in liveItems) {
        item.setThiefMagnet(false);
      }
      return;
    }

    for (var i = liveItems.length - 1; i >= 0; i--) {
      final item = liveItems[i];
      if (item.collected || item.stolen) continue;

      // Same rule as coins: phase through ALL non-jewels (bars, bombs, junk).
      if (!item.type.isJewel) {
        item.setThiefMagnet(false);
        continue;
      }

      ThiefComponent? nearest;
      var bestDist = double.infinity;
      for (final t in _pack) {
        final stealPoint = t.position - Vector2(0, t.size.y * 0.72);
        final d = (stealPoint - item.position).length;
        if (d < bestDist) {
          bestDist = d;
          nearest = t;
        }
      }
      if (nearest == null) continue;

      final stealPoint = nearest.position - Vector2(0, nearest.size.y * 0.72);
      final delta = stealPoint - item.position;
      final dist = delta.length;
      final inRange =
          dist < GameConfig.thiefMagnetRadius &&
          item.position.y > nearest.position.y - nearest.size.y * 1.1 &&
          item.position.y < nearest.position.y + 40;

      if (inRange) {
        item.setThiefMagnet(true);
        final pull = min(GameConfig.thiefMagnetPullSpeed * dt, dist);
        if (dist > 0.001) {
          item.position += delta.normalized() * pull;
        }
      } else {
        item.setThiefMagnet(false);
      }

      if (dist < 22) {
        _thiefSteal(item);
      }
    }
  }

  void _spawnUpdate(double dt) {
    _bombCooldown = max(0, _bombCooldown - dt);

    spawnTimer -= dt;
    if (spawnTimer > 0) return;

    final beat = spawns.nextBeat(progress: progress);
    spawnTimer = spawns.gapFor(beat, progress: progress);

    // Empty corridor beat — teach “challenge incoming” before bomb gates.
    if (beat.silence) return;

    if (beat.bombPattern || beat.type.isBomb) {
      final bombLive = liveItems.any((e) => e.type.isBomb);
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

    // Spider web — rare interrupt (never replaces magnet / row).
    final level = background.corridorIndex + 1;
    if (!beat.type.isMagnet &&
        !beat.row &&
        level >= GameConfig.webFromCorridor &&
        _rng.nextDouble() < GameConfig.webSpawnChance &&
        !liveItems.any((e) => e.type.isWeb)) {
      final lane = beat.lane ?? _rng.nextInt(GameConfig.bombLaneCount);
      _spawnLiveItem(
        type: ItemType.web,
        position: Vector2(_laneX(lane), -40),
        fallSpeed: background.speed,
      );
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

  void _spawnLiveItem({
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
  }

  void _releaseLiveItem(FallingItem item) {
    liveItems.remove(item);
    pool.release(item);
  }

  /// Single / dual / stagger — always at least one free row (never a full wall).
  void _spawnBombPattern(SpawnBeat beat) {
    final dual =
        beat.forceDual ?? (_rng.nextDouble() < GameConfig.bombDualChance);
    final y = -40.0;
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
        _spawnLiveItem(
          type: ItemType.bomb,
          position: Vector2(_laneX(lane), y),
          fallSpeed: speed,
        );
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
      _spawnLiveItem(
        type: ItemType.bomb,
        position: Vector2(_laneX(lane), y),
        fallSpeed: speed,
      );

      // Dodge-punish: second bomb arrives a beat later on the escape lane.
      final follow = beat.staggerBombLane;
      if (follow != null && follow != lane) {
        final delayY = -(speed * 0.34).clamp(48.0, 130.0);
        _spawnLiveItem(
          type: ItemType.bomb,
          position: Vector2(_laneX(follow), y + delayY),
          fallSpeed: speed,
        );
        _lastBombLane = follow;
      }
    }

    _bombCooldown =
        GameConfig.bombCooldownMin +
        _rng.nextDouble() *
            (GameConfig.bombCooldownMax - GameConfig.bombCooldownMin);
    spawnTimer = max(spawnTimer, _bombCooldown * 0.5);
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
      final item = liveItems[i];
      if (item.collected || item.stolen) continue;

      final pastBottom = item.position.y > size.y + 60;
      final pastFeet = item.position.y > player.position.y + 36;
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
        _goldStreak = 0;
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
          _punishMistake(GameConfig.leadLossOnMissRare);
        } else {
          _punishMistake(GameConfig.leadLossOnMiss);
        }
      }
      item.magnetBy = ItemMagnet.none;
      _releaseLiveItem(item);
    }
  }

  /// Mistakes queue chase debt — thief closes the gap over time, no instant pass.
  void _punishMistake(double baseLoss) {
    successStreak = 0;
    mistakeStreak = (mistakeStreak + 1).clamp(1, 6);
    final extra = (mistakeStreak - 1) * GameConfig.leadLossPerMistakeStreak;
    final add = (baseLoss + extra).clamp(0.0, 2.2);
    _leadDebt = (_leadDebt + add).clamp(0.0, GameConfig.leadDebtMax);
    _pulseBanner(
      mistakeStreak <= 1 ? 'Вор догоняет…' : 'Вор всё ближе!',
      const Color(0xFFFF7043),
    );
  }

  /// Player ran into a spider web — bomb-like hitch: slow + thief closes in.
  /// (No crystal loss — that's bombs only.)
  void _triggerWebSnare() {
    _webSnareTimer = GameConfig.webSnareDuration;
    // Same chase pipeline as a bomb / miss so the thief actually gains.
    _punishMistake(GameConfig.leadLossOnWeb);
    audio.play('miss');
    _pulseBanner('Паутина! Вор догоняет', const Color(0xFFB0BEC5));
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
    final rate = GameConfig.leadDebtPerSec * (1 + (mistakeStreak - 1) * 0.22);
    final step = min(_leadDebt, rate * dt);
    _leadDebt -= step;
    lead.applyDelta(-step);
  }

  /// Clean catches stack — you open a bigger gap behind you.
  void _rewardSuccess(double baseGain, {bool showPullAway = false}) {
    mistakeStreak = 0;
    _leadDebt = 0;
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
      if (item.type.isBomb) {
        _goldStreak = 0;
        stats.player.registerCatch(isBomb: true);
        final lostCrystal = stats.player.loseOneRare();
        cleanTimer = 0;
        _punishMistake(GameConfig.leadLossOnBomb);
        audio.play('bomb');
        add(
          ParticleBurst(position: item.position.clone(), color: Colors.orange),
        );
        add(
          ScreenFlash(
            color: const Color(0xFFFF6D00),
            peakAlpha: 0.16,
            duration: 0.32,
          ),
        );
        _shake(14);
        add(
          FloatingText(
            text: lostCrystal ? '−1' : 'Бум!',
            position: item.position.clone(),
            color: lostCrystal ? const Color(0xFFFF5252) : Colors.orangeAccent,
          ),
        );
        _releaseLiveItem(item);
        return;
      }

      if (item.type.isWeb) {
        _goldStreak = 0;
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

      if (item.type.isMagnet) {
        _activateMagnetPower();
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

      // Gold coin / gold bar (coal)
      stats.player.addItem(item.type);
      stats.player.registerCatch(isBomb: false);
      _rewardSuccess(GameConfig.leadGainOnCatch);

      final popup = _lootPopupFor(item.type);
      if (item.type == ItemType.gold) {
        _goldStreak++;
        final pitch = 1.0 + min(0.48, (_goldStreak - 1) * 0.055);
        audio.playCatchPitched(pitch);
      } else {
        audio.play('catch');
      }

      add(
        ParticleBurst(
          position: item.position.clone(),
          color: item.type.color,
          count: item.type == ItemType.gold ? 8 : 10,
        ),
      );
      add(
        FloatingText(
          text: popup,
          position: item.position.clone(),
          color: item.type == ItemType.gold
              ? const Color(0xFFFFD54F)
              : item.type.color,
          fontSize: popup == '+10' ? 26 : 22,
        ),
      );
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
    _rewardSuccess(GameConfig.leadGainOnRare, showPullAway: true);
    audio.play('rare');
    add(BasketSpark(position: player.basketWorldCenter.clone()));

    if (stats.player.currentStreak > 0 &&
        stats.player.currentStreak % GameConfig.comboThreshold == 0) {
      _rewardSuccess(GameConfig.leadGainOnCombo, showPullAway: true);
      audio.play('combo');
      add(
        FloatingText(
          text: '+10',
          position: item.position.clone() - Vector2(0, 28),
          color: const Color(0xFFFFD54F),
          fontSize: 24,
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
    audio.play('steal');
    add(
      ScreenFlash(
        color: const Color(0xFFEF5350),
        peakAlpha: 0.14,
        duration: 0.3,
      ),
    );
    _shake(11);
    add(
      ParticleBurst(
        position: item.position.clone(),
        color: item.type.color,
        count: 12,
      ),
    );
    add(
      FloatingText(
        text: '+1',
        position: thief.position - Vector2(0, 50),
        color: item.type.color,
      ),
    );
    _releaseLiveItem(item);
  }

  void _beginFinishBeat() {
    if (finished) return;
    finished = true;
    _finishBeat = true;
    _finishBeatTimer = 1.85;
    _playRate = 0.55;

    final win = stats.playerWins;
    final you = stats.player.rareTotal;
    final thief = stats.thief.rareTotal;
    _pulseBanner(
      win ? 'Победа! $you–$thief' : 'Вор выиграл $thief–$you',
      win ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
    );
    add(
      ScreenFlash(
        color: win ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
        peakAlpha: 0.14,
        duration: 0.45,
      ),
    );
    add(
      FloatingText(
        text: win ? 'Ты собрал больше!' : 'Вор унёс больше!',
        position: Vector2(size.x / 2, size.y * 0.28),
        color: win ? const Color(0xFF81C784) : const Color(0xFFFF8A65),
        fontSize: 28,
      ),
    );
    add(
      FloatingText(
        text: 'Ты $you   Вор $thief',
        position: Vector2(size.x / 2, size.y * 0.36),
        color: const Color(0xFFFFE082),
        fontSize: 22,
      ),
    );
    audio.play(win ? 'combo' : 'steal');
  }

  /// Pause for in-run menu sheet.
  void pauseForMenu() {
    if (finished || _finishBeat) return;
    pauseEngine();
  }

  void resumeFromMenu() {
    if (finished || _finishBeat) return;
    resumeEngine();
  }

  /// End the run early and show results (forfeit / quit from menu).
  void endRunEarly() {
    if (finished || _finishBeat) return;
    finished = true;
    _finishBeat = false;
    _webSnareTimer = 0;
    _magnetPowerTimer = 0;
    _goldStreak = 0;
    _playRate = 1;
    pauseEngine();
    overlays.add('results');
  }

  void restart() {
    overlays.remove('results');
    overlays.remove('pause');
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
    _webSnareTimer = 0;
    _magnetPowerTimer = 0;
    _goldStreak = 0;
    successStreak = 0;
    _lastBombLane = -1;
    _bombCooldown = 0;
    _corridorDesired = -1;
    _corridorApplied = -1;
    _corridorFxAt = -1;
    _corridorGen = 0;
    finished = false;
    _finaleAnnounced = false;
    _finishBeat = false;
    _finishBeatTimer = 0;
    bannerText = null;
    bannerTimer = 0;
    _playRate = 1;
    shakeOffset.setZero();
    dragX = null;
    chaseArrow.setActive(false);
    background.resetCorridors();
    AssetLibrary.applyCorridorJewels(0);
    pool.clearJewels();
    _clearExtraThieves();
    _layoutActors();
    resumeEngine();
  }

  void _clearExtraThieves() {
    thiefBlue?.removeFromParent();
    thiefBlue = null;
  }

  /// After shaft 6 → blue joins as the second rival.
  void _syncExtraThieves() {
    final level = background.corridorIndex + 1;
    final wantBlue = level >= GameConfig.blueThiefFromCorridor;

    if (wantBlue && thiefBlue == null) {
      final t = ThiefComponent(kind: ThiefKind.blue);
      thiefBlue = t;
      // Await load before scale — otherwise late _shadow crashes.
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
    if (distance > 1) {
      _pulseBanner('Синий вор!', const Color(0xFF42A5F5));
    }
  }

  void _syncCorridorTheme() {
    final idx = (distance / GameConfig.corridorSegmentMeters).floor().clamp(
      0,
      GameConfig.corridorCount - 1,
    );
    // Already applied this shaft — nothing to do.
    if (idx == _corridorApplied && idx == _corridorDesired) return;
    // Load already in flight for this idx.
    if (idx == _corridorDesired && idx != _corridorApplied) return;

    _corridorDesired = idx;
    final gen = ++_corridorGen;

    // Title / flash / audio once per shaft enter (not every frame).
    if (idx != _corridorFxAt && distance > 1) {
      _corridorFxAt = idx;
      children.whereType<CorridorTitle>().toList().forEach(
        (e) => e.removeFromParent(),
      );
      add(
        CorridorTitle(
          label: '${idx + 1} из ${GameConfig.corridorCount}',
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
      background.setCorridorIndex(idx);
      AssetLibrary.applyCorridorJewels(idx);
      for (final item in liveItems) {
        if (item.type.isJewel) item.refreshSprite();
      }
      _corridorApplied = idx;
    });
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    dragX = event.localPosition.x.clamp(_pathMinX, _pathMaxX);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    dragX = ((dragX ?? player.position.x) + event.localDelta.x).clamp(
      _pathMinX,
      _pathMaxX,
    );
  }

  @override
  void onTapDown(TapDownEvent event) {
    dragX = event.localPosition.x.clamp(_pathMinX, _pathMaxX);
  }
}
