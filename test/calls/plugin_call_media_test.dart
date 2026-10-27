import 'dart:typed_data';

import 'package:btox/calls/android_calls.dart';
import 'package:btox/calls/call_info.dart';
import 'package:btox/calls/plugin_call_media.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox_call_media/btox_call_media.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_call_media.dart';

final class _Plugin implements FlutterLocalNotificationsPlugin {
  final shown = <(int, String?, String?, AndroidNotificationDetails?)>[];
  final cancelled = <(int, String?)>[];

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async => shown.add((id, title, body, notificationDetails?.android));

  @override
  Future<void> cancel({required int id, String? tag}) async =>
      cancelled.add((id, tag));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle() => Future.delayed(Duration.zero);

void main() {
  late FakeCallMedia media;

  setUp(() {
    final platform = BtoxCallMedia.instance;
    media = FakeCallMedia();
    BtoxCallMedia.instance = media;
    addTearDown(() => BtoxCallMedia.instance = platform);
  });

  test("the call's audio goes to and from the plugin", () async {
    final frames = <Int16List>[];
    final routes = <(AudioRoute, Set<AudioRoute>)>[];
    var failed = false;
    final audio = PluginCallAudio();
    await audio.start(
      frames.add,
      speaker: true,
      onRoutes: (route, available) => routes.add((route, available)),
      onFailed: () => failed = true,
    );
    media.microphoneFrames.add(Uint8List.fromList([1, 0, 2, 0]));
    media.routeChanges.add((AudioRoute.wired, {AudioRoute.wired}));
    media.microphoneFrames.addError(Exception('Gone'));
    await _settle();
    expect(frames, [
      [1, 2],
    ]);
    expect(routes.single.$1, AudioRoute.wired);
    expect(routes.single.$2, {AudioRoute.wired});
    expect(failed, isTrue);

    audio.play(Int16List.fromList([2, 4]), channels: 2, sampleRate: 48000);
    expect(media.played, [
      [3, 0],
    ]);
    await audio.setRoute(AudioRoute.speaker);
    await audio.setRingBack(on: true);
    await audio.setRinging(on: false);
    await audio.stop();
    expect(media.asked, [
      'start on speaker',
      'speaker',
      'ring back',
      'no ring',
      'stop',
    ]);
  });

  test("the camera's frames come from the plugin until it stops", () async {
    final frames = <I420Frame>[];
    var stopped = false;
    final video = PluginCallVideo();
    await video.startCamera(
      front: false,
      onFrame: frames.add,
      onStopped: () => stopped = true,
    );
    final frame = I420Frame(2, 2, Uint8List(6));
    media.camera
      ..add(frame)
      ..addError(Exception('Taken'));
    await _settle();
    expect(frames, [frame]);
    expect(stopped, isTrue);
    await video.stopCamera();
    expect(media.asked, ['back camera', 'no camera']);
  });

  test('on Android, a call rings full screen until it stops, and a missed one '
      'stays', () {
    final plugin = _Plugin();
    final notifier = AndroidCallNotifier(plugin);
    final friend = PublicKey(Uint8List(32)..fillRange(0, 32, 2));
    final call = CallInfo(
      chat: ChatRef(Id(1), GraphId.friend(PublicKey(Uint8List(32)), friend)),
      friend: friend,
      name: 'Bob',
      phase: CallPhase.ringing,
    );

    notifier
      ..ring(call)
      ..stopRinging(Id(1))
      ..missed(call.copyWith(video: true));
    final [(id, title, body, ringing), (_, _, missed, _)] = plugin.shown;
    expect((id, title, body), (1, 'Bob', 'Incoming voice call'));
    expect(ringing!.fullScreenIntent, isTrue);
    expect(
      [for (final action in ringing.actions!) action.id],
      [declineAction, answerAction],
    );
    expect(missed, 'Missed video call');
    expect(plugin.cancelled, [(1, 'call')]);
  });
}
