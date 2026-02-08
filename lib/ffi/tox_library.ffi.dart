import 'dart:ffi';

import 'package:btox/ffi/generated/toxcore.ffi.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:ffi/ffi.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'dart:ffi';

export 'package:btox/ffi/generated/toxcore.ffi.dart';

part 'tox_library.ffi.g.dart';

@riverpod
Future<ToxLibrary> toxFfi(Ref ref) async {
  return ToxLibrary(
    malloc,
    ToxFfi(AnyPlatform.instance.isAndroid
        ? DynamicLibrary.open('libtoxcore.so')
        : DynamicLibrary.process()),
  );
}

typedef CChar = Char;

typedef CEnum = UnsignedInt;

final class ToxLibrary {
  final Allocator allocator;
  final ToxFfi ffi;

  const ToxLibrary(this.allocator, this.ffi);
}
