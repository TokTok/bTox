import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/sync/account.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:flutter/material.dart';

final class ChatInviteListItem extends StatelessWidget {
  final AccountInvite invite;
  final String text;
  final void Function({required bool join}) onAnswer;

  const ChatInviteListItem({
    super.key,
    required this.invite,
    required this.text,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final failed = invite.status == InviteStatus.failed;
    // A chat that turned the account away has spent the invite.
    final spent = failed && invite.chat != null;
    return ListTile(
      leading: CircleIdenticon(bytes: invite.from),
      title: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: switch (invite.status) {
        InviteStatus.joining => Text(l10n.joiningInvite),
        InviteStatus.failed => Text(switch ((invite.needsPassword, spent)) {
          (true, _) => l10n.inviteNeedsPassword,
          (_, true) => l10n.inviteSpent,
          _ => l10n.inviteFailed,
        }),
        _ => null,
      },
      trailing: invite.status == InviteStatus.joining
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!spent)
                  IconButton(
                    icon: Icon(failed ? Icons.refresh : Icons.check),
                    tooltip: failed ? l10n.retryInvite : l10n.joinInvite,
                    onPressed: () => onAnswer(join: true),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.declineInvite,
                  onPressed: () => onAnswer(join: false),
                ),
              ],
            ),
    );
  }
}
