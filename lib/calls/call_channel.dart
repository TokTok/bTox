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

/// This isolate's calls, for the UI, which may run in another isolate.
final class CallHost {
  static final instance = CallHost._();

  final _calls = <Id<Profiles>, Calls>{};
  final _current = <Id<Profiles>, CallInfo>{};
  final _subscribers = <SendPort>{};
  final _videoWatchers = <SendPort, VideoView>{};
  // The ports of each isolate showing the UI, by its control port: an
  // isolate's exit is told once, so all of them go then.
  final _isolates = <SendPort, Set<SendPort>>{};
  ReceivePort? _port;

  void Function(bool busy)? onBusy;

  CallHost._();

  /// One microphone and speaker serve every profile.
  bool busyElsewhere(Id<Profiles> profile) =>
      _current.keys.any((other) => other != profile);

  void add(Id<Profiles> profile, Calls calls) {
    _calls[profile] = calls;
    _open();
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
    for (final subscriber in _subscribers) {
      subscriber.send(['calls', _state()]);
    }
  }

  void showVideo(VideoView view, I420Frame frame) {
    for (final MapEntry(key: watcher, value: watched)
        in _videoWatchers.entries) {
      if (watched == view) {
        watcher.send([
          'frame',
          [
            frame.width,
            frame.height,
            TransferableTypedData.fromList([frame.data]),
          ],
        ]);
      }
    }
  }

  List<Object?> _state() => [
    for (final call in _current.values) call.toMessage(),
  ];

  void _open() {
    if (_port != null) {
      return;
    }
    final port = _port = ReceivePort('calls');
    port.listen((message) {
      try {
        _receive(message);
      } on Exception catch (e) {
        _logger.w('Failed to do $message: $e');
      }
    });
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(port.sendPort, _portName);
  }

  void _watchExit(SendPort control, SendPort port) {
    if (_isolates[control] case final ports?) {
      ports.add(port);
    } else {
      _isolates[control] = {port};
      Isolate(control)
          .addOnExitListener(_port!.sendPort, response: ['exited', control]);
    }
  }

  void _receive(Object? message) {
    Calls? of(int profile) => _calls[Id<Profiles>(profile)];
    switch (message) {
      case [SendPort subscriber, SendPort control]:
        _subscribers.add(subscriber);
        _watchExit(control, subscriber);
        subscriber.send(['hello', Isolate.current.controlPort, _state()]);
      case ['watchVideo', int view, SendPort watcher, SendPort control]:
        _videoWatchers[watcher] = VideoView.values[view];
        _watchExit(control, watcher);
        watcher.send(['hello', Isolate.current.controlPort, null]);
      case ['unwatchVideo', SendPort watcher]:
        _videoWatchers.remove(watcher);
      case ['exited', SendPort control]:
        var subscribed = false;
        for (final port in _isolates.remove(control) ?? const <SendPort>{}) {
          subscribed |= _subscribers.remove(port);
          _videoWatchers.remove(port);
        }
        if (subscribed) {
          for (final calls in _calls.values) {
            calls.setShown(shown: false);
          }
        }
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
    }
  }
}

Stream<List<CallInfo>> watchCalls() => watchPublisher(
  _portName,
  request: (port) => [port, Isolate.current.controlPort],
  update: 'calls',
  parse: (message) => [
    for (final call in message! as List<Object?>)
      CallInfo.fromMessage(call! as List<Object?>),
  ],
).map((calls) => calls ?? const []);

Stream<I420Frame> watchVideo(VideoView view) => watchPublisher(
  _portName,
  request: (port) => [
    'watchVideo',
    view.index,
    port,
    Isolate.current.controlPort,
  ],
  update: 'frame',
  parse: (message) => switch (message) {
    [int width, int height, TransferableTypedData data] => I420Frame(
      width,
      height,
      data.materialize().asUint8List(),
    ),
    _ => null,
  },
  cancel: (port) => ['unwatchVideo', port],
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
