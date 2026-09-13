import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:sodium/sodium.dart' hide SodiumInit;
import 'package:sodium/sodium.js.dart';
import 'package:web/web.dart';

Future<Sodium> loadSodium() => SodiumInit.initFromSodiumJS(_loadLibSodiumJS);

extension type _SodiumBrowserInit._(JSObject _) implements JSObject {
  external _SodiumBrowserInit({JSFunction onload});
}

@JS('sodium')
external JSObject? get _sodiumGlobal;

@JS('sodium')
external set _sodiumGlobal(JSObject? value);

Future<LibSodiumJS> _loadLibSodiumJS() {
  // Reuse an already-loaded sodium.js if one is present.
  final existing = _sodiumGlobal;
  if (existing != null && existing.has('ready')) {
    final sodium = existing as LibSodiumJS;
    return sodium.ready.toDart.then((_) => sodium);
  }

  // Otherwise, load it: sodium.js calls window.sodium.onload(sodium) once ready.
  final completer = Completer<LibSodiumJS>();
  void onload(LibSodiumJS sodium) => completer.complete(sodium);
  _sodiumGlobal = _SodiumBrowserInit(onload: onload.toJS);

  final script = HTMLScriptElement()
    ..type = 'text/javascript'
    ..async = true
    ..src = 'sodium.js';
  document.body!.append(script);

  return completer.future;
}
