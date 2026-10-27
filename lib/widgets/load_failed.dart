import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// In place of what couldn't be loaded. The error itself is logged by
/// [ProviderErrorLogger].
final class LoadFailed extends StatelessWidget {
  const LoadFailed({super.key});

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(AppLocalizations.of(context)!.loadFailed));
}
