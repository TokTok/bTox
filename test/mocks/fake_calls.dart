import 'dart:typed_data';

import 'package:btox/calls/call_audio.dart';
import 'package:btox/calls/call_protocol.dart';
import 'package:btox/calls/call_video.dart';
import 'package:btox/models/crypto.dart';

final class FakeCallProtocol implements CallProtocol {
  final signals = <CallSignal>[];
  final asked = <String>[];
  final sent = <Int16List>[];
  final videoSent = <I420Frame>[];
  @override
  var ringsElsewhere = false;

  @override
  List<CallSignal> poll() {
    final polled = [...signals];
    signals.clear();
    return polled;
  }

  @override
  Duration get interval => Duration.zero;

  @override
  bool call(PublicKey friend, {required bool video}) {
    asked.add(video ? 'video call' : 'call');
    return true;
  }

  @override
  void answer(PublicKey friend, {required bool video}) =>
      asked.add(video ? 'answer video' : 'answer');

  // Thrown by hangUp, as when Tox is gone.
  Object? hangUpError;

  @override
  void hangUp(PublicKey friend) {
    asked.add('hang up');
    if (hangUpError case final error?) {
      throw error;
    }
  }

  @override
  void sendAudio(PublicKey friend, Int16List pcm) => sent.add(pcm);

  @override
  void setVideo(PublicKey friend, {required bool on}) =>
      asked.add(on ? 'video' : 'no video');

  @override
  void sendVideo(PublicKey friend, I420Frame frame) => videoSent.add(frame);
}

final class FakeCallVideo implements CallVideo {
  void Function(I420Frame frame)? onFrame;
  void Function()? onStopped;
  bool? front;

  @override
  Future<void> startCamera({
    required bool front,
    required void Function(I420Frame frame) onFrame,
    required void Function() onStopped,
  }) async {
    this.front = front;
    this.onFrame = onFrame;
    this.onStopped = onStopped;
  }

  @override
  Future<void> stopCamera() async => onFrame = null;
}

final class FakeCallAudio implements CallAudio {
  void Function(Int16List frame)? onFrame;
  void Function()? onFailed;
  var fails = false;
  final played = <Int16List>[];
  final tones = <String>[];
  bool? speaker;
  void Function(AudioRoute route, Set<AudioRoute> available)? onRoutes;

  @override
  Future<void> start(
    void Function(Int16List frame) onFrame, {
    required bool speaker,
    required void Function(AudioRoute route, Set<AudioRoute> available)
    onRoutes,
    required void Function() onFailed,
  }) async {
    if (fails) {
      throw Exception('No microphone');
    }
    this.onFrame = onFrame;
    this.onFailed = onFailed;
    this.onRoutes = onRoutes;
    this.speaker = speaker;
  }

  @override
  void play(Int16List pcm, {required int channels, required int sampleRate}) =>
      played.add(pcm);

  @override
  Future<void> setRoute(AudioRoute route) async {}

  @override
  Future<void> setRingBack({required bool on}) async =>
      tones.add(on ? 'ring back' : 'no ring back');

  @override
  Future<void> setRinging({required bool on}) async =>
      tones.add(on ? 'ring' : 'no ring');

  @override
  Future<void> stop() async => onFrame = null;
}
