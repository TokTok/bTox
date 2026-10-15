import 'package:btox/calls/call_channel.dart';
import 'package:btox/calls/call_info.dart';
import 'package:btox/messages/message_format.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'calls.g.dart';

/// The calls going on, wherever they run.
@Riverpod(keepAlive: true)
Stream<List<CallInfo>> calls(Ref ref) => watchCalls();

/// Whether [profile] can call here: this device runs it, or its home
/// device is online and connects calls to it.
@riverpod
bool canCall(Ref ref, Id<Profiles> profile) {
  if (AnyPlatform.instance.isWeb) {
    return false;
  }
  if (ref.watch(profileProvider(profile).select((p) => p.value?.home)) ==
      null) {
    return true;
  }
  final live = ref.watch(liveFactsProvider(profile)).value;
  return live?.find(
        const Subject.account(),
        (value) => value is CallRelayValue ? value.relays : null,
      ) ??
      false;
}

typedef CallRecord = ({ChatSummary chat, ChatEntry entry});

@riverpod
Stream<List<(EventId, SyncEvent)>> _callEvents(Ref ref, Id<Profiles> id) =>
    watchDb(ref, (db) => db.watchCalls(id));

/// The calls in [profile]'s chats with friends, the latest first.
@riverpod
List<CallRecord> callHistory(Ref ref, Id<Profiles> profile) {
  final chats = {
    for (final chat
        in ref.watch(chatsForProfileProvider(profile)).value ??
            const <ChatSummary>[])
      if (chat.key is PublicKey) chat.ref.graph: chat,
  };
  final events =
      ref.watch(_callEventsProvider(profile)).value ??
      const <(EventId, SyncEvent)>[];
  final ends = {
    for (final (_, event) in events)
      if (event.content case final CallEnded end) end.call: end,
  };
  return [
    for (final (id, event) in events)
      if ((chats[event.graph], entryOf(id, event, MessageFormats.none))
          case (final chat?, final entry?) when event.content is Call)
        (
          chat: chat,
          entry: switch (ends[id]) {
            final end? => endedAs(entry, end),
            null => entry,
          },
        ),
  ]..sort((a, b) => b.entry.timestamp.compareTo(a.entry.timestamp));
}
