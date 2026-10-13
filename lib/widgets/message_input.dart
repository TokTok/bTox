import 'package:btox/attachments/attachments.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/content.dart';
import 'package:btox/widgets/attachment_selector.dart';
import 'package:btox/widgets/chat_location_bubble.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

const _logger = Logger(['MessageInput']);

enum _EditMode { text, attachment, emoji }

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
    final hasText = useValueListenable(messageInputController).text.isNotEmpty;
    final drafts = useState(const <Content>[]);
    final editMode = useState(_EditMode.text);
    final theme = Theme.of(context);
    final canSend = hasText || drafts.value.isNotEmpty;

    void reset() {
      messageInputController.text = '';
      drafts.value = const [];
      messageInputFocus.requestFocus();
      editMode.value = _EditMode.text;
    }

    void toggle(_EditMode mode) =>
        editMode.value = editMode.value == mode ? _EditMode.text : mode;

    void send() {
      final text = messageInputController.text;
      if (text.isEmpty && drafts.value.isEmpty) {
        return;
      }
      drafts.value.forEach(onSend);
      if (text.isNotEmpty) {
        onSend(TextContent(text: text));
      }
      reset();
    }

    void remove(Content draft) {
      drafts.value = [...drafts.value]..remove(draft);
      if (draft case FileContent(:final path)) {
        deleteAttachment(path)
            .catchError((Object e) => _logger.w('Failed to delete $path: $e'));
      }
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (replyingTo case final reply?) ...[
          Container(
            color: theme.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.reply, color: buttonColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      AppLocalizations.of(context)!.re(reply.plainText),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 3,
                    ),
                  ),
                ),
                InkWell(
                  onTap: onTapCloseReply,
                  child: Icon(Icons.close, color: theme.primaryColorLight),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Divider(height: 1),
          ),
        ],
        if (drafts.value.isNotEmpty)
          SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                for (final draft in drafts.value)
                  _Draft(draft, onRemove: () => remove(draft)),
              ],
            ),
          ),
        if (editMode.value == _EditMode.emoji)
          EmojiPicker(
            key: const Key('emojiPicker'),
            textEditingController: messageInputController,
            config: Config(
              categoryViewConfig: CategoryViewConfig(
                backgroundColor: theme.scaffoldBackgroundColor,
                recentTabBehavior: recentEmojis
                    ? RecentTabBehavior.RECENT
                    : RecentTabBehavior.NONE,
              ),
              emojiViewConfig: EmojiViewConfig(
                backgroundColor: theme.scaffoldBackgroundColor,
                emojiSizeMax: 24,
              ),
              bottomActionBarConfig: BottomActionBarConfig(
                backgroundColor: theme.scaffoldBackgroundColor,
                buttonIconColor: theme.iconTheme.color!,
              ),
              searchViewConfig: SearchViewConfig(
                backgroundColor: theme.scaffoldBackgroundColor,
                buttonIconColor: theme.iconTheme.color!,
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
                            _logger.d(
                              'Content inserted: ${content.mimeType}, '
                              '${content.uri}, ${content.data?.length} bytes',
                            );
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
                      fillColor: theme.splashColor,
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
                    onPressed: () => toggle(_EditMode.emoji),
                  ),
                ],
              ),
            ),
            IconButton(
              color: buttonColor,
              icon: Icon(canSend ? Icons.send : Icons.add_circle),
              iconSize: 42,
              padding: EdgeInsets.zero,
              onPressed: canSend ? send : () => toggle(_EditMode.attachment),
            ),
          ],
        ),
        if (editMode.value == _EditMode.attachment)
          AttachmentSelector(
            onSelected: (attachments) {
              drafts.value = [...drafts.value, ...attachments];
              editMode.value = _EditMode.text;
            },
          ),
      ],
    );
  }
}

/// An attachment waiting to be sent.
final class _Draft extends StatelessWidget {
  final Content content;
  final void Function() onRemove;

  const _Draft(this.content, {required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget iconLabel(IconData icon, String label) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall,
        ),
      ],
    );

    final preview = switch (content) {
      FileContent(:final path, :final name) =>
        imagePreview(path) ?? iconLabel(Icons.insert_drive_file, name),
      LocationContent(:final latitude, :final longitude) => LocationMap(
        latitude: latitude,
        longitude: longitude,
      ),
      _ => iconLabel(Icons.attach_file, content.plainText),
    };
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Stack(
        children: [
          Container(
            width: 64,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.splashColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: preview,
          ),
          Positioned(
            top: 0,
            right: 0,
            child: InkWell(
              onTap: onRemove,
              child: const Icon(Icons.cancel, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
