// ignore_for_file: recursive_getters
// No running of this code, it's only for Drift's code generator.
// coverage:ignore-file

import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:drift/drift.dart';

abstract class Contacts extends Table {
  IntColumn get id =>
      integer().autoIncrement().map(const IdConverter<Contacts>())();
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();

  TextColumn get name => text().nullable()();
  TextColumn get publicKey => text().map(const PublicKeyConverter())();

  // Resent whenever Tox starts, until the friend first comes online.
  TextColumn get friendRequestAddress =>
      text().map(const ToxAddressConverter()).nullable()();
  TextColumn get friendRequestMessage => text().nullable()();

  BoolColumn get online => boolean().withDefault(const Constant(false))();
}

abstract class FriendRequests extends Table {
  IntColumn get id =>
      integer().autoIncrement().map(const IdConverter<FriendRequests>())();
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();

  TextColumn get publicKey => text().map(const PublicKeyConverter())();
  TextColumn get message => text()();
  DateTimeColumn get timestamp => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {profileId, publicKey},
  ];
}

abstract class Messages extends Table {
  IntColumn get id =>
      integer().autoIncrement().map(const IdConverter<Messages>())();
  IntColumn get contactId =>
      integer().references(Contacts, #id).map(const IdConverter<Contacts>())();

  TextColumn get author => text().map(const PublicKeyConverter())();

  // The SHA-256 hash of the message content, timestamp, and parent/merge hashes.
  TextColumn get sha => text()
      .check(sha.length.equals(Sha256.kLength * 2))
      .map(const Sha256Converter())();
  IntColumn get parent => integer()
      .references(Messages, #id)
      .map(const IdConverter<Messages>())
      .nullable()();
  IntColumn get merged => integer()
      .references(Messages, #id)
      .map(const IdConverter<Messages>())
      .nullable()();

  DateTimeColumn get timestamp => dateTime()();
  TextColumn get content => text().map(const ContentConverter())();

  // Null for received messages and for ours from before schema version 2.
  BoolColumn get delivered => boolean().nullable()();
}

abstract class Profiles extends Table {
  IntColumn get id =>
      integer().autoIncrement().map(const IdConverter<Profiles>())();

  BoolColumn get active => boolean().withDefault(const Constant(false))();
  TextColumn get settings => text().map(const ProfileSettingsConverter())();

  TextColumn get secretKey => text()
      .check(secretKey.length.equals(SecretKey.kLength * 2))
      .map(const SecretKeyConverter())();
  TextColumn get publicKey => text()
      .check(publicKey.length.equals(PublicKey.kLength * 2))
      .map(const PublicKeyConverter())();
  IntColumn get nospam => integer()
      .check(nospam.isBetweenValues(0, 0xFFFFFFFF))
      .map(const NospamConverter())();
}
