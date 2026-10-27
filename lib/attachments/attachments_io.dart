import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
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

// The longest file name most file systems take, in bytes.
const _maxNameBytes = 255;

/// A new path in [directory] that keeps [name] recognisable, cut short to
/// fit, keeping its extension.
String newAttachmentPath(String directory, String name) {
  final prefix = '${DateTime.now().microsecondsSinceEpoch}_';
  final base = path.basename(name);
  final extension = path.extension(base);
  final room = _maxNameBytes - prefix.length;
  final extensionBytes = utf8.encode(extension).length;
  final fitted = utf8.encode(base).length <= room
      ? base
      : extensionBytes <= room ~/ 2
      ? _cut(path.withoutExtension(base), room - extensionBytes) + extension
      : _cut(base, room);
  return path.join(directory, '$prefix$fitted');
}

/// The start of [text] that fits in [bytes] of UTF-8.
String _cut(String text, int bytes) {
  final kept = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    bytes -= utf8.encode(char).length;
    if (bytes < 0) {
      break;
    }
    kept.write(char);
  }
  return kept.toString();
}

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

/// Copies the attachment [file] into [directory] under a new name, so each
/// chat that has it keeps its own.
Future<FileContent> copyAttachment(String directory, FileContent file) async {
  final target = newAttachmentPath(directory, file.name);
  await File(file.path).copy(target);
  return file.copyWith(path: target);
}

Future<void> deleteAttachment(String path) => File(path).delete();

bool attachmentExists(String path) => File(path).existsSync();

Future<BlobId> blobOf(String path) async => BlobId(
  Uint8List.fromList((await sha256.bind(File(path).openRead()).first).bytes),
);

/// [file] if it's an image, decoded to fit [size] physical pixels square:
/// photos are far bigger than they're shown.
Widget? imagePreview(String file, {required int size}) =>
    switch (path.extension(file).toLowerCase()) {
      final extension when _imageExtensions.contains(extension) => _shaped(
        file,
        Image(
          image: ResizeImage(
            FileImage(File(file)),
            width: size,
            height: size,
            policy: ResizeImagePolicy.fit,
          ),
          fit: BoxFit.cover,
          errorBuilder: _missing,
        ),
      ),
      _ => null,
    };

// The most pixels a picture may have to be shown, as Flutter may decode all
// of them however small it shows it: 64 Mi, 256 MiB as RGBA, so 50 MP photos
// still show.
const _maxPixels = 1 << 26;

final _sizes = <String, Size>{};

/// The size of the picture [file], as its header says, turned the way it's
/// shown: much sooner known than its pixels.
Future<Size?> _sizeOf(String file) async {
  if (_sizes[file] case final size?) {
    return size;
  }
  try {
    final Size size;
    final buffer = await ui.ImmutableBuffer.fromFilePath(file);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      size = Size(descriptor.width.toDouble(), descriptor.height.toDouble());
      descriptor.dispose();
    } finally {
      buffer.dispose();
    }
    return _sizes[file] = size;
  } on Exception {
    // Shown as missing, as it won't decode either.
    return null;
  }
}

/// The picture [file], [shown] at its size once its header says it has no
/// more than [_maxPixels] pixels, else [missing].
final class _Sized extends HookWidget {
  final String file;
  final Widget Function(Size size) shown;
  final Widget waiting;
  final Widget missing;

  const _Sized({
    required this.file,
    required this.shown,
    required this.waiting,
    this.missing = _broken,
  });

  @override
  Widget build(BuildContext context) {
    final read = useFuture(
      useMemoized(() => _sizeOf(file), [file]),
      initialData: _sizes[file],
    );
    return switch (read.data) {
      final size? when size.width * size.height <= _maxPixels => shown(size),
      null when read.connectionState != ConnectionState.done => waiting,
      _ => missing,
    };
  }
}

/// [child], the picture [file], in its shape and size from the start, so the
/// chat doesn't jump when the picture shows.
Widget _shaped(String file, Widget child) => _Sized(
  file: file,
  // No bigger than the picture, which isn't scaled up.
  shown: (size) => ConstrainedBox(
    constraints: BoxConstraints.loose(size),
    child: AspectRatio(aspectRatio: size.width / size.height, child: child),
  ),
  waiting: const AspectRatio(aspectRatio: 1),
  missing: const AspectRatio(aspectRatio: 1, child: _broken),
);

const _broken = Icon(Icons.broken_image);

Widget _missing(BuildContext context, Object error, StackTrace? stackTrace) =>
    _broken;

final class Attachment {
  final RandomAccessFile _file;

  Attachment.create(String path)
    : _file = File(path).openSync(mode: FileMode.write);

  Attachment.open(String path) : _file = File(path).openSync();

  Attachment.resume(String path)
    : _file = File(path).openSync(mode: FileMode.append);

  int get length => _file.lengthSync();

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
