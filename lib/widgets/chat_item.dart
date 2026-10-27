import 'dart:math';

import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/pages/message_info_page.dart';
import 'package:btox/widgets/bubble_footer.dart';
import 'package:btox/widgets/call_entry.dart';
import 'package:btox/widgets/chat_context_menu.dart';
import 'package:btox/widgets/chat_file_bubble.dart';
import 'package:btox/widgets/chat_location_bubble.dart';
import 'package:btox/widgets/chat_text.dart';
import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:btox/widgets/dates.dart';
import 'package:btox/widgets/sender_name.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// When the bubble is dragged past this fraction of the max bubble drag, the
/// reply icon will grow, indicating that the message will be replied to.
const _kBubbleDragActivation = 0.8;

/// The maximum drag distance for the bubble (in either direction).
const _kMaxBubbleDrag = 48.0;

const _kBubbleMargin = EdgeInsets.symmetric(horizontal: 16, vertical: 1);

/// Messages an author sends this close together show as one run.
const _kRunGap = Duration(minutes: 3);

/// Space above a run, beyond the margin of each bubble in it.
const _kRunSpacing = 6.0;

const _kSelectedOpacity = 0.12;

/// Whether [below] continues the run of [above]. In group chats, authors are
/// told apart by their keys, or by name where a bot relayed their messages.
bool inRun(ChatEntry above, ChatEntry below) =>
    !above.notice &&
    !below.notice &&
    above.mine == below.mine &&
    (above.from != null || below.from != null
        ? above.from == below.from
        : above.sender == below.sender) &&
    localDay(above.timestamp) == localDay(below.timestamp) &&
    below.timestamp.difference(above.timestamp).abs() < _kRunGap;

Color _bubbleColor(bool isSender, ThemeData theme) {
  return isSender
      ? theme.colorScheme.primaryContainer
      : theme.colorScheme.surfaceContainerHighest;
}

TextStyle _textStyle(bool isSender, ThemeData theme) {
  return theme.textTheme.bodyLarge!.copyWith(
    color: isSender
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface,
  );
}

final class ChatItem extends HookWidget {
  final ChatRef chat;
  final ChatEntry entry;
  // Of a run with the messages above and below: see [inRun].
  final bool joinsAbove;
  final bool joinsBelow;
  // Null while no messages are selected.
  final bool? selected;
  final void Function()? onReply;
  final void Function()? onSelect;
  final void Function()? onForward;
  // Null for a message without text.
  final void Function()? onCopy;

  const ChatItem({
    super.key,
    required this.chat,
    required this.entry,
    this.joinsAbove = false,
    this.joinsBelow = false,
    this.selected,
    this.onReply,
    this.onSelect,
    this.onForward,
    this.onCopy,
  });

  bool get isSender => entry.mine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleDrag = useState(0.0);
    final showTime = useState(false);

    final dragValue = isSender
        ? max(0.0, -bubbleDrag.value)
        : max(0.0, bubbleDrag.value);
    final replyIconExtraSize =
        dragValue > _kMaxBubbleDrag * _kBubbleDragActivation ? 8.0 : 0.0;

