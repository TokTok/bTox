import 'dart:async';
import 'dart:ui';

import 'package:btox/ffi/toxcore.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/services/connection_status_channel.dart';
import 'package:btox/services/message_notifier.dart';
import 'package:btox/services/stay_online_policy.dart';
import 'package:btox/services/tox_owner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      // The header already shows the app name.
      initialNotificationTitle: connectionStatusText(null),
      initialNotificationContent: '',
      foregroundServiceTypes: [AndroidForegroundType.remoteMessaging],
    ),
  );
}

String connectionStatusText(Tox_Connection? status) => switch (status) {
  null => 'Offline',
  Tox_Connection.TOX_CONNECTION_NONE => 'Connecting…',
  Tox_Connection.TOX_CONNECTION_TCP => 'Online via TCP relay',
  Tox_Connection.TOX_CONNECTION_UDP => 'Online',
};

/// Tells the background service which chat is on screen, if any.
void reportOpenChat(Id<Contacts>? contactId) {
  if (AnyPlatform.instance.isMobile) {
    FlutterBackgroundService().invoke('openChat', {
      'contactId': contactId?.value,
    });
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
    final contactId = args?['contactId'] as int?;
    _BackgroundService.instance.openChat = contactId == null
        ? null
        : Id(contactId);
  });

  await _BackgroundService.instance.start(
    onStatus: (status) {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: connectionStatusText(status),
          content: '',
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
    required void Function(Tox_Connection? status) onStatus,
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
    runToxOwner(container, (status) {
      publisher.publish(status);
      onStatus(status);
    });
  }

  set openChat(Id<Contacts>? contactId) => _notifier?.openChat = contactId;

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
