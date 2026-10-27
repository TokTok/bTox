import 'package:btox/attachments/attachments.dart';
import 'package:btox/background_service.dart';
import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/pages/chat_details_page.dart';
import 'package:btox/pages/forward_page.dart';
import 'package:btox/providers/attachments.dart';
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/drafts.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/sync/setting.dart' show PictureEncoding;
import 'package:btox/widgets/chat_avatar.dart';
import 'package:btox/widgets/chat_item.dart';
import 'package:btox/widgets/copy_text.dart';
import 'package:btox/widgets/dates.dart';
import 'package:btox/widgets/load_failed.dart';
import 'package:btox/widgets/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['ChatPage']);

final class ChatPage extends HookConsumerWidget {
  final ChatRef chat;
  final bool recentEmojis;

  const ChatPage({super.key, required this.chat, this.recentEmojis = true});

  static Route<void> route(ChatRef chat) => MaterialPageRoute(
    settings: RouteSettings(arguments: chat),
    builder: (_) => ChatPage(chat: chat),
  );

  /// Opens [chat] over the chat list, unless it's open already: then what's
  /// being written in it stays as it is.
  static void open(NavigatorState navigator, ChatRef chat) {
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    if (top?.settings.arguments != chat) {
      navigator
        ..popUntil((route) => route.isFirst)
        ..push(route(chat));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(chatDraftProvider(chat));
    final messages = useScrollController();
    useEffect(() {
      reportOpenChat(chat);
      return () => reportOpenChat(null);
    }, [chat]);
    useOnAppLifecycleStateChange(
      (_, state) =>
          reportOpenChat(state == AppLifecycleState.resumed ? chat : null),
    );
    final summaryAsync = ref.watch(chatProvider(chat));
    final entriesAsync = ref.watch(chatEntriesProvider(chat));
    final selected = useState(const <EventId>{});
    final chosen = [
      for (final entry in entriesAsync.value ?? const <ChatEntry>[])
        if (selected.value.contains(entry.event)) entry,
    ];
    void unselect() => selected.value = const {};

    Future<void> forward(List<ChatEntry> entries) async {
      final messenger = ScaffoldMessenger.of(context);
      final l10n = AppLocalizations.of(context)!;
      final files = entries.any((e) => e.content is FileContent);
      // Read now, as the chat may close while the user is picking.
      final opened = ref.read(databaseProvider.future);
      final directory = files
          ? ref.read(attachmentsDirectoryProvider.future)
          : null;
      final to = await Navigator.push(
        context,
        ForwardPage.route(chat.profile, files: files),
      );
      if (to == null) {
        return;
      }
      try {
        final database = await opened;
        for (final entry in entries) {
          switch (entry.content) {
            case final FileContent file:
              await database.addFileSend(
                to.profile,
                to.graph,
                await copyAttachment((await directory)!, file),
              );
            case final content:
              if (messageTextOf(content) case final text?) {
                await database.addSend(to.profile, to.graph, text);
              }
          }
        }
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(l10n.messagesForwarded(entries.length))),
          );
      } on Exception catch (e) {
        _logger.e('Failed to forward to ${to.graph}: $e');
        messenger.showSnackBar(SnackBar(content: Text(l10n.sendFailed)));
      }
    }

