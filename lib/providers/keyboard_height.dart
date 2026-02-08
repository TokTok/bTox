import 'package:btox/platform/any_platform.dart';
import 'package:flutter/services.dart';
import 'package:keyboard_height_plugin/keyboard_height_plugin.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'keyboard_height.g.dart';

@riverpod
Stream<double> keyboardHeight(Ref ref) {
  if (!AnyPlatform.instance.isMobile) {
    return Stream.empty();
  }
  final _ = KeyboardHeightPlugin();
  return const EventChannel('keyboardHeightEventChannel')
      .receiveBroadcastStream()
      .map((event) => event as double);
}
