import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/services.dart';

import '../items/item_type.dart';
import '../systems/game_settings.dart';
import 'asset_workers.dart';
import 'game_config.dart';
import 'player_skins.dart';

/// Loads PNGs and slices run cycles for play. Keep boot staged — menu must
/// never call this; GameLoadingScreen covers the wait.
class AssetLibrary {
  AssetLibrary._();

  static SpriteAnimation? minerRun;
  static SpriteAnimation? thiefRun;
  static SpriteAnimation? thiefRunBlue;

  /// All playable skins keyed by [PlayerSkin.id].
  static final Map<String, SpriteAnimation> skinRuns = {};

  /// First corridor (classic) — kept for callers that expect a single sprite.
  static Sprite? tunnel;

  /// Ordered shafts from assets/images/bgc/1.png … 10.png (index 0 → 1.png).
  /// Names must match the art — verified against each PNG.
  static final List<Sprite> corridors = [];
  static const List<String> corridorNames = [
    'Ледяная шахта', // 1.png — snow, ice, blue crystals
    'Грибная шахта', // 2.png — moss, neon mushrooms
    'Янтарная шахта', // 3.png — warm orange crystals, gold ore
    'Изумрудная шахта', // 4.png — green crystals, moss
    'Лавовая шахта', // 5.png — magma floor, red crystals
    'Кристальная шахта', // 6.png — deep ice + blue crystal carts
    'Аметистовая шахта', // 7.png — purple crystals / lanterns
    'Золотая шахта', // 8.png — amber glow, gold-filled carts
    'Моховая шахта', // 9.png — vines, emerald glow
    'Теневая шахта', // 10.png — dark purple amethyst tunnel
  ];
  static final Map<ItemType, Sprite> items = {};

  /// Per-corridor jewel sets — unused; one global diamond for all shafts.
  static final List<List<Sprite>> corridorJewels = [];
  static const int _assetVersion = 59;
  static int _loadedVersion = 0;

  static Future<void>? _loadFuture;
  static final Map<String, Future<void>> _skinFutures = {};
  static Future<void>? _thiefBlueFuture;
  static bool _prefetchStarted = false;
  /// Bumps when a new core load starts — stale loads must not write results.
  static int _loadGen = 0;

  static final List<bool> _corridorLoaded =
      List<bool>.filled(GameConfig.corridorAssetCount, false);
  static bool _universalDiamondLoaded = false;

  /// No overlap — pre-baked seamless PNGs. Overlap looked like a transparent band.
  static const double corridorSeamFadeFrac = 0;

  static bool get ready =>
      minerRun != null &&
      thiefRun != null &&
      skinRuns.isNotEmpty &&
      corridors.isNotEmpty &&
      items.containsKey(ItemType.diamond) &&
      _loadedVersion == _assetVersion;

  /// Optional background warm — never throws to the zone (avoids debugger ANR).
  static Future<void> warmUp() async {
    try {
      await ensureLoaded(prefetchRest: false);
    } catch (e, st) {
      assert(() {
        // ignore: avoid_print
        print('AssetLibrary.warmUp failed: $e\n$st');
        return true;
      }());
    }
  }

  static SpriteAnimation minerRunForSelected() {
    final id = GameSettings.instance.selectedSkinId;
    return skinRuns[id] ?? skinRuns[PlayerSkins.defaultId] ?? minerRun!;
  }

  static Sprite corridorAt(int index) {
    if (corridors.isEmpty) {
      throw StateError('Corridors not loaded');
    }
    final i = index.clamp(0, corridors.length - 1);
    return corridors[i];
  }

  /// Prefetch extra corridors after the run is on screen (never during boot).
  static void startBackgroundPrefetch() {
    if (!ready) return;
    unawaited(() async {
      try {
        await _prefetchRemaining();
      } catch (e, st) {
        assert(() {
          // ignore: avoid_print
          print('Asset prefetch skipped: $e\n$st');
          return true;
        }());
      }
    }());
  }

  /// Soft blue-thief load — never throws to the zone (Long mode background).
  static Future<void> ensureThiefBlueLoadedSafe() async {
    try {
      await ensureThiefBlueLoaded();
    } catch (e, st) {
      assert(() {
        // ignore: avoid_print
        print('Blue thief load skipped: $e\n$st');
        return true;
      }());
    }
  }

