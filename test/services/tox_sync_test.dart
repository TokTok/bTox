import 'dart:convert';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/messaging.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/services/message_notifier.dart';
import 'package:btox/services/tox_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/fake_toxcore.dart';

final _friendAddress = ToxAddress.fromString('${'2' * 72}0000');
final _me = PublicKey(Uint8List(32));

Future<void> _until(bool Function() condition) async {
  for (int i = 0; i < 50 && !condition(); i++) {
    await Future.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

Future<void> _settle() => Future.delayed(const Duration(milliseconds: 50));

void main() {
  late Database db;
  late FakeToxcore tox;
  late Id<Profiles> profileId;
  late ToxSync sync;
  late List<(Id<Contacts>, String, String, String?)> shown;
  late MessageNotifier notifier;

  setUp(() async {
    db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    tox = FakeToxcore();
    profileId = await db.addProfile(
      ProfilesCompanion.insert(
        signedIn: const Value(true),
        settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: _me,
        nospam: ToxAddressNospam(0),
      ),
    );
    shown = [];
    notifier = MessageNotifier(
      (id, title, body, account) async => shown.add((id, title, body, account)),
      (id) async {},
    );
    sync = ToxSync(
      db,
      tox,
      profileId,
      maxMessageLength: 10,
      notifier: notifier,
    );
    addTearDown(sync.dispose);
  });

  Future<Id<Contacts>> addContact({bool withRequest = false}) => db.addContact(
    ContactsCompanion.insert(
      profileId: profileId,
      publicKey: _friendAddress.publicKey,
      friendRequestAddress: Value(withRequest ? _friendAddress : null),
      friendRequestMessage: Value(withRequest ? 'Add me' : null),
    ),
  );

  Future<Id<Messages>> send(
    Id<Contacts> contactId,
    Content content, {
    PublicKey? author,
  }) => db.addMessage(
    newMessage(
      contactId: contactId,
      parent: null,
      merged: null,
      author: author ?? _me,
      timestamp: DateTime.utc(2026),
      content: content,
    ).copyWith(delivered: Value(author == null ? false : null)),
  );

  void setOnline(int friendNumber, bool online) => sync.handleEvent(
    ToxEventFriendConnectionStatus(
      friendNumber: friendNumber,
      connectionStatus: online
          ? Tox_Connection.TOX_CONNECTION_UDP
          : Tox_Connection.TOX_CONNECTION_NONE,
    ),
  );

  void receipt(int messageId) => sync.handleEvent(
    ToxEventFriendReadReceipt(friendNumber: 0, messageId: messageId),
  );

  Future<bool?> delivered(Id<Messages> id) async =>
      (await db.getMessage(id)).delivered;

  List<String> sentTexts() => [
    for (final (_, _, text) in tox.sentMessages) text,
  ];

  test('sets our name and status message', () async {
    sync.start();
    await _until(() => tox.name == 'Me');

    await db.updateProfileSettings(
      profileId,
      ProfileSettings(nickname: 'New', statusMessage: 'Busy'),
    );
    await _until(() => tox.name == 'New' && tox.statusMessage == 'Busy');
  });

  test('sends friend requests, preferring them for re-added friends', () async {
    await addContact();
    await addContact(withRequest: true);
    sync.start();
    await _until(() => tox.friends.isNotEmpty);
    expect(tox.friends, [_friendAddress.publicKey]);
    expect(tox.friendRequests, [(_friendAddress, 'Add me')]);

    setOnline(0, true);
    await _settle();
    final contacts = await db.select(db.contacts).get();
    expect(contacts.map((c) => c.friendRequestAddress), [null, null]);
  });

  test('deletes the friend with their last contact', () async {
    final first = await addContact();
    final second = await addContact();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);

    await db.deleteContact(first);
    await _settle();
    expect(tox.deletedFriends, isEmpty);

    await db.deleteContact(second);
    await _until(() => tox.deletedFriends.isNotEmpty);
    expect(tox.deletedFriends, [0]);
  });

  test("tracks the friend's online state", () async {
    final contactId = await addContact();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);
    Future<bool> online() async =>
        (await db.watchContact(contactId).first).online;

    setOnline(0, true);
    await _settle();
    expect(await online(), isTrue);

    setOnline(0, false);
    await _settle();
    expect(await online(), isFalse);
  });

  group('messages', () {
    late Id<Contacts> contactId;

    setUp(() async {
      contactId = await addContact();
      sync.start();
      await _until(() => tox.friends.isNotEmpty);
    });

    test('are sent once the friend is online, until delivered', () async {
      final id = await send(contactId, TextContent(text: 'hi'));
      await send(contactId, MediaContent(url: 'unsupported'));
      await send(
        contactId,
        TextContent(text: 'theirs'),
        author: _friendAddress.publicKey,
      );
      await _settle();
      expect(tox.sentMessages, isEmpty);

      setOnline(0, true);
      expect(sentTexts(), ['hi']);

      receipt(tox.sentMessages.single.$2);
      await _settle();
      expect(await delivered(id), isTrue);

      setOnline(0, false);
      setOnline(0, true);
      await _settle();
      expect(sentTexts(), ['hi']);
    });

    test('are sent again after the friend went offline', () async {
      setOnline(0, true);
      final id = await send(contactId, TextContent(text: 'hi'));
      await _until(() => tox.sentMessages.isNotEmpty);

      setOnline(0, false);
      setOnline(0, true);
      expect(sentTexts(), ['hi', 'hi']);

      receipt(tox.sentMessages.first.$2);
      await _settle();
      expect(await delivered(id), isFalse);
    });

    test('that fail are sent again on the next attempt', () async {
      tox.unreachableFriends.add(0);
      setOnline(0, true);
      await send(contactId, TextContent(text: 'hi'));
      await _settle();
      expect(tox.sentMessages, isEmpty);

      tox.unreachableFriends.clear();
      setOnline(0, true);
      expect(sentTexts(), ['hi']);
    });

    test('too long for Tox are delivered in parts', () async {
      setOnline(0, true);
      final id = await send(
        contactId,
        TextContent(text: 'hello brave new world'),
      );
      await _until(() => tox.sentMessages.isNotEmpty);
      expect(sentTexts(), ['hello ', 'brave new ', 'world']);

      for (final (_, messageId, _) in tox.sentMessages.take(2)) {
        receipt(messageId);
      }
      await _settle();
      expect(await delivered(id), isFalse);

      receipt(tox.sentMessages.last.$2);
      await _settle();
      expect(await delivered(id), isTrue);
    });
  });

  test('splitMessage never splits a character', () {
    final parts = splitMessage('ü' * 6 + '😀' * 3, 7);
    expect(parts, ['üüü', 'üüü', '😀', '😀', '😀']);
    expect(splitMessage('a bbbbbbbbbbb', 10), ['a bbbbbbbb', 'bbb']);
  });

  void receive(int friendNumber, String text) => sync.handleEvent(
    ToxEventFriendMessage(
      friendNumber: friendNumber,
      type: Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
      message: utf8.encode(text),
    ),
  );

  test('saves and notifies messages, except for the open chat', () async {
    final contactId = await addContact();
    sync.start();
    await _until(() => tox.friends.isNotEmpty && tox.name == 'Me');

    notifier.openChat = contactId;
    receive(0, 'seen');
    notifier.openChat = null;
    receive(0, 'Grüße ✓');
    final messages = await db
        .watchMessagesFor(contactId)
        .firstWhere((messages) => messages.length == 2);

    expect(
      [for (final m in messages) (m.content as TextContent).text],
      ['seen', 'Grüße ✓'],
    );
    expect(messages.first.author, _friendAddress.publicKey);
    expect(shown, [(contactId, 'Unknown', 'Grüße ✓', 'Me')]);
  });

  test('ignores messages from unknown friends', () async {
    final contactId = await addContact();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);

    receive(1, 'from a stranger');
    receive(0, 'from a friend');
    final messages = await db
        .watchMessagesFor(contactId)
        .firstWhere((messages) => messages.isNotEmpty);
    await _settle();

    expect(await db.select(db.messages).get(), hasLength(1));
    expect((messages.single.content as TextContent).text, 'from a friend');
  });

  test('saves friend names', () async {
    await addContact();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);

    sync.handleEvent(
      ToxEventFriendName(friendNumber: 0, name: utf8.encode('toxxi')),
    );
    final contacts = await db
        .select(db.contacts)
        .watch()
        .firstWhere((c) => c.single.name != null);
    expect(contacts.single.name, 'toxxi');
  });

  test('keeps the latest friend request', () async {
    sync.start();
    for (final message in ['add me', 'please add me']) {
      sync.handleEvent(
        ToxEventFriendRequest(
          publicKey: _friendAddress.publicKey,
          message: utf8.encode(message),
        ),
      );
    }
    final requests = await db
        .watchFriendRequestsFor(profileId)
        .firstWhere((r) => r.isNotEmpty && r.single.message != 'add me');

    expect(requests.single.publicKey, _friendAddress.publicKey);
    expect(await db.select(db.contacts).get(), isEmpty);
  });

  test('sends and receives locations as geo text', () async {
    final contactId = await addContact();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);
    setOnline(0, true);

    await send(
      contactId,
      const LocationContent(latitude: 52.37, longitude: 4.89),
    );
    await _until(() => tox.sentMessages.isNotEmpty);
    expect(sentTexts().join(), 'geo:52.37,4.89');

    receive(0, 'geo:-33.9,18.4');
    final messages = await db
        .watchMessagesFor(contactId)
        .firstWhere((messages) => messages.length == 2);
    expect(
      messages.last.content,
      const LocationContent(latitude: -33.9, longitude: 18.4),
    );
  });

  test('refuses avatars and cancels declined files', () async {
    final contactId = await addContact();
    sync.start();
    await _until(() => tox.friends.isNotEmpty);
    await db.updateAppSettings(
      const AppSettingsCompanion(autoAcceptFileSize: Value(0)),
    );
    await _settle();

    void offer(int fileNumber, Tox_File_Kind kind) => sync.handleEvent(
      ToxEventFileRecv(
        friendNumber: 0,
        fileNumber: fileNumber,
        kind: kind.value,
        fileSize: 10,
        filename: utf8.encode('a.txt'),
      ),
    );
    offer(0, Tox_File_Kind.TOX_FILE_KIND_AVATAR);
    offer(1, Tox_File_Kind.TOX_FILE_KIND_DATA);
    final offered = await db
        .watchMessagesFor(contactId)
        .firstWhere((messages) => messages.isNotEmpty);
    expect(offered.single.fileState, FileState.offered);
    expect(tox.fileControls, [
      (0, 0, Tox_File_Control.TOX_FILE_CONTROL_CANCEL),
    ]);

    await db.setFileState(offered.single.id, FileState.cancelled);
    await _until(() => tox.fileControls.length == 2);
    expect(tox.fileControls.last, (
      0,
      1,
      Tox_File_Control.TOX_FILE_CONTROL_CANCEL,
    ));
  });
}
