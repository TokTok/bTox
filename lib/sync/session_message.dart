import 'dart:typed_data';

import 'package:btox/models/crypto.dart';
import 'package:btox/sync/codec.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/frames.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_message.freezed.dart';

const syncVersion = 1;

const _tagHello = 0;
const _tagSummary = 1;
const _tagHeads = 2;
const _tagWant = 3;
const _tagEvents = 4;
const _tagHistory = 5;
const _tagWantBlob = 6;
const _tagNoBlob = 7;
const _tagFacts = 8;
const _tagCall = 9;

const _callConnect = 0;
const _callHangUp = 1;

/// The Tox file kind blobs are sent as. It reuses the sync packet ID.
const blobFileKind = syncPacketId;

/// What a device offers, sent in [Hello]. Unknown bits are kept, so a newer
/// device's features pass through unharmed.
extension type const Features(int bits) {
  static const none = Features(0);
  static const accountSync = Features(1);

  bool contains(Features other) => bits & other.bits == other.bits;
}

@freezed
sealed class CallAction with _$CallAction {
  /// Answers it, or places it, and has the home device call this device
  /// once it's connected.
  const factory CallAction.connect({required bool video}) = ConnectCall;

  /// Also declines it while it rings.
  const factory CallAction.hangUp() = HangUpCall;
}

@freezed
sealed class SessionMessage with _$SessionMessage {
  const factory SessionMessage.hello({
    @Default(syncVersion) int version,
    required Features features,
  }) = Hello;
  const factory SessionMessage.summary(List<(GraphId, HeadsDigest)> graphs) =
      Summary;
  const factory SessionMessage.heads({
    required GraphId graph,
    required List<EventId> heads,
  }) = Heads;
  const factory SessionMessage.want(List<EventId> ids) = Want;

  /// Encoded events, as stored.
  const factory SessionMessage.events(List<Uint8List> events) = Events;

  /// Asks for up to [limit] ancestors of [before], newest first.
  const factory SessionMessage.history({
    required GraphId graph,
    required List<EventId> before,
    required int limit,
  }) = History;

  /// Asks for a blob, sent as a file transfer whose file ID is the blob's.
  const factory SessionMessage.wantBlob(BlobId blob) = WantBlob;
  const factory SessionMessage.noBlob(BlobId blob) = NoBlob;

  /// Live facts, which aren't stored: with [all], every one there is.
  const factory SessionMessage.facts(List<Fact> facts, {required bool all}) =
      FactsUpdate;

  /// From a device, about the account's call with [friend].
  const factory SessionMessage.call(PublicKey friend, CallAction action) =
      CallControl;

  const SessionMessage._();

  /// Null for messages this version doesn't know.
  static SessionMessage? decode(Uint8List data) => decodeExact(
    data,
    (unpacker) => readVariant<SessionMessage?>(unpacker, (tag, m) {
      List<EventId> ids(Fields list) =>
          list.list((item) => EventId(item.bin()));
      return switch (tag) {
        _tagHello => m.fields(
          (f) => Hello(version: f.uint(), features: Features(f.uint())),
        ),
        _tagSummary => Summary(
          m.list(
            (item) => item.tuple(
              (entry) => (GraphId(entry.bin()), HeadsDigest(entry.bin())),
            ),
          ),
        ),
        _tagHeads => m.fields(
          (f) => Heads(graph: GraphId(f.bin()), heads: ids(f)),
        ),
        _tagWant => Want(ids(m)),
        _tagEvents => Events(m.list((item) => item.bin())),
        _tagHistory => m.fields(
          (f) =>
              History(graph: GraphId(f.bin()), before: ids(f), limit: f.uint()),
        ),
        _tagWantBlob => WantBlob(BlobId(m.bin())),
        _tagNoBlob => NoBlob(BlobId(m.bin())),
        _tagFacts => m.fields(
          (f) => FactsUpdate(
            f.list((item) => item.tuple(readFact)),
            all: f.flag(),
          ),
        ),
        _tagCall => m.fields((f) {
          final friend = PublicKey(f.bin());
          return switch (_readCallAction(f)) {
            final action? => CallControl(friend, action),
            null => null,
          };
        }),
        _ => null,
      };
    }, (_) => null),
  );

  /// `[tag, [fields]]`, or `[tag, field]` for one with a single field.
  Uint8List encode() {
    ArrayWriter ids(List<EventId> ids) {
      final list = ArrayWriter();
      for (final id in ids) {
        list.bin(id.bytes);
      }
      return list;
    }

    ArrayWriter list<T>(Iterable<T> items, ArrayWriter Function(T) item) {
      final list = ArrayWriter();
      for (final value in items) {
        list.array(item(value));
      }
      return list;
    }

    final m = ArrayWriter();
    switch (this) {
      case Hello(:final version, :final features):
        m
            .uint(_tagHello)
            .array(ArrayWriter().uint(version).uint(features.bits));
      case Summary(:final graphs):
        m
            .uint(_tagSummary)
            .array(
              list(
                graphs,
                (entry) =>
                    ArrayWriter().bin(entry.$1.bytes).bin(entry.$2.bytes),
              ),
            );
      case Heads(:final graph, :final heads):
        m
            .uint(_tagHeads)
            .array(ArrayWriter().bin(graph.bytes).array(ids(heads)));
      case Want(ids: final wanted):
        m.uint(_tagWant).array(ids(wanted));
      case Events(:final events):
        final list = ArrayWriter();
        for (final event in events) {
          list.bin(event);
        }
        m.uint(_tagEvents).array(list);
      case History(:final graph, :final before, :final limit):
        m
            .uint(_tagHistory)
            .array(
              ArrayWriter().bin(graph.bytes).array(ids(before)).uint(limit),
            );
      case WantBlob(:final blob):
        m.uint(_tagWantBlob).bin(blob.bytes);
      case NoBlob(:final blob):
        m.uint(_tagNoBlob).bin(blob.bytes);
      case CallControl(:final friend, :final action):
        final fields = ArrayWriter().bin(friend.bytes);
        switch (action) {
          case ConnectCall(:final video):
            fields.array(ArrayWriter().uint(_callConnect).flag(video));
          case HangUpCall():
            fields.uint(_callHangUp);
        }
        m.uint(_tagCall).array(fields);
      case FactsUpdate(:final facts, :final all):
        m
            .uint(_tagFacts)
            .array(
              ArrayWriter()
                  .array(list(facts, (fact) => encodeFact(fact.$1, fact.$2)))
                  .flag(all),
            );
    }
    return m.encode();
  }
}

/// Null for an action this version doesn't know.
CallAction? _readCallAction(Fields f) => f.variant<CallAction?>(
  (tag, a) => tag == _callConnect ? CallAction.connect(video: a.flag()) : null,
  (tag) => tag == _callHangUp ? const CallAction.hangUp() : null,
);
