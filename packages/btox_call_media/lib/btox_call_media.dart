import 'dart:typed_data';

import 'package:btox_call_media/src/platform_call_media.dart';

enum AudioRoute { earpiece, speaker, wired, bluetooth }

/// Planes one after the other, without padding.
final class I420Frame {
  final int width;
  final int height;
  final Uint8List data;

  I420Frame(this.width, this.height, this.data)
    : assert(data.length == size(width, height));

  static int size(int width, int height) =>
      width * height + 2 * ((width + 1) ~/ 2) * ((height + 1) ~/ 2);

  int get chromaWidth => (width + 1) ~/ 2;

  int get chromaHeight => (height + 1) ~/ 2;

  Uint8List get y => Uint8List.sublistView(data, 0, width * height);

  Uint8List get u => Uint8List.sublistView(
    data,
    width * height,
    width * height + chromaWidth * chromaHeight,
  );

  Uint8List get v =>
      Uint8List.sublistView(data, width * height + chromaWidth * chromaHeight);
}

/// There's none, or another app holds it.
final class CallMediaException implements Exception {
  final String message;

  const CallMediaException(this.message);

  @override
  String toString() => 'CallMediaException: $message';
}

/// Audio as 16-bit mono PCM, little-endian, in frames, and video as I420.
abstract interface class BtoxCallMedia {
  static BtoxCallMedia instance = platformCallMedia();

  Stream<Uint8List> get frames;

  Stream<(AudioRoute, Set<AudioRoute>)> get routes;

  /// On Android, also the call's foreground service, whose notification shows
  /// [title] in [channel]. The audio goes to a headset, else the loudspeaker
  /// if [speaker], else the earpiece.
  Future<void> start({
    required int sampleRate,
    required int frameSamples,
    required bool speaker,
    required String title,
    required String channel,
  });

  void play(Uint8List pcm);

  /// Until a headset connects.
  Future<void> setRoute(AudioRoute route);

  Future<void> setRingBack({required bool on});

  /// Vibrates too, where the phone does.
  Future<void> setRinging({required bool on});

  Future<void> stop();

  Stream<I420Frame> get cameraFrames;

  /// Once the audio started.
  Future<void> startCamera({required bool front});

  Future<void> stopCamera();

  /// From the UI, asking if needed.
  Future<bool> requestPermissions({required bool camera});

  /// Since Android 14, the user decides.
  Future<bool> canRingOverLockScreen();

  Future<void> allowRingingOverLockScreen();

  /// From the UI. Turns the screen on, as for a call ringing.
  Future<void> showOverLockScreen({required bool on});
}
