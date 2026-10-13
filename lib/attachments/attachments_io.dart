import 'dart:io';
import 'dart:typed_data';

import 'package:btox/models/content.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const filesSupported = true;

const _imageExtensions = {'.gif', '.jpeg', '.jpg', '.png', '.webp'};

Future<String> attachmentsDirectory() async {
  final dir = Directory(
    path.join((await getApplicationSupportDirectory()).path, 'attachments'),
  );
  await dir.create(recursive: true);
  return dir.path;
}

/// A new path in [directory] that keeps [name] recognisable.
String newAttachmentPath(String directory, String name) => path.join(
  directory,
  '${DateTime.now().microsecondsSinceEpoch}_${path.basename(name)}',
);

/// Copies [file] into [directory], where the background service can read it.
Future<FileContent> saveAttachment(String directory, XFile file) async {
  final target = newAttachmentPath(directory, file.name);
  await file.saveTo(target);
  return FileContent(
    name: file.name,
    size: await File(target).length(),
    path: target,
  );
}

Future<void> deleteAttachment(String path) => File(path).delete();

Widget? imagePreview(String file) =>
    _imageExtensions.contains(path.extension(file).toLowerCase())
    ? Image.file(File(file), fit: BoxFit.cover)
    : null;

final class Attachment {
  final RandomAccessFile _file;

  Attachment.create(String path)
    : _file = File(path).openSync(mode: FileMode.write);

  Attachment.open(String path) : _file = File(path).openSync();

  Uint8List read(int position, int length) {
    _file.setPositionSync(position);
    return _file.readSync(length);
  }

  void write(int position, Uint8List data) {
    _file.setPositionSync(position);
    _file.writeFromSync(data);
  }

  void close() => _file.closeSync();
}
