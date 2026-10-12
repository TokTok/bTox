import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

final class ToxIdView extends StatelessWidget {
  final ToxAddress address;

  const ToxIdView({super.key, required this.address});

  @override
  Widget build(BuildContext context) {
    final toxId = address.toJson();
    return Column(
      children: [
        ListTile(
          title: Text(AppLocalizations.of(context)!.toxId),
          subtitle: SelectableText(toxId),
          trailing: IconButton(
            icon: const Icon(Icons.copy),
            tooltip: AppLocalizations.of(context)!.copyToxId,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: toxId));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context)!.toxIdCopied),
                ),
              );
            },
          ),
        ),
        // Same as qTox, so its users can scan it.
        QrImageView(
          data: 'tox:$toxId',
          size: 200,
          backgroundColor: Colors.white,
        ),
      ],
    );
  }
}
