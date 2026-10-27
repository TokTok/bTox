import 'dart:async';
import 'dart:typed_data';

import 'package:btox_call_media/btox_call_media.dart';

final class FakeCallMedia implements BtoxCallMedia {
  final microphoneFrames = StreamController<Uint8List>.broadcast();
  final routeChanges =
      StreamController<(AudioRoute, Set<AudioRoute>)>.broadcast();
  final camera = StreamController<I420Frame>.broadcast();
  final asked = <String>[];
  final played = <Uint8List>[];
  var microphoneAllowed = true;
  var cameraAllowed = true;
  var ringsOverLockScreen = true;

  @override
  Stream<Uint8List> get frames => microphoneFrames.stream;

  @override
  Stream<(AudioRoute, Set<AudioRoute>)> get routes => routeChanges.stream;

  @override
  Stream<I420Frame> get cameraFrames => camera.stream;

  @override
  Future<void> start({
    required int sampleRate,
    required int frameSamples,
    required bool speaker,
    required String title,
    required String channel,
  }) async => asked.add(speaker ? 'start on speaker' : 'start');

  @override
  void play(Uint8List pcm) => played.add(pcm);

  @override
  Future<void> setRoute(AudioRoute route) async => asked.add(route.name);

  @override
  Future<void> setRingBack({required bool on}) async =>
      asked.add(on ? 'ring back' : 'no ring back');

  @override
  Future<void> setRinging({required bool on}) async =>
      asked.add(on ? 'ring' : 'no ring');

  @override
  Future<void> stop() async => asked.add('stop');

  @override
  Future<void> startCamera({required bool front}) async =>
      asked.add(front ? 'front camera' : 'back camera');

  @override
  Future<void> stopCamera() async => asked.add('no camera');

  @override
  Future<bool> requestPermissions({required bool camera}) async {
    asked.add(camera ? 'camera permission' : 'microphone permission');
    return camera ? cameraAllowed : microphoneAllowed;
  }

  @override
  Future<bool> canRingOverLockScreen() async => ringsOverLockScreen;

  @override
  Future<void> allowRingingOverLockScreen() async =>
      asked.add('allow ringing over the lock screen');

  @override
  Future<void> showOverLockScreen({required bool on}) async {}
}
