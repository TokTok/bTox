import 'dart:typed_data';

import 'package:btox/db/database.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/home.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

final _me = PublicKey(Uint8List(32));

void main() {
  late Database db;
  late Id<Profiles> profileId;
  late Home home;

  setUp(() async {
    db = Database(NativeDatabase.memory());
    addTearDown(db.close);
    profileId = await db.addProfile(
      ProfilesCompanion.insert(
        settings: ProfileSettings(nickname: 'Me', statusMessage: ''),
        secretKey: SecretKey(Uint8List(32)),
        publicKey: _me,
        nospam: ToxAddressNospam(0),
      ),
    );
    home = await Home.load(db, await db.watchProfile(profileId).first);
  });

  test('an event counts once it is saved', () async {
    final failed = await home.record(
      home.account,
      const FactContent(
        subject: Subject.account(),
        value: FactValue.name('Lost'),
      ),
      save: (_) async => throw Exception('disk full'),
    );
    expect(failed, isNull);
    expect(home.store.eventsIn(home.account), isEmpty);
    expect(home.state.name, isNull);

    final (_, saved, _) = (await home.record(
      home.account,
      const FactContent(
        subject: Subject.account(),
        value: FactValue.name('Me'),
      ),
    ))!;
    expect(saved.parents, isEmpty);
    expect(await db.getSyncEvents(profileId), hasLength(1));
  });

  test('a row whose event was not saved is written again', () async {
    final transfer = Transfer(
      id: Id(1),
      profileId: profileId,
      graph: GraphId.friend(_me, PublicKey(Uint8List(32)..fillRange(0, 32, 2))),
      incoming: false,
      name: 'cat.png',
      size: 3,
      path: '/files/cat.png',
      state: FileState.active,
      transferred: 0,
    );
    // Its row isn't there yet, so its event can't be saved with it.
    await home.startFiles([transfer], 'Me');
    expect(home.store.graphs, isEmpty);

    await db.into(db.transfers).insert(transfer);
    await home.startFiles([transfer], 'Me');
    expect((await db.watchTransfers(profileId).first).single.event, isNotNull);
  });
}
