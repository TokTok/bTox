import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:btox/attachments/attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path/path.dart' as path;

/// A black PNG picture of [side] by [side] pixels, small as a file.
Uint8List _png(int side) {
  List<int> u32(int value) => [
    for (var shift = 24; shift >= 0; shift -= 8) value >> shift & 0xff,
  ];
  int crc(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = crc & 1 == 1 ? 0xedb88320 ^ crc >> 1 : crc >> 1;
      }
    }
    return crc ^ 0xffffffff;
  }

  List<int> chunk(String type, List<int> data) {
    final body = [...ascii.encode(type), ...data];
    return [...u32(data.length), ...body, ...u32(crc(body))];
  }

  // A filter byte, then a bit per pixel, for each row.
  final rows = Uint8List((1 + (side + 7) ~/ 8) * side);
  return Uint8List.fromList([
    ...[0x89, ...ascii.encode('PNG'), 0x0d, 0x0a, 0x1a, 0x0a],
    // One bit of grey per pixel.
    ...chunk('IHDR', [...u32(side), ...u32(side), 1, 0, 0, 0, 0]),
    ...chunk('IDAT', zlib.encode(rows)),
    ...chunk('IEND', []),
  ]);
}

void main() {
  test('a long name is cut to fit, keeping its extension', () async {
    final directory = await Directory.systemTemp.createTemp();
    addTearDown(() => directory.delete(recursive: true));
    final photo = File(newAttachmentPath(directory.path, '${'é' * 200}.jpeg'));
    await photo.create();
    expect(path.extension(photo.path), '.jpeg');
    expect(path.basename(photo.path), contains('éé'));

    final odd = File(newAttachmentPath(directory.path, 'x.${'y' * 300}'));
    await odd.create();
    expect(utf8.encode(path.basename(odd.path)).length, 255);
  });

  testWidgets('a picture with more pixels than can be shown is missing, and '
      'sent as it is', (tester) async {
    final directory = Directory.systemTemp.createTempSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final big = File('${directory.path}/big.png')..writeAsBytesSync(_png(8193));

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            // As big as a chat shows it at most.
            ConstrainedBox(
              constraints: BoxConstraints.loose(const Size.square(240)),
              child: imagePreview(big.path, size: 240),
            ),
            Expanded(child: picture(big.path)),
          ],
        ),
      ),
    );
    for (
      var i = 0;
      i < 50 && find.byIcon(Icons.broken_image).evaluate().length < 2;
      i++
    ) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byIcon(Icons.broken_image), findsNWidgets(2));
    expect(find.byType(RawImage), findsNothing);
    // The preview keeps its shape.
    expect(
      tester.getSize(find.byIcon(Icons.broken_image).first),
      const Size.square(240),
    );

    final sent = await tester.runAsync(
      () => savePictureAsQoi(directory.path, XFile(big.path)),
    );
    expect(sent!.name, 'big.png');
  });
}
