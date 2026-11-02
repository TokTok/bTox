import 'dart:typed_data';

import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/database.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'avatars.g.dart';

/// Null until the image is here.
@riverpod
Stream<Uint8List?> avatar(Ref ref, Id<Profiles> profile, BlobId blob) =>
    watchDb(ref, (db) => db.watchAvatar(profile, blob));
