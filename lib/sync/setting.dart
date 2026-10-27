import 'dart:typed_data';

import 'package:btox/models/crypto.dart';
import 'package:btox/packets/messagepack.dart';
import 'package:btox/sync/codec.dart';
import 'package:drift/drift.dart' show TypeConverter;
import 'package:freezed_annotation/freezed_annotation.dart';

export 'package:btox/sync/codec.dart' show Kept;

part 'setting.freezed.dart';

const _scopeAccount = 0;
const _scopeConversation = 1;

/// What a setting applies to.
@freezed
sealed class Scope with _$Scope {
  const factory Scope.account() = AccountScope;
  const factory Scope.conversation(GraphId graph) = ConversationScope;

  /// From a newer version: applies to nothing here.
  const factory Scope.unknown(int tag) = UnknownScope;
}

/// How pictures are sent in a conversation.
enum PictureEncoding { original, qoi }

/// A setting, by kind. A scope has at most one of each kind.
@freezed
sealed class Setting with _$Setting {
  /// The conversation doesn't notify until [until], or ever where it's null,
  /// but for messages naming the account where [mentions].
  const factory Setting.mute({DateTime? until, required bool mentions}) = Mute;

  const factory Setting.pictureFormat(PictureEncoding format) = PictureFormat;

  /// Of a kind this version doesn't know, or that doesn't decode: kept and
  /// passed on, but not acted on.
  const factory Setting.unknown(int kind) = UnknownSetting;

  static const muteKind = 0;
  static const pictureFormatKind = 1;

  const Setting._();

  int get kind => switch (this) {
    Mute() => muteKind,
    PictureFormat() => pictureFormatKind,
    UnknownSetting(:final kind) => kind,
  };
}

extension MuteHolds on Mute {
  bool holdsAt(DateTime now) => until?.isAfter(now) ?? true;
}

// The account is a bare tag, a conversation is `[tag, graph]`.
ArrayWriter addScope(ArrayWriter into, Scope scope) => switch (scope) {
  AccountScope() => into.uint(_scopeAccount),
  ConversationScope(:final graph) => into.array(
    ArrayWriter().uint(_scopeConversation).bin(graph.bytes),
  ),
  // Never re-encoded: stores keep the bytes they received.
  UnknownScope() => throw StateError('Unknown scopes are not written'),
};

Scope readScope(Fields f) => f.variant<Scope>(
  (tag, s) => switch (tag) {
    _scopeConversation => Scope.conversation(GraphId(s.bin())),
    _ => null,
  },
  (tag) => tag == _scopeAccount ? const Scope.account() : Scope.unknown(tag),
);

ArrayWriter _fields(Setting setting) => switch (setting) {
  Mute(:final until, :final mentions) =>
    ArrayWriter().optUint(until?.millisecondsSinceEpoch).flag(mentions),
  PictureFormat(:final format) => ArrayWriter().uint(format.index),
  // Never re-encoded: stores keep the bytes they received.
  UnknownSetting() => throw StateError('Unknown settings are not written'),
};

// `[kind, [fields]]`, its fields in an array even where there's one, so
// every kind can gain fields, and a kept one as it came.
ArrayWriter addSetting(ArrayWriter into, Kept<Setting> setting) =>
    switch (setting.bytes) {
      final bytes? => into.raw(bytes),
      null => into.array(
        ArrayWriter().uint(setting.value.kind).array(_fields(setting.value)),
      ),
    };

Kept<Setting> readSetting(Fields f) {
  final bytes = f.raw();
  return Kept.read(
    decodeExact(
      bytes,
      (unpacker) => readLenient<Setting>(
        unpacker,
        (kind, s) => switch (kind) {
          Setting.muteKind => Setting.mute(
            until: switch (s.optUint()) {
              final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
              null => null,
            },
            mentions: s.flag(),
          ),
          // Unknown formats send pictures as they are.
          Setting.pictureFormatKind => Setting.pictureFormat(
            PictureEncoding.values.elementAtOrNull(s.uint()) ??
                PictureEncoding.original,
          ),
          _ => null,
        },
        Setting.unknown,
      ),
    ),
    bytes,
  );
}

extension KeptSetting on Kept<Setting> {
  /// [setting] in place of this one, with the fields of this one after its
  /// own as they came.
  Kept<Setting> withSetting(Setting setting) {
    var fields = _fields(setting).encode();
    if (bytes case final bytes?) {
      final old = Unpacker(bytes);
      if (old.unpackListLength() == 2 && old.unpackInt() == setting.kind) {
        fields = carry(old.takeValue(), fields);
      }
    }
    return Kept.read(
      setting,
      (Packer()
            ..packListLength(2)
            ..packInt(setting.kind)
            ..packRaw(fields))
          .takeBytes(),
    );
  }
}

// What a converter below wrote: an array of the one value.
T _decode<T>(Uint8List bytes, T Function(Fields) read) =>
    decodeExact(bytes, (unpacker) {
      final fields = Fields(unpacker);
      final value = read(fields);
      fields.exact();
      return value;
    });

/// A scope as the sync protocol writes it, as kept in the database.
final class ScopeConverter extends TypeConverter<Scope, Uint8List> {
  const ScopeConverter();

  @override
  Scope fromSql(Uint8List fromDb) => _decode(fromDb, readScope);

  @override
  Uint8List toSql(Scope value) => addScope(ArrayWriter(), value).encode();
}

/// A setting as the sync protocol writes it, as kept in the database.
final class SettingConverter extends TypeConverter<Kept<Setting>, Uint8List> {
  const SettingConverter();

  @override
  Kept<Setting> fromSql(Uint8List fromDb) => _decode(fromDb, readSetting);

  @override
  Uint8List toSql(Kept<Setting> value) =>
      addSetting(ArrayWriter(), value).encode();
}
