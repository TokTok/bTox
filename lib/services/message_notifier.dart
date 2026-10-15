import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:btox/calls/android_calls.dart';
import 'package:btox/calls/call_channel.dart';
import 'package:btox/calls/calls.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/chat_log.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/sync/account.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'message_notifier.g.dart';

const _logger = Logger(['MessageNotifier']);

const _settings = InitializationSettings(
  android: AndroidInitializationSettings('ic_bg_service_small'),
);

// Keeps them apart from the background service notification.
const _tag = 'message';
const _requestTag = 'request';
const _inviteTag = 'invite';

// Explicit groups, so Android doesn't bundle messages with the service
// notification under a summary that only opens the app.
const _messageGroup = 'messages';
const _serviceGroup = 'service';

int _idOfKey(CryptoBytes key) =>
    ByteData.sublistView(key.bytes).getInt32(0) & 0x7fffffff;

(int, String) _idOf(ChatRef chat) => (_idOfKey(chat.graph), _tag);

/// Only the Tox owner has one (on Android).
@Riverpod(keepAlive: true, name: 'messageNotifierProvider')
MessageNotifier? messageNotifier(Ref ref) => null;

final class MessageNotifier {
  // Adds to a chat's notification, naming its account if given. An untitled
  // one is from someone without a name.
  final Future<void> Function(
    ChatRef chat,
    String? title,
    List<NotifiedMessage> messages,
    String? account,
  )
  _show;
  final Future<void> Function(ChatRef chat) _cancel;
  ChatRef? _openChat;
  // One at a time, as each adds to what the one before showed.
  var _updates = Future<void>.value();

  /// With several, notifications say which account they're for.
  var signedInAccounts = 1;

  final Future<void> Function(
    Id<Profiles> profile,
    PublicKey from,
    String message,
    String? account,
  )?
  request;

  /// Rings, and tells of missed calls.
  final CallNotifier? calls;

  final Future<void> Function(
    Id<Profiles> profile,
    EventId id,
    AccountInvite invite,
    String? from,
    String? account,
  )?
  _invite;
  final Future<void> Function(EventId id)? _uninvite;

  MessageNotifier(
    this._show,
    this._cancel, {
    this.request,
    this.calls,
    Future<void> Function(
      Id<Profiles> profile,
      EventId id,
      AccountInvite invite,
      String? from,
      String? account,
    )?
    invite,
    Future<void> Function(EventId id)? uninvite,
  }) : _invite = invite,
       _uninvite = uninvite;

