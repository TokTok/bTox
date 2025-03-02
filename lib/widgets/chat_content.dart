import 'package:btox/models/content.dart';
import 'package:btox/widgets/chat_text.dart';
import 'package:flutter/material.dart';

const double _kStateIconBottom = 4;
const double _kStateIconRight = 6;
const double _kStateIconSize = 18;

final class ChatContent extends StatelessWidget {
  final Content content;
  final Color color;
  final TextStyle textStyle;
  final double bubbleRadius;
  final ChatContentDirection direction;
  final ChatContentState state;
  final EdgeInsets padding;
  final double extraWidth;

  const ChatContent({
    super.key,
    required this.content,
    required this.color,
    required this.textStyle,
    this.bubbleRadius = 20,
    this.direction = ChatContentDirection.sent,
    this.state = ChatContentState.none,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    this.extraWidth = 48,
  });

  @override
  Widget build(BuildContext context) {
    final Positioned? stateIcon = switch (state) {
      ChatContentState.none => null,
      ChatContentState.sent => const Positioned(
          bottom: _kStateIconBottom,
          right: _kStateIconRight,
          child: Icon(
            Icons.done,
            size: _kStateIconSize,
            color: Color(0xFF97AD8E),
          ),
        ),
      ChatContentState.delivered => const Positioned(
          bottom: _kStateIconBottom,
          right: _kStateIconRight,
          child: Icon(
            Icons.done_all,
            size: _kStateIconSize,
            color: Color(0xFF97AD8E),
          ),
        ),
      ChatContentState.seen => const Positioned(
          bottom: _kStateIconBottom,
          right: _kStateIconRight,
          child: Icon(
            Icons.done_all,
            size: _kStateIconSize,
            color: Color(0xFF92DEDA),
          ),
        ),
    };

    return Row(
      mainAxisAlignment: switch (direction) {
        ChatContentDirection.sent => MainAxisAlignment.end,
        ChatContentDirection.received => MainAxisAlignment.start,
      },
      children: [
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - extraWidth,
          ),
          padding: padding,
          child: _bubble(stateIcon),
        ),
      ],
    );
  }

  Widget _bubble(Positioned? stateIcon) {
    switch (content) {
      case TextContent(text: var text):
        return ChatText(
          stateIcon: stateIcon,
          text: text,
          color: color,
          textStyle: textStyle,
          bubbleRadius: bubbleRadius,
        );
      default:
        return ChatText(
          stateIcon: stateIcon,
          text: content.toString(),
          color: color,
          textStyle: textStyle,
          bubbleRadius: bubbleRadius,
        );
    }
  }
}

enum ChatContentDirection { sent, received }

enum ChatContentState { none, sent, delivered, seen }
