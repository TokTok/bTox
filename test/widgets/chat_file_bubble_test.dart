import 'dart:io';
import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/attachments.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/widgets/chat_file_bubble.dart';
import 'package:btox/widgets/chat_item.dart';
import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:btox/widgets/picture_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../mocks/test_app.dart';

final _event = EventId(Uint8List(32));
final _chat = ChatRef(
  Id(1),
  GraphId.friend(PublicKey(Uint8List(32)), PublicKey(Uint8List(32)..[0] = 1)),
);

void main() {
  testWidgets('an offered file can be accepted', (tester) async {
    final db = Database(NativeDatabase.memory());
    // Drift doesn't progress in the test's fake async zone.
    final id = (await tester.runAsync(() async {
      final profile = await db.addProfile(
        ProfilesCompanion.insert(
          settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      );
      return db.addTransfer(
        TransfersCompanion.insert(
          profileId: profile,
          graph: GraphId.account(PublicKey(Uint8List(32))),
          incoming: true,
          name: 'notes.txt',
          size: 2048,
          path: '',
          state: FileState.offered,
        ),
      );
    }))!;

    Future<void> show() async {
      final transfer = await tester.runAsync(
        () => (db.select(
          db.transfers,
        )..where((t) => t.id.equals(id.value))).getSingle(),
      );
      await tester.pumpWidget(
        testApp(
          ChatFileBubble(
            corners: bubbleCorners(mine: false),
            chat: _chat,
            entry: ChatEntry(
              event: _event,
              mine: false,
              content: FileContent(name: transfer!.name, size: transfer.size),
              timestamp: DateTime(2026),
              file: FileProgress(
                state: transfer.state,
                transferred: transfer.transferred,
                transfer: transfer.id,
              ),
            ),
            color: Colors.white,
            textStyle: const TextStyle(),
          ),
          overrides: [databaseProvider.overrideWith((ref) => db)],
        ),
      );
      await tester.pumpAndSettle();
    }

    await show();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.runAsync(pumpEventQueue);
    await show();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Accept'), findsNothing);

    await tester.runAsync(() => db.setTransferState(id, FileState.cancelled));
    await show();
    expect(find.text('Cancelled'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('a photo is decoded no bigger than it is shown', (tester) async {
    final photo = File('assets/images/btox-icon.png').absolute.path;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: ChatFileBubble(
            corners: bubbleCorners(mine: false),
            chat: _chat,
            entry: ChatEntry(
              event: _event,
              mine: false,
              content: FileContent(name: 'cat.png', size: 5000000, path: photo),
              timestamp: DateTime(2026),
              file: const FileProgress(state: FileState.done),
            ),
            color: Colors.white,
            textStyle: const TextStyle(),
          ),
        ),
      ),
    );
    // Its header is read outside the test's fake time.
    for (var i = 0; i < 50 && find.byType(Image).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final image = tester.widget<Image>(find.byType(Image)).image;
    final shown = 240 * tester.view.devicePixelRatio;
    expect(
      (image as ResizeImage).width,
      shown.round(),
      reason: 'at most ${shown}px, as shown',
    );
  });

  testWidgets('a photo of ours shows as it goes, and opens full screen', (
    tester,
  ) async {
    final photo = File('assets/images/btox-icon.png').absolute.path;
    Future<void> show(FileState state) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: ChatItem(
                chat: _chat,
                entry: ChatEntry(
                  event: _event,
                  mine: true,
                  content: FileContent(
                    name: 'cat.png',
                    size: 5000000,
                    path: photo,
                  ),
                  timestamp: DateTime(2026),
                  file: FileProgress(state: state, transferred: 1000000),
                ),
              ),
            ),
          ),
        ),
      );
      // Decoding happens outside the test's fake time.
      for (
        var i = 0;
        i < 50 &&
            (find.byType(Image).evaluate().isEmpty ||
                tester.getSize(find.byType(Image)).isEmpty);
        i++
      ) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await show(FileState.active);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('cat.png'), findsNothing);
    expect(find.text('4.8 MB'), findsNothing);
    expect(find.byIcon(Icons.schedule), findsOneWidget);

    await show(FileState.done);
    expect(find.byIcon(Icons.done_all), findsOneWidget);

    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(PictureView), findsOneWidget);
  });

  testWidgets('a file offered to the home device is answered for it', (
    tester,
  ) async {
    final db = Database(NativeDatabase.memory());
    final profile = (await tester.runAsync(
      () => db.addProfile(
        ProfilesCompanion.insert(
          settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      ),
    ))!;
    final chat = ChatRef(profile, _chat.graph);
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: ChatFileBubble(
            corners: bubbleCorners(mine: false),
            chat: chat,
            entry: ChatEntry(
              event: _event,
              mine: false,
              content: const FileContent(name: 'cat.png', size: 5000000),
              timestamp: DateTime(2026),
              file: const FileProgress(state: FileState.offered),
            ),
            color: Colors.white,
            textStyle: const TextStyle(),
          ),
        ),
        overrides: [databaseProvider.overrideWith((ref) => db)],
      ),
    );

    await tester.tap(find.text('Accept'));
    await tester.runAsync(pumpEventQueue);
    final answer = (await tester.runAsync(
      () => db.watchIntents(profile).first,
    ))!.single;
    expect(
      (answer.graph, answer.content),
      (chat.graph, FileAnswered(file: _event, accepted: true)),
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('a file at the home device is downloaded here', (tester) async {
    final db = Database(NativeDatabase.memory());
    final profile = (await tester.runAsync(
      () => db.addProfile(
        ProfilesCompanion.insert(
          settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
          secretKey: SecretKey(Uint8List(32)),
          publicKey: PublicKey(Uint8List(32)),
          nospam: ToxAddressNospam(0),
        ),
      ),
    ))!;
    final chat = ChatRef(profile, _chat.graph);
    final blob = BlobId(Uint8List(32)..[0] = 7);
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: ChatFileBubble(
            corners: bubbleCorners(mine: false),
            chat: chat,
            entry: ChatEntry(
              event: _event,
              mine: false,
              content: const FileContent(name: 'cat.png', size: 5000000),
              timestamp: DateTime(2026),
              file: FileProgress(state: FileState.done, blob: blob),
            ),
            color: Colors.white,
            textStyle: const TextStyle(),
          ),
        ),
        overrides: [
          databaseProvider.overrideWith((ref) => db),
          attachmentsDirectoryProvider.overrideWith((ref) => '/files'),
        ],
      ),
    );

    await tester.tap(find.text('Download'));
    await tester.runAsync(pumpEventQueue);
    final fetch = (await tester.runAsync(
      () => db.watchTransfers(profile).first,
    ))!.single;
    expect(
      (fetch.event, fetch.blobId, fetch.incoming, fetch.state),
      (_event, blob, true, FileState.active),
    );
    expect(fetch.path, startsWith('/files/'));

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
