import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:btox/calls/call_audio.dart';
import 'package:btox/calls/call_info.dart';
import 'package:btox/calls/call_protocol.dart';
import 'package:btox/calls/call_video.dart';
import 'package:btox/calls/calls.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/services/isolate_channel.dart';

const _logger = Logger(['CallChannel']);

const _portName = 'btox-calls';
const _callsTopic = 'calls';

String _videoTopic(VideoView view) => 'video-${view.name}';

/// This isolate's calls, for the UI, which may run in another isolate.
final class CallHost {
  static final instance = CallHost._();

  final _calls = <Id<Profiles>, Calls>{};
  final _current = <Id<Profiles>, CallInfo>{};
  Publisher? _publisher;

  void Function(bool busy)? onBusy;

  CallHost._();

  /// One microphone and speaker serve every profile.
  bool busyElsewhere(Id<Profiles> profile) =>
      _current.keys.any((other) => other != profile);

  void add(Id<Profiles> profile, Calls calls) {
    _calls[profile] = calls;
    _publisher ??= Publisher(
      _portName,
      current: (topic) => topic == _callsTopic ? _state() : null,
      subscribersChanged: (topic, count) {
        // With no UI left, calls ring on their own.
        if (topic == _callsTopic && count == 0) {
          for (final calls in _calls.values) {
            calls.setShown(shown: false);
          }
        }
      },
      onMessage: _receive,
    );
  }

  void remove(Id<Profiles> profile) {
    _calls.remove(profile);
    changed(profile, null);
  }

  void changed(Id<Profiles> profile, CallInfo? call) {
    if (call == null) {
      _current.remove(profile);
    } else {
      _current[profile] = call;
    }
    onBusy?.call(_current.isNotEmpty);
    _publisher?.publish(_callsTopic, _state);
  }

  void showVideo(VideoView view, I420Frame frame) => _publisher?.publish(
    _videoTopic(view),
    () => [
      frame.width,
      frame.height,
      TransferableTypedData.fromList([frame.data]),
    ],
  );

  List<Object?> _state() => [
    for (final call in _current.values) call.toMessage(),
  ];

  void _receive(Object? message) {
    Calls? of(int profile) => _calls[Id<Profiles>(profile)];
    switch (message) {
      case ['call', int profile, String friend, bool video]:
        of(profile)?.call(PublicKey.fromJson(friend), video: video);
      case ['answer', int profile]:
        of(profile)?.answer();
      case ['hangUp', int profile]:
        of(profile)?.hangUp();
      case ['mute', int profile, bool muted]:
        of(profile)?.setMuted(muted: muted);
      case ['camera', int profile, bool on]:
        of(profile)?.setCamera(on: on);
      case ['flipCamera', int profile]:
        of(profile)?.flipCamera();
      case ['route', int profile, int route]:
        of(profile)?.setRoute(AudioRoute.values[route]);
      case ['shown', bool shown]:
        for (final calls in _calls.values) {
          calls.setShown(shown: shown);
        }
      default:
        _logger.w('Unknown call command: $message');
    }
  }
}

Stream<List<CallInfo>> watchCalls() => watchPublisher(
  _portName,
  _callsTopic,
  (message) => [
    for (final call in message! as List<Object?>)
      CallInfo.fromMessage(call! as List<Object?>),
  ],
).map((calls) => calls ?? const []);

Stream<I420Frame> watchVideo(VideoView view) => watchPublisher(
  _portName,
  _videoTopic(view),
  (message) => switch (message) {
    [int width, int height, TransferableTypedData data] => I420Frame(
      width,
      height,
      data.materialize().asUint8List(),
    ),
    _ => null,
  },
  leave: true,
).where((frame) => frame != null).cast<I420Frame>();

abstract final class CallCommands {
  static void call(
    Id<Profiles> profile,
    PublicKey friend, {
    required bool video,
  }) => _send(['call', profile.value, friend.toJson(), video]);

  static void answer(Id<Profiles> profile) => _send(['answer', profile.value]);

  static void hangUp(Id<Profiles> profile) => _send(['hangUp', profile.value]);

  static void mute(Id<Profiles> profile, {required bool muted}) =>
      _send(['mute', profile.value, muted]);

  static void camera(Id<Profiles> profile, {required bool on}) =>
      _send(['camera', profile.value, on]);

  static void flipCamera(Id<Profiles> profile) =>
      _send(['flipCamera', profile.value]);

  static void route(Id<Profiles> profile, AudioRoute route) =>
      _send(['route', profile.value, route.index]);

  /// So calls ringing show on the UI.
  static void shown({required bool shown}) =>
      IsolateNameServer.lookupPortByName(_portName)?.send(['shown', shown]);

  static void _send(List<Object?> command) {
    final host = IsolateNameServer.lookupPortByName(_portName);
    if (host == null) {
      _logger.w('No calls to ${command.first}');
    }
    host?.send(command);
  }
}