    final sender = entry.sender;
    final corners = bubbleCorners(
      mine: isSender,
      joinsAbove: joinsAbove,
      joinsBelow: joinsBelow,
    );
    final header = sender != null && !isSender && !joinsAbove
        ? SenderName(sender, author: entry.from)
        : null;
    // The last bubble of a run says when it was sent, and how far ours got,
    // as does one tapped. Others say it only while ours is on its way.
    final saysWhen = !joinsBelow || showTime.value;
    final state = entry.delivery;
    final color = _bubbleColor(isSender, theme);
    final textStyle = _textStyle(isSender, theme);
    final footer = saysWhen || state == ChatContentState.pending
        ? BubbleFooter(
            time: saysWhen ? timeText(context, entry.timestamp) : null,
            state: state,
            color: textStyle.color!.withValues(alpha: 0.7),
          )
        : null;
    void toggleTime() => showTime.value = !showTime.value;
    final bubble = switch (entry.content) {
      FileContent() => ChatFileBubble(
        chat: chat,
        entry: entry,
        color: color,
        textStyle: textStyle,
        corners: corners,
        header: header,
        footer: footer,
      ),
      LocationContent(:final latitude, :final longitude) => ChatLocationBubble(
        profile: chat.profile,
        latitude: latitude,
        longitude: longitude,
        color: color,
        corners: corners,
        header: header,
        footer: footer,
        onTap: (_, _) => toggleTime(),
      ),
      final content => ChatText(
        text: content.plainText,
        color: color,
        textStyle: textStyle,
        corners: corners,
        header: header,
        footer: footer,
      ),
    };
    final placed = Padding(
      padding: _kBubbleMargin.add(
        isSender
            ? EdgeInsets.only(right: dragValue)
            : EdgeInsets.only(left: dragValue),
      ),
      child: Align(
        alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          // Room on the other side for dragging it to reply.
          constraints: BoxConstraints(
            maxWidth:
                MediaQuery.sizeOf(context).width -
                _kBubbleMargin.horizontal -
                _kMaxBubbleDrag,
          ),
          child: bubble,
        ),
      ),
    );
    if (selected case final selected?) {
      return Column(
        children: [
          if (!joinsAbove) const SizedBox(height: _kRunSpacing),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            onLongPress: onSelect,
            child: ColoredBox(
              color: selected
                  ? theme.colorScheme.primary.withValues(
                      alpha: _kSelectedOpacity,
                    )
                  : Colors.transparent,
              child: Row(
                children: [
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: _kBubbleMargin.left,
                    ),
                    child: Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Expanded(child: IgnorePointer(child: placed)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        if (!joinsAbove) const SizedBox(height: _kRunSpacing),
        Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _kBubbleMargin.left + 8 - replyIconExtraSize / 2,
                ),
                child: Align(
                  alignment: isSender
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  // Transparent to opaque depending on drag state.
                  child: Opacity(
                    opacity: dragValue / _kMaxBubbleDrag,
                    child: Icon(Icons.reply, size: 24 + replyIconExtraSize),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                final delta = details.primaryDelta;
                if (delta == null) {
                  return;
                }
                bubbleDrag.value = clampDouble(
                  bubbleDrag.value + delta,
                  -_kMaxBubbleDrag,
                  _kMaxBubbleDrag,
                );
              },
              onHorizontalDragEnd: (details) {
                if (dragValue / _kMaxBubbleDrag > _kBubbleDragActivation) {
                  onReply?.call();
                }
                bubbleDrag.value = 0;
              },
              onHorizontalDragCancel: () => bubbleDrag.value = 0,
              onTap: toggleTime,
              onLongPressStart: (details) async {
                final messenger = ScaffoldMessenger.of(context);
                final notImplemented = AppLocalizations.of(context)!
                    .notImplemented;
                void notYet() => messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(notImplemented)));
                await ChatContextMenu.show(
                  context,
                  details.globalPosition,
                  onReply: () => onReply?.call(),
                  onForward: onForward,
                  onCopy: onCopy,
                  onSelect: () => onSelect?.call(),
                  onInfo: () => Navigator.push(
                    context,
                    MessageInfoPage.route(chat, entry),
                  ),
                  onDelete: notYet,
                );
              },
              child: placed,
            ),
          ],
        ),
      ],
    );
  }
}

final class ChatNotice extends StatelessWidget {
  final ChatEntry entry;

  const ChatNotice({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    if (entry.content case final CallContent call) {
      return ChatCallNotice(call: call);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Center(
        child: Text(
          entry.content.plainText,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

/// Above the messages of a [day].
final class ChatDay extends StatelessWidget {
  final DateTime day;

  const ChatDay({super.key, required this.day});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    child: Center(
      child: Text(
        dayText(context, day),
        style: Theme.of(context).textTheme.labelMedium,
      ),
    ),
  );
}
