import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Asks which of [accounts] (nicknames by key) to use, all by default.
Future<Set<T>?> showAccountPicker<T>(
  BuildContext context, {
  required String title,
  required String action,
  required Map<T, String> accounts,
}) => showDialog<Set<T>>(
  context: context,
  builder: (_) =>
      _AccountPicker(title: title, action: action, accounts: accounts),
);

final class _AccountPicker<T> extends HookWidget {
  final String title;
  final String action;
  final Map<T, String> accounts;

  const _AccountPicker({
    required this.title,
    required this.action,
    required this.accounts,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selected = useState({...accounts.keys});

    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final MapEntry(:key, :value) in accounts.entries)
            CheckboxListTile(
              title: Text(value),
              value: selected.value.contains(key),
              onChanged: (checked) => selected.value = checked!
                  ? {...selected.value, key}
                  : ({...selected.value}..remove(key)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: selected.value.isEmpty
              ? null
              : () => Navigator.pop(context, selected.value),
          child: Text(action),
        ),
      ],
    );
  }
}
