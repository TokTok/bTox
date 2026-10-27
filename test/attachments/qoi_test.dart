import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:btox/attachments/attachments.dart';
import 'package:btox/attachments/qoi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// A QOI file of [width] by [height] with [chunks].
Uint8List _qoi(int width, int height, List<int> chunks, {int channels = 4}) {
  final header = ByteData(14)
    ..setUint32(0, 0x716f6966) // "qoif"
    ..setUint32(4, width)
    ..setUint32(8, height)
    ..setUint8(12, channels);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...chunks,
    ...[0, 0, 0, 0, 0, 0, 0, 1],
  ]);
}

// Each kind of chunk once: RGB, DIFF, LUMA, RGBA, INDEX, then a RUN of two.
final _picture = _qoi(7, 1, [
  0xfe, 10, 20, 30, // 10 20 30 255
  0x40 | 3 << 4 | 1 << 2 | 2, // 11 19 30 255
  0x80 | 34, 9 << 4 | 7, // 14 21 31 255
  0xff, 1, 2, 3, 4, // 1 2 3 4
  (10 * 3 + 20 * 5 + 30 * 7 + 255 * 11) % 64, // 10 20 30 255
  0xc0 | 1, // twice more
]);

void main() {
  test('decodes each kind of chunk', () {
    final pixels = decodeQoi(_picture);
    expect((pixels.width, pixels.height), (7, 1));
    expect(pixels.rgba, [
      ...[10, 20, 30, 255],
      ...[11, 19, 30, 255],
      ...[14, 21, 31, 255],
      ...[1, 2, 3, 4],
      ...[10, 20, 30, 255],
      ...[10, 20, 30, 255],
      ...[10, 20, 30, 255],
    ]);
  });

  test("a run's pixels go into the index too", () {
    // A run of the start pixel, then it by index.
    final pixels = decodeQoi(
      _qoi(3, 1, [0xc0, 0xfe, 9, 9, 9, (255 * 11) % 64]),
    );
    expect(pixels.rgba, [
      ...[0, 0, 0, 255],
      ...[9, 9, 9, 255],
      ...[0, 0, 0, 255],
    ]);
  });

  test('what is malformed or too big fails to decode', () {
    final ok = _qoi(1, 1, [0xfe, 1, 2, 3]);
    for (final bytes in [
      Uint8List(0),
      ok.sublist(0, 13),
      Uint8List.fromList([...'qoix'.codeUnits, ...ok.sublist(4)]),
      ok.sublist(0, ok.length - 1),
      _qoi(0, 1, [0xfe, 1, 2, 3]),
      _qoi(1, 1, [0xfe, 1, 2, 3], channels: 5),
      // A chunk cut short, and data after the last pixel.
      _qoi(1, 1, [0xfe, 1]),
      _qoi(1, 1, [0xfe, 1, 2, 3, 0xfe, 4, 5, 6]),
      // More pixels than the header says.
      _qoi(1, 1, [0xc0 | 5]),
      // More pixels than its data could hold.
      _qoi(65536, 65536, [0xc0]),
      // Sides whose product overflows to fewer pixels.
      _qoi(3221253850, 4294929459, List.filled(60, 0xc0 | 61)),
      _qoi(1000, 1000, List.filled(1000, 0xc0 | 61)),
      // More pixels than bTox shows.
      _qoi(8192, 8192, List.filled(8192 * 8192 ~/ 62 + 1, 0xc0 | 61)),
    ]) {
      expect(() => decodeQoi(bytes), throwsFormatException);
    }
  });

  test('fitted, it takes the pixels the smaller picture falls on', () {
    // 4×2, each pixel's red its place.
    final rgba = Uint8List.fromList([
      for (var i = 0; i < 8; i++) ...[i, 0, 0, 255],
    ]);
    final (:width, :height, rgba: fitted) = decodeQoi(
      encodeQoi(rgba, 4, 2),
      fit: 2,
    );
    expect((width, height), (2, 1));
    expect(fitted, [0, 0, 0, 255, 2, 0, 0, 255]);
  });

  test('what it encodes decodes the same', () {
    // Every kind of chunk: long runs, wrapping steps, small and large ones,
    // repeats and alpha.
    final pixels = [
      for (var i = 0; i < 70; i++) ...[0, 0, 0, 255],
      ...[255, 1, 0, 255],
      ...[0, 255, 1, 255],
      ...[20, 40, 10, 255],
      ...[200, 100, 50, 255],
      ...[255, 1, 0, 255],
      ...[200, 100, 50, 128],
      ...[200, 100, 50, 128],
      ...[0, 0, 0, 0],
    ];
    final rgba = Uint8List.fromList(pixels);
    final opaque = Uint8List.fromList(pixels.sublist(0, 74 * 4));
    for (final (picture, width, height, channels) in [
      (rgba, 78, 1, 4),
      (rgba, 6, 13, 4),
      (opaque, 74, 1, 3),
    ]) {
      final encoded = encodeQoi(picture, width, height);
      expect(encoded[12], channels);
      final decoded = decodeQoi(encoded);
      expect((decoded.width, decoded.height), (width, height));
      expect(decoded.rgba, picture);
    }
  });

  testWidgets('a picture is sent as QOI with its pixels, a file as it is', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final rgba = Uint8List.fromList([
      for (var i = 0; i < 6; i++) ...[i * 40, 255 - i * 40, i, 255],
    ]);
    await tester.runAsync(() async {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgba,
        3,
        2,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final png = await (await completer.future).toByteData(
        format: ui.ImageByteFormat.png,
      );
      final photo = File('${directory.path}/photo.png')
        ..writeAsBytesSync(png!.buffer.asUint8List());
      final notes = File('${directory.path}/notes.jpg')
        ..writeAsStringSync('not a picture');

      final sent = await savePictureAsQoi(directory.path, XFile(photo.path));
      expect(sent.name, 'photo.qoi');
      final decoded = decodeQoi(File(sent.path).readAsBytesSync());
      expect((decoded.width, decoded.height), (3, 2));
      expect(decoded.rgba, rgba);

      final kept = await savePictureAsQoi(directory.path, XFile(notes.path));
      expect(
        (kept.name, File(kept.path).readAsStringSync()),
        ('notes.jpg', 'not a picture'),
      );
    });
  });

  testWidgets('a QOI file shows as a picture, a bad one as missing', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync();
    addTearDown(() => directory.deleteSync(recursive: true));
    final good = File('${directory.path}/good.QOI')..writeAsBytesSync(_picture);
    final bad = File('${directory.path}/bad.qoi')
      ..writeAsBytesSync(_qoi(65536, 65536, [0xc0]));

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            // A chat's largest preview.
            ConstrainedBox(
              constraints: BoxConstraints.loose(const Size.square(240)),
              child: imagePreview(good.path, size: 4),
            ),
            picture(bad.path),
          ],
        ),
      ),
    );
    RawImage? shown() =>
        tester.widgetList<RawImage>(find.byType(RawImage)).firstOrNull;
    for (
      var i = 0;
      i < 50 &&
          (shown()?.image == null ||
              find.byIcon(Icons.broken_image).evaluate().isEmpty);
      i++
    ) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    // Shrunk to fit the preview.
    expect((shown()?.image?.width, shown()?.image?.height), (4, 1));
    expect(find.byIcon(Icons.broken_image), findsOneWidget);
  });
}
