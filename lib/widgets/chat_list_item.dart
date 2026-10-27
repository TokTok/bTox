import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/widgets/chat_avatar.dart';
import 'package:btox/widgets/dates.dart';
import 'package:flutter/material.dart';

final class ChatListItem extends StatelessWidget {
  final ChatSummary chat;
  final void Function(ChatSummary) onTap;
  final void Function(ChatSummary)? onLongPress;

  const ChatListItem({
    super.key,
    required this.chat,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = chat.last;
    final draft = chat.draft;
    final unread = chat.unread > 0;
    // A muted chat's unread messages show, but don't call for attention.
    final muted = chat.mute != null;
    return ListTile(
      leading: ChatAvatar(bytes: chat.key, online: chat.online),
      title: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              chat.name ?? AppLocalizations.of(context)!.defaultContactName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: unread
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
          ),
          if (muted)
            Icon(
              Icons.notifications_off_outlined,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          if (last != null)
            Text(
              recentText(context, last.timestamp),
              style: theme.textTheme.bodySmall?.copyWith(
                color: unread && !muted ? theme.colorScheme.primary : null,
              ),
            ),
        ],
      ),
      subtitle: draft == null && last == null
          ? null
          : Row(
              spacing: 8,
              children: [
                Expanded(
                  child: draft != null
                      ? _Preview(
                          draft,
                          label: TextSpan(
                            text:
                                '${AppLocalizations.of(context)!.draftLabel} ',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        )
                      : _Preview(
                          last!.content,
                          label: switch (last.sender) {
                            final sender? => TextSpan(text: '$sender: '),
                            null => null,
                          },
                          notice: last.notice,
                        ),
                ),
                if (unread)
                  Badge(
                    label: Text('${chat.unread}'),
                    backgroundColor: muted
                        ? theme.colorScheme.outline
                        : theme.colorScheme.primary,
                    textColor: muted
                        ? theme.colorScheme.surface
                        : theme.colorScheme.onPrimary,
                  ),
              ],
            ),
      onTap: () => onTap(chat),
      onLongPress: switch (onLongPress) {
        final longPress? => () => longPress(chat),
        null => null,
      },
    );
  }
}

/// A chat's latest entry or draft.
final class _Preview extends StatelessWidget {
  final Content content;
  // Before it: who wrote it, or that it is a draft.
  final InlineSpan? label;
  final bool notice;

  const _Preview(this.content, {this.label, this.notice = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    InlineSpan icon(IconData icon) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Icon(icon, size: 16),
      ),
    );
    final (leading, text) = switch (content) {
      FileContent(:final name) => (icon(Icons.attach_file), name),
      LocationContent() => (icon(Icons.location_on), l10n.locationMessage),
      TextContent(:final text) => (null, text),
    };
    return Text.rich(
      TextSpan(
        children: [
          ?label,
          ?leading,
          TextSpan(text: text),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: notice ? const TextStyle(fontStyle: FontStyle.italic) : null,
    );
  }
}
