import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/widgets/contact_avatar.dart';
import 'package:flutter/material.dart';

final class ContactListItem extends StatelessWidget {
  final Contact contact;
  final Function(Contact) onTap;
  final Function(Contact)? onLongPress;

  const ContactListItem({
    super.key,
    required this.contact,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        contact.name ?? AppLocalizations.of(context)!.defaultContactName,
      ),
      subtitle: Text(
        contact.publicKey.toJson(),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ContactAvatar(contact: contact),
      onTap: () => onTap(contact),
      onLongPress: () => onLongPress?.call(contact),
    );
  }
}
