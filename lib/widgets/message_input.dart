import 'dart:async';
import 'dart:math';

import 'package:btox/attachments/attachments.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/content.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/drafts.dart';
import 'package:btox/widgets/attachment_selector.dart';
import 'package:btox/widgets/chat_location_bubble.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

const _logger = Logger(['MessageInput']);

const _kPanelHeight = 280.0;
// How much of a short screen, as in landscape, a panel takes at most, so
// the chat stays in sight.
const _kMaxPanelShare = 0.5;
const _draftSize = 64.0;
const _draftPadding = 4.0;
const _kKeyboardTimeout = Duration(milliseconds: 500);

// Restarts Android's keyboard, as its own text fields do when their text is
// replaced, so it goes back to letters.
const _keyboard = MethodChannel('btox/keyboard');

enum _EditMode { text, attachment, emoji }

final class MessageInput extends HookWidget {
  final String hintText;
  final ChatDraft draft;
  final bool recentEmojis;
  // Tox only sends files to friends.
  final bool files;

  /// Whether [Content] was sent. What wasn't comes back to the draft.
  final Future<bool> Function(Content) onSend;

  const MessageInput({
    super.key,
    required this.hintText,
    required this.draft,
    required this.recentEmojis,
    this.files = true,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final messageInputController = draft.text;
    final messageInputFocus = useFocusNode();
    // Coming back from a page over the chat would give the field its focus
    // again, which opens a phone's keyboard: there it takes none while
    // covered.
    final covered = switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS => ModalRoute.of(context)?.secondaryAnimation,
      _ => null,
    };
    useEffect(() {
      void cover(AnimationStatus status) =>
          messageInputFocus.canRequestFocus = status.isDismissed;
      covered?.addStatusListener(cover);
      return () => covered?.removeStatusListener(cover);
    }, [covered]);
    final hasText = useValueListenable(messageInputController).text
        .trim()
        .isNotEmpty;
    final drafts = draft.attachments;
    useValueListenable(drafts);
    final replyingTo = useValueListenable(draft.replyingTo);
    final editMode = useState(_EditMode.text);
    final theme = Theme.of(context);
    final canSend = hasText || drafts.value.isNotEmpty;

    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final systemBar = MediaQuery.viewPaddingOf(context).bottom;
    // A panel takes the keyboard's place, so the input stays where it was.
    final panelHeight = _useKeyboardHeight(inset) ?? _kPanelHeight;

    // The panel's space, held while the keyboard comes to take it, until it
    // stops rising or never starts.
    final held = useState<double?>(null);
    useEffect(
      () => held.value == null
          ? null
          : Timer(_kKeyboardTimeout, () => held.value = null).cancel,
      [held.value, inset],
    );

    void showKeyboard() {
      editMode.value = _EditMode.text;
      held.value = panelHeight;
      messageInputFocus.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    }

    void reset() {
      messageInputController.text = '';
      if (AnyPlatform.instance.isAndroid) {
        _logger.unawaited(
          'restart the keyboard',
          _keyboard.invokeMethod<void>('restart'),
        );
      }
      drafts.value = const [];
      draft.replyingTo.value = null;
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

    Future<void> send() async {
      final text = messageInputController.text.trim();
      final attachments = drafts.value;
      final reply = replyingTo;
      if (text.isEmpty && attachments.isEmpty) {
        return;
      }
      // A reply starts with what it answers, quoted as Tox clients quote.
      final quote = switch (reply) {
        final reply? => quoted(reply.plainText),
        null => null,
      };
      final quoteContent = quote == null
          ? null
          : TextContent(text: text.isEmpty ? quote : '$quote\n$text');
      final contents = [
        ?quoteContent,
        ...attachments,
        if (quote == null && text.isNotEmpty) TextContent(text: text),
      ];
      reset();
      for (final (i, content) in contents.indexed) {
        if (!await onSend(content)) {
          final unsent = contents.sublist(i);
          if (text.isNotEmpty && unsent.any((c) => c is TextContent)) {
            // Ahead of anything written since.
            final since = messageInputController.text;
            messageInputController.text = since.isEmpty
                ? text
                : '$text\n$since';
          }
          if (unsent.contains(quoteContent)) {
            draft.replyingTo.value = reply;
          }
          drafts.value = [
            ...attachments.where(unsent.contains),
            ...drafts.value,
          ];
          return;
        }
      }
    }

    // Replying goes on to writing the reply, as it's chosen, not in a build.
    final showsKeyboard = useRef(showKeyboard)..value = showKeyboard;
    useEffect(() {
      void replying() {
        if (draft.replyingTo.value != null) {
          showsKeyboard.value();
        }
      }

      draft.replyingTo.addListener(replying);
      return () => draft.replyingTo.removeListener(replying);
    }, [draft]);

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
        files: files,
        onSelected: (attachments) {
          drafts.value = [...drafts.value, ...attachments];
          editMode.value = _EditMode.text;
        },
      ),
    };
    final bottom = max(
      panel != null ? panelHeight : held.value ?? 0,
      max(inset, systemBar),
    );

