import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/sprite.dart';

import '../items/item_type.dart';
import 'game_config.dart';

/// Loads PNGs, strips sheet backgrounds to real alpha, slices run cycles.
class AssetLibrary {
  AssetLibrary._();

  static SpriteAnimation? minerRun;
  static SpriteAnimation? thiefRun;

  /// First corridor (classic) — kept for callers that expect a single sprite.
  static Sprite? tunnel;

  /// Ordered biomes: classic → warm → forest → ice (one per km).
  static final List<Sprite> corridors = [];
  static const List<String> corridorNames = [
    'Кристальная шахта',
    'Тёплая шахта',
    'Зелёная шахта',
    'Ледяная шахта',
  ];
  static final Map<ItemType, Sprite> items = {};
  static const int _assetVersion = 8;
  static int _loadedVersion = 0;

  static bool get ready =>
      minerRun != null &&
      thiefRun != null &&
      corridors.length == GameConfig.corridorCount &&
      _loadedVersion == _assetVersion;

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
    tunnel = null;
    corridors.clear();

    Flame.images.prefix = '';

    final minerImg = await _loadWhiteKeyed('assets/persnew.png');
    final thiefImg = await _loadWhiteKeyed('assets/vor1.png');
    final elementsImg = await _loadBlackKeyed('assets/elements.png');
    const corridorPaths = [
      'assets/bgc.png',
      'assets/mine_corridor_warm.png',
      'assets/mine_corridor_forest.png',
      'assets/mine_corridor_ice.png',
    ];
    final corridorImgs = <ui.Image>[];
    for (final path in corridorPaths) {
      corridorImgs.add(await Flame.images.load(path));
    }

    // Miner: stabilize feet + smoother step rate (was looking jittery).
    minerRun = await _sliceRunAnimationStabilized(
      minerImg,
      columns: 9,
      rows: 2,
      stepTime: 1 / GameConfig.minerRunFps,
    );
    thiefRun = await _sliceRunAnimationStabilized(
      thiefImg,
      columns: 9,
      rows: 2,
      stepTime: 1 / GameConfig.runFps,
    );
    for (final img in corridorImgs) {
      corridors.add(Sprite(img));
    }
    tunnel = corridors.first;

    _sliceElements(elementsImg);
    _loadedVersion = _assetVersion;
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

    final diamond = crop(w * 0.08, h * 0.12, w * 0.30, h * 0.52);
    final coin = crop(w * 0.38, h * 0.10, w * 0.62, h * 0.50);
    final bomb = crop(w * 0.68, h * 0.10, w * 0.92, h * 0.52);
    final bar = crop(w * 0.08, h * 0.52, w * 0.32, h * 0.88);
    final bag = crop(w * 0.36, h * 0.50, w * 0.64, h * 0.92);

    items[ItemType.diamond] = diamond;
    items[ItemType.gold] = coin;
    items[ItemType.bomb] = bomb;
    items[ItemType.coal] = bar;
    items[ItemType.legendary] = bag;
    items[ItemType.ruby] = diamond;
    items[ItemType.emerald] = diamond;
    items[ItemType.amethyst] = diamond;
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
