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
  static const int _assetVersion = 21;
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

  /// Slice run frames: drop sheet bleed, plant feet, keep hand/basket X stable.
  /// Skips duplicate row/cells and arm-flare outliers that make hands "pop".
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

    // Build raw cells for row 0 first; row 1 is almost always a duplicate.
    final cellCount = columns; // one run cycle row
    final keeps = <List<bool>>[];
    final upperWidths = <int>[];
    final fingerprints = <int>[];

    for (var col = 0; col < cellCount; col++) {
      final ox = col * frameW;
      final oy = 0;

      final opaque = List<bool>.filled(frameW * frameH, false);
      var any = false;
      for (var y = 0; y < frameH; y++) {
        for (var x = 0; x < frameW; x++) {
          if (src[idx(ox + x, oy + y) + 3] < 16) continue;
          opaque[y * frameW + x] = true;
          any = true;
        }
      }

      final keep = any
          ? _keepBodyComponents(opaque, frameW, frameH)
          : opaque;
      keeps.add(keep);

      var minX = frameW;
      var maxX = 0;
      var upperW = 0;
      var fp = 0;
      final midY = (frameH * 0.45).round();
      for (var y = 0; y < frameH; y++) {
        for (var x = 0; x < frameW; x++) {
          if (!keep[y * frameW + x]) continue;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < midY) {
            upperW++;
            fp = (fp * 33 + x * 17 + y) & 0x7fffffff;
          } else {
            fp = (fp * 31 + x + y * 3) & 0x7fffffff;
          }
        }
      }
      upperWidths.add(upperW);
      fingerprints.add(fp);
    }

    // Drop near-duplicate consecutive cells (sheets often repeat poses).
    final picked = <int>[];
    for (var i = 0; i < cellCount; i++) {
      if (picked.isEmpty) {
        picked.add(i);
        continue;
      }
      final prev = picked.last;
      if (fingerprints[i] == fingerprints[prev]) continue;
      // Near-identical silhouette → stutter hold, skip.
      final a = upperWidths[i];
      final b = upperWidths[prev];
      final similarUpper = a > 0 &&
          b > 0 &&
          (a - b).abs() / max(a, b) < 0.04 &&
          fingerprints[i] ~/ 1000 == fingerprints[prev] ~/ 1000;
      if (similarUpper) continue;
      picked.add(i);
    }
    if (picked.length < 4) {
      picked
        ..clear()
        ..addAll(List.generate(min(6, cellCount), (i) => i));
    }

    // Drop arm-flare outliers (hands jump up the barrel rim).
    final widths = [
      for (final i in picked) upperWidths[i],
    ]..sort();
    final medianUpper = widths[widths.length ~/ 2];
    final smoothed = <int>[];
    for (final i in picked) {
      if (medianUpper > 0 && upperWidths[i] > medianUpper * 1.14) {
        // Keep the stride pose but reuse previous calm arms/hands silhouette
        // by skipping this flare cell entirely.
        continue;
      }
      smoothed.add(i);
    }
    final sequence = smoothed.length >= 4 ? smoothed : picked;

    final frames = <Sprite>[];
    for (final col in sequence) {
      final ox = col * frameW;
      final keep = keeps[col];

      var maxY = 0;
      var found = false;
      for (var y = 0; y < frameH; y++) {
        for (var x = 0; x < frameW; x++) {
          if (!keep[y * frameW + x]) continue;
          found = true;
          if (y > maxY) maxY = y;
        }
      }

      final out = Uint8List(frameW * frameH * 4);
      if (found) {
        // Plant feet only — keep original X so hands don't slide on the rim.
        final shiftY = (frameH - 2) - maxY;
        for (var y = 0; y < frameH; y++) {
          for (var x = 0; x < frameW; x++) {
            if (!keep[y * frameW + x]) continue;
            final dx = x;
            final dy = y + shiftY;
            if (dx < 0 || dy < 0 || dx >= frameW || dy >= frameH) continue;
            final si = idx(ox + x, y);
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
      frames.add(Sprite(await completer.future));
    }

    // Slightly slower step if we dropped frames — same real stride feel.
    final tunedStep = stepTime * (cellCount / max(frames.length, 1)).clamp(1.0, 1.35);
    return SpriteAnimation.spriteList(frames, stepTime: tunedStep, loop: true);
  }

  /// Keep the body blob + any sizable nearby scraps (hands), drop tiny bleed.
  static List<bool> _keepBodyComponents(
    List<bool> opaque,
    int w,
    int h,
  ) {
    final seen = List<bool>.filled(w * h, false);
    final starts = <int>[];
    final counts = <int>[];
    final stack = <int>[];

    void flood(int start, void Function(int i) visit) {
      stack
        ..clear()
        ..add(start);
      seen[start] = true;
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        visit(i);
        final x = i % w;
        final y = i ~/ w;
        // 8-connected — thin wrists stay attached to the body.
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final ni = ny * w + nx;
            if (seen[ni] || !opaque[ni]) continue;
            seen[ni] = true;
            stack.add(ni);
          }
        }
      }
    }

    for (var i = 0; i < opaque.length; i++) {
      if (!opaque[i] || seen[i]) continue;
      var count = 0;
      flood(i, (_) => count++);
      starts.add(i);
      counts.add(count);
    }

    var best = 0;
    for (final c in counts) {
      if (c > best) best = c;
    }
    final keep = List<bool>.filled(w * h, false);
    if (best <= 0) return keep;

    // Keep main body + any chunk big enough to be a hand/arm (not bleed dust).
    final minKeep = max(28, (best * 0.045).round());
    seen.fillRange(0, seen.length, false);
    for (var ci = 0; ci < starts.length; ci++) {
      if (counts[ci] < minKeep) continue;
      flood(starts[ci], (i) => keep[i] = true);
    }
    return keep;
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