    return PopScope(
      canPop: panel == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          editMode.value = _EditMode.text;
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // On a short screen, what's above the field scrolls.
            Flexible(
              child: SingleChildScrollView(
                reverse: true,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
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
                              Icon(
                                Icons.reply,
                                color: theme.colorScheme.primary,
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 8,
                                  ),
                                  child: Text(
                                    AppLocalizations.of(context)!
                                        .re(reply.plainText),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 3,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: AppLocalizations.of(context)!
                                    .cancelReply,
                                onPressed: () => draft.replyingTo.value = null,
                                icon: const Icon(Icons.close),
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
                          height: _draftSize + 2 * _draftPadding,
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
                                  keyboardType: TextInputType.multiline,
                                  textCapitalization:
                                      TextCapitalization.sentences,
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
                                    // Room for the emoji button.
                                    contentPadding:
                                        const EdgeInsetsDirectional.only(
                                          start: 48,
                                          end: 24,
                                          top: 12,
                                          bottom: 12,
                                        ),
                                    fillColor: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    filled: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(24),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: AppLocalizations.of(context)!.emoji,
                                  icon: const Icon(
                                    Icons.emoji_emotions_outlined,
                                  ),
                                  onPressed: () => toggle(_EditMode.emoji),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filled(
                            tooltip: canSend
                                ? AppLocalizations.of(context)!.send
                                : AppLocalizations.of(context)!.attach,
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
              ),
            ),
            SizedBox(
              height: panel == null
                  ? bottom
                  : min(bottom, constraints.maxHeight * _kMaxPanelShare),
              child: panel == null
                  ? null
                  : Padding(
                      padding: EdgeInsets.only(bottom: systemBar),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: panel,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The open keyboard's height, once it has been seen: the largest inset since
/// it last closed, as it's less while the keyboard moves.
double? _useKeyboardHeight(double inset) {
  final open = useRef(0.0);
  final height = useRef<double?>(null);
  open.value = inset == 0 ? 0 : max(open.value, inset);
  if (open.value > 0) {
    height.value = open.value;
  }
  return height.value;
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
        imagePreview(
              path,
              // Cropped to a square, so wide images need twice the size.
              size: (2 * _draftSize * MediaQuery.devicePixelRatioOf(context))
                  .round(),
            ) ??
            iconLabel(Icons.insert_drive_file, name),
      LocationContent(:final latitude, :final longitude) => LocationMap(
        latitude: latitude,
        longitude: longitude,
      ),
      _ => iconLabel(Icons.attach_file, content.plainText),
    };
    return Padding(
      padding: const EdgeInsets.all(_draftPadding),
      child: Stack(
        children: [
          Container(
            width: _draftSize,
            height: _draftSize,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: preview,
          ),
          PositionedDirectional(
            top: 0,
            end: 0,
            child: IconButton(
              tooltip: AppLocalizations.of(context)!.removeAttachment,
              onPressed: onRemove,
              iconSize: 20,
              style: IconButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.cancel),
            ),
          ),
        ],
      ),
    );
  }
}
