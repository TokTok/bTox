import 'dart:math';
import 'dart:typed_data';

/// The most pixels a QOI picture may have to be shown: 128 MiB as RGBA.
const maxQoiPixels = 1 << 25;

const _magic = 0x716f6966; // "qoif"
// Magic, width, height, channels and colour space.
const qoiHeaderSize = 14;
const _end = [0, 0, 0, 0, 0, 0, 0, 1];
// The longest run.
const _maxRun = 62;

const _opRgb = 0xfe;
const _opRgba = 0xff;
const _opIndex = 0;
const _opDiff = 1;
const _opLuma = 2;
const _opRun = 3;

typedef QoiPixels = ({int width, int height, Uint8List rgba});

/// The most bytes a QOI picture of [maxQoiPixels] can take.
final maxQoiBytes = qoiHeaderSize + maxQoiPixels * 5 + _end.length;

/// The size in the QOI header [bytes] start with. Throws a [FormatException]
/// if there's none.
({int width, int height}) qoiSize(Uint8List bytes) {
  if (bytes.length < qoiHeaderSize) {
    throw const FormatException('Too short for a QOI picture');
  }
  final header = ByteData.sublistView(bytes);
  final width = header.getUint32(4);
  final height = header.getUint32(8);
  final channels = bytes[12];
  final colourSpace = bytes[13];
  if (header.getUint32(0) != _magic ||
      width == 0 ||
      height == 0 ||
      (channels != 3 && channels != 4) ||
      colourSpace > 1) {
    throw const FormatException('Not a QOI picture');
  }
  return (width: width, height: height);
}

/// The RGBA pixels of the QOI picture [bytes], shrunk to fit [fit] pixels
/// square if given. Throws a [FormatException] if it's malformed or has more
/// than [maxQoiPixels].
QoiPixels decodeQoi(Uint8List bytes, {int? fit}) {
  if (bytes.length < qoiHeaderSize + _end.length) {
    throw const FormatException('Too short for a QOI picture');
  }
  final (:width, :height) = qoiSize(bytes);
  final end = bytes.length - _end.length;
  for (final (i, byte) in _end.indexed) {
    if (bytes[end + i] != byte) {
      throw const FormatException('A QOI picture without its end');
    }
  }
  // Each side first, so the product can't overflow.
  if (width > maxQoiPixels ||
      height > maxQoiPixels ||
      width * height > maxQoiPixels) {
    throw FormatException('A QOI picture of $width×$height is too big');
  }
  final pixels = width * height;
  if (pixels > (end - qoiHeaderSize) * _maxRun) {
    throw const FormatException('More pixels than the QOI data holds');
  }

  final scale = fit == null ? 1 : min(1, fit / max(width, height));
  // At least a pixel, for thin pictures.
  final outWidth = max(1, (width * scale).round());
  final outHeight = max(1, (height * scale).round());
  // Each source column or row's output one, or -1.
  Int32List picks(int from, int to) {
    final picked = Int32List(from)..fillRange(0, from, -1);
    for (var i = 0; i < to; i++) {
      picked[i * from ~/ to] = i;
    }
    return picked;
  }

  final columns = picks(width, outWidth);
  final rows = picks(height, outHeight);
  final rgba = Uint8List(outWidth * outHeight * 4);
  // Pixels seen, by hash.
  final index = Uint8List(64 * 4);
  var (r, g, b, a) = (0, 0, 0, 255);
  var at = qoiHeaderSize;
  var run = 0;
  void need(int count) {
    if (at + count > end) {
      throw const FormatException('The QOI data ends before its pixels do');
    }
  }

  var (x, y) = (0, 0);
  for (var p = 0; p < pixels; p++) {
    if (run > 0) {
      run--;
    } else {
      need(1);
      final op = bytes[at++];
      if (op == _opRgb) {
        need(3);
        (r, g, b) = (bytes[at], bytes[at + 1], bytes[at + 2]);
        at += 3;
      } else if (op == _opRgba) {
        need(4);
        (r, g, b, a) = (bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3]);
        at += 4;
      } else {
        switch (op >> 6) {
          case _opIndex:
            final i = op * 4;
            (r, g, b, a) = (index[i], index[i + 1], index[i + 2], index[i + 3]);
          case _opDiff:
            r = (r + (op >> 4 & 3) - 2) & 0xff;
            g = (g + (op >> 2 & 3) - 2) & 0xff;
            b = (b + (op & 3) - 2) & 0xff;
          case _opLuma:
            need(1);
            final next = bytes[at++];
            final dg = (op & 0x3f) - 32;
            r = (r + dg - 8 + (next >> 4)) & 0xff;
            g = (g + dg) & 0xff;
            b = (b + dg - 8 + (next & 0x0f)) & 0xff;
          default:
            run = op & 0x3f;
        }
      }
      final i = (r * 3 + g * 5 + b * 7 + a * 11) % 64 * 4;
      index
        ..[i] = r
        ..[i + 1] = g
        ..[i + 2] = b
        ..[i + 3] = a;
    }
    final row = rows[y];
    final column = columns[x];
    if (row >= 0 && column >= 0) {
      final out = (row * outWidth + column) * 4;
      rgba
        ..[out] = r
        ..[out + 1] = g
        ..[out + 2] = b
        ..[out + 3] = a;
    }
    if (++x == width) {
      x = 0;
      y++;
    }
  }
  if (run > 0 || at != end) {
    throw const FormatException('More QOI data than its pixels');
  }
  return (width: outWidth, height: outHeight, rgba: rgba);
}

