import 'package:btox/models/crypto.dart';
import 'package:btox/sync/event.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/sync/store.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'account.freezed.dart';

@freezed
abstract class AccountFriend with _$AccountFriend {
  const factory AccountFriend({
    @Default(false) bool wanted,
    String? name,
    String? statusMessage,
    // A friend request waiting for an answer.
    String? request,
    // Where a friend request of ours goes, until they accept it.
    ToxAddressNospam? nospam,
    String? requestMessage,
  }) = _AccountFriend;
}

@freezed
abstract class AccountChat with _$AccountChat {
  const factory AccountChat({
    String? name,
    @Default(false) bool joined,
    String? selfName,
  }) = _AccountChat;
}

@freezed
abstract class AccountState with _$AccountState {
  const factory AccountState({
    String? name,
    String? statusMessage,
    @Default({}) Map<PublicKey, AccountFriend> friends,
    @Default({}) Map<ChatId, AccountChat> chats,
    // Per conversation, the rank and ID of the last event read.
    @Default({}) Map<GraphId, (int, EventId)> read,
    // Per scope, its settings by kind.
    @Default({}) Map<Scope, Map<int, Kept<Setting>>> settings,
    // The kept facts, of which the fields above show some.
    required Facts facts,
  }) = _AccountState;

  const AccountState._();

  T? setting<T extends Setting>(Scope scope) => settings[scope]?.values
      .map((kept) => kept.value)
      .whereType<T>()
      .firstOrNull;

  /// The setting of [scope] that is a [T] as [change] makes it, to write:
  /// the fields of it this version doesn't know stay as they came.
  Kept<Setting>? edit<T extends Setting>(Scope scope, T Function(T) change) {
    for (final kept in settings[scope]?.values ?? const <Kept<Setting>>[]) {
      if (kept.value case final T value) {
        return kept.withSetting(change(value));
      }
    }
    return null;
  }

  /// What [events] add up to, in rank order, so the last writer wins.
  factory AccountState.of(Iterable<(EventId, SyncEvent)> events) =>
      AccountFold().update([...events]);
}

/// What a graph's events add up to, as [AccountState.of] says, kept as more
/// are added: those that come after the rest are added to it, and anything
/// else adds them all up again.
final class AccountFold {
  var _facts = Facts();
  final _friends = <PublicKey, AccountFriend>{};
  final _settings = <Scope, Map<int, Kept<Setting>>>{};
  final _read = <GraphId, (int, EventId)>{};
  // The last event added, in rank order.
  (int, EventId)? _last;
  var _events = const <(EventId, SyncEvent)>[];
  AccountState? _state;

  /// The state of [events], which are those it had before and more, or any.
  AccountState update(List<(EventId, SyncEvent)> events) {
    final grown =
        events.length >= _events.length &&
        (_events.isEmpty || events[_events.length - 1].$1 == _events.last.$1);
    if (!grown || !_addAll(events.skip(_events.length))) {
      _facts = Facts();
      for (final map in [_friends, _settings, _read]) {
        map.clear();
      }
      _last = null;
      _state = null;
      _addAll(events);
    }
    _events = events;
    return _state ??= _build();
  }

  /// Whether [added] all came after the events added before, and so were.
  bool _addAll(Iterable<(EventId, SyncEvent)> added) {
    for (final (id, event) in rankOrder(added)) {
      if (!isAfter((event.rank, id), _last)) {
        return false;
      }
      _last = (event.rank, id);
      _state = null;
      _add(id, event);
    }
    return true;
  }

  AccountFriend _friend(PublicKey pk) => _friends[pk] ?? const AccountFriend();

  void _add(EventId id, SyncEvent event) {
    switch (event.content) {
      case FactContent(:final subject, :final value):
        _facts.set(subject, value);
      case WantFriend(:final pk, :final requestMessage, :final nospam):
        _friends[pk] = _friend(pk).copyWith(
          wanted: true,
          request: null,
          nospam: nospam,
          requestMessage: requestMessage,
        );
      case UnwantFriend(:final pk):
        _friends[pk] = _friend(pk).copyWith(wanted: false, request: null);
      case FriendRequested(:final pk, :final message):
        _friends[pk] = _friend(pk).copyWith(request: message);
      case SettingContent(:final scope, :final setting):
        (_settings[scope] ??= {})[setting.value.kind] = setting;
      case ClearSetting(:final scope, :final kind):
        if (_settings[scope] case final kinds?) {
          kinds.remove(kind);
          if (kinds.isEmpty) {
            _settings.remove(scope);
          }
        }
      case ReadUpTo(:final graph, :final event, :final rank):
        if (isAfter((rank, event), _read[graph])) {
          _read[graph] = (rank, event);
        }
      default:
        break;
    }
  }

  AccountState _build() {
    final facts = _facts.copy();
    String? statusMessageOf(Subject subject) =>
        facts.find(subject, (v) => v is StatusMessageValue ? v.message : null);
    final friends = {..._friends};
    for (final subject in facts.subjects) {
      if (subject case FriendSubject(:final pk)) {
        friends[pk] = (friends[pk] ?? const AccountFriend()).copyWith(
          name: facts.nameOf(subject),
          statusMessage: statusMessageOf(subject),
        );
      }
    }
    return AccountState(
      name: facts.nameOf(const Subject.account()),
      statusMessage: statusMessageOf(const Subject.account()),
      friends: friends,
      chats: {
        for (final subject in facts.subjects)
          if (subject case ChatSubject(:final chat))
            chat: AccountChat(
              name: facts.nameOf(subject),
              joined:
                  facts.find(
                    subject,
                    (v) => v is JoinedValue ? v.joined : null,
                  ) ??
                  false,
              selfName: facts.find(
                subject,
                (v) => v is SelfNameValue ? v.name : null,
              ),
            ),
      },
      read: {..._read},
      settings: {
        for (final MapEntry(:key, :value) in _settings.entries) key: {...value},
      },
      facts: facts,
    );
  }
}

/// Whether [a] comes after [b] in last-writer-wins order: by rank, then ID.
bool isAfter((int, EventId) a, (int, EventId)? b) =>
    b == null || compareRanks(a, b) > 0;
