import 'dart:async';
import 'dart:ui';

import 'package:btox/logger.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/connection_status.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/providers/provider_error_logger.dart';
import 'package:btox/services/connection_status_channel.dart';
import 'package:btox/services/message_notifier.dart';
import 'package:btox/services/stay_online_policy.dart';
import 'package:btox/services/tox_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:riverpod/riverpod.dart';

const _logger = Logger(['BackgroundService']);

Future<void> initializeService() async {
  // On desktop and web, the UI opens the database and runs Tox itself.
  if (!AnyPlatform.instance.isMobile) {
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  final service = FlutterBackgroundService();

  await service.configure(
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: _onStart,
      onBackground: _onIosBackground,
    ),
    androidConfiguration: AndroidConfiguration(
      autoStart: true,
      onStart: _onStart,
      isForegroundMode: true,
      // The service sets this from the stay-online setting.
      autoStartOnBoot: false,
      // Without a title, Android shows the app name in its place.
      initialNotificationTitle: '',
      initialNotificationContent: connectionStatusText(null),
      foregroundServiceTypes: [AndroidForegroundType.remoteMessaging],
    ),
  );
}

/// Starts the background service again if it stopped, as it may just as
/// the UI comes back.
Future<void> ensureServiceRunning() async {
  final service = FlutterBackgroundService();
  if (!await service.isRunning()) {
    _logger.i('Starting the background service again');
    await service.startService();
  }
}

/// Tells the background service which chat is on screen, if any.
void reportOpenChat(ChatRef? chat) {
  if (AnyPlatform.instance.isMobile) {
    FlutterBackgroundService().invoke('openChat', {'chat': chat?.key});
  }
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  _logger.d('Processing iOS background fetch');

  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  return true;
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  _logger.d('Starting background service');
  DartPluginRegistrant.ensureInitialized();

  service.on('openChat').listen((args) {
    final key = args?['chat'] as String?;
    _BackgroundService.instance.openChat = key == null
        ? null
        : ChatRef.ofKey(key);
  });

  await _BackgroundService.instance.start(
    onStatuses: (statuses, names) {
      if (service is AndroidServiceInstance) {
        showServiceNotification(
          connectionSummaryText(statuses.values),
          connectionStatusLines(statuses, names),
        );
      }
    },
    onStop: () {
      _BackgroundService.instance.stop();
      service.stopSelf();
      _logger.d('Background process is now stopped');
    },
    onAutoStartOnBoot: (value) {
      if (service is AndroidServiceInstance) {
        service.setAutoStartOnBootMode(value);
      }
    },
  );
}

final class _BackgroundService {
  static final _BackgroundService instance = _BackgroundService._();
  ProviderContainer? _container;
  ConnectionStatusPublisher? _publisher;
  StayOnlinePolicy? _policy;
  MessageNotifier? _notifier;

  _BackgroundService._();

  Future<void> start({
    required void Function(
      ConnectionStatuses statuses,
      Map<Id<Profiles>, String> names,
    )
    onStatuses,
    required void Function() onStop,
    required void Function(bool) onAutoStartOnBoot,
  }) async {
    if (_container != null) {
      return;
    }

    final policy = _policy = StayOnlinePolicy(
      onStop: onStop,
      onAutoStartOnBoot: onAutoStartOnBoot,
    );
    final notifier = _notifier = AnyPlatform.instance.isAndroid
        ? await MessageNotifier.android()
        : null;
    final publisher = _publisher = ConnectionStatusPublisher(
      onSubscribersChanged: (count) {
        policy.uiCount = count;
        if (count == 0) {
          notifier?.openChat = null;
        }
      },
    );
    final container = _container = ProviderContainer(
      observers: const [ProviderErrorLogger()],
      overrides: [
        databaseProvider.overrideWith(hostedDatabase),
        messageNotifierProvider.overrideWithValue(notifier),
      ],
    );
    // Keep the database open while the service runs.
    container.listen(databaseProvider, (_, _) {});
    container.listen(
      stayOnlineProvider,
      (_, stayOnline) => policy.stayOnline = stayOnline,
      fireImmediately: true,
    );
    container.listen(
      signedInProfilesProvider,
      (_, profiles) => notifier?.signedInAccounts = profiles.length,
      fireImmediately: true,
    );
    container.listen(toxSessionsProvider, (_, statuses) {
      publisher.publish(statuses);
      onStatuses(statuses, {
        for (final profile in container.read(signedInProfilesProvider))
          profile.id: profile.settings.nickname,
      });
    }, fireImmediately: true);
  }

  set openChat(ChatRef? chat) => _notifier?.openChat = chat;

  void stop() {
    _policy?.dispose();
    _policy = null;
    _container?.dispose();
    _container = null;
    _publisher?.close();
    _publisher = null;
    _notifier = null;
  }
}
