import 'dart:async';
import 'dart:math';

import 'package:btox/attachments/attachments.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/content.dart';
import 'package:btox/widgets/attachment_selector.dart';
import 'package:btox/widgets/chat_location_bubble.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

const _logger = Logger(['MessageInput']);

const _kPanelHeight = 280.0;
const _kKeyboardTimeout = Duration(milliseconds: 500);

enum _EditMode { text, attachment, emoji }

final class MessageInput extends HookWidget {
  final String hintText;
  final Content? replyingTo;
  final bool recentEmojis;
  final void Function(Content) onSend;
  final void Function() onTapCloseReply;

  const MessageInput({
    super.key,
    required this.hintText,
    this.replyingTo,
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
    final keyboardHeight = useRef<double?>(null);
    final keyboardMax = useRef(0.0);
    final showingKeyboard = useState(false);
    final showingKeyboardTimer = useRef<Timer?>(null);
    useEffect(() {
      return () => showingKeyboardTimer.value?.cancel();
    }, const []);
    final theme = Theme.of(context);
    final canSend = hasText || drafts.value.isNotEmpty;

    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final systemBar = MediaQuery.viewPaddingOf(context).bottom;
    if (editMode.value == _EditMode.text && !showingKeyboard.value) {
      // The keyboard's height, not a point in its closing animation.
      keyboardMax.value = inset == 0 ? 0 : max(keyboardMax.value, inset);
      if (keyboardMax.value > 0) {
        keyboardHeight.value = keyboardMax.value;
      }
    }

    void showKeyboard() {
      editMode.value = _EditMode.text;
      // Hold the panel's space until the keyboard has taken it.
      if (keyboardHeight.value != null) {
        showingKeyboard.value = true;
        showingKeyboardTimer.value?.cancel();
        showingKeyboardTimer.value = Timer(
          _kKeyboardTimeout,
          () => showingKeyboard.value = false,
        );
      }
      messageInputFocus.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    }

    void reset() {
      messageInputController.text = '';
      drafts.value = const [];
      messageInputFocus.requestFocus();
      editMode.value = _EditMode.text;
    }

    void toggle(_EditMode mode) {
      if (editMode.value == mode) {
        showKeyboard();
      } else {
        editMode.value = mode;
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      }
    }

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

    final panel = switch (editMode.value) {
      _EditMode.text => null,
      _EditMode.emoji => EmojiPicker(
        key: const Key('emojiPicker'),
        textEditingController: messageInputController,
        config: Config(
          height: null,
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
      _EditMode.attachment => AttachmentSelector(
        onSelected: (attachments) {
          drafts.value = [...drafts.value, ...attachments];
          editMode.value = _EditMode.text;
        },
      ),
    };
    // A panel takes the keyboard's place, so the input stays where it was.
    final keyboard = max(inset, systemBar);
    final bottom = panel != null || showingKeyboard.value
        ? max(keyboardHeight.value ?? _kPanelHeight, keyboard)
        : keyboard;

    return PopScope(
      canPop: panel == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          editMode.value = _EditMode.text;
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyingTo case final reply?) ...[
                  Container(
                    color: theme.colorScheme.surfaceContainerHigh,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.reply, color: theme.colorScheme.primary),
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
                          child: const Icon(Icons.close),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Stack(
                        alignment: AlignmentDirectional.bottomStart,
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
                            onTap: () {
                              if (editMode.value != _EditMode.text) {
                                showKeyboard();
                              }
                            },
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
                                left: 48,
                                right: 24,
                                top: 12,
                                bottom: 12,
                              ),
                              fillColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.emoji_emotions_outlined),
                            onPressed: () => toggle(_EditMode.emoji),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      icon: Icon(canSend ? Icons.send : Icons.add),
                      onPressed: canSend
                          ? send
                          : () => toggle(_EditMode.attachment),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: bottom,
            child: panel == null
                ? null
                : Padding(
                    padding: EdgeInsets.only(bottom: systemBar),
                    child: Align(alignment: Alignment.topCenter, child: panel),
                  ),
          ),
        ],
      ),
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
              color: theme.colorScheme.surfaceContainerHighest,
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
