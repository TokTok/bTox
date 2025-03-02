import 'package:btox/db/database.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/messaging.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mySecretKey = SecretKey.fromJson(
      String.fromCharCodes(Iterable.generate(64, (_) => 'F'.codeUnits.first)));
  final myToxId = ToxAddress.fromString(
      String.fromCharCodes(Iterable.generate(76, (_) => '0'.codeUnits.first)));
  final friendPk = PublicKey.fromJson(
      '0000000000000000000000000000000000000000000000000000000000000000');

  testDatabase('Messages can be added to the database', (Database db) async {
    final profileId = await db.addProfile(
      ProfilesCompanion.insert(
        active: Value(true),
        settings: ProfileSettings(
          nickname: 'Yeetman',
          statusMessage: 'Yeeting everyone',
        ),
        secretKey: mySecretKey,
        publicKey: myToxId.publicKey,
        nospam: myToxId.nospam,
      ),
    );

    expect(profileId.value, 1);

    final contactId = await db.addContact(
      ContactsCompanion.insert(
        profileId: profileId,
        name: Value('Neatman'),
        publicKey: friendPk,
      ),
    );

    expect(contactId.value, 1);

    // Happy new year in 2025.
    final firstMsg = await db.getMessage(await db.addMessage(newMessage(
      contactId: contactId,
      parent: null,
      merged: null,
      author: myToxId.publicKey,
      timestamp: DateTime(2025, 1, 1, 0, 2, 10, 123),
      content: TextContent(text: 'Happy new year!'),
    )));

    expect(firstMsg.sha.toJson(),
        'B7D2BD769A3A5E8D8445B75A76370A384FA87514AA5979F27365CE26D3CE6CD8');

    // Happy new year in 2026.
    final secondMsg = await db.getMessage(await db.addMessage(newMessage(
      contactId: contactId,
      parent: firstMsg,
      merged: null,
      author: myToxId.publicKey,
      timestamp: DateTime(2026, 1, 1, 0, 2, 10, 123),
      content: TextContent(text: 'Happy new year!'),
    )));

    expect(secondMsg.sha.toJson(),
        '4E0F0A708C4E82000A89F5549E7F68E149F7DBC392AAC7B87B89CDECC5AB5642');
  }, tags: ['models']);

  testDatabase('Two separate histories can be merged', (db) async {
    final profileId = await db.addProfile(
      ProfilesCompanion.insert(
        active: Value(true),
        settings: ProfileSettings(
          nickname: 'Yeetman',
          statusMessage: 'Yeeting everyone',
        ),
        secretKey: mySecretKey,
        publicKey: myToxId.publicKey,
        nospam: myToxId.nospam,
      ),
    );

    expect(profileId.value, 1);

    final contactId = await db.addContact(
      ContactsCompanion.insert(
        profileId: profileId,
        name: Value('Neatman'),
        publicKey: friendPk,
      ),
    );

    expect(contactId.value, 1);

    // Happy new year in 2025.
    final myFirstMsg = await db.getMessage(await db.addMessage(newMessage(
      contactId: contactId,
      parent: null,
      merged: null,
      author: myToxId.publicKey,
      // 2 minutes after midnight.
      timestamp: DateTime(2025, 1, 1, 0, 2, 10, 123),
      content: TextContent(text: 'Happy new year!'),
    )));

    // Friend's happy new year in 2025.
    final friendFirstMsg = await db.getMessage(await db.addMessage(newMessage(
      contactId: contactId,
      parent: null,
      merged: null,
      author: friendPk,
      // 1 minute before my message.
      timestamp: myFirstMsg.timestamp.subtract(const Duration(minutes: 1)),
      content: TextContent(text: 'Happy new year!'),
    )));

    final mergedMessage = await db.getMessage(await db.addMessage(newMessage(
      contactId: contactId,
      parent: myFirstMsg,
      merged: friendFirstMsg,
      author: myToxId.publicKey,
      // 1 minute after my message.
      timestamp: myFirstMsg.timestamp.add(const Duration(minutes: 1)),
      content: TextContent(text: 'Haha, jinx!'),
    )));

    expect(mergedMessage.sha.toJson(),
        'BF17F7ABA56A3FDC7B0DED4A4308248364B0E0E7981C68DAFAF7B2CF867C7E2E');
  }, tags: ['models']);

  test('Microseconds are ignored in hash calculation', () async {
    final msg1 = newMessage(
      contactId: Id(1),
      parent: null,
      merged: null,
      author: myToxId.publicKey,
      timestamp: DateTime(2025, 1, 1, 0, 2, 10, 123, 456),
      content: TextContent(text: 'Happy new year!'),
    );

    final msg2 = newMessage(
      contactId: Id(1),
      parent: null,
      merged: null,
      author: myToxId.publicKey,
      timestamp: msg1.timestamp.value.add(const Duration(microseconds: 100)),
      content: TextContent(text: 'Happy new year!'),
    );

    expect(msg1.sha, msg2.sha);
  }, tags: ['models']);

  test('Milliseconds are not ignored in hash calculation', () async {
    final msg1 = newMessage(
      contactId: Id(1),
      parent: null,
      merged: null,
      author: myToxId.publicKey,
      timestamp: DateTime(2025, 1, 1, 0, 2, 10, 123),
      content: TextContent(text: 'Happy new year!'),
    );

    final msg2 = newMessage(
      contactId: Id(1),
      parent: null,
      merged: null,
      author: myToxId.publicKey,
      timestamp: msg1.timestamp.value.add(const Duration(microseconds: 1000)),
      content: TextContent(text: 'Happy new year!'),
    );

    expect(msg1.sha, isNot(msg2.sha));
  }, tags: ['models']);
}

void testDatabase(
  String description,
  Future<void> Function(Database) body, {
  List<String> tags = const [],
}) {
  test(description, () async {
    final db = Database(NativeDatabase.memory());

    try {
      await body(db);
    } finally {
      await db.close();
    }
  }, tags: tags);
}
