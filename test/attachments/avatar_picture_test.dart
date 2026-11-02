import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:btox/attachments/avatar_picture.dart';
import 'package:btox/sync/avatar_files.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/png.dart';

void main() {
  testWidgets('makes a small square avatar of a picture', (tester) async {
    await tester.runAsync(() async {
      final avatar = (await avatarPicture(await png(600, 400)))!;
      expect(avatar.length, lessThanOrEqualTo(maxAvatarSize));
      final descriptor = await ui.ImageDescriptor.encoded(
        await ui.ImmutableBuffer.fromUint8List(avatar),
      );
      expect((descriptor.width, descriptor.height), (256, 256));
    });
  });

  testWidgets('makes none of what is no picture', (tester) async {
    await tester.runAsync(() async {
      expect(await avatarPicture(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });
}
