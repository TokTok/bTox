// ignore_for_file: recursive_getters
// No running of this code, it's only for Drift's code generator.
// coverage:ignore-file

import 'package:btox/models/app_defaults.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/sync/setting.dart';
import 'package:drift/drift.dart';

/// A file transfer's progress. Incoming files start as offered until accepted,
/// and are paused when they stop before all of it came, until sent again.
enum FileState { offered, active, done, cancelled, paused }

abstract class AppSettings extends Table {
  IntColumn get id => integer()();
  BoolColumn get stayOnline => boolean().withDefault(const Constant(true))();
  // Larger incoming files wait until accepted.
  IntColumn get autoAcceptFileSize =>
      integer().withDefault(const Constant(defaultAutoAcceptFileSize))();
  // The profile the UI shows.
  IntColumn get currentProfile =>
      integer().map(const IdConverter<Profiles>()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

abstract class CachedBootstrapNodes extends Table {
  IntColumn get id => integer()();
  TextColumn get json => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Friends to add or remove, until the account has the change.
abstract class FriendChanges extends Table {
  IntColumn get id =>
      integer().autoIncrement().map(const IdConverter<FriendChanges>())();
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  TextColumn get publicKey =>
      text().map(const HexConverter(PublicKey.fromJson))();
  BoolColumn get wanted => boolean()();
  // With these, a friend request to send.
  IntColumn get nospam => integer().map(const NospamConverter()).nullable()();
  TextColumn get message => text().nullable()();
  // With a friend no longer wanted: their chat goes too.
  BoolColumn get deleteChat => boolean().withDefault(const Constant(false))();
}

/// Chats deleted on this device, by the rank their next event takes, so it
/// comes after the read markers that pointed into them.
abstract class DeletedChats extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  TextColumn get graph => text().map(const HexConverter(GraphId.fromJson))();
  IntColumn get rank => integer()();

  @override
  Set<Column> get primaryKey => {profileId, graph};
}

/// Files moving between this device's Tox and its attachments directory, by
/// the event that started them. One without an event is still to be sent.
abstract class Transfers extends Table {
  IntColumn get id =>
      integer().autoIncrement().map(const IdConverter<Transfers>())();
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  TextColumn get graph => text().map(const HexConverter(GraphId.fromJson))();
  TextColumn get event =>
      text().map(const HexConverter(EventId.fromJson)).nullable()();
  BoolColumn get incoming => boolean()();
  TextColumn get name => text()();
  IntColumn get size => integer()();
  TextColumn get path => text()();
  TextColumn get state => textEnum<FileState>()();
  IntColumn get transferred => integer().withDefault(const Constant(0))();
  // A linked account's file: its blob, which moves between here and the
  // home device.
  TextColumn get blobId =>
      text().map(const HexConverter(BlobId.fromJson)).nullable()();
  // A friend's file coming here: what their Tox calls it.
  TextColumn get fileId =>
      text().map(const HexConverter(FileId.fromJson)).nullable()();
}

/// Answers to files offered to a linked account's home device, until the
/// background service writes them as events.
abstract class FileAnswers extends Table {
  IntColumn get id =>
      integer().autoIncrement().map(const IdConverter<FileAnswers>())();
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  TextColumn get graph => text().map(const HexConverter(GraphId.fromJson))();
  // The event that started the file.
  TextColumn get file => text().map(const HexConverter(EventId.fromJson))();
  BoolColumn get accepted => boolean()();
}

/// Answers to a linked account's invites to chats, until the background
/// service writes them as events.
abstract class InviteAnswers extends Table {
  IntColumn get id =>
      integer().autoIncrement().map(const IdConverter<InviteAnswers>())();
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  // The invite's event.
  TextColumn get invite => text().map(const HexConverter(EventId.fromJson))();
  BoolColumn get accepted => boolean()();
  // To join a group that has one.
  TextColumn get password => text().nullable()();
}

/// Settings of an account to set or clear, until the background service
/// writes the change as an event.
@DataClassName('SettingChange')
abstract class SettingChanges extends Table {
  IntColumn get id =>
      integer().autoIncrement().map(const IdConverter<SettingChanges>())();
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  BlobColumn get scope => blob().map(const ScopeConverter())();
  IntColumn get kind => integer()();
  // Null to clear it.
  BlobColumn get setting => blob().map(const SettingConverter()).nullable()();
}

/// What Tox says now, only true while it runs: who is online, who is in a
/// chat. One row per subject and kind of value.
abstract class LiveFacts extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  // Encoded as the sync protocol writes them.
  BlobColumn get subject => blob()();
  IntColumn get kind => integer()();
  BlobColumn get fact => blob()();

  @override
  Set<Column> get primaryKey => {profileId, subject, kind};
}

abstract class Profiles extends Table {
  IntColumn get id =>
      integer().autoIncrement().map(const IdConverter<Profiles>())();

