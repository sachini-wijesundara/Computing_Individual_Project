import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Normalized centroid (0–1) and span of detected hair region from segmentation.
class HairTrackResult {
  final double nx;
  final double ny;
  final double nSpan;
  const HairTrackResult(
      {required this.nx, required this.ny, required this.nSpan});
}

class _HairBboxJob {
  final Uint8List modelBytes;
  final Uint8List rgba;
  final int w;
  final int h;
  const _HairBboxJob(this.modelBytes, this.rgba, this.w, this.h);
}

/// Runs TFLite hair segmenter; returns hair-mask bounding box in normalized coords.
HairTrackResult? _hairBboxIsolate(_HairBboxJob job) {
  Interpreter? interpreter;
  try {
    interpreter = Interpreter.fromBuffer(
      job.modelBytes,
      options: InterpreterOptions()..threads = 2,
    );
    final inShape = interpreter.getInputTensor(0).shape;
    final outShape = interpreter.getOutputTensor(0).shape;
    final mh = inShape[1];
    final mw = inShape[2];
    final numClasses = outShape.length >= 4 ? outShape[3] : 1;
    final hairCh = numClasses > 1 ? 1 : 0;

    final src = img.Image(width: job.w, height: job.h);
    int bi = 0;
    for (var y = 0; y < job.h; y++) {
      for (var x = 0; x < job.w; x++) {
        final r = job.rgba[bi++];
        final g = job.rgba[bi++];
        final b = job.rgba[bi++];
        bi++; // a
        src.setPixelRgb(x, y, r.toDouble(), g.toDouble(), b.toDouble());
      }
    }

    final resized = img.copyResize(src, width: mw, height: mh);
    final input = Float32List(mh * mw * 3);
    var ix = 0;
    for (var y = 0; y < mh; y++) {
      for (var x = 0; x < mw; x++) {
        final p = resized.getPixel(x, y);
        input[ix++] = p.r / 255.0;
        input[ix++] = p.g / 255.0;
        input[ix++] = p.b / 255.0;
      }
    }

    final inputTensor = input.reshape([1, mh, mw, 3]);
    final output = Float32List(mh * mw * numClasses);
    final outTensor = output.reshape([1, mh, mw, numClasses]);
    interpreter.run(inputTensor, outTensor);

    const thr = 0.26;
    var minX = mw, minY = mh, maxX = 0, maxY = 0;
    var any = false;
    for (var y = 0; y < mh; y += 2) {
      for (var x = 0; x < mw; x += 2) {
        final idx = (y * mw + x) * numClasses + hairCh;
        if (output[idx] >= thr) {
          any = true;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (!any || maxX <= minX || maxY <= minY) return null;

    final cx = (minX + maxX) / 2.0 / mw;
    // Anchor above bbox centre so the style silhouette sits on the head, not mid-length hair.
    final bh = (maxY - minY).toDouble();
    final anchorY = minY + bh * 0.18;
    final ny = anchorY / mh;
    final span = (math.max((maxX - minX).toDouble(), bh) / mw)
        .clamp(0.12, 0.95)
        .toDouble();
    return HairTrackResult(nx: cx, ny: ny, nSpan: span);
  } catch (_) {
    return null;
  } finally {
    interpreter?.close();
  }
}

/// Convert YUV420 camera frame to RGBA bytes (fixed size [w*h*4]).
Uint8List? yuv420ToRgba(CameraImage image) {
  try {
    final w = image.width;
    final h = image.height;
    final out = Uint8List(w * h * 4);
    final yPlane = image.planes[0];
    final yBuf = yPlane.bytes;
    final yStride = yPlane.bytesPerRow;

    if (image.planes.length == 2) {
      // NV12 / NV21 style: Y + interleaved UV
      final uvPlane = image.planes[1];
      final uvBuf = uvPlane.bytes;
      final uvStride = uvPlane.bytesPerRow;
      var oi = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final yi = y * yStride + x;
          final yp = yBuf[yi];
          final uvi = (y >> 1) * uvStride + (x & ~1);
          final u = uvBuf[uvi];
          final v = uvBuf[uvi + 1];
          final r = (yp + 1.370705 * (v - 128)).round().clamp(0, 255);
          final g = (yp - 0.337633 * (u - 128) - 0.698001 * (v - 128))
              .round()
              .clamp(0, 255);
          final b = (yp + 1.732446 * (u - 128)).round().clamp(0, 255);
          out[oi++] = r;
          out[oi++] = g;
          out[oi++] = b;
          out[oi++] = 255;
        }
      }
      return out;
    }

    if (image.planes.length >= 3) {
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];
      final uBuf = uPlane.bytes;
      final vBuf = vPlane.bytes;
      final uStride = uPlane.bytesPerRow;
      final vStride = vPlane.bytesPerRow;
      var oi = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final yi = y * yStride + x;
          final yp = yBuf[yi];
          final uvx = x >> 1;
          final uvy = y >> 1;
          final u = uBuf[uvy * uStride + uvx];
          final v = vBuf[uvy * vStride + uvx];
          final r = (yp + 1.370705 * (v - 128)).round().clamp(0, 255);
          final g = (yp - 0.337633 * (u - 128) - 0.698001 * (v - 128))
              .round()
              .clamp(0, 255);
          final b = (yp + 1.732446 * (u - 128)).round().clamp(0, 255);
          out[oi++] = r;
          out[oi++] = g;
          out[oi++] = b;
          out[oi++] = 255;
        }
      }
      return out;
    }
  } catch (_) {}
  return null;
}

/// Downsample RGBA to max side [maxSide] for faster processing.
(Uint8List rgba, int w, int h) downsampleRgba(Uint8List rgba, int w, int h,
    {int maxSide = 256}) {
  if (w <= maxSide && h <= maxSide) return (rgba, w, h);
  final scale = maxSide / (w > h ? w : h);
  final nw = (w * scale).round().clamp(1, maxSide);
  final nh = (h * scale).round().clamp(1, maxSide);
  final out = Uint8List(nw * nh * 4);
  for (var y = 0; y < nh; y++) {
    for (var x = 0; x < nw; x++) {
      final sx = (x * w / nw).floor().clamp(0, w - 1);
      final sy = (y * h / nh).floor().clamp(0, h - 1);
      final si = (sy * w + sx) * 4;
      final oi = (y * nw + x) * 4;
      out[oi] = rgba[si];
      out[oi + 1] = rgba[si + 1];
      out[oi + 2] = rgba[si + 2];
      out[oi + 3] = rgba[si + 3];
    }
  }
  return (out, nw, nh);
}

/// Full pipeline: YUV frame → hair bbox (async isolate).
Future<HairTrackResult?> trackHairFromCameraImage({
  required CameraImage image,
  required Uint8List modelBytes,
}) async {
  final rgbaFull = yuv420ToRgba(image);
  if (rgbaFull == null) return null;
  final (rgba, w, h) =
      downsampleRgba(rgbaFull, image.width, image.height, maxSide: 288);
  return compute(_hairBboxIsolate, _HairBboxJob(modelBytes, rgba, w, h));
}