  static Future<void> ensureLoaded({bool prefetchRest = false}) async {
    Flame.images.prefix = '';
    if (ready) {
      await _ensureSelectedSkin();
      if (prefetchRest) startBackgroundPrefetch();
      return;
    }

    // Join in-flight load — never start a second _loadCore (race = hang).
    final existing = _loadFuture;
    if (existing != null) {
      try {
        await existing;
      } catch (_) {
        if (identical(_loadFuture, existing)) _loadFuture = null;
      }
      if (ready) {
        await _ensureSelectedSkin();
        if (prefetchRest) startBackgroundPrefetch();
        return;
      }
      // Failed / abandoned — bump gen so a late write can't mark ready.
      _loadGen++;
      _loadFuture = null;
    }

    final gen = ++_loadGen;
    final load = _loadCore(gen);
    _loadFuture = load;
    try {
      await load;
    } catch (_) {
      if (_loadGen == gen) _loadFuture = null;
      rethrow;
    }
    if (_loadGen != gen) {
      // Superseded — wait for the newer load if any.
      final newer = _loadFuture;
      if (newer != null) await newer;
    }
    if (!ready) {
      _loadFuture = null;
      throw StateError('AssetLibrary finished but not ready');
    }
    if (prefetchRest) startBackgroundPrefetch();
  }

  static Future<void> _ensureSelectedSkin() async {
    await ensureSkinLoaded(GameSettings.instance.selectedSkinId);
    minerRun = minerRunForSelected();
  }

  static Future<void> _loadCore(int gen) async {
    items.clear();
    minerRun = null;
    thiefRun = null;
    thiefRunBlue = null;
    skinRuns.clear();
    _skinFutures.clear();
    _thiefBlueFuture = null;
    _prefetchStarted = false;
    tunnel = null;
    corridors.clear();
    corridorJewels.clear();
    _corridorLoaded.fillRange(0, _corridorLoaded.length, false);
    _universalDiamondLoaded = false;

    Flame.images.prefix = '';

    final selected = GameSettings.instance.selectedSkinId;
    final needDefault = selected != PlayerSkins.defaultId;

    bool alive() => _loadGen == gen;

    // Staged boot — one heavy decode at a time so loading UI stays alive.
    final elementsImg = await _loadImage('assets/elements.png');
    if (!alive()) return;
    _sliceElements(elementsImg);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!alive()) return;

