import 'dart:typed_data';

import 'package:btox/models/content.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter/widgets.dart';

/// Browsers have no file system for bTox to keep files in.
const filesSupported = false;

Future<String> attachmentsDirectory() async => '';

Future<FileContent> saveAttachment(String directory, XFile file) =>
    throw UnsupportedError('No attachments on the web');

Future<void> deleteAttachment(String path) async {}

Widget? imagePreview(String path) => null;

final class Attachment {
  Attachment.create(String path) {
    throw UnsupportedError('No attachments on the web');
  }

  Attachment.open(String path) {
    throw UnsupportedError('No attachments on the web');
  }

  Uint8List read(int position, int length) => throw UnimplementedError();

  void write(int position, Uint8List data) => throw UnimplementedError();

  void close() {}
}

String newAttachmentPath(String directory, String name) => name;
