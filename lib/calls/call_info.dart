import 'package:btox/calls/call_audio.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'call_info.freezed.dart';

enum CallPhase {
  /// Ours, ringing at the friend's.
  calling,

  /// The friend's, ringing here.
  ringing,
  active,
}

/// A call as the UI shows it.
@freezed
abstract class CallInfo with _$CallInfo {
  const factory CallInfo({
    required ChatRef chat,
    required PublicKey friend,
    String? name,
    required CallPhase phase,
    // Placed as a video call.
    @Default(false) bool video,
    // When it was answered.
    DateTime? connectedAt,
    @Default(false) bool muted,
    @Default(AudioRoute.earpiece) AudioRoute route,
    @Default({AudioRoute.earpiece, AudioRoute.speaker}) Set<AudioRoute> routes,
    // Whether our camera is on, and which.
    @Default(false) bool camera,
    @Default(true) bool frontCamera,
    // Whether the friend sends video.
    @Default(false) bool friendVideo,
  }) = _CallInfo;

  const CallInfo._();

  /// As isolates pass it.
  List<Object?> toMessage() => [
    chat.key,
    friend.toJson(),
    name,
    phase.index,
    video,
    connectedAt?.microsecondsSinceEpoch,
    muted,
    route.index,
    [for (final route in routes) route.index],
    camera,
    frontCamera,
    friendVideo,
  ];

  static CallInfo fromMessage(List<Object?> message) => switch (message) {
    [
      String chat,
      String friend,
      String? name,
      int phase,
      bool video,
      int? connectedAt,
      bool muted,
      int route,
      List<Object?> routes,
      bool camera,
      bool frontCamera,
      bool friendVideo,
    ] =>
      CallInfo(
        chat: ChatRef.ofKey(chat)!,
        friend: PublicKey.fromJson(friend),
        name: name,
        phase: CallPhase.values[phase],
        video: video,
        connectedAt: connectedAt == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(connectedAt),
        muted: muted,
        route: AudioRoute.values[route],
        routes: {for (final r in routes.cast<int>()) AudioRoute.values[r]},
        camera: camera,
        frontCamera: frontCamera,
        friendVideo: friendVideo,
      ),
    _ => throw FormatException('Not a call: $message'),
  };
}
