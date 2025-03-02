import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/content.dart';
import 'package:btox/widgets/attachment_selector.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

const _logger = Logger(['MessageInput']);

enum _SendMode {
  text,
  attachment,
}

enum _EditMode {
  text,
  attachment,
  emoji,
}

final class MessageInput extends HookWidget {
  final String hintText;
  final Content? replyingTo;
  final Color buttonColor;
  final bool recentEmojis;
  final void Function(Content) onSend;
  final void Function() onTapCloseReply;

  const MessageInput({
    super.key,
    required this.hintText,
    this.replyingTo,
    this.buttonColor = Colors.blue,
    required this.recentEmojis,
    required this.onSend,
    required this.onTapCloseReply,
  });

  @override
  Widget build(BuildContext context) {
    final messageInputController = useTextEditingController();
    final messageInputFocus = useFocusNode();
    final sendMode = useState(_SendMode.attachment);
    final editMode = useState(_EditMode.text);

    useEffect(() {
      void updateSendMode() {
        sendMode.value = messageInputController.text.isEmpty
            ? _SendMode.attachment
            : _SendMode.text;
      }

      messageInputController.addListener(updateSendMode);
      return () => messageInputController.removeListener(updateSendMode);
    }, []);

    void send([String? message]) {
      message ??= messageInputController.text;
      if (message.isNotEmpty) {
        onSend(TextContent(text: message));
        messageInputController.text = '';
        messageInputFocus.requestFocus();
        editMode.value = _EditMode.text;
      }
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (replyingTo != null) ...[
          Container(
            color: Theme.of(context).primaryColor,
            padding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 16,
            ),
            child: Row(
              children: [
                Icon(Icons.reply, color: buttonColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      AppLocalizations.of(context)!.re(replyingTo.toString()),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 3,
                    ),
                  ),
                ),
                InkWell(
                  onTap: onTapCloseReply,
                  child: Icon(
                    Icons.close,
                    color: Theme.of(context).primaryColorLight,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Divider(height: 1),
          ),
        ],
        if (editMode.value == _EditMode.emoji)
          EmojiPicker(
            key: const Key('emojiPicker'),
            textEditingController: messageInputController,
            config: Config(
              categoryViewConfig: CategoryViewConfig(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                recentTabBehavior: recentEmojis
                    ? RecentTabBehavior.RECENT
                    : RecentTabBehavior.NONE,
              ),
              emojiViewConfig: EmojiViewConfig(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                emojiSizeMax: 24,
              ),
              bottomActionBarConfig: BottomActionBarConfig(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                buttonIconColor: Theme.of(context).iconTheme.color!,
              ),
              searchViewConfig: SearchViewConfig(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                buttonIconColor: Theme.of(context).iconTheme.color!,
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  TextField(
                    key: const Key('messageField'),
                    controller: messageInputController,
                    focusNode: messageInputFocus,
                    autofocus: true,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 3,
                    onTap: () => editMode.value = _EditMode.text,
                    onSubmitted: (_) => send(),
                    contentInsertionConfiguration:
                        ContentInsertionConfiguration(
                      onContentInserted: (content) {
                        _logger.d('Content inserted: ${content.mimeType}, '
                            '${content.uri}, ${content.data?.length} bytes');
                      },
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: hintText,
                      hintMaxLines: 1,
                      contentPadding: const EdgeInsets.only(
                        left: 36,
                        right: 24,
                        top: 8,
                        bottom: 8,
                      ),
                      fillColor: Theme.of(context).splashColor,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    iconSize: 24,
                    onPressed: () {
                      if (editMode.value == _EditMode.emoji) {
                        editMode.value = _EditMode.text;
                      } else {
                        editMode.value = _EditMode.emoji;
                      }
                    },
                  ),
                ],
              ),
            ),
            IconButton(
              color: buttonColor,
              icon: switch (sendMode.value) {
                _SendMode.text => const Icon(Icons.send),
                _SendMode.attachment => const Icon(Icons.add_circle),
              },
              iconSize: 42,
              padding: EdgeInsets.zero,
              onPressed: () {
                switch (sendMode.value) {
                  case _SendMode.text:
                    send();
                    break;
                  case _SendMode.attachment:
                    editMode.value = switch (editMode.value) {
                      _EditMode.attachment => _EditMode.text,
                      _ => _EditMode.attachment,
                    };
                    break;
                }
              },
            ),
          ],
        ),
        if (editMode.value == _EditMode.attachment)
          AttachmentSelector(
            onSelected: (attachments) {
              onSend(_contentAttachments(attachments));
              messageInputController.text = '';
              messageInputFocus.requestFocus();
              editMode.value = _EditMode.text;
            },
          ),
      ],
    );
  }
}

Content _contentAttachments(List<Content> attachments) {
  // TODO: Implement merging attachments.
  return attachments.single;
}
