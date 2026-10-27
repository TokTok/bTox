import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Asks for a passphrase until [run] accepts it. Where [optional], it may be
/// empty.
Future<T?> showPassphraseDialog<T>(
  BuildContext context, {
  required String title,
  required String action,
  required T Function(String passphrase) run,
  bool obscure = true,
  bool optional = false,
  String? helper,
}) => showDialog<T>(
  context: context,
  builder: (_) => _PassphraseDialog<T>(
    title: title,
    action: action,
    run: run,
    obscure: obscure,
    optional: optional,
    helper: helper,
  ),
);

final class _PassphraseDialog<T> extends HookWidget {
  final String title;
  final String action;
  final T Function(String passphrase) run;
  final bool obscure;
  final bool optional;
  final String? helper;

  const _PassphraseDialog({
    required this.title,
    required this.action,
    required this.run,
    required this.obscure,
    required this.optional,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = useTextEditingController();
    final error = useState<String?>(null);

    void submit() {
      if (controller.text.isEmpty && !optional) {
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
          helperText: helper,
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
