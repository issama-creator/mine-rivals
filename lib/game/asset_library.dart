import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/sprite.dart';

import '../items/item_type.dart';
import '../systems/game_settings.dart';
import 'asset_workers.dart';
import 'game_config.dart';
import 'player_skins.dart';

/// Loads PNGs, strips sheet backgrounds to real alpha, slices run cycles.
/// Heavy pixel work runs in isolates so the menu / loading UI stays responsive.
class AssetLibrary {
  AssetLibrary._();

  static SpriteAnimation? minerRun;
  static SpriteAnimation? thiefRun;
  static SpriteAnimation? thiefRunBlue;

  /// All playable skins keyed by [PlayerSkin.id].
  static final Map<String, SpriteAnimation> skinRuns = {};

  /// First corridor (classic) — kept for callers that expect a single sprite.
  static Sprite? tunnel;

  /// Ordered shafts from assets/images/bgc/1.png … 10.png.
  static final List<Sprite> corridors = [];
  static const List<String> corridorNames = [
    'Шахта 1',
    'Шахта 2',
    'Шахта 3',
    'Шахта 4',
    'Шахта 5',
    'Шахта 6',
    'Шахта 7',
    'Шахта 8',
    'Шахта 9',
    'Шахта 10',
  ];
  static final Map<ItemType, Sprite> items = {};

  /// Per corridor: gems for that shaft.
  static final List<List<Sprite>> corridorJewels = [];
  static const int _assetVersion = 35;
  static int _loadedVersion = 0;

  static Future<void>? _loadFuture;
  static final Map<String, Future<void>> _skinFutures = {};
  static Future<void>? _thiefBlueFuture;

  static final List<bool> _corridorLoaded =
      List<bool>.filled(GameConfig.corridorAssetCount, false);
  static final List<bool> _jewelLoaded =
      List<bool>.filled(GameConfig.corridorAssetCount, false);

  /// No overlap — pre-baked seamless PNGs. Overlap looked like a transparent band.
  static const double corridorSeamFadeFrac = 0;

  static bool get ready =>
      minerRun != null &&
      thiefRun != null &&
      skinRuns.isNotEmpty &&
      corridors.isNotEmpty &&
      corridorJewels.isNotEmpty &&
      _loadedVersion == _assetVersion;

  /// Kick off core load from the menu (non-blocking). Safe to call often.
  static Future<void> warmUp() => ensureLoaded();

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

  static Future<void> ensureLoaded() {
    // Always clear before any load — skins can warm from the menu first.
    Flame.images.prefix = '';
    if (ready) {
      return _ensureSelectedSkin();
    }
    return _loadFuture ??= _loadCore().catchError((Object e, StackTrace st) {
      _loadFuture = null;
      Error.throwWithStackTrace(e, st);
    });
  }

  static Future<void> _ensureSelectedSkin() async {
    await ensureSkinLoaded(GameSettings.instance.selectedSkinId);
    minerRun = minerRunForSelected();
  }

  static Future<void> _loadCore() async {
    items.clear();
    minerRun = null;
    thiefRun = null;
    thiefRunBlue = null;
    skinRuns.clear();
    _skinFutures.clear();
    _thiefBlueFuture = null;
    tunnel = null;
    corridors.clear();
    corridorJewels.clear();
    _corridorLoaded.fillRange(0, _corridorLoaded.length, false);
    _jewelLoaded.fillRange(0, _jewelLoaded.length, false);

    Flame.images.prefix = '';

    final selected = GameSettings.instance.selectedSkinId;
    final needDefault = selected != PlayerSkins.defaultId;

    // Parallel boot — isolate work + image IO overlap.
    final results = await Future.wait<Object?>([
      _loadBlackKeyed('assets/elements.png'),
      _loadCorridorSlot(0),
      _loadJewelSlot(0),
      _loadThiefPrimary(),
      ensureSkinLoaded(selected),
      if (needDefault) ensureSkinLoaded(PlayerSkins.defaultId),
    ]);

    final elementsImg = results[0]! as ui.Image;
    _sliceElements(elementsImg);
    applyCorridorJewels(0);
    minerRun = minerRunForSelected();
    _loadedVersion = _assetVersion;

    unawaited(_prefetchRemaining());
  }

  static Future<void> _loadThiefPrimary() async {
    final thiefImg = await Flame.images.load('assets/images/vors/vor1.png');
    thiefRun = await _sliceRunAnimationStabilized(
      thiefImg,
      columns: 9,
      rows: 2,
      stepTime: 1 / GameConfig.runFps,
    );
  }

