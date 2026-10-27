import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// Asks whether to go ahead with [action].
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => _Confirm(
        title: title,
        content: Text(message),
        action: action,
        result: () => true,
      ),
    ) ??
    false;

/// Asks whether to go ahead with [action], offering [option], ticked at
/// first. Null if not, else whether [option] stayed ticked.
Future<bool?> confirmWithOption(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  required String option,
}) {
  var ticked = true;
  return showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => _Confirm(
        title: title,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            CheckboxListTile(
              value: ticked,
              onChanged: (value) => setState(() => ticked = value!),
              title: Text(option),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        action: action,
        result: () => ticked,
      ),
    ),
  );
}

final class _Confirm extends StatelessWidget {
  final String title;
  final Widget content;
  final String action;
  final bool Function() result;

  const _Confirm({
    required this.title,
    required this.content,
    required this.action,
    required this.result,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(title),
    content: content,
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(AppLocalizations.of(context)!.cancel),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, result()),
        child: Text(action),
      ),
    ],
  );
}
