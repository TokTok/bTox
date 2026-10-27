import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/messages/links.dart';
import 'package:btox/widgets/bubble_footer.dart';
import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:btox/widgets/chat_text_emoji.dart';
import 'package:emoji_regex/emoji_regex.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:url_launcher/url_launcher.dart';

/// Matches one single emoji.
final _emojiRegex = RegExp('^(?:${emojiRegex().pattern})\$');

// Between the text and the footer on its last line.
const _kFooterGap = 8.0;

const _kLinkStyle = TextStyle(decoration: TextDecoration.underline);

Future<void> _open(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = AppLocalizations.of(context)!.openLinkFailed;
  if (!await launchUrl(uri)) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failed)));
  }
}

final class ChatText extends HookWidget {
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
    final links = useMemoized(() => findLinks(text), [text]);
    final recognizers = useMemoized(
      () => [
        for (final link in links)
          TapGestureRecognizer()..onTap = () => _open(context, link.uri),
      ],
      [links],
    );
    useEffect(
      () => () {
        for (final recognizer in recognizers) {
          recognizer.dispose();
        }
      },
      [recognizers],
    );
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
            for (final (i, link) in links.indexed) ...[
              TextSpan(
                text: text.substring(i == 0 ? 0 : links[i - 1].end, link.start),
              ),
              TextSpan(
                text: text.substring(link.start, link.end),
                style: _kLinkStyle,
                recognizer: recognizers[i],
              ),
            ],
            TextSpan(text: text.substring(links.lastOrNull?.end ?? 0)),
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
