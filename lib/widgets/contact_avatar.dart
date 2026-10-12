import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:flutter/material.dart';

final class ContactAvatar extends StatelessWidget {
  final Contact contact;

  const ContactAvatar({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: contact.online ? l10n.online : l10n.offline,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleIdenticon(publicKey: contact.publicKey),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: contact.online ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
