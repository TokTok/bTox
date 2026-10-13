import 'package:btox/db/database.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _settings = InitializationSettings(
  android: AndroidInitializationSettings('ic_bg_service_small'),
);

// Keeps them apart from the background service notification.
const _tag = 'message';

/// Only the Tox owner has one (on Android).
final messageNotifierProvider = Provider<MessageNotifier?>((ref) => null);

final class MessageNotifier {
  final Future<void> Function(
    Id<Contacts> id,
    String title,
    String body,
    String? account,
  )
  _show;
  final Future<void> Function(Id<Contacts> id) _cancel;
  Id<Contacts>? _openChat;

  MessageNotifier(this._show, this._cancel);

  static Future<MessageNotifier> android() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: _settings);
    return MessageNotifier(
      (id, title, body, account) => plugin.show(
        id: id.value,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Messages',
            importance: Importance.high,
            priority: Priority.high,
            tag: _tag,
            subText: account,
          ),
        ),
        payload: '${id.value}',
      ),
      (id) => plugin.cancel(id: id.value, tag: _tag),
    );
  }

  /// The chat on screen, gets no notifications.
  set openChat(Id<Contacts>? id) {
    _openChat = id;
    if (id != null) {
      _cancel(id);
    }
  }

  void notify(Contact contact, String text, String? account) {
    if (contact.id != _openChat) {
      _show(contact.id, contact.name ?? 'Unknown', text, account);
    }
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
          styleInformation: lines.isEmpty ? null : InboxStyleInformation(lines),
        ),
      ),
    );

/// Calls [openChat] for tapped notifications, including one that started
/// the app.
Future<void> handleNotificationTaps(
  void Function(Id<Contacts>) openChat,
) async {
  if (!AnyPlatform.instance.isAndroid) {
    return;
  }
  void open(String? payload) {
    if (int.tryParse(payload ?? '') case final id?) {
      openChat(Id(id));
    }
  }

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: _settings,
    onDidReceiveNotificationResponse: (response) => open(response.payload),
  );
  final launch = await plugin.getNotificationAppLaunchDetails();
  if (launch != null && launch.didNotificationLaunchApp) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => open(launch.notificationResponse?.payload),
    );
  }
}
