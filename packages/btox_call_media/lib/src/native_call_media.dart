import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:btox_call_media/btox_call_media.dart';
import 'package:ffi/ffi.dart';

typedef _AudioFrame = Void Function(Pointer<Int16> pcm, Int32 samples);
typedef _Routes = Void Function(Int32 route, Int32 available);
typedef _VideoFrame = Void Function(
  Pointer<Uint8> i420,
  Int32 width,
  Int32 height,
);
typedef _Stopped = Void Function();
typedef _Permissions = Void Function(Bool granted);

final DynamicLibrary _library = switch (Platform.operatingSystem) {
  'ios' ||
  'macos' => DynamicLibrary.open('btox_call_media.framework/btox_call_media'),
  'windows' => DynamicLibrary.open('btox_call_media.dll'),
  // Where Flutter bundles it, which the engine's library path may not name.
  _ => DynamicLibrary.open(
    '${File(Platform.resolvedExecutable).parent.path}/lib/libbtox_call_media.so',
  ),
};

final _audioStart = _library
    .lookupFunction<
      Bool Function(
        Int32,
        Int32,
        Bool,
        Pointer<NativeFunction<_AudioFrame>>,
        Pointer<NativeFunction<_Routes>>,
      ),
      bool Function(
        int,
        int,
        bool,
        Pointer<NativeFunction<_AudioFrame>>,
        Pointer<NativeFunction<_Routes>>,
      )
    >('btox_audio_start');
final _audioPlay = _library
    .lookupFunction<
      Void Function(Pointer<Int16>, Int32),
      void Function(Pointer<Int16>, int)
    >('btox_audio_play');
final _audioSetRoute = _library
    .lookupFunction<Void Function(Int32), void Function(int)>(
      'btox_audio_set_route',
    );
final _audioSetRingBack = _library
    .lookupFunction<Void Function(Bool), void Function(bool)>(
      'btox_audio_set_ring_back',
    );
final _audioSetRinging = _library
    .lookupFunction<Void Function(Bool), void Function(bool)>(
      'btox_audio_set_ringing',
    );
final _audioStop = _library.lookupFunction<Void Function(), void Function()>(
  'btox_audio_stop',
);
final _cameraStart = _library
    .lookupFunction<
      Bool Function(
        Bool,
        Pointer<NativeFunction<_VideoFrame>>,
        Pointer<NativeFunction<_Stopped>>,
      ),
      bool Function(
        bool,
        Pointer<NativeFunction<_VideoFrame>>,
        Pointer<NativeFunction<_Stopped>>,
      )
    >('btox_camera_start');
final _cameraStop = _library.lookupFunction<Void Function(), void Function()>(
  'btox_camera_stop',
);
final _requestPermissions = _library
    .lookupFunction<
      Void Function(Bool, Pointer<NativeFunction<_Permissions>>),
      void Function(bool, Pointer<NativeFunction<_Permissions>>)
    >('btox_request_permissions');
final _free = _library
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'btox_free',
    );

final class NativeCallMedia implements BtoxCallMedia {
  final _frames = StreamController<Uint8List>.broadcast();
  final _routes = StreamController<(AudioRoute, Set<AudioRoute>)>.broadcast();
  final _cameraFrames = StreamController<I420Frame>.broadcast();
  var _audioOn = false;
  var _cameraOn = false;
  Pointer<Int16> _playback = nullptr;
  var _playbackSamples = 0;

  // Each listener is made once and kept: what the library posts is freed
  // here, and what's still queued when a listener closes would be lost.
  late final _onFrame = NativeCallable<_AudioFrame>.listener((
    Pointer<Int16> pcm,
    int samples,
  ) {
    if (_audioOn) {
      _frames.add(
        Uint8List.fromList(pcm.cast<Uint8>().asTypedList(samples * 2)),
      );
    }
    _free(pcm.cast());
  });
  late final _onRoutes = NativeCallable<_Routes>.listener((
    int route,
    int available,
  ) {
    if (_audioOn) {
      _routes.add((
        AudioRoute.values[route],
        {
          for (final r in AudioRoute.values)
            if (available & (1 << r.index) != 0) r,
        },
      ));
    }
  });
  late final _onCameraFrame = NativeCallable<_VideoFrame>.listener((
    Pointer<Uint8> i420,
    int width,
    int height,
  ) {
    if (_cameraOn) {
      _cameraFrames.add(
        I420Frame(
          width,
          height,
          Uint8List.fromList(i420.asTypedList(I420Frame.size(width, height))),
        ),
      );
    }
    _free(i420.cast());
  });
  late final _onCameraStopped = NativeCallable<_Stopped>.listener(() {
    if (_cameraOn) {
      _cameraFrames.addError(const CallMediaException('The camera stopped'));
    }
  });

  @override
  Stream<Uint8List> get frames => _frames.stream;

  @override
  Stream<(AudioRoute, Set<AudioRoute>)> get routes => _routes.stream;

  @override
  Future<void> start({
    required int sampleRate,
    required int frameSamples,
    required bool speaker,
    required String title,
    required String channel,
  }) async {
    await stop();
    if (!_audioStart(
      sampleRate,
      frameSamples,
      speaker,
      _onFrame.nativeFunction,
      _onRoutes.nativeFunction,
    )) {
      throw const CallMediaException('No call audio');
    }
    _audioOn = true;
  }

  @override
  void play(Uint8List pcm) {
    if (!_audioOn) {
      return;
    }
    final samples = pcm.length ~/ 2;
    if (samples > _playbackSamples) {
      malloc.free(_playback);
      _playback = malloc<Int16>(samples);
      _playbackSamples = samples;
    }
    _playback.cast<Uint8>().asTypedList(pcm.length).setAll(0, pcm);
    _audioPlay(_playback, samples);
  }

  @override
  Future<void> setRoute(AudioRoute route) async => _audioSetRoute(route.index);

  @override
  Future<void> setRingBack({required bool on}) async => _audioSetRingBack(on);

  @override
  Future<void> setRinging({required bool on}) async => _audioSetRinging(on);

  @override
  Future<void> stop() async {
    await stopCamera();
    _audioStop();
    _audioOn = false;
  }

  @override
  Stream<I420Frame> get cameraFrames => _cameraFrames.stream;

  @override
  Future<void> startCamera({required bool front}) async {
    await stopCamera();
    if (!_cameraStart(
      front,
      _onCameraFrame.nativeFunction,
      _onCameraStopped.nativeFunction,
    )) {
      throw const CallMediaException('No camera');
    }
    _cameraOn = true;
  }

  @override
  Future<void> stopCamera() async {
    if (_cameraOn) {
      _cameraStop();
      _cameraOn = false;
    }
  }

  @override
  Future<bool> requestPermissions({required bool camera}) {
    final granted = Completer<bool>();
    late final NativeCallable<_Permissions> done;
    done = NativeCallable<_Permissions>.listener((bool allowed) {
      done.close();
      granted.complete(allowed);
    });
    _requestPermissions(camera, done.nativeFunction);
    return granted.future;
  }

  @override
  Future<bool> canRingOverLockScreen() async => true;

  @override
  Future<void> allowRingingOverLockScreen() async {}

  @override
  Future<void> showOverLockScreen({required bool on}) async {}
}
