import 'dart:typed_data';

import 'package:btox/models/crypto.dart';
import 'package:btox_call_media/btox_call_media.dart' show I420Frame;
import 'package:freezed_annotation/freezed_annotation.dart';

export 'package:btox_call_media/btox_call_media.dart' show I420Frame;

part 'call_protocol.freezed.dart';

/// Audio frames calls take and give: 20 ms of 48 kHz mono 16-bit PCM.
const callSampleRate = 48000;
const callFrameSamples = callSampleRate ~/ 50;

@freezed
sealed class CallSignal with _$CallSignal {
  const factory CallSignal.ringing(PublicKey friend, {required bool video}) =
      CallRinging;

  const factory CallSignal.answered(PublicKey friend) = CallAnswered;

  const factory CallSignal.finished(
    PublicKey friend, {
    @Default(false) bool failed,
  }) = CallFinished;

  const factory CallSignal.audio(
    PublicKey friend,
    Int16List pcm, {
    required int channels,
    required int sampleRate,
  }) = CallAudioFrame;

  const factory CallSignal.friendVideo(PublicKey friend, {required bool on}) =
      CallFriendVideo;

  const factory CallSignal.video(PublicKey friend, I420Frame frame) =
      CallVideoFrame;
}

abstract interface class CallProtocol {
  List<CallSignal> poll();

  Duration get interval;

  bool get ringsElsewhere;

  bool call(PublicKey friend, {required bool video});

  void answer(PublicKey friend, {required bool video});

  /// Also declines it while it rings.
  void hangUp(PublicKey friend);

  /// One frame of [callFrameSamples].
  void sendAudio(PublicKey friend, Int16List pcm);

  /// Once the call is answered.
  void setVideo(PublicKey friend, {required bool on});

  void sendVideo(PublicKey friend, I420Frame frame);
}
