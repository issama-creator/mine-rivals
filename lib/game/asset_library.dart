import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/sprite.dart';

import '../items/item_type.dart';
import '../systems/game_settings.dart';
import 'game_config.dart';
import 'player_skins.dart';

/// Loads PNGs, strips sheet backgrounds to real alpha, slices run cycles.
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

  /// Per corridor: 3 gem sprites [0]=diamond, [1]=ruby, [2]=emerald.
  static final List<List<Sprite>> corridorJewels = [];
  static const int _assetVersion = 19;
  static int _loadedVersion = 0;

  static bool get ready =>
      minerRun != null &&
      thiefRun != null &&
      thiefRunBlue != null &&
      skinRuns.length == PlayerSkins.all.length &&
      corridors.length == GameConfig.corridorCount &&
      corridorJewels.length == GameConfig.corridorCount &&
      _loadedVersion == _assetVersion;

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

  static Future<void> ensureLoaded() async {
    if (ready) return;
    items.clear();
    minerRun = null;
    thiefRun = null;
    thiefRunBlue = null;
    skinRuns.clear();
    tunnel = null;
    corridors.clear();
    corridorJewels.clear();

    Flame.images.prefix = '';

    // Playable skins (transparent 9×2 sheets).
    for (final skin in PlayerSkins.all) {
      final img = await Flame.images.load(skin.sheetAsset);
      skinRuns[skin.id] = await _sliceRunAnimationStabilized(
        img,
        columns: 9,
        rows: 2,
        stepTime: 1 / GameConfig.minerRunFps,
      );
    }
    minerRun = minerRunForSelected();

    final thiefImg = await Flame.images.load('assets/images/vors/vor1.png');
    final thiefBlueImg = await Flame.images.load(
      'assets/images/vors/vor-blue.png',
    );
    final elementsImg = await _loadBlackKeyed('assets/elements.png');
    final corridorPaths = [
      for (var i = 1; i <= GameConfig.corridorCount; i++)
        'assets/images/bgc/$i.png',
    ];
    final corridorImgs = <ui.Image>[];
    for (final path in corridorPaths) {
      corridorImgs.add(await Flame.images.load(path));
    }

    // Per-corridor crystal crops: 0 diamond, 1 ruby, 2 emerald, 3 amethyst, 4 legendary.
    for (var c = 1; c <= GameConfig.corridorCount; c++) {
      final gems = <Sprite>[];
      for (var g = 0; g < 5; g++) {
        final img = await Flame.images.load(
          'assets/images/kristales/crops/c${c}_$g.png',
        );
        gems.add(Sprite(img));
      }
      corridorJewels.add(gems);
    }

    Future<SpriteAnimation> sliceThief(ui.Image img) {
      return _sliceRunAnimationStabilized(
        img,
        columns: 9,
        rows: 2,
        stepTime: 1 / GameConfig.runFps,
      );
    }

    thiefRun = await sliceThief(thiefImg);
    thiefRunBlue = await sliceThief(thiefBlueImg);
    for (final img in corridorImgs) {
      corridors.add(Sprite(img));
    }
    tunnel = corridors.first;

    _sliceElements(elementsImg);
    applyCorridorJewels(0);
    _loadedVersion = _assetVersion;
  }

  /// Swap jewel art for the active shaft — coins/bombs stay global.
  static void applyCorridorJewels(int corridorIndex) {
    if (corridorJewels.isEmpty) return;
    final i = corridorIndex.clamp(0, corridorJewels.length - 1);
    final gems = corridorJewels[i];
    items[ItemType.diamond] = gems[0];
    items[ItemType.ruby] = gems[1];
    items[ItemType.emerald] = gems[2];
    items[ItemType.amethyst] = gems[3];
    items[ItemType.legendary] = gems[4];
  }

  /// Slice frames and bottom-center each one so the run cycle doesn't hop.
  static Future<SpriteAnimation> _sliceRunAnimationStabilized(
    ui.Image image, {
    required int columns,
    required int rows,
    required double stepTime,
  }) async {
    final frameW = image.width ~/ columns;
    final frameH = image.height ~/ rows;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return _sliceRunAnimationFallback(image, columns, rows, stepTime);
    }
    final src = byteData.buffer.asUint8List();
    final imgW = image.width;

    int idx(int x, int y) => (y * imgW + x) * 4;

    final frames = <Sprite>[];
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < columns; col++) {
        final ox = col * frameW;
        final oy = row * frameH;

        var minX = frameW;
        var minY = frameH;
        var maxX = 0;
        var maxY = 0;
        var found = false;

        for (var y = 0; y < frameH; y++) {
          for (var x = 0; x < frameW; x++) {
            final a = src[idx(ox + x, oy + y) + 3];
            if (a < 20) continue;
            found = true;
            if (x < minX) minX = x;
            if (y < minY) minY = y;
            if (x > maxX) maxX = x;
            if (y > maxY) maxY = y;
          }
        }

        final out = Uint8List(frameW * frameH * 4);
        if (found) {
          final contentW = maxX - minX + 1;
          final contentH = maxY - minY + 1;
          // Bottom-center: plant feet, keep basket stable horizontally.
          final dstX = ((frameW - contentW) / 2).round();
          final dstY = frameH - contentH - 2;
          for (var y = 0; y < contentH; y++) {
            for (var x = 0; x < contentW; x++) {
              final sx = ox + minX + x;
              final sy = oy + minY + y;
              final dx = dstX + x;
              final dy = dstY + y;
              if (dx < 0 || dy < 0 || dx >= frameW || dy >= frameH) continue;
              final si = idx(sx, sy);
              final di = (dy * frameW + dx) * 4;
              out[di] = src[si];
              out[di + 1] = src[si + 1];
              out[di + 2] = src[si + 2];
              out[di + 3] = src[si + 3];
            }
          }
        }

        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          out,
          frameW,
          frameH,
          ui.PixelFormat.rgba8888,
          completer.complete,
        );
        final frameImage = await completer.future;
        frames.add(Sprite(frameImage));
      }
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
    // Jewels are applied per-corridor via applyCorridorJewels.
  }

  static Future<ui.Image> _loadWhiteKeyed(String path) async {
    final raw = await Flame.images.load(path);
    return _mapPixels(raw, (r, g, b, a) {
      final maxC = max(r, max(g, b));
      final minC = min(r, min(g, b));
      if (minC >= 215) return (0, 0, 0, 0);
      if (minC >= 190 && (maxC - minC) <= 28) return (0, 0, 0, 0);
      if (r >= 245 && g >= 245 && b >= 245) return (0, 0, 0, 0);
      return (r, g, b, a);
    });
  }

  static Future<ui.Image> _loadBlackKeyed(String path) async {
    final raw = await Flame.images.load(path);
    return _mapPixels(raw, (r, g, b, a) {
      if (a < 8) return (r, g, b, 0);
      if (r < 28 && g < 28 && b < 28) return (r, g, b, 0);
      return (r, g, b, a);
    });
  }

  static Future<ui.Image> _mapPixels(
    ui.Image src,
    (int, int, int, int) Function(int r, int g, int b, int a) map,
  ) async {
    final byteData = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return src;
    final bytes = Uint8List.fromList(byteData.buffer.asUint8List());
    for (var i = 0; i < bytes.length; i += 4) {
      final out = map(bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]);
      bytes[i] = out.$1;
      bytes[i + 1] = out.$2;
      bytes[i + 2] = out.$3;
      bytes[i + 3] = out.$4;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      src.width,
      src.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