    final lifecycle = useAppLifecycleState();
    final newest = ref.watch(newestEventsProvider(chat));
    useEffect(
      () {
        if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
          for (final MapEntry(key: graph, value: upTo) in newest.entries) {
            _logger.unawaited(
              'mark the chat read',
              ref
                  .read(databaseProvider.future)
                  .then((db) => db.setRead(chat.profile, graph, upTo)),
            );
          }
        }
        return null;
      },
      // By value, as each rebuild makes the map anew.
      [
        lifecycle,
        for (final MapEntry(:key, :value) in newest.entries) (key, value),
      ],
    );

    // Opening a chat, e.g. from a notification, switches to its account.
    useEffect(() {
      if (ref.read(currentProfileProvider)?.id != chat.profile) {
        _logger.unawaited(
          "switch to the chat's account",
          ref
              .read(databaseProvider.future)
              .then(
                (db) => db.updateAppSettings(
                  AppSettingsCompanion(currentProfile: Value(chat.profile)),
                ),
              ),
        );
      }
      return null;
    }, [chat.profile]);

    String? selfName;
    if (chosen.isNotEmpty) {
      final profile = ref.watch(profileProvider(chat.profile)).value;
      selfName =
          ref.watch(chatDetailsProvider(chat)).value?.selfName ??
          (profile == null
              ? null
              : ref.watch(profileIdentityProvider(profile)).name);
    }

    return summaryAsync.when(
      data: (summary) => PopScope(
        canPop: chosen.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            unselect();
          }
        },
        child: Scaffold(
          // The input makes room for the keyboard, or a panel in its place.
          resizeToAvoidBottomInset: false,
          appBar: chosen.isNotEmpty
              ? AppBar(
                  leading: CloseButton(onPressed: unselect),
                  title: Text(
                    AppLocalizations.of(context)!
                        .messagesSelected(chosen.length),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.forward_outlined),
                      tooltip: AppLocalizations.of(context)!.forward,
                      onPressed: chosen.every((e) => e.forwardable)
                          ? () {
                              unselect();
                              forward(chosen);
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: AppLocalizations.of(context)!.copy,
                      onPressed:
                          chosen.any((e) => messageTextOf(e.content) != null)
                          ? () {
                              _copy(
                                context,
                                chosen,
                                nameOf: (entry) =>
                                    (entry.mine
                                        ? selfName
                                        : entry.sender ?? summary.name) ??
                                    AppLocalizations.of(context)!
                                        .defaultContactName,
                              );
                              unselect();
                            }
                          : null,
                    ),
                  ],
                )
              : AppBar(
                  title: Tooltip(
                    message: AppLocalizations.of(context)!.chatDetails,
                    child: InkWell(
                      onTap: () =>
                          Navigator.push(context, ChatDetailsPage.route(chat)),
                      child: Row(
                        children: [
                          if (MediaQuery.of(context).size.width > 150)
                            Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: ChatAvatar(
                                bytes: summary.key,
                                online: summary.online,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              summary.name ??
                                  AppLocalizations.of(context)!
                                      .defaultContactName,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          body: entriesAsync.when(
            data: (entries) => LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  Expanded(
                    child: _Messages(
                      chat: chat,
                      entries: entries,
                      draft: draft,
                      controller: messages,
                      selected: selected,
                      onForward: forward,
                    ),
                  ),
                  if (summary.closed)
                    const _Closed()
                  else if (chosen.isNotEmpty)
                    const SafeArea(top: false, child: SizedBox.shrink())
                  else
                    // On a short screen, the input may take it all.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight,
                      ),
                      child: _Input(
                        chat: chat,
                        files: summary.key is PublicKey,
                        draft: draft,
                        recentEmojis: recentEmojis,
                        // What's sent shows at the bottom.
                        onSent: () {
                          if (messages.hasClients) {
                            messages.jumpTo(messages.position.minScrollExtent);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const LoadFailed(),
          ),
        ),
      ),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Scaffold(body: LoadFailed()),
    );
  }
}

void _copy(
  BuildContext context,
  List<ChatEntry> entries, {
  String Function(ChatEntry entry)? nameOf,
}) {
  final texts = [
    for (final entry in entries)
      if (messageTextOf(entry.content) case final text?) (entry, text),
  ];
  copyText(
    ScaffoldMessenger.of(context),
    [
      for (final (entry, text) in texts)
        nameOf != null && texts.length > 1 ? '${nameOf(entry)}: $text' : text,
    ].join('\n'),
    AppLocalizations.of(context)!.messagesCopied(texts.length),
  );
}

final class _Input extends ConsumerWidget {
  final ChatRef chat;
  // Tox only sends files to friends.
  final bool files;
  final ChatDraft draft;
  final bool recentEmojis;
  final void Function() onSent;

  const _Input({
    required this.chat,
    required this.files,
    required this.draft,
    required this.recentEmojis,
    required this.onSent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context)!.sendFailed;
    // Taken now, as what's sent goes on when the chat closes meanwhile.
    final opened = ref.watch(databaseProvider.future);
    return MessageInput(
      hintText: AppLocalizations.of(context)!.messageInput,
      draft: draft,
      recentEmojis: recentEmojis,
      files: files,
      picturesAsQoi:
          ref.watch(pictureFormatProvider(chat)) == PictureEncoding.qoi,
      onSend: (content) async {
        try {
          final database = await opened;
          switch (content) {
            case final FileContent file:
              await database.addFileSend(chat.profile, chat.graph, file);
            case final content:
              if (messageTextOf(content) case final text?) {
                await database.addSend(chat.profile, chat.graph, text);
              }
          }
          onSent();
          return true;
        } on Exception catch (e) {
          _logger.e('Failed to send to ${chat.graph}: $e');
          messenger.showSnackBar(SnackBar(content: Text(failed)));
          return false;
        }
      },
    );
  }
}

// How near the bottom still counts as being there, in logical pixels.
const _bottomSlack = 24.0;

/// The chat's entries, the newest at the bottom. Reading further up keeps
/// its place as new ones come, which wait below.
final class _Messages extends HookWidget {
  final ChatRef chat;
  final List<ChatEntry> entries;
  final ChatDraft draft;
  final ScrollController controller;
  final ValueNotifier<Set<EventId>> selected;
  final void Function(List<ChatEntry> entries) onForward;

  const _Messages({
    required this.chat,
    required this.entries,
    required this.draft,
    required this.controller,
    required this.selected,
    required this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    // The newest entry when the bottom was last in view. Newer ones go
    // below it, so what's above it stays where it is.
    final anchor = useRef<EventId?>(null);
    final reanchored = useState(0);
    final away = useState(false);
    bool atBottom(ScrollMetrics m) =>
        m.pixels <= m.minScrollExtent + _bottomSlack;
    var newest = entries.indexWhere((e) => e.event == anchor.value);
    if (newest == -1 ||
        !controller.hasClients ||
        atBottom(controller.position)) {
      newest = entries.length - 1;
      anchor.value = entries.lastOrNull?.event;
    }
    final waiting = entries.length - 1 - newest;
    final unseen = entries.skip(newest + 1).where((e) => !e.mine).length;

    final selecting = entries.any((e) => selected.value.contains(e.event));

    Widget item(int i) {
      final entry = entries[i];
      final day = localDay(entry.timestamp);
      return Column(
        key: ValueKey(entry.event),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (i == 0 || localDay(entries[i - 1].timestamp) != day)
            ChatDay(day: day),
          if (entry.notice)
            ChatNotice(entry: entry)
          else
            ChatItem(
              chat: chat,
              entry: entry,
              joinsAbove: i > 0 && inRun(entries[i - 1], entry),
              joinsBelow:
                  i + 1 < entries.length && inRun(entry, entries[i + 1]),
              selected: selecting ? selected.value.contains(entry.event) : null,
              onReply: () => draft.replyingTo.value = entry.content,
              onSelect: () =>
                  selected.value = selected.value.contains(entry.event)
                  ? ({...selected.value}..remove(entry.event))
                  : {...selected.value, entry.event},
              onForward: entry.forwardable ? () => onForward([entry]) : null,
              onCopy: messageTextOf(entry.content) == null
                  ? null
                  : () => _copy(context, [entry]),
            ),
        ],
      );
    }

    // A message keeps its state, such as a swipe to reply, as new ones come.
    int? indexOf(Key key, int? Function(int i) index) => switch (key) {
      ValueKey<EventId>(:final value) => switch (entries.indexWhere(
        (e) => e.event == value,
      )) {
        -1 => null,
        final i => index(i),
      },
      _ => null,
    };

    const center = ValueKey('newest');
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            away.value = !atBottom(metrics);
            // Back at the bottom, the ones that waited below join the rest.
            if (notification is ScrollEndNotification &&
                anchor.value != entries.last.event &&
                atBottom(metrics)) {
              anchor.value = entries.last.event;
              reanchored.value++;
              controller.jumpTo(0);
              away.value = false;
            }
            return false;
          },
          child: CustomScrollView(
            key: const Key('messages'),
            controller: controller,
            reverse: true,
            center: center,
            slivers: [
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, j) => item(newest + 1 + j),
                  childCount: waiting,
                  findChildIndexCallback: (key) =>
                      indexOf(key, (i) => i > newest ? i - newest - 1 : null),
                ),
              ),
              SliverList(
                key: center,
                delegate: SliverChildBuilderDelegate(
                  (context, j) => item(newest - j),
                  childCount: newest + 1,
                  findChildIndexCallback: (key) =>
                      indexOf(key, (i) => i > newest ? null : newest - i),
                ),
              ),
            ],
          ),
        ),
        if (away.value || waiting > 0)
          PositionedDirectional(
            end: 16,
            bottom: 16,
            child: Badge(
              isLabelVisible: unseen > 0,
              label: Text('$unseen'),
              child: FloatingActionButton.small(
                heroTag: null,
                tooltip: AppLocalizations.of(context)!.newestMessages,
                onPressed: () => controller.animateTo(
                  controller.position.minScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                ),
                child: const Icon(Icons.keyboard_arrow_down),
              ),
            ),
          ),
      ],
    );
  }
}

/// In place of the input, where nothing can be sent any more.
final class _Closed extends StatelessWidget {
  const _Closed();

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        AppLocalizations.of(context)!.chatClosed,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}
