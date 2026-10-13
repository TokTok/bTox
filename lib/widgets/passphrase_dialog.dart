import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Asks for a passphrase until [run] accepts it.
Future<Uint8List?> showPassphraseDialog(
  BuildContext context, {
  required String title,
  required String action,
  required Uint8List Function(String passphrase) run,
  bool obscure = true,
}) => showDialog<Uint8List>(
  context: context,
  builder: (_) => _PassphraseDialog(
    title: title,
    action: action,
    run: run,
    obscure: obscure,
  ),
);

final class _PassphraseDialog extends HookWidget {
  final String title;
  final String action;
  final Uint8List Function(String passphrase) run;
  final bool obscure;

  const _PassphraseDialog({
    required this.title,
    required this.action,
    required this.run,
    required this.obscure,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = useTextEditingController();
    final error = useState<String?>(null);

    void submit() {
      if (controller.text.isEmpty) {
        return;
      }
      try {
        Navigator.pop(context, run(controller.text));
      } on ApiException {
        error.value = l10n.wrongPassword;
      }
    }

    return AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        obscureText: obscure,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.password,
          errorText: error.value,
        ),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: submit, child: Text(action)),
      ],
    );
  }
}