    await _loadHazardOrFallback(
      ItemType.dynamiteCart,
      'assets/images/hazards/dynamite_cart.png',
    );
    if (!alive()) return;
    await _loadHazardOrFallback(
      ItemType.spikes,
      'assets/images/hazards/spikes.png',
    );
    if (!alive()) return;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!alive()) return;

    await _loadCorridorSlot(0);
    if (!alive()) return;
    await _loadUniversalDiamond();
    if (!alive()) return;
    applyCorridorJewels(0);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!alive()) return;

    await _loadThiefPrimary();
    if (!alive()) return;
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!alive()) return;
    await ensureSkinLoaded(selected);
    if (!alive()) return;
    if (needDefault) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!alive()) return;
      await ensureSkinLoaded(PlayerSkins.defaultId);
    }
    if (!alive()) return;

    minerRun = minerRunForSelected();
    _loadedVersion = _assetVersion;
  }

  static Future<ui.Image> _loadImage(String path) {
    Flame.images.prefix = '';
    return Flame.images.load(path).timeout(const Duration(seconds: 12));
  }

  static Future<void> _loadHazardOrFallback(ItemType type, String path) async {
    ui.Image? img;
    // Bounded decode — oversized hazard PNGs used to ANR the loading screen.
    try {
      final data = await rootBundle
          .load(path)
          .timeout(const Duration(seconds: 5));
      final bytes = Uint8List.sublistView(data);
      final codec = await ui
          .instantiateImageCodec(bytes, targetWidth: 256)
          .timeout(const Duration(seconds: 5));
      final frame =
          await codec.getNextFrame().timeout(const Duration(seconds: 5));
      img = frame.image;
      try {
        Flame.images.add(path, img);
      } catch (_) {}
    } catch (e) {
      // ignore: avoid_print
      print('Hazard rootBundle miss ($path): $e');
    }
    if (img == null) {
      try {
        img = await _loadImage(path);
      } catch (e) {
        // ignore: avoid_print
        print('Hazard Flame load miss ($path): $e');
      }
    }
    if (img != null) {
      items[type] = Sprite(img);
      // ignore: avoid_print
      print('Hazard OK $type ${img.width}x${img.height}');
      return;
    }
    // Never plant gold/bomb here — that made spikes look like coins.
    items.remove(type);
    // ignore: avoid_print
    print('Hazard MISSING $type — no sprite planted');
  }

  /// True only when [type] has its own hazard PNG (not loot/bomb crop).
  static bool hasRealHazardArt(ItemType type) {
    final s = items[type];
    if (s == null) return false;
    final gold = items[ItemType.gold];
    final bomb = items[ItemType.bomb];
    if (gold != null &&
        identical(s.image, gold.image) &&
        s.srcPosition == gold.srcPosition &&
        s.srcSize == gold.srcSize) {
      return false;
    }
    if (bomb != null &&
        identical(s.image, bomb.image) &&
        s.srcPosition == bomb.srcPosition &&
        s.srcSize == bomb.srcSize) {
      return false;
    }
    return true;
  }

  static Future<void> _loadThiefPrimary() async {
    final thiefImg = await _loadImage('assets/images/vors/vor1.png');
    thiefRun = await _sliceRunAnimationStabilized(
      thiefImg,
      columns: 9,
      rows: 2,
      stepTime: 1 / GameConfig.runFps,
    );
  }

  static Future<void> _prefetchRemaining() async {
    if (_prefetchStarted) return;
    _prefetchStarted = true;
    for (var i = 1; i < GameConfig.corridorAssetCount; i++) {
      try {
        await _loadCorridorSlot(i);
      } catch (_) {
        // Keep going — missing one shaft must not kill the run.
        _corridorLoaded[i] = false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await ensureThiefBlueLoadedSafe();
  }

  static Future<void> ensureCorridorReady(int index) async {
    final i = index.clamp(0, GameConfig.corridorAssetCount - 1);
    try {
      await _loadCorridorSlot(i);
      await _loadUniversalDiamond();
      applyCorridorJewels(i);
    } catch (_) {
      // Caller keeps previous corridor art.
    }
  }

  static Future<void> ensureThiefBlueLoaded() {
    if (thiefRunBlue != null) return Future.value();
    return _thiefBlueFuture ??= () async {
      try {
        final thiefBlueImg = await _loadImage('assets/images/vors/vor-blue.png');
        thiefRunBlue = await _sliceRunAnimationStabilized(
          thiefBlueImg,
          columns: 9,
          rows: 2,
          stepTime: 1 / GameConfig.runFps,
        );
      } catch (_) {
        _thiefBlueFuture = null;
        rethrow;
      }
    }();
  }

  /// Raw corridor art for all shafts (1.png…10.png) — no seam bake / no alpha fade.
  static Future<void> _loadCorridorSlot(int index) async {
    final i = index.clamp(0, GameConfig.corridorAssetCount - 1);
    if (_corridorLoaded[i]) return;
    final img = await _loadImage('assets/images/bgc/${i + 1}.png');
    final sprite = Sprite(img);
    while (corridors.length <= i) {
      corridors.add(sprite);
    }
    corridors[i] = sprite;
    _corridorLoaded[i] = true;
    if (i == 0) tunnel = sprite;
  }

  /// One shared diamond for every jewel type on every shaft.
  static Future<void> _loadUniversalDiamond() async {
    if (_universalDiamondLoaded && items.containsKey(ItemType.diamond)) {
      return;
    }
    final img = await _loadImage('assets/images/items/diamond.png');
    final sprite = Sprite(img);
    items[ItemType.diamond] = sprite;
    items[ItemType.ruby] = sprite;
    items[ItemType.emerald] = sprite;
    items[ItemType.amethyst] = sprite;
    items[ItemType.legendary] = sprite;
    corridorJewels
      ..clear()
      ..add([sprite, sprite, sprite, sprite, sprite]);
    _universalDiamondLoaded = true;
  }

  /// Slice one skin when picked (avoids freezing on all 7 at boot).
  static Future<void> ensureSkinLoaded(String skinId) {
    if (skinRuns.containsKey(skinId)) return Future.value();
    return _skinFutures[skinId] ??= () async {
      try {
        Flame.images.prefix = '';
        final skin = PlayerSkins.byId(skinId);
        final img = await _loadImage(skin.sheetAsset);
        skinRuns[skin.id] = await _sliceRunAnimationStabilized(
          img,
          columns: 9,
          rows: 2,
          stepTime: 1 / GameConfig.minerRunFps,
        );
      } catch (_) {
        _skinFutures.remove(skinId);
        rethrow;
      }
    }();
  }

  /// Keep jewel sprites pinned to the universal diamond (all corridors).
  static void applyCorridorJewels(int corridorIndex) {
    final gem = items[ItemType.diamond];
    if (gem == null) return;
    items[ItemType.diamond] = gem;
    items[ItemType.ruby] = gem;
    items[ItemType.emerald] = gem;
    items[ItemType.amethyst] = gem;
    items[ItemType.legendary] = gem;
  }

  /// Slice run frames off the UI isolate, then decode images on the main isolate.
  /// Same path as before the crop-by-feet experiment (grounds + stabilizes X).
  static Future<SpriteAnimation> _sliceRunAnimationStabilized(
    ui.Image image, {
    required int columns,
    required int rows,
    required double stepTime,
  }) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return _sliceRunAnimationFallback(image, columns, rows, stepTime);
    }

    final src = Uint8List.fromList(byteData.buffer.asUint8List());
    final imgW = image.width;
    final imgH = image.height;
    final sliced = await Isolate.run(
      () => sliceRunFrames(
        SliceRunRequest(
          src: src,
          imgW: imgW,
          imgH: imgH,
          columns: columns,
          rows: rows,
        ),
      ),
    );

    final frames = <Sprite>[];
    for (final pixels in sliced.frames) {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        sliced.frameW,
        sliced.frameH,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      frames.add(Sprite(await completer.future));
      await Future<void>.delayed(Duration.zero);
    }

    return SpriteAnimation.spriteList(frames, stepTime: stepTime, loop: true);
  }

  static SpriteAnimation _sliceRunAnimationFallback(
    ui.Image image,
    int columns,
    int rows,
    double stepTime,
  ) {
    final frameW = image.width ~/ columns;
    final frameH = image.height ~/ rows;
    final sheet = SpriteSheet(
      image: image,
      srcSize: Vector2(frameW.toDouble(), frameH.toDouble()),
    );
    final frames = <Sprite>[];
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        frames.add(sheet.getSprite(row, col));
      }
    }
    return SpriteAnimation.spriteList(frames, stepTime: stepTime, loop: true);
  }

  static void _sliceElements(ui.Image image) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();

    Sprite crop(double left, double top, double right, double bottom) {
      return Sprite(
        image,
        srcPosition: Vector2(left, top),
        srcSize: Vector2(right - left, bottom - top),
      );
    }

    final coin = crop(w * 0.38, h * 0.10, w * 0.62, h * 0.50);
    // Square crop: full round body + fuse, almost no ground bloom.
    final bomb = crop(w * 0.6862, h * 0.1445, w * 0.9076, h * 0.4766);
    final bar = crop(w * 0.08, h * 0.52, w * 0.32, h * 0.88);

    items[ItemType.gold] = coin;
    items[ItemType.bomb] = bomb;
    items[ItemType.coal] = bar;
    // Web/magnet/pit drawn procedurally — placeholder only for Flame.
    // Dynamite cart / spikes loaded from hazards/ after elements slice.
    items[ItemType.web] = bomb;
    items[ItemType.magnet] = coin;
    items[ItemType.pit] = bomb;
    items[ItemType.heart] = coin;
    items[ItemType.potion] = coin;
    // Hazards must come from hazards/*.png — do NOT plant bomb placeholders
    // here (that made "spikes" look like bombs and hide the real art).
    items.remove(ItemType.dynamiteCart);
    items.remove(ItemType.spikes);
  }

}
