import 'package:btox/widgets/bubble_footer.dart';
import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:btox/widgets/chat_text_emoji.dart';
import 'package:emoji_regex/emoji_regex.dart';
import 'package:flutter/material.dart';

/// Matches one single emoji.
final _emojiRegex = RegExp('^(?:${emojiRegex().pattern})\$');

// Between the text and the footer on its last line.
const _kFooterGap = 8.0;

final class ChatText extends StatelessWidget {
  final BubbleFooter? footer;
  final String text;
  final Color color;
  final TextStyle textStyle;
  final BorderRadius corners;
  final Widget? header;

  const ChatText({
    super.key,
    this.footer,
    required this.text,
    required this.color,
    required this.textStyle,
    required this.corners,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final footer = this.footer;
    if (_emojiRegex.hasMatch(text)) {
      return IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?header,
            ChatTextEmoji(emoji: text, textStyle: textStyle),
            if (footer != null)
              Align(alignment: Alignment.centerRight, child: footer),
          ],
        ),
      );
    }
    return ChatTextBubble(
      corners: corners,
      color: color,
      header: header,
      footer: footer,
      contentHasFooterSpace: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text),
            if (footer != null)
              WidgetSpan(
                child: Padding(
                  padding: const EdgeInsets.only(left: _kFooterGap),
                  child: footerSpace(footer),
                ),
              ),
          ],
        ),
        style: textStyle,
      ),
    );
  }
}
