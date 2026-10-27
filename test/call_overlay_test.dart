import 'dart:typed_data';

import 'package:btox/calls/call_channel.dart';
import 'package:btox/calls/call_protocol.dart';
import 'package:btox/calls/calls.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/pages/call_page.dart';
import 'package:btox/widgets/call_overlay.dart';
import 'package:btox/widgets/call_video_view.dart';
import 'package:btox_call_media/btox_call_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'mocks/fake_call_media.dart';
import 'mocks/fake_calls.dart';
import 'mocks/settle.dart';

final _me = PublicKey(Uint8List(32));
final _bob = PublicKey(Uint8List(32)..fillRange(0, 32, 2));
final _profile = Id<Profiles>(1);

void main() {
  late FakeCallProtocol protocol;
  late FakeCallAudio audio;
  late FakeCallVideo video;
  late Calls calls;

  Future<void> show(WidgetTester tester) async {
    protocol = FakeCallProtocol();
    audio = FakeCallAudio();
    video = FakeCallVideo();
    calls = (await tester.runAsync(
      () async => Calls(
        _profile,
        _me,
        protocol,
        audio,
        video: video,
        chatOf: (friend) => GraphId.friend(_me, friend),
        nameOf: (friend) => 'Bob',
        selfName: () => 'Me',
        record: (chat, content) async => null,
        changed: (call) => CallHost.instance.changed(_profile, call),
        showVideo: CallHost.instance.showVideo,
      ),
    ))!;
    CallHost.instance.add(_profile, calls);
    addTearDown(() {
      CallHost.instance.remove(_profile);
      calls.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => CallOverlay(child: child!),
          home: const Scaffold(body: Text('Chats')),
        ),
      ),
    );
  }

  Future<void> answered(WidgetTester tester, {bool video = false}) async {
    calls.call(_bob, video: video);
    protocol.signals.addAll([
      CallSignal.answered(_bob),
      if (video) CallSignal.friendVideo(_bob, on: true),
    ]);
    await settle(
      tester,
      until: () => find.byTooltip('Hang up').evaluate().isNotEmpty,
    );
  }

  testWidgets('a call ringing here shows over the chats, and declining ends '
      'it', (tester) async {
    await show(tester);
    protocol.signals.add(CallSignal.ringing(_bob, video: false));
    await settle(
      tester,
      until: () => find.text('Incoming voice call').evaluate().isNotEmpty,
    );
    expect(find.text('Bob'), findsOneWidget);

    await tester.tap(find.byTooltip('Decline'));
    await settle(
      tester,
      until: () => find.byType(CallScreen).evaluate().isEmpty,
    );
    expect(protocol.asked, ['hang up']);
    expect(find.text('Chats'), findsOneWidget);
  });

  testWidgets('a call going on can be muted, put on the speaker, hidden, and '
      'hung up', (tester) async {
    await show(tester);
    await answered(tester);

    await tester.tap(find.byTooltip('Mute'));
    await settle(tester, until: () => calls.current?.muted ?? false);
    await tester.tap(find.byTooltip('Speaker'));
    await settle(
      tester,
      until: () => calls.current?.route == AudioRoute.speaker,
    );

    await tester.tap(find.byTooltip('Hide the call'));
    await tester.pump();
    expect(find.byType(CallScreen), findsNothing);
    await tester.tap(find.text('Return to the call'));
    await tester.pump();

    await tester.tap(find.byTooltip('Hang up'));
    await settle(
      tester,
      until: () => find.byType(CallScreen).evaluate().isEmpty,
    );
    expect(protocol.asked, ['call', 'hang up']);
    expect(find.text('Return to the call'), findsNothing);
  });

  testWidgets('with headphones in, the audio goes where it is picked', (
    tester,
  ) async {
    await show(tester);
    await answered(tester);
    audio.onRoutes!(AudioRoute.wired, {
      AudioRoute.earpiece,
      AudioRoute.speaker,
      AudioRoute.wired,
    });
    await settle(
      tester,
      until: () => find.byTooltip('Headphones').evaluate().isNotEmpty,
    );

    await tester.tap(find.byTooltip('Headphones'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Speaker'));
    await settle(
      tester,
      until: () => calls.current?.route == AudioRoute.speaker,
    );
  });

  testWidgets("a video call shows the friend's video and ours, whose camera "
      'can be switched and turned off', (tester) async {
    await show(tester);
    await answered(tester, video: true);
    expect(find.byType(CallVideoView), findsNWidgets(2));

    await tester.tap(find.byTooltip('Switch camera'));
    await settle(tester, until: () => video.front == false);
    await tester.tap(find.byTooltip('Camera'));
    await settle(
      tester,
      until: () => find.byType(CallVideoView).evaluate().length == 1,
    );
    expect(protocol.asked, ['video call', 'no video']);
  });

  testWidgets('a call is answered once the microphone may be used, and goes on '
      'without a camera that may not be', (tester) async {
    final media = FakeCallMedia()
      ..microphoneAllowed = false
      ..cameraAllowed = false;
    final platform = BtoxCallMedia.instance;
    BtoxCallMedia.instance = media;
    addTearDown(() => BtoxCallMedia.instance = platform);
    await show(tester);
    protocol.signals.add(CallSignal.ringing(_bob, video: true));
    await settle(
      tester,
      until: () => find.text('Incoming video call').evaluate().isNotEmpty,
    );

    await tester.tap(find.byTooltip('Answer'));
    await settle(
      tester,
      until: () => find.text('Calls need the microphone').evaluate().isNotEmpty,
    );
    expect(protocol.asked, isEmpty);

    media.microphoneAllowed = true;
    await tester.tap(find.byTooltip('Answer'));
    await settle(
      tester,
      until: () => find.byTooltip('Hang up').evaluate().isNotEmpty,
    );
    await settle(
      tester,
      until: () => find
          .text('bTox may not use the camera, so the call goes on without it')
          .evaluate()
          .isNotEmpty,
    );

    await tester.tap(find.byTooltip('Camera'));
    await settle(tester, until: () => calls.current?.camera == false);
    await tester.tap(find.byTooltip('Camera'));
    await settle(tester);
    expect(calls.current?.camera, isFalse);
    expect(media.asked, [
      'microphone permission',
      'microphone permission',
      'camera permission',
      'camera permission',
    ]);
  });
}
