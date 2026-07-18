import 'dart:math';
import 'dart:typed_data';

/// Isolate-safe pixel jobs — keep UI thread free while sheets are processed.

Uint8List blackKeyRgba(Uint8List src) {
  final out = Uint8List.fromList(src);
  for (var i = 0; i < out.length; i += 4) {
    final r = out[i];
    final g = out[i + 1];
    final b = out[i + 2];
    final a = out[i + 3];
    if (a < 8 || (r < 28 && g < 28 && b < 28)) {
      out[i + 3] = 0;
    }
  }
  return out;
}

class SliceRunRequest {
  const SliceRunRequest({
    required this.src,
    required this.imgW,
    required this.imgH,
    required this.columns,
    required this.rows,
  });

  final Uint8List src;
  final int imgW;
  final int imgH;
  final int columns;
  final int rows;
}

class SliceRunResult {
  const SliceRunResult({
    required this.frameW,
    required this.frameH,
    required this.frames,
  });

  final int frameW;
  final int frameH;
  final List<Uint8List> frames;
}

SliceRunResult sliceRunFrames(SliceRunRequest job) {
  final frameW = job.imgW ~/ job.columns;
  final frameH = job.imgH ~/ job.rows;
  final src = job.src;
  final imgW = job.imgW;
  final imgH = job.imgH;
  final marginX = max(3, frameW ~/ 10);
  final marginY = max(2, frameH ~/ 18);
  final cellCount = job.columns;
  final maskW = frameW + marginX * 2;
  final maskH = frameH + marginY * 2;

  int idx(int x, int y) => (y * imgW + x) * 4;

  final masks = <List<bool>>[];
  final footprints = <int>[];
  final upperAreas = <int>[];
  final footCXs = <double>[];
  final maxYs = <int>[];
  final minXs = <int>[];
  final maxXs = <int>[];
  final minYs = <int>[];

  for (var col = 0; col < cellCount; col++) {
    final ox = col * frameW;
    final opaque = List<bool>.filled(maskW * maskH, false);
    for (var my = 0; my < maskH; my++) {
      for (var mx = 0; mx < maskW; mx++) {
        final sx = ox - marginX + mx;
        final sy = 0 - marginY + my;
        if (sx < 0 || sy < 0 || sx >= imgW || sy >= imgH) continue;
        if (src[idx(sx, sy) + 3] < 14) continue;
        opaque[my * maskW + mx] = true;
      }
    }

    final seedX = marginX + frameW ~/ 2;
    final seedY = marginY + (frameH * 0.55).round();
    final keep = _floodFromSeed(opaque, maskW, maskH, seedX, seedY);
    masks.add(keep);

    var minX = maskW;
    var maxX = 0;
    var minY = maskH;
    var maxY = 0;
    var upper = 0;
    var footSumX = 0;
    var footCount = 0;
    var fp = 0;
    var any = false;
    final midY = (maskH * 0.42).round();
    final footBand = (maskH * 0.82).round();
    for (var y = 0; y < maskH; y++) {
      for (var x = 0; x < maskW; x++) {
        if (!keep[y * maskW + x]) continue;
        any = true;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (y < midY) upper++;
        if (y >= footBand) {
          footSumX += x;
          footCount++;
        }
        fp = (fp * 31 + x * 7 + y * 3) & 0x7fffffff;
      }
    }
    if (!any) {
      minX = marginX;
      maxX = marginX + frameW - 1;
      minY = marginY;
      maxY = marginY + frameH - 1;
    }
    footprints.add(fp);
    upperAreas.add(upper);
    minXs.add(minX);
    maxXs.add(maxX);
    minYs.add(minY);
    maxYs.add(maxY);
    footCXs.add(footCount > 0 ? footSumX / footCount : (minX + maxX) * 0.5);
  }

  final picked = <int>[];
  for (var i = 0; i < cellCount; i++) {
    if (picked.isEmpty) {
      picked.add(i);
      continue;
    }
    final prev = picked.last;
    if (footprints[i] == footprints[prev]) continue;
    final a = upperAreas[i];
    final b = upperAreas[prev];
    if (a > 0 && b > 0 && (a - b).abs() / max(a, b) < 0.035) continue;
    picked.add(i);
  }
  if (picked.length < 4) {
    picked
      ..clear()
      ..addAll(List.generate(min(6, cellCount), (i) => i));
  }

  final sortedUpper = [for (final i in picked) upperAreas[i]]..sort();
  final medianUpper = sortedUpper[sortedUpper.length ~/ 2];
  final sequence = <int>[];
  for (final i in picked) {
    if (medianUpper > 0 && upperAreas[i] > medianUpper * 1.16) continue;
    sequence.add(i);
  }
  final cycle = sequence.length >= 4 ? sequence : picked;

  var maxContentW = 1;
  var maxContentH = 1;
  for (final i in cycle) {
    maxContentW = max(maxContentW, maxXs[i] - minXs[i] + 1);
    maxContentH = max(maxContentH, maxYs[i] - minYs[i] + 1);
  }
  final scale = min(
    (frameW * 0.90) / maxContentW,
    (frameH * 0.94) / maxContentH,
  ).clamp(0.72, 1.0);

  final frames = <Uint8List>[];
  for (final col in cycle) {
    final ox = col * frameW;
    final keep = masks[col];
    final footCX = footCXs[col];
    final footY = maxYs[col].toDouble();
    final out = Uint8List(frameW * frameH * 4);
    for (var my = 0; my < maskH; my++) {
      for (var mx = 0; mx < maskW; mx++) {
        if (!keep[my * maskW + mx]) continue;
        final sx = ox - marginX + mx;
        final sy = 0 - marginY + my;
        if (sx < 0 || sy < 0 || sx >= imgW || sy >= imgH) continue;
        final dx = (frameW * 0.5 + (mx - footCX) * scale).round();
        final dy = (frameH - 2 + (my - footY) * scale).round();
        if (dx < 0 || dy < 0 || dx >= frameW || dy >= frameH) continue;
        final si = idx(sx, sy);
        final di = (dy * frameW + dx) * 4;
        if (out[di + 3] > src[si + 3]) continue;
        out[di] = src[si];
        out[di + 1] = src[si + 1];
        out[di + 2] = src[si + 2];
        out[di + 3] = src[si + 3];
      }
    }
    frames.add(out);
  }

  return SliceRunResult(frameW: frameW, frameH: frameH, frames: frames);
}

List<bool> _floodFromSeed(
  List<bool> opaque,
  int w,
  int h,
  int seedX,
  int seedY,
) {
  final keep = List<bool>.filled(w * h, false);
  final seed = seedY * w + seedX;
  if (seedX < 0 || seedY < 0 || seedX >= w || seedY >= h || !opaque[seed]) {
    return _keepBodyComponents(opaque, w, h);
  }
  final stack = <int>[seed];
  keep[seed] = true;
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w;
    final y = i ~/ w;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final ni = ny * w + nx;
        if (keep[ni] || !opaque[ni]) continue;
        keep[ni] = true;
        stack.add(ni);
      }
    }
  }
  return keep;
}

List<bool> _keepBodyComponents(List<bool> opaque, int w, int h) {
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

  final minKeep = max(28, (best * 0.045).round());
  seen.fillRange(0, seen.length, false);
  for (var ci = 0; ci < starts.length; ci++) {
    if (counts[ci] < minKeep) continue;
    flood(starts[ci], (i) => keep[i] = true);
  }
  return keep;
}