  static Future<MessageNotifier> android() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: _settings,
      onDidReceiveBackgroundNotificationResponse: declineFromNotification,
    );
    final l10n = lookupAppLocalizations(
      basicLocaleListResolution(
        PlatformDispatcher.instance.locales,
        AppLocalizations.supportedLocales,
      ),
    );
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;
    NotificationDetails alert(
      String tag, {
      String? account,
      StyleInformation? style,
    }) => NotificationDetails(
      android: AndroidNotificationDetails(
        'messages',
        'Messages',
        importance: Importance.high,
        priority: Priority.high,
        tag: tag,
        groupKey: _messageGroup,
        subText: account,
        styleInformation: style,
      ),
    );
    return MessageNotifier(
      (chat, title, messages, account) async {
        final (id, tag) = _idOf(chat);
        final name = title ?? l10n.defaultContactName;
        // Unless it was dismissed, it lists the messages before these.
        final shown = await android.getActiveNotificationMessagingStyle(
          id: id,
          tag: tag,
        );
        final listed = [
          ...?shown?.messages,
          for (final m in messages)
            Message(m.text, m.time, Person(name: m.sender ?? name)),
        ];
        final group = listed.any((m) => m.person?.name != name);
        return plugin.show(
          id: id,
          title: name,
          body: messages.last.text,
          notificationDetails: alert(
            tag,
            style: MessagingStyleInformation(
              Person(name: l10n.you),
              conversationTitle: switch (account) {
                final account? => l10n.chatInAccount(name, account),
                null => group ? name : null,
              },
              groupConversation: group,
              messages: listed,
            ),
          ),
          payload: chat.key,
        );
      },
      (chat) {
        final (id, tag) = _idOf(chat);
        return plugin.cancel(id: id, tag: tag);
      },
      request: (profile, from, message, account) => plugin.show(
        id: _idOfKey(from),
        title: l10n.friendRequest,
        body: message,
        notificationDetails: alert(_requestTag, account: account),
        payload: '${profile.value}',
      ),
      invite: (profile, id, invite, from, account) => plugin.show(
        id: _idOfKey(id),
        title: l10n.inviteNotification,
        body: inviteText(l10n, invite, from),
        notificationDetails: alert(_inviteTag, account: account),
        payload: '${profile.value}',
      ),
      uninvite: (id) => plugin.cancel(id: _idOfKey(id), tag: _inviteTag),
      calls: AndroidCallNotifier(plugin),
    );
  }

  /// The chat on screen, gets no notifications.
  set openChat(ChatRef? chat) {
    _openChat = chat;
    if (chat != null) {
      _update(() => _cancel(chat));
    }
  }

  /// Takes back [chat]'s notification, as it was read elsewhere.
  void read(ChatRef chat) => _update(() => _cancel(chat));

  /// Adds [messages] to [chat]'s notification.
  void notify(
    ChatRef chat,
    String? title,
    List<NotifiedMessage> messages,
    String? account,
  ) {
    if (chat != _openChat) {
      final named = signedInAccounts > 1 ? account : null;
      _update(() => _show(chat, title, messages, named));
    }
  }

  void invited(
    Id<Profiles> profile,
    EventId id,
    AccountInvite invite,
    String? from,
    String? account,
  ) {
    if (_invite case final show?) {
      final named = signedInAccounts > 1 ? account : null;
      _update(() => show(profile, id, invite, from, named));
    }
  }

  void uninvited(EventId id) {
    if (_uninvite case final cancel?) {
      _update(() => cancel(id));
    }
  }

  void _update(Future<void> Function() update) {
    _updates = _updates
        .then((_) => update())
        .catchError((Object e) => _logger.e('Failed to notify: $e'));
  }
}

// flutter_background_service's defaults for its own notification.
const _serviceChannel = 'FOREGROUND_DEFAULT';
const _serviceNotificationId = 112233;

/// Replaces the background service's notification, which can't list lines.
/// Without a title, Android shows the app name in its place.
Future<void> showServiceNotification(String summary, List<String> lines) =>
    FlutterLocalNotificationsPlugin().show(
      id: _serviceNotificationId,
      body: summary,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _serviceChannel,
          'Background Service',
          importance: Importance.low,
          ongoing: true,
          onlyAlertOnce: true,
          showWhen: false,
          groupKey: _serviceGroup,
          styleInformation: lines.isEmpty ? null : InboxStyleInformation(lines),
        ),
      ),
    );

/// Calls [openChat] for tapped notifications, including one that started
/// the app, [answer] for a call answered from its notification, which then
/// shows, and [openRequests] for a friend request or an invite to a profile.
Future<void> handleNotificationTaps(
  void Function(ChatRef) openChat, {
  required void Function(ChatRef) answer,
  required void Function(Id<Profiles>) openRequests,
}) async {
  if (!AnyPlatform.instance.isAndroid) {
    return;
  }
  void open(NotificationResponse? response) {
    final payload = response?.payload ?? '';
    if (ChatRef.ofKey(payload) case final chat?) {
      switch (response?.actionId) {
        case answerAction:
          answer(chat);
        case null:
          openChat(chat);
      }
    } else if (int.tryParse(payload) case final profile?) {
      openRequests(Id(profile));
    }
  }

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: _settings,
    onDidReceiveNotificationResponse: open,
    onDidReceiveBackgroundNotificationResponse: declineFromNotification,
  );
  final launch = await plugin.getNotificationAppLaunchDetails();
  if (launch != null && launch.didNotificationLaunchApp) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => open(launch.notificationResponse),
    );
  }
}

/// Declines a call from its notification, without showing the app.
@pragma('vm:entry-point')
void declineFromNotification(NotificationResponse response) {
  if (response.actionId == declineAction) {
    if (ChatRef.ofKey(response.payload ?? '') case final chat?) {
      CallCommands.hangUp(chat.profile);
    }
  }
}
