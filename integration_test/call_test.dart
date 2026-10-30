import 'dart:async';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/api/toxcore/tox_options.dart';
import 'package:btox/calls/call_audio.dart';
import 'package:btox/calls/call_info.dart';
import 'package:btox/calls/call_protocol.dart';
import 'package:btox/calls/call_video.dart';
import 'package:btox/calls/calls.dart';
import 'package:btox/calls/plugin_call_media.dart';
import 'package:btox/calls/toxav_protocol.dart';
import 'package:btox/ffi/tox_library.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import '../test/mocks/fake_calls.dart';

final class _CountedAudio implements CallAudio {
  final _audio = PluginCallAudio();
  var played = 0;

  @override
  Future<void> start(
    void Function(Int16List frame) onFrame, {
    required bool speaker,
    required void Function(AudioRoute route, Set<AudioRoute> available)
    onRoutes,
    required void Function() onFailed,
  }) => _audio.start(
    onFrame,
    speaker: speaker,
    onRoutes: onRoutes,
    onFailed: onFailed,
  );

  @override
  void play(Int16List pcm, {required int channels, required int sampleRate}) {
    played++;
    _audio.play(pcm, channels: channels, sampleRate: sampleRate);
  }

  @override
  Future<void> setRoute(AudioRoute route) => _audio.setRoute(route);

  @override
  Future<void> setRingBack({required bool on}) => _audio.setRingBack(on: on);

  @override
  Future<void> setRinging({required bool on}) => _audio.setRinging(on: on);

  @override
  Future<void> stop() => _audio.stop();
}

final class _Peer {
  final Toxcore tox;
  int? online;
  late final Timer _loop;

  _Peer(ToxLibrary lib)
    : tox = Toxcore(lib, const ToxOptions(localDiscoveryEnabled: false)) {
    _loop = Timer.periodic(const Duration(milliseconds: 20), (_) {
      for (final event in tox.iterate()) {
        if (event case ToxEventFriendConnectionStatus(
          :final friendNumber,
          :final connectionStatus,
        )) {
          online = connectionStatus == Tox_Connection.TOX_CONNECTION_NONE
              ? null
              : friendNumber;
        }
      }
    });
  }

  PublicKey get pk => tox.selfGetPublicKey();

  void befriend(_Peer other) {
    tox.bootstrap(
      '127.0.0.1',
      other.tox.selfGetUdpPort(),
      other.tox.selfGetDhtId(),
    );
    tox.friendAddNorequest(other.pk);
  }

  Calls calls(
    _Peer friend,
    CallAudio audio,
    CallVideo video, {
    required void Function(CallInfo? call) changed,
    void Function(VideoView view, I420Frame frame)? showVideo,
  }) => Calls(
    const Id(1),
    pk,
    ToxavProtocol(
      tox.startAv(),
      (key) => key == friend.pk ? online : null,
      (number) => number == online ? friend.pk : null,
    ),
    audio,
    video: video,
    chatOf: (key) => GraphId.friend(pk, key),
    nameOf: (_) => null,
    selfName: () => '',
    record: (_, _) async => null,
    changed: changed,
    showVideo: showVideo,
  );

  void kill() {
    _loop.cancel();
    tox.kill();
  }
}

Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $what');
    }
    await Future.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Alice has the platform's audio and camera, Bob a tone and made-up
  // frames: only one call at a time has the sound card.
  testWidgets('a video call between two Toxes uses the platform audio', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final lib = await container.read(toxFfiProvider.future);
      final alice = _Peer(lib);
      final bob = _Peer(lib);
      addTearDown(alice.kill);
      addTearDown(bob.kill);
      alice.befriend(bob);
      bob.befriend(alice);
      await _until(
        () => alice.online != null && bob.online != null,
        'the friends to connect',
      );

      final aliceAudio = _CountedAudio();
      CallInfo? aliceCall;
      var aliceFrames = 0;
      final aliceCalls = alice.calls(
        bob,
        aliceAudio,
        PluginCallVideo(),
        changed: (call) => aliceCall = call,
        showVideo: (view, _) {
          if (view == VideoView.remote) {
            aliceFrames++;
          }
        },
      );
      addTearDown(aliceCalls.dispose);
      final bobAudio = FakeCallAudio();
      final bobVideo = FakeCallVideo();
      CallInfo? bobCall;
      final bobCalls = bob.calls(
        alice,
        bobAudio,
        bobVideo,
        changed: (call) => bobCall = call,
      );
      addTearDown(bobCalls.dispose);
      final tone = Int16List.fromList([
        for (var i = 0; i < callFrameSamples; i++) (i % 48 < 24) ? 8000 : -8000,
      ]);
      final picture = I420Frame(320, 240, Uint8List(I420Frame.size(320, 240)));
      final sending = Timer.periodic(const Duration(milliseconds: 20), (_) {
        bobAudio.onFrame?.call(tone);
        bobVideo.onFrame?.call(picture);
      });
      addTearDown(sending.cancel);

      bobCalls.call(alice.pk, video: true);
      await _until(
        () => aliceCall?.phase == CallPhase.ringing,
        'the call to ring',
      );
      aliceCalls.answer();
      await _until(
        () => bobCall?.phase == CallPhase.active,
        'the call to connect',
      );
      await _until(
        () =>
            aliceAudio.played > 50 &&
            bobAudio.played.length > 50 &&
            aliceFrames > 10,
        'audio both ways and video',
      );
      expect(aliceCall?.phase, CallPhase.active);

      bobCalls.hangUp();
      await _until(() => aliceCall == null, 'the call to end');
    });
  });
}
