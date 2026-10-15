import 'dart:typed_data';

import 'package:btox_call_media/btox_call_media.dart' show AudioRoute;

export 'package:btox_call_media/btox_call_media.dart' show AudioRoute;

/// The microphone and the earpiece, loudspeaker or headset, during a call,
/// and the tones calls make.
abstract interface class CallAudio {
  /// Starts both, on the loudspeaker if [speaker] and there's no headset.
  /// [onFrame] gets each frame the microphone records, as
  /// `CallProtocol.sendAudio` takes it, [onRoutes] where the audio goes and
  /// could go, as that changes, and [onFailed] when the microphone stops and
  /// can't start again.
  Future<void> start(
    void Function(Int16List frame) onFrame, {
    required bool speaker,
    required void Function(AudioRoute route, Set<AudioRoute> available)
    onRoutes,
    required void Function() onFailed,
  });

  void play(Int16List pcm, {required int channels, required int sampleRate});

  Future<void> setRoute(AudioRoute route);

  /// Once started, the tone of our call ringing at the friend's.
  Future<void> setRingBack({required bool on});

  /// The ringtone of a call ringing here.
  Future<void> setRinging({required bool on});

  Future<void> stop();
}