/// [rgba], [width] by [height] pixels, as QOI, with alpha only if a pixel isn't
/// opaque.
Uint8List encodeQoi(Uint8List rgba, int width, int height) {
  final pixels = width * height;
  if (width == 0 || height == 0 || rgba.length != pixels * 4) {
    throw ArgumentError('$width×$height pixels need ${pixels * 4} bytes');
  }
  var alpha = false;
  for (var i = 3; i < rgba.length && !alpha; i += 4) {
    alpha = rgba[i] != 0xff;
  }
  // At worst, each pixel takes an RGBA chunk.
  final out = Uint8List(qoiHeaderSize + pixels * 5 + _end.length);
  ByteData.sublistView(out)
    ..setUint32(0, _magic)
    ..setUint32(4, width)
    ..setUint32(8, height)
    ..setUint8(12, alpha ? 4 : 3);
  var at = qoiHeaderSize;
  // Pixels seen, by hash, as 0xRRGGBBAA.
  final index = Uint32List(64);
  var (pr, pg, pb, pa) = (0, 0, 0, 255);
  var run = 0;
  // Wrapped to a signed byte.
  int diff(int x, int y) => ((x - y + 128) & 0xff) - 128;

  for (var i = 0; i < rgba.length; i += 4) {
    final (r, g, b, a) = (rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]);
    final hash = (r * 3 + g * 5 + b * 7 + a * 11) % 64;
    final packed = r << 24 | g << 16 | b << 8 | a;
    final same = r == pr && g == pg && b == pb && a == pa;
    if (same) {
      run++;
    }
    if (run > 0 && (!same || run == _maxRun || i + 4 == rgba.length)) {
      out[at++] = _opRun << 6 | (run - 1);
      run = 0;
    }
    if (same) {
      // A run's pixels are indexed too.
      index[hash] = packed;
      continue;
    }
    if (index[hash] == packed) {
      out[at++] = _opIndex << 6 | hash;
    } else {
      index[hash] = packed;
      if (a != pa) {
        out
          ..[at] = _opRgba
          ..[at + 1] = r
          ..[at + 2] = g
          ..[at + 3] = b
          ..[at + 4] = a;
        at += 5;
      } else {
        final (dr, dg, db) = (diff(r, pr), diff(g, pg), diff(b, pb));
        final (drg, dbg) = (diff(dr, dg), diff(db, dg));
        if (dr >= -2 && dr <= 1 && dg >= -2 && dg <= 1 && db >= -2 && db <= 1) {
          out[at++] = _opDiff << 6 | (dr + 2) << 4 | (dg + 2) << 2 | (db + 2);
        } else if (drg >= -8 &&
            drg <= 7 &&
            dg >= -32 &&
            dg <= 31 &&
            dbg >= -8 &&
            dbg <= 7) {
          out
            ..[at] = _opLuma << 6 | (dg + 32)
            ..[at + 1] = (drg + 8) << 4 | (dbg + 8);
          at += 2;
        } else {
          out
            ..[at] = _opRgb
            ..[at + 1] = r
            ..[at + 2] = g
            ..[at + 3] = b;
          at += 4;
        }
      }
    }
    (pr, pg, pb, pa) = (r, g, b, a);
  }
  out.setAll(at, _end);
  // A copy, dropping the worst case's room.
  return out.sublist(0, at + _end.length);
}
