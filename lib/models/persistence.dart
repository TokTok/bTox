// ignore_for_file: recursive_getters

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
