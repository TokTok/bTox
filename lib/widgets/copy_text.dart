import 'package:btox/logger.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _logger = Logger(['CopyText']);

const _clipboard = MethodChannel('btox/clipboard');

// Whether the system shows what was copied, as Android does since 13.
final _systemConfirms = AnyPlatform.instance.isAndroid
    ? _clipboard.invokeMethod<bool>('confirmsCopies').then((v) => v ?? false)
    : Future.value(false);

/// Copies [text], and says [copied] where the system doesn't say it.
void copyText(ScaffoldMessengerState messenger, String text, String copied) =>
    _logger.unawaited('copy', () async {
      await Clipboard.setData(ClipboardData(text: text));
      if (!await _systemConfirms) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(copied)));
      }
    }());
