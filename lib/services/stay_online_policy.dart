import 'dart:async';

import 'package:btox/providers/profiles.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'stay_online_policy.g.dart';

@Riverpod(keepAlive: true)
bool? stayOnline(Ref ref) => ref.watch(appSettingsProvider).value?.stayOnline;

final class StayOnlinePolicy {
  final void Function() onStop;

  final void Function(bool) onAutoStartOnBoot;

  final Duration grace;

  int _uis = 0;
  bool _inCall = false;
  bool? _stayOnline;
  Timer? _stopTimer;

  StayOnlinePolicy({
    required this.onStop,
    required this.onAutoStartOnBoot,
    this.grace = const Duration(seconds: 15),
  }) {
    _update();
  }

  set uiCount(int count) {
    final joined = count > _uis;
    _uis = count;
    // A starting UI configures the service, resetting its boot mode.
    if (joined) {
      _assertAutoStartOnBoot();
    }
    _update();
  }

  /// A call goes on with the UI closed.
  set inCall(bool value) {
    _inCall = value;
    _update();
  }

  set stayOnline(bool? value) {
    _stayOnline = value;
    _assertAutoStartOnBoot();
    _update();
  }

  void dispose() {
    _stopTimer?.cancel();
    _stopTimer = null;
  }

  void _assertAutoStartOnBoot() {
    if (_stayOnline case final stayOnline?) {
      onAutoStartOnBoot(stayOnline);
    }
  }

  void _update() {
    if (_uis > 0 || _inCall || _stayOnline == true) {
      _stopTimer?.cancel();
      _stopTimer = null;
    } else {
      _stopTimer ??= Timer(grace, onStop);
    }
  }
}