  static Future<void> _prefetchRemaining() async {
    for (var i = 1; i < GameConfig.corridorAssetCount; i++) {
      await _loadCorridorSlot(i);
      await _loadJewelSlot(i);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await ensureThiefBlueLoaded();
  }

  static Future<void> ensureCorridorReady(int index) async {
    final i = index.clamp(0, GameConfig.corridorAssetCount - 1);
    await Future.wait([
      _loadCorridorSlot(i),
      _loadJewelSlot(i),
    ]);
  }

  static Future<void> ensureThiefBlueLoaded() {
    if (thiefRunBlue != null) return Future.value();
    return _thiefBlueFuture ??= () async {
      final thiefBlueImg = await Flame.images.load(
        'assets/images/vors/vor-blue.png',
      );
      thiefRunBlue = await _sliceRunAnimationStabilized(
        thiefBlueImg,
        columns: 9,
        rows: 2,
        stepTime: 1 / GameConfig.runFps,
      );
    }();
  }

  /// Raw corridor art for all shafts (1.png…10.png) — no seam bake / no alpha fade.
  static Future<void> _loadCorridorSlot(int index) async {
    final i = index.clamp(0, GameConfig.corridorAssetCount - 1);
    if (_corridorLoaded[i]) return;
    final img = await Flame.images.load('assets/images/bgc/${i + 1}.png');
    final sprite = Sprite(img);
    while (corridors.length <= i) {
      corridors.add(sprite);
    }
    corridors[i] = sprite;
    _corridorLoaded[i] = true;
    if (i == 0) tunnel = sprite;
  }

  static Future<void> _loadJewelSlot(int index) async {
    final i = index.clamp(0, GameConfig.corridorAssetCount - 1);
    if (_jewelLoaded[i]) return;
    final gems = <Sprite>[];
    final c = i + 1;
    final loaded = await Future.wait([
      for (var g = 0; g < 5; g++)
        Flame.images.load('assets/images/kristales/crops/c${c}_$g.png'),
    ]);
    for (final img in loaded) {
      gems.add(Sprite(img));
    }
    while (corridorJewels.length <= i) {
      corridorJewels.add(<Sprite>[]);
    }
    corridorJewels[i] = gems;
    _jewelLoaded[i] = true;
  }

  /// Slice one skin when picked (avoids freezing on all 7 at boot).
  static Future<void> ensureSkinLoaded(String skinId) {
    if (skinRuns.containsKey(skinId)) return Future.value();
    return _skinFutures[skinId] ??= () async {
      // Paths are absolute from project root — never use Flame's default
      // `assets/images/` prefix (that produced assets/images/assets/images/...).
      Flame.images.prefix = '';
      final skin = PlayerSkins.byId(skinId);
      final img = await Flame.images.load(skin.sheetAsset);
      skinRuns[skin.id] = await _sliceRunAnimationStabilized(
        img,
        columns: 9,
        rows: 2,
        stepTime: 1 / GameConfig.minerRunFps,
      );
    }();
  }

  /// Swap jewel art for the active shaft — coins/bombs stay global.
  static void applyCorridorJewels(int corridorIndex) {
    if (corridorJewels.isEmpty) return;
    final i = corridorIndex.clamp(0, corridorJewels.length - 1);
    final gems = corridorJewels[i];
    if (gems.length < 5) return;
    items[ItemType.diamond] = gems[0];
    items[ItemType.ruby] = gems[1];
    items[ItemType.emerald] = gems[2];
    items[ItemType.amethyst] = gems[3];
    items[ItemType.legendary] = gems[4];
  }

  /// Slice run frames off the UI isolate, then decode images on the main isolate.
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
    final bomb = crop(w * 0.68, h * 0.10, w * 0.92, h * 0.52);
    final bar = crop(w * 0.08, h * 0.52, w * 0.32, h * 0.88);

    items[ItemType.gold] = coin;
    items[ItemType.bomb] = bomb;
    items[ItemType.coal] = bar;
    // Web/magnet drawn procedurally — placeholder only for Flame.
    items[ItemType.web] = bomb;
    items[ItemType.magnet] = coin;
    items[ItemType.pit] = bomb;
  }

  static Future<ui.Image> _loadBlackKeyed(String path) async {
    final raw = await Flame.images.load(path);
    final byteData = await raw.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return raw;
    final src = Uint8List.fromList(byteData.buffer.asUint8List());
    final keyed = await Isolate.run(() => blackKeyRgba(src));
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      keyed,
      raw.width,
      raw.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