  BoolColumn get signedIn => boolean().withDefault(const Constant(false))();
  TextColumn get settings => text().map(const ProfileSettingsConverter())();

  TextColumn get secretKey => text()
      .check(secretKey.length.equals(SecretKey.kLength * 2))
      .map(const HexConverter(SecretKey.fromJson))();
  TextColumn get publicKey => text()
      .check(publicKey.length.equals(PublicKey.kLength * 2))
      .map(const HexConverter(PublicKey.fromJson))();
  IntColumn get nospam => integer()
      .check(nospam.isBetweenValues(0, 0xFFFFFFFF))
      .map(const NospamConverter())();

  // For an account linked from another device: that device.
  TextColumn get home =>
      text().map(const HexConverter(ToxAddress.fromString)).nullable()();
  // Sent to that device with a friend request, until it first comes online.
  TextColumn get pairingMessage => text().nullable()();
}

/// What a chat's page sends, until the background service writes it as an
/// event.
abstract class ChatSends extends Table {
  IntColumn get id =>
      integer().autoIncrement().map(const IdConverter<ChatSends>())();
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  TextColumn get graph => text().map(const HexConverter(GraphId.fromJson))();
  TextColumn get message => text()();
}

@DataClassName('StoredEvent')
@TableIndex(name: 'sync_events_graph', columns: {#profileId, #graph})
@TableIndex(
  name: 'sync_events_shown',
  columns: {#profileId, #shown, #graph, #rank},
)
abstract class SyncEvents extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  TextColumn get id => text().map(const HexConverter(EventId.fromJson))();
  TextColumn get graph => text().map(const HexConverter(GraphId.fromJson))();
  IntColumn get rank => integer()();
  // Someone else's message or file, counted as unread until the account has
  // read past it.
  BoolColumn get received => boolean()();
  // Shows as an entry in its chat, so the chat list can show the latest.
  BoolColumn get shown => boolean().withDefault(const Constant(false))();
  BlobColumn get bytes => blob()();

  @override
  Set<Column> get primaryKey => {profileId, id};
}

/// How far each linked chat has been notified on this device, by rank, which
/// stays the same when its events sync again.
@DataClassName('NotifiedUpTo')
abstract class LinkedNotified extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  TextColumn get graph => text().map(const HexConverter(GraphId.fromJson))();
  IntColumn get rank => integer()();

  @override
  Set<Column> get primaryKey => {profileId, graph};
}

/// How far each chat has been seen on this device. The background service
/// records it when that's further than the account knows.
abstract class ChatReads extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  TextColumn get graph => text().map(const HexConverter(GraphId.fromJson))();
  TextColumn get event => text().map(const HexConverter(EventId.fromJson))();
  IntColumn get rank => integer()();

  @override
  Set<Column> get primaryKey => {profileId, graph};
}

/// What's being written in a chat on this device, until it's sent.
@DataClassName('StoredDraft')
abstract class ChatDrafts extends Table {
  IntColumn get profileId =>
      integer().references(Profiles, #id).map(const IdConverter<Profiles>())();
  TextColumn get graph => text().map(const HexConverter(GraphId.fromJson))();
  TextColumn get message => text()();
  TextColumn get attachments => text().map(const ContentListConverter())();
  TextColumn get replyingTo =>
      text().map(const ContentConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {profileId, graph};
}
