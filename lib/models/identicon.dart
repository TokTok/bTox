// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2019 by The qTox Project Contributors
// Copyright © 2024-2025 The TokTok team.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:btox/logger.dart';
import 'package:btox/models/bytes.dart';
import 'package:btox/models/crypto.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'identicon.g.dart';

/// Width from the center to the outside, for 5 columns it's 3, 6 -> 3, 7 -> 4.
const _kActiveCols = (_kIdenticonRows + 1) ~/ 2;

// Maximum value for a color number (6 bytes, i.e. (1 << (8 * _kIdenticonColorBytes)) - 1).
const double _kColorIntMax = 0xffffffffffff;

/// Number of colors to use for the identicon.
const _kColors = 2;

/// Specifies how many bytes should define the foreground color
/// must be smaller than 8, else there'll be overflows.
const _kIdenticonColorBytes = 6;

/// Specifies how many rows of blocks the identicon should have.
const _kIdenticonRows = 5;

const _logger = Logger(['Identicon']);

@Riverpod(keepAlive: true)
Identicon identicon(Ref ref, PublicKey publicKey) {
  _logger.d('Creating identicon for public key: $publicKey');
  return Identicon.fromPublicKey(publicKey);
}

double _bytesToColor(Uint8List bytes) {
  assert(bytes.length == _kIdenticonColorBytes, 'bytes: $bytes');

  final data =
      ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
  // Using int32 here to make sure all systems behave the same.
  final hi = _toDouble(data.getInt32(0));
  final lo = data.getUint16(4);

  assert(hi >= 0 && hi <= _kColorIntMax / 0x10000, 'hi: $hi');
  assert(lo >= 0, 'lo: $lo');

  // Using double because int could be 32 bit (on web).
  final hue = hi * 0x10000 + lo.toDouble();
  assert(hue >= 0 && hue <= _kColorIntMax, 'hue: $hue');

  // Normalize to 0.0 ... 360.0.
  return hue / _kColorIntMax.toDouble() * 360.0;
}

/// Special toDouble that converts a negative int to its twos complement
/// positive version.
///
/// We do this because web may have 32 bit signed ints.
double _toDouble(int value) {
  if (value < 0) {
    return value.toDouble() + 0x100000000;
  }
  return value.toDouble();
}

Uint8List _upscale(int factor, Uint8List pixels) {
  final size = sqrt(pixels.length / 4).round();
  assert(size * size * 4 == pixels.length);
  final scaled = Uint8List(pixels.length * factor * factor);
  for (int row = 0; row < size; ++row) {
    for (int col = 0; col < size; ++col) {
      final color = pixels.buffer.asUint8List(row * size * 4 + col * 4);
      for (int y = 0; y < factor; ++y) {
        for (int x = 0; x < factor; ++x) {
          final idx =
              (row * factor + y) * size * factor * 4 + (col * factor + x) * 4;
          scaled.setRange(idx, idx + 4, color);
        }
      }
    }
  }
  return scaled;
}

final class Identicon extends ImageProvider<ui.Image> {
  final List<List<int>> identiconColors;
  final List<Color> colors;
  final int scale;
  final Uint8List rgba;
  final Future<ui.Image> image;

  const Identicon(
    this.identiconColors,
    this.colors,
    this.scale,
    this.rgba,
    this.image,
  );

  factory Identicon.fromBytes(Uint8List data) {
    _logger.v('Generating identicon from data: $data');
    List<Color> colors = List.filled(_kColors, Colors.black);

    assert(_kColors == 2);
    // hash with sha256
    var hash = Uint8List.fromList(sha256.convert(data).bytes);
    for (int colorIndex = 0; colorIndex < _kColors; ++colorIndex) {
      final hashPart = Uint8List.view(hash.buffer,
          hash.length - _kIdenticonColorBytes, _kIdenticonColorBytes);
      hash = Uint8List.view(
          hash.buffer, hash.offsetInBytes, hash.length - _kIdenticonColorBytes);

      final hue = _bytesToColor(hashPart);
      _logger.v('Color $colorIndex: $hue');
      // change offset when COLORS != 2
      final lig = colorIndex / _kColors + 0.3;
      const sat = 0.5;
      final hsl = HSLColor.fromAHSL(1.0, hue, sat, lig);
      colors[colorIndex] = hsl.toColor();
    }

    // compute the block colors from the hash
    final identiconColors = List.generate(_kIdenticonRows, (row) {
      return List<int>.filled(_kActiveCols, 0);
    });
    for (int row = 0; row < _kIdenticonRows; ++row) {
      for (int col = 0; col < _kActiveCols; ++col) {
        final hashIdx = row * _kActiveCols + col;
        final colorIndex = hash[hashIdx % hash.length] % _kColors;
        identiconColors[row][col] = colorIndex;
      }
    }

    final matrix = toMatrix(identiconColors);
    final pixels = <int>[];

    for (int row = 0; row < _kIdenticonRows; ++row) {
      for (int col = 0; col < _kIdenticonRows; ++col) {
        final color = colors[matrix[row][col]];
        pixels.addAll([
          (color.r * 255).round(),
          (color.g * 255).round(),
          (color.b * 255).round(),
          255,
        ]);
      }
    }

    // We don't need to scale it by a lot, but giving the original size makes
    // Flutter scale it very fuzzily.
    const int scale = 10;
    final rgba = _upscale(scale, Uint8List.fromList(pixels));

    return Identicon(
      identiconColors,
      colors,
      scale,
      rgba,
      toImage(rgba, scale),
    );
  }

  factory Identicon.fromPublicKey(PublicKey publicKey) {
    return Identicon.fromBytes(publicKey.bytes);
  }

  @override
  int get hashCode => memHash(rgba);

  @override
  bool operator ==(Object other) {
    return other is Identicon && memEquals(rgba, other.rgba);
  }

  @override
  ImageStreamCompleter loadImage(ui.Image key, ImageDecoderCallback decode) {
    return ImmediateImageStreamCompleter(
      ImageInfo(
        image: key.clone(),
        debugLabel: 'Identicon',
      ),
    );
  }

  @override
  Future<ui.Image> obtainKey(ImageConfiguration configuration) async {
    return image;
  }

  static Future<ui.Image> toImage(Uint8List rgba, int scale) async {
    _logger.v('Generating identicon image');
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: _kIdenticonRows * scale,
      height: _kIdenticonRows * scale,
      pixelFormat: ui.PixelFormat.rgba8888,
    );

    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static List<List<int>> toMatrix(List<List<int>> identiconColors) {
    final matrix = List.generate(_kIdenticonRows, (row) {
      return List<int>.filled(_kIdenticonRows, 0);
    });
    for (int row = 0; row < _kIdenticonRows; ++row) {
      for (int col = 0; col < _kIdenticonRows; ++col) {
        // mirror on vertical axis
        final columnIdx = (col * 2 - (_kIdenticonRows - 1)).abs() ~/ 2;
        final colorIdx = identiconColors[row][columnIdx];
        matrix[row][col] = colorIdx;
      }
    }
    return matrix;
  }
}

final class ImmediateImageStreamCompleter extends ImageStreamCompleter {
  ImmediateImageStreamCompleter(ImageInfo info) {
    setImage(info);
  }
}
