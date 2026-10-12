import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:flutter/material.dart';

final class FriendRequestListItem extends StatelessWidget {
  final FriendRequest request;
  final void Function(FriendRequest) onAccept;
  final void Function(FriendRequest) onReject;

  const FriendRequestListItem({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleIdenticon(publicKey: request.publicKey),
      title: Text(
        request.message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        request.publicKey.toJson(),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: AppLocalizations.of(context)!.acceptFriendRequest,
            onPressed: () => onAccept(request),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: AppLocalizations.of(context)!.rejectFriendRequest,
            onPressed: () => onReject(request),
          ),
        ],
      ),
    );
  }
}
