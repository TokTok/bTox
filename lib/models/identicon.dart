// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2019 by The qTox Project Contributors
// Copyright © 2024-2025 The TokTok team.

import 'dart:typed_data';

import 'package:btox/logger.dart';
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
Identicon identicon(Ref ref, CryptoBytes bytes) {
  _logger.d('Creating identicon for $bytes');
  return Identicon.fromBytes(bytes.bytes);
}

double _bytesToColor(Uint8List bytes) {
  assert(bytes.length == _kIdenticonColorBytes, 'bytes: $bytes');

  final data = ByteData.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
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

/// A key's picture: blocks of two colours, mirrored left to right, as qTox
/// draws them.
final class Identicon {
  final List<List<int>> identiconColors;
  final List<Color> colors;

  const Identicon(this.identiconColors, this.colors);

  factory Identicon.fromBytes(Uint8List data) {
    _logger.v('Generating identicon from data: $data');
    List<Color> colors = List.filled(_kColors, Colors.black);

    assert(_kColors == 2);
    // hash with sha256
    var hash = Uint8List.fromList(sha256.convert(data).bytes);
    for (int colorIndex = 0; colorIndex < _kColors; ++colorIndex) {
      final hashPart = Uint8List.view(
        hash.buffer,
        hash.length - _kIdenticonColorBytes,
        _kIdenticonColorBytes,
      );
      hash = Uint8List.view(
        hash.buffer,
        hash.offsetInBytes,
        hash.length - _kIdenticonColorBytes,
      );

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

    return Identicon(identiconColors, colors);
  }

  /// Each block's colour, by row and column.
  List<List<Color>> get blocks => [
    for (final row in toMatrix(identiconColors))
      [for (final colorIndex in row) colors[colorIndex]],
  ];

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
