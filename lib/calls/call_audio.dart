import 'dart:typed_data';

import 'package:btox_call_media/btox_call_media.dart' show AudioRoute;

export 'package:btox_call_media/btox_call_media.dart' show AudioRoute;

abstract interface class CallAudio {
  /// On the loudspeaker if [speaker] and there's no headset. [onFailed] is for
  /// when the microphone stops for good.
  Future<void> start(
    void Function(Int16List frame) onFrame, {
    required bool speaker,
    required void Function(AudioRoute route, Set<AudioRoute> available)
    onRoutes,
    required void Function() onFailed,
  });

  void play(Int16List pcm, {required int channels, required int sampleRate});

  Future<void> setRoute(AudioRoute route);

  Future<void> setRingBack({required bool on});

  Future<void> setRinging({required bool on});

  Future<void> stop();
}
