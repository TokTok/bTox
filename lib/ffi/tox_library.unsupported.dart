import 'package:btox/ffi/generated/toxcore.js.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wasm_ffi/ffi.dart';

export 'package:btox/ffi/generated/toxcore.js.dart';
export 'package:wasm_ffi/ffi.dart';

part 'tox_library.unsupported.g.dart';

@riverpod
Future<ToxLibrary> toxFfi(Ref ref) async {
  throw UnimplementedError('Tox FFI is not implemented on this platform');
}

typedef CChar = Int8;

typedef CEnum = Uint32;

final class ToxLibrary {
  final Allocator allocator;
  final ToxFfi ffi;

  const ToxLibrary(this.allocator, this.ffi);
}
