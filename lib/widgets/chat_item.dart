import 'dart:math';

import 'package:btox/db/database.dart';
import 'package:btox/widgets/chat_content.dart';
import 'package:btox/widgets/chat_context_menu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// When the bubble is dragged past this fraction of the max bubble drag, the
/// reply icon will grow, indicating that the message will be replied to.
const _kBubbleDragActivation = 0.8;

/// The maximum drag distance for the bubble (in either direction).
const _kMaxBubbleDrag = 48.0;

Color _bubbleColor(bool isSender, ThemeData theme) {
  return isSender ? Colors.blue[900]! : theme.splashColor;
}

final class ChatItem extends HookWidget {
  final Message message;
  final bool isSender;
  final void Function()? onReply;

  const ChatItem({
    super.key,
    required this.message,
    required this.isSender,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final bubbleDrag = useState(0.0);
    final showTime = useState(false);

    final dragValue =
        isSender ? max(0.0, -bubbleDrag.value) : max(0.0, bubbleDrag.value);
    final replyIconExtraSize =
        dragValue > _kMaxBubbleDrag * _kBubbleDragActivation ? 8.0 : 0.0;

    return Column(
      children: [
        Stack(
          children: [
            _align(Padding(
              padding: EdgeInsets.all(8.0 - replyIconExtraSize / 2),
              // Transparent to opaque depending on drag state.
              child: Opacity(
                opacity: dragValue / _kMaxBubbleDrag,
                child: Icon(
                  Icons.reply,
                  size: 24 + replyIconExtraSize,
                ),
              ),
            )),
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
              onTap: () => showTime.value = !showTime.value,
              onLongPressStart: (details) async {
                await ChatContextMenu.show(
                  context,
                  details.globalPosition,
                  onReply: () {
                    onReply?.call();
                  },
                  onForward: () {},
                  onCopy: () {
                    Clipboard.setData(
                        ClipboardData(text: message.content.toString()));
                  },
                  onSelect: () {},
                  onInfo: () {},
                  onDelete: () {},
                );
              },
              child: Padding(
                padding: isSender
                    ? EdgeInsets.only(right: dragValue)
                    : EdgeInsets.only(left: dragValue),
                child: ChatContent(
                  content: message.content,
                  extraWidth: _kMaxBubbleDrag,
                  color: _bubbleColor(isSender, Theme.of(context)),
                  direction: isSender
                      ? ChatContentDirection.sent
                      : ChatContentDirection.received,
                  state:
                      isSender ? ChatContentState.seen : ChatContentState.none,
                  textStyle: Theme.of(context).textTheme.bodyLarge!,
                ),
              ),
            ),
          ],
        ),
        if (showTime.value)
          _align(
            Text(
              message.timestamp
                  .toLocal()
                  .toIso8601String()
                  .split('T')
                  .last
                  .split('.')
                  .first,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _align(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: isSender ? Alignment.topRight : Alignment.topLeft,
        child: child,
      ),
    );
  }
}
