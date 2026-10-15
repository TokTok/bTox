import 'dart:typed_data';

import 'package:btox/calls/call_info.dart';
import 'package:btox/calls/calls.dart';
import 'package:btox/calls/plugin_call_media.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The notification actions on a ringing call.
const answerAction = 'answer';
const declineAction = 'decline';

// Android's Notification.FLAG_INSISTENT: the sound repeats until answered.
const _insistent = 4;

// Each profile has one call at a time, by its id.
const _ringingTag = 'call';
const _missedTag = 'missed-call';

/// Rings with a full-screen notification, which shows the incoming call
/// over the lock screen, and notifies missed calls.
final class AndroidCallNotifier implements CallNotifier {
  final FlutterLocalNotificationsPlugin _plugin;

  AndroidCallNotifier(this._plugin);

  @override
  void ring(CallInfo call) {
    final l10n = systemL10n();
    _plugin.show(
      id: call.chat.profile.value,
      title: call.name ?? l10n.defaultContactName,
      body: call.video ? l10n.incomingVideoCall : l10n.incomingCall,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'ringing',
          l10n.incomingCalls,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          additionalFlags: Int32List.fromList([_insistent]),
          sound: const UriAndroidNotificationSound(
            'content://settings/system/ringtone',
          ),
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          tag: _ringingTag,
          actions: [
            AndroidNotificationAction(
              declineAction,
              l10n.declineCall,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              answerAction,
              l10n.answerCall,
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      payload: call.chat.key,
    );
  }

  @override
  void stopRinging(Id<Profiles> profile) =>
      _plugin.cancel(id: profile.value, tag: _ringingTag);

  @override
  void missed(CallInfo call) {
    final l10n = systemL10n();
    _plugin.show(
      id: ByteData.sublistView(call.chat.graph.bytes).getInt32(0) & 0x7fffffff,
      title: call.name ?? l10n.defaultContactName,
      body: call.video ? l10n.missedVideoCall : l10n.missedCall,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'missed_calls',
          l10n.missedCalls,
          importance: Importance.high,
          category: AndroidNotificationCategory.missedCall,
          tag: _missedTag,
        ),
      ),
      payload: call.chat.key,
    );
  }
}
