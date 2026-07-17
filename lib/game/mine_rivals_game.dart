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
  MineRivalsGame({this.onFinished});

  final void Function(MatchStats stats)? onFinished;

  final LeadSystem lead = LeadSystem();
  final MatchStats stats = MatchStats();
  final ItemPool pool = ItemPool();
  final SpawnDirector spawns = SpawnDirector();
  final AudioManager audio = AudioManager();
  final Random _rng = Random();

  late PlayerComponent player;
  late ThiefComponent thief;
  late ParallaxBackground background;
  late ChaseArrow chaseArrow;

  double distance = 0;
  double spawnTimer = 0;
  double cleanTimer = 0;
  double dustTimer = 0;
  double cameraBob = 0;
  /// Consecutive misses/bombs — each one pushes the thief further away.
  int mistakeStreak = 0;
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

  /// Short HUD banner (steal / finale / etc).
  String? bannerText;
  Color bannerColor = const Color(0xFFEF5350);
  double bannerTimer = 0;

  double get playRate => _playRate;

  double get progress =>
      (distance / GameConfig.levelLengthMeters).clamp(0.0, 1.0);

  double get remainingMeters =>
      (GameConfig.levelLengthMeters - distance).clamp(0.0, GameConfig.levelLengthMeters);

  bool get inFinale =>
      remainingMeters <= GameConfig.finaleMeters && !finished;

  @override
  Color backgroundColor() => const Color(0xFF1A120B);

  @override
  Future<void> onLoad() async {
    await AssetLibrary.ensureLoaded();
    await audio.init();

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
    thief.position = Vector2(size.x * 0.5, depth.thiefY);
    player.applyDepthScale(depth.playerScale);
    thief.applyDepthScale(depth.thiefScale);
    _updateDrawOrder();
  }

  void _updateDrawOrder() {
    if (player.position.y >= thief.position.y) {
      player.priority = 25;
      thief.priority = 12;
    } else {
      player.priority = 12;
      thief.priority = 25;
    }
  }

  void _updateChaseArrow() {
    // Only when you're ahead and the thief is a speck / off the bottom edge.
    final farBehind = lead.playerLeads &&
        lead.leadDistance >= GameConfig.chaseArrowLeadMin &&
        !lead.isOvertaking;
    final offish = thief.position.y > size.y * 0.92 ||
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

    final targetRate = inFinale ? 0.62 : 1.0;
    _playRate += (targetRate - _playRate) * (1 - (1 / (1 + 6 * dt)));
    final step = dt * _playRate;
    final pace = GameConfig.runSpeedAt(progress);

    distance += pace * step;
    background.setWorldSpeed(pace * _playRate);
    _syncCorridorTheme();
    _syncFinale();
    cameraBob += step * 3.2;

    final playingClean = cleanTimer > 2.5;
    lead.update(step, playingClean: playingClean);
    cleanTimer += step;

    final depth = lead.depthPositions(screenHeight: size.y, dt: step);
    final bob = sin(cameraBob) * 0.35;
    player.position.y = depth.playerY + bob * 0.25 + shakeOffset.y * 0.35;
    thief.position.y = depth.thiefY + bob * 0.15 + shakeOffset.y * 0.2;
    player.applyDepthScale(depth.playerScale, step);
    thief.applyDepthScale(depth.thiefScale, step);

    final minX = 70.0;
    final maxX = size.x - 70.0;
    final desiredX = dragX ?? player.position.x;
    player.moveToward(desiredX + shakeOffset.x, minX, maxX, step);
    final closeBehind = lead.playerLeads && lead.leadDistance.abs() < 2.2;
    final sprinting = lead.isOvertaking && lead.sprintOvertake;
    thief.runLane(
      screenCenterX: size.x * 0.5,
      playerX: player.position.x,
      dt: step,
      overtaking: lead.isOvertaking,
      overtakeT: lead.overtakeT,
      breathingDownNeck:
          closeBehind || (!lead.playerLeads && lead.leadDistance.abs() < 2.2),
      sprinting: sprinting,
    );

    _updateChaseArrow();
    _updateDrawOrder();

    dustTimer += step;
    if (dustTimer > 0.22) {
      dustTimer = 0;
      add(DustPuff(position: player.position + Vector2(0, -6)));
      if (_rng.nextBool()) {
        add(DustPuff(position: thief.position + Vector2(0, -6)));
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
    add(
      ScreenShake(
        onOffset: (o) => shakeOffset = o,
        intensity: intensity,
      ),
    );
  }

  void _magnetAndCatchUpdate(double dt) {
    final basket = player.basketWorldCenter;
    for (final item in children.whereType<FallingItem>().toList()) {
      if (item.collected || item.stolen) continue;

      // Non-jewels (coin, bar, bomb): player only — thief always phases through.
      if (!item.type.isJewel) {
        if (item.type.isBomb) {
          item.setPlayerMagnet(false);
          final dx = (basket.x - item.position.x).abs();
          final dy = (basket.y - item.position.y).abs();
          // Tighter than loot — glancing pass doesn't always explode.
          if (dx <= GameConfig.bombCatchRadius &&
              dy <= GameConfig.bombCatchRadius) {
            onItemCaught(item);
          }
        } else {
          _playerMagnetOrCatch(item, basket, dt);
        }
        continue;
      }

      // Jewels: player magnets only while leading.
      if (!lead.playerLeads) continue;

      _playerMagnetOrCatch(item, basket, dt);
    }
  }

  void _playerMagnetOrCatch(FallingItem item, Vector2 basket, double dt) {
    final delta = basket - item.position;
    final dist = delta.length;
    final dx = delta.x.abs();
    final dy = item.position.y - basket.y;

    final canAssist =
        dx < 12 && dy > -8 && dy < 16 && dist < GameConfig.magnetRadius;
    if (canAssist) {
      item.setPlayerMagnet(true);
      final pull = min(GameConfig.magnetPullSpeed * dt, dist);
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
    final thiefHuntsJewels = !lead.playerLeads ||
        (lead.isOvertaking && lead.pendingLeader == Leader.thief);

    if (!thiefHuntsJewels) {
      for (final item in children.whereType<FallingItem>()) {
        item.setThiefMagnet(false);
      }
      return;
    }

    final stealPoint = thief.position - Vector2(0, thief.size.y * 0.72);

    for (final item in children.whereType<FallingItem>().toList()) {
      if (item.collected || item.stolen) continue;

      // Same rule as coins: phase through ALL non-jewels (bars, bombs, junk).
      if (!item.type.isJewel) {
        item.setThiefMagnet(false);
        continue;
      }

      final delta = stealPoint - item.position;
      final dist = delta.length;

      final inRange = dist < GameConfig.thiefMagnetRadius &&
          item.position.y > stealPoint.y - 80 &&
          item.position.y < stealPoint.y + 40 &&
          item.life < 6.0;

      if (inRange) {
        item.setThiefMagnet(true);
        final pull = min(GameConfig.thiefMagnetPullSpeed * dt, dist);
        if (dist > 0.001) {
          item.position += delta.normalized() * pull;
        }
      } else {
        item.setThiefMagnet(false);
      }

      if (dist < 32) {
        _thiefSteal(item);
      }
    }
  }

  void _spawnUpdate(double dt) {
    _bombCooldown = max(0, _bombCooldown - dt);

    spawnTimer -= dt;
    if (spawnTimer > 0) return;
    spawnTimer = spawns.nextInterval(progress: progress);

    var type = spawns.rollType(progress: progress);
    if (type.isBomb) {
      final bombLive =
          children.whereType<FallingItem>().any((e) => e.type.isBomb);
      if (bombLive || _bombCooldown > 0) {
        type = _rng.nextBool() ? ItemType.gold : ItemType.coal;
      } else {
        _spawnBombPattern();
        return;
      }
    }

    final x = _pickLootX();
    final item = pool.acquire(
      type: type,
      position: Vector2(x, -40),
      fallSpeed: background.speed,
    );
    add(item);
  }

  /// Single bomb OR a 2-lane gate — always exactly one free row to dodge.
  void _spawnBombPattern() {
    final dual = _rng.nextDouble() < GameConfig.bombDualChance;
    final y = -40.0;
    final speed = background.speed;

    if (dual) {
      // Pick the escape lane (never seal all three).
      var freeLane = _rng.nextInt(GameConfig.bombLaneCount);
      if (freeLane == _lastBombLane && GameConfig.bombLaneCount > 1) {
        freeLane = (freeLane + 1 + _rng.nextInt(GameConfig.bombLaneCount - 1)) %
            GameConfig.bombLaneCount;
      }
      for (var lane = 0; lane < GameConfig.bombLaneCount; lane++) {
        if (lane == freeLane) continue;
        final item = pool.acquire(
          type: ItemType.bomb,
          position: Vector2(_laneX(lane), y),
          fallSpeed: speed,
        );
        add(item);
      }
      // Remember free lane so the next gate opens somewhere else.
      _lastBombLane = freeLane;
    } else {
      final lanes = List<int>.generate(GameConfig.bombLaneCount, (i) => i)
        ..removeWhere((l) => l == _lastBombLane)
        ..shuffle(_rng);
      final lane =
          lanes.isEmpty ? _rng.nextInt(GameConfig.bombLaneCount) : lanes.first;
      _lastBombLane = lane;
      final item = pool.acquire(
        type: ItemType.bomb,
        position: Vector2(_laneX(lane), y),
        fallSpeed: speed,
      );
      add(item);
    }

    _bombCooldown = GameConfig.bombCooldownMin +
        _rng.nextDouble() *
            (GameConfig.bombCooldownMax - GameConfig.bombCooldownMin);
    spawnTimer = max(spawnTimer, _bombCooldown * 0.55);
  }

  /// Loot prefers the three lanes (slight jitter).
  double _pickLootX() {
    final lane = _rng.nextInt(GameConfig.bombLaneCount);
    final jitter = (_rng.nextDouble() - 0.5) * 18;
    return _laneX(lane) + jitter;
  }

  double _laneX(int lane) {
    final minX = 70.0;
    final maxX = size.x - 70.0;
    final t = (lane + 0.5) / GameConfig.bombLaneCount;
    return minX + (maxX - minX) * t;
  }

  void _missUpdate() {
    final basket = player.basketWorldCenter;
    for (final item in children.whereType<FallingItem>().toList()) {
      if (item.collected || item.stolen) continue;

      final pastBottom = item.position.y > size.y + 60;
      final pastFeet = item.position.y > player.position.y + 36;
      final stuck = item.life > 7.5;
      if (!pastBottom && !pastFeet && !stuck) continue;

      if (!item.type.isBomb && (pastFeet || pastBottom)) {
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
      pool.release(item);
    }
  }

  /// Each mistake stacks — thief can pull +5…+10m ahead on a bad streak.
  void _punishMistake(double baseLoss) {
    successStreak = 0;
    mistakeStreak = (mistakeStreak + 1).clamp(1, 6);
    final extra =
        (mistakeStreak - 1) * GameConfig.leadLossPerMistakeStreak;
    final total = (baseLoss + extra).clamp(0.0, 10.0);
    lead.applyDelta(-total);
    _pulseBanner(
      '−${total.toStringAsFixed(0)} м',
      const Color(0xFFFF7043),
    );
  }

  /// Clean catches stack — you open a bigger gap behind you.
  void _rewardSuccess(double baseGain, {bool showPullAway = false}) {
    mistakeStreak = 0;
    successStreak = (successStreak + 1).clamp(1, 8);
    final extra = (successStreak - 1) * GameConfig.successStreakLeadBonus;
    final total = (baseGain + extra).clamp(0.0, 8.0);
    lead.applyDelta(total);
    if (showPullAway || successStreak >= 3) {
      _pulseBanner(
        '+${total.toStringAsFixed(0)} м',
        const Color(0xFF66BB6A),
      );
    }
  }

  void onItemCaught(FallingItem item) {
    if (item.collected || item.stolen || finished || _finishBeat) return;

    // Non-jewels always go to the player — never redirected to thief.
    if (!item.type.isJewel) {
      item.collected = true;
      if (item.type.isBomb) {
        stats.player.registerCatch(isBomb: true);
        cleanTimer = 0;
        _punishMistake(GameConfig.leadLossOnBomb);
        audio.play('bomb');
        add(ParticleBurst(position: item.position.clone(), color: Colors.orange));
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
            text: '−1',
            position: item.position.clone(),
            color: Colors.orangeAccent,
          ),
        );
        pool.release(item);
        return;
      }

      // Gold coin / gold bar (coal) / any future junk loot
      stats.player.addItem(item.type);
      stats.player.registerCatch(isBomb: false);
      _rewardSuccess(GameConfig.leadGainOnCatch);
      audio.play('catch');
      add(
        ParticleBurst(
          position: item.position.clone(),
          color: item.type.color,
          count: 10,
        ),
      );
      add(
        FloatingText(
          text: item.type.popupLabel,
          position: item.position.clone(),
          color: item.type.color,
        ),
      );
      pool.release(item);
      return;
    }

    item.collected = true;

    // Jewels: contested by lead.
    if (!lead.playerLeads && !lead.isOvertaking) {
      item.collected = false;
      _thiefSteal(item);
      return;
    }

    stats.player.addItem(item.type);
    stats.player.registerCatch(isBomb: false);
    _rewardSuccess(GameConfig.leadGainOnRare, showPullAway: true);
    audio.play('rare');

    if (stats.player.currentStreak > 0 &&
        stats.player.currentStreak % GameConfig.comboThreshold == 0) {
      _rewardSuccess(GameConfig.leadGainOnCombo, showPullAway: true);
      audio.play('combo');
      add(
        FloatingText(
          text: '+1',
          position: item.position.clone() - Vector2(0, 28),
          color: const Color(0xFFFFD54F),
          fontSize: 22,
        ),
      );
    }

    add(
      ParticleBurst(
        position: item.position.clone(),
        color: item.type.color,
        count: 18,
      ),
    );
    add(
      FloatingText(
        text: item.type.popupLabel,
        position: item.position.clone(),
        color: item.type.color,
      ),
    );
    pool.release(item);
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
    pool.release(item);
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

  void restart() {
    overlays.remove('results');
    children.whereType<FallingItem>().toList().forEach((e) => e.removeFromParent());
    children.whereType<FloatingText>().toList().forEach((e) => e.removeFromParent());
    children.whereType<CorridorTitle>().toList().forEach((e) => e.removeFromParent());
    children.whereType<DustPuff>().toList().forEach((e) => e.removeFromParent());
    children.whereType<ParticleBurst>().toList().forEach((e) => e.removeFromParent());
    children.whereType<ScreenFlash>().toList().forEach((e) => e.removeFromParent());
    children.whereType<ScreenShake>().toList().forEach((e) => e.removeFromParent());

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
    successStreak = 0;
    _lastBombLane = -1;
    _bombCooldown = 0;
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
    _layoutActors();
    resumeEngine();
  }

  void _syncCorridorTheme() {
    final idx = (distance / GameConfig.corridorSegmentMeters)
        .floor()
        .clamp(0, GameConfig.corridorCount - 1);
    final changed = idx != background.corridorIndex;
    background.setCorridorIndex(idx);
    if (changed && distance > 1) {
      // Clear any leftover titles, then show a quiet top label for 2s.
      children.whereType<CorridorTitle>().toList().forEach((e) => e.removeFromParent());
      add(
        CorridorTitle(
          label: '${idx + 1}-й уровень',
          position: Vector2(size.x * 0.5, 52),
        ),
      );
      add(
        ScreenFlash(
          color: const Color(0xFFFFE082),
          peakAlpha: 0.06,
          duration: 0.55,
        ),
      );
      audio.play('overtake');
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    dragX = event.localPosition.x;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    dragX = (dragX ?? player.position.x) + event.localDelta.x;
  }

  @override
  void onTapDown(TapDownEvent event) {
    dragX = event.localPosition.x;
  }
}
