import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

final class ChatContextMenu {
  static Future<void> show(
    BuildContext context,
    Offset position, {
    required void Function() onReply,
    required void Function() onForward,
    // Null for a message without text.
    required void Function()? onCopy,
    required void Function() onSelect,
    required void Function() onInfo,
    required void Function() onDelete,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final chosen = await showMenu<void Function()>(
      context: context,
      // Taking focus would give it back to the message field on closing,
      // which then opens the keyboard.
      requestFocus: false,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        for (final (label, icon, action) in [
          (l10n.reply, Icons.reply_outlined, onReply),
          (l10n.forward, Icons.forward_outlined, onForward),
          if (onCopy != null) (l10n.copy, Icons.copy, onCopy),
          (l10n.select, Icons.check_circle_outline, onSelect),
          (l10n.info, Icons.info_outline, onInfo),
          (l10n.delete, Icons.delete_outline, onDelete),
        ])
          PopupMenuItem(
            value: action,
            child: Row(
              children: [Icon(icon), const SizedBox(width: 12), Text(label)],
            ),
          ),
      ],
    );
    chosen?.call();
  }
}
