import 'dart:async';

import 'package:btox/attachments/attachments.dart';
import 'package:btox/db/database.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/database.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'drafts.g.dart';

const _logger = Logger(['Drafts']);

const _kSaveDelay = Duration(milliseconds: 500);

/// What's being written in a chat: kept while the app runs, so leaving the
/// chat, or opening it again from a notification, loses nothing.
final class ChatDraft {
  final text = TextEditingController();
  final attachments = ValueNotifier<List<Content>>(const []);
  final replyingTo = ValueNotifier<Content?>(null);

  bool get isEmpty =>
      text.text.isEmpty &&
      attachments.value.isEmpty &&
      replyingTo.value == null;

  (String, List<Content>, Content?) get _contents =>
      (text.text, attachments.value, replyingTo.value);
}

/// Restores the chat's draft from the database, and saves it there as it
/// changes.
@Riverpod(keepAlive: true)
ChatDraft chatDraft(Ref ref, ChatRef chat) {
  final draft = ChatDraft();
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  _logger.unawaited('keep a draft', () async {
    final db = await ref.read(databaseProvider.future);
    final stored = await db.getDraft(chat.profile, chat.graph);
    var saved = stored == null
        ? ('', const <Content>[], null)
        : (stored.message, stored.attachments, stored.replyingTo);
    // Unless writing started before it was read.
    if (stored != null && draft.isEmpty) {
      draft.text.text = stored.message;
      // A backup brings no files.
      draft.attachments.value = [
        for (final content in stored.attachments)
          if (content is! FileContent || attachmentExists(content.path))
            content,
      ];
      draft.replyingTo.value = stored.replyingTo;
    }

    void save() {
      final contents = draft._contents;
      if (contents == saved) {
        return;
      }
      saved = contents;
      final (message, attachments, replyingTo) = contents;
      _logger.unawaited(
        'save a draft',
        draft.isEmpty
            ? db.clearDraft(chat.profile, chat.graph)
            : db.setDraft(
                StoredDraft(
                  profileId: chat.profile,
                  graph: chat.graph,
                  message: message,
                  attachments: attachments,
                  replyingTo: replyingTo,
                ),
              ),
      );
    }

    void changed() {
      timer?.cancel();
      timer = Timer(_kSaveDelay, save);
    }

    for (final listenable in [
      draft.text,
      draft.attachments,
      draft.replyingTo,
    ]) {
      listenable.addListener(changed);
    }
    save();
  }());
  return draft;
}

@riverpod
Stream<Map<GraphId, StoredDraft>> drafts(Ref ref, Id<Profiles> id) =>
    watchDb(ref, (db) => db.watchDrafts(id));
