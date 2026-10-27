import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:flutter/material.dart';

final class FriendRequestListItem extends StatelessWidget {
  final PublicKey publicKey;
  final String message;
  final void Function() onAccept;
  final void Function() onReject;

  const FriendRequestListItem({
    super.key,
    required this.publicKey,
    required this.message,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleIdenticon(bytes: publicKey),
      title: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(publicKey.toJson(), overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: AppLocalizations.of(context)!.acceptFriendRequest,
            onPressed: onAccept,
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: AppLocalizations.of(context)!.rejectFriendRequest,
            onPressed: onReject,
          ),
        ],
      ),
    );
  }
}
