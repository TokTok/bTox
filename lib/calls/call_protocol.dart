import 'dart:typed_data';

import 'package:btox/models/crypto.dart';
import 'package:btox_call_media/btox_call_media.dart' show I420Frame;
import 'package:freezed_annotation/freezed_annotation.dart';

export 'package:btox_call_media/btox_call_media.dart' show I420Frame;

part 'call_protocol.freezed.dart';

/// Audio frames calls take and give: 20 ms of 48 kHz mono 16-bit PCM.
const callSampleRate = 48000;
const callFrameSamples = callSampleRate ~/ 50;

/// What a call protocol tells of a call with a friend.
@freezed
sealed class CallSignal with _$CallSignal {
  /// The friend calls.
  const factory CallSignal.ringing(PublicKey friend, {required bool video}) =
      CallRinging;

  /// The friend answered.
  const factory CallSignal.answered(PublicKey friend) = CallAnswered;

  /// The call ended, at either end, or [failed].
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

  /// Whether the friend sends video, as it changes.
  const factory CallSignal.friendVideo(PublicKey friend, {required bool on}) =
      CallFriendVideo;

  const factory CallSignal.video(PublicKey friend, I420Frame frame) =
      CallVideoFrame;
}

/// Calls with friends over one protocol, such as toxav. Each call is the
/// one with a friend.
abstract interface class CallProtocol {
  /// What happened since the last time, in order.
  List<CallSignal> poll();

  /// How soon to poll again.
  Duration get interval;

  /// Whether calls ring on other devices too, which may answer them.
  bool get ringsElsewhere;

  /// Whether the call was placed.
  bool call(PublicKey friend, {required bool video});

  void answer(PublicKey friend, {required bool video});

  /// Ends the call, or declines it while it rings.
  void hangUp(PublicKey friend);

  /// One frame of [callFrameSamples].
  void sendAudio(PublicKey friend, Int16List pcm);

  /// Once the call is answered, starts or stops sending video.
  void setVideo(PublicKey friend, {required bool on});

  void sendVideo(PublicKey friend, I420Frame frame);
}
