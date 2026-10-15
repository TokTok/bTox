import 'dart:typed_data';

import 'package:btox_call_media/src/platform_call_media.dart';

/// Where a call's audio goes.
enum AudioRoute { earpiece, speaker, wired, bluetooth }

/// A video frame: I420, its planes one after the other without padding.
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

/// The microphone, the speaker or the camera can't be used: there's none,
/// or another app holds it.
final class CallMediaException implements Exception {
  final String message;

  const CallMediaException(this.message);

  @override
  String toString() => 'CallMediaException: $message';
}

/// Call audio and video: audio as 16-bit mono PCM, little-endian, in
/// frames, and video as I420.
abstract interface class BtoxCallMedia {
  static final BtoxCallMedia instance = platformCallMedia();

  /// The frames the microphone records, once started.
  Stream<Uint8List> get frames;

  /// Where the audio goes, and where it could, once started.
  Stream<(AudioRoute, Set<AudioRoute>)> get routes;

  /// Starts the microphone and the speaker, and on Android the call's
  /// foreground service, whose notification shows [title] in [channel]. The
  /// audio goes to a headset, else the loudspeaker if [speaker], else the
  /// earpiece.
  Future<void> start({
    required int sampleRate,
    required int frameSamples,
    required bool speaker,
    required String title,
    required String channel,
  });

  void play(Uint8List pcm);

  /// Routes the audio to [route] until a headset connects.
  Future<void> setRoute(AudioRoute route);

  /// Plays the tone of a call ringing at the friend's.
  Future<void> setRingBack({required bool on});

  /// Rings, and vibrates where the phone does.
  Future<void> setRinging({required bool on});

  /// Stops the audio, and the camera.
  Future<void> stop();

  /// The frames the camera gives, once started.
  Stream<I420Frame> get cameraFrames;

  /// Once the audio started, the camera.
  Future<void> startCamera({required bool front});

  Future<void> stopCamera();

  /// From the UI: whether bTox may use the microphone, and the [camera],
  /// asking if needed.
  Future<bool> requestPermissions({required bool camera});

  /// Whether a call ringing may show full screen. Since Android 14, the
  /// user decides.
  Future<bool> canRingOverLockScreen();

  /// Opens the setting that lets calls ring full screen.
  Future<void> allowRingingOverLockScreen();

  /// From the UI: shows it over the lock screen, turning the screen on, as
  /// for a call ringing.
  Future<void> showOverLockScreen({required bool on});
}
