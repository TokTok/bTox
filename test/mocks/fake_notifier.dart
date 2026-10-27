import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/services/message_notifier.dart';

/// A notification: its chat, title, newest message and account.
typedef Shown = (ChatRef, String?, String, String?);

/// Keeps each notification in [shown], its newest message as "sender: text"
/// where it has a sender. Several accounts are signed in, so each names its
/// account.
MessageNotifier fakeNotifier(
  List<Shown> shown, {
  Future<void> Function(Id<Profiles>, PublicKey, String, String?)? request,
  List<(EventId, String?)>? invited,
  List<EventId>? uninvited,
  List<ChatRef>? cancelled,
}) => MessageNotifier(
  (chat, title, messages, account) async {
    final (:sender, :text, time: _) = messages.last;
    shown.add((chat, title, sender == null ? text : '$sender: $text', account));
  },
  (chat) async => cancelled?.add(chat),
  request: request,
  invite: (_, id, _, from, _) async => invited?.add((id, from)),
  uninvite: (id) async => uninvited?.add(id),
)..signedInAccounts = 2;
