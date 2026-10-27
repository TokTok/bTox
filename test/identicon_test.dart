import 'dart:typed_data';
import 'dart:ui';

import 'package:btox/models/identicon.dart';
import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Identicon generation should agree with qTox', () {
    final data = Uint8List.fromList(
      hex.decode(
        '7A114177E3934588EED87E6FE8B18AF7DC581C1FBB67F973EE5BF07B6EFABB72',
      ),
    );

    final identicon = Identicon.fromBytes(data);

    expect(Identicon.toMatrix(identicon.identiconColors), [
      [0, 0, 0, 0, 0],
      [1, 1, 0, 1, 1],
      [0, 0, 0, 0, 0],
      [0, 1, 1, 1, 0],
      [1, 0, 0, 0, 1],
    ]);

    // 0: QColor(AHSL 1, 0.909194, 0.500008, 0.300008)
    //  = QColor(ARGB 1, 0.450019, 0.149996, 0.313451)
    //  = #732650
    expect(_toCssColor(identicon.colors[0]), '#732650');
    // 1: QColor(AHSL 1, 0.978278, 0.500008, 0.8) = #e6b2b9
    expect(_toCssColor(identicon.colors[1]), '#e6b3b9');
  }, tags: ['identicon']);
}

String _toCssColor(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  final rgb = [r, g, b].map((c) => c.toRadixString(16).padLeft(2, '0')).join();
  return '#$rgb';
}
