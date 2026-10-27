import 'package:btox/attachments/attachments.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/attachments.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/widgets/bubble_footer.dart';
import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:btox/widgets/picture_view.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['ChatFileBubble']);

const _previewSize = 240.0;

String fileSizeText(int bytes) => switch (bytes) {
  < 1024 => '$bytes B',
  < 1024 * 1024 => '${(bytes / 1024).toStringAsFixed(1)} KB',
  _ => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
};

final class ChatFileBubble extends ConsumerWidget {
  final ChatRef chat;
  final ChatEntry entry;
  final Color color;
  final TextStyle textStyle;
  final BorderRadius corners;
  final Widget? header;
  final BubbleFooter? footer;

  const ChatFileBubble({
    super.key,
    required this.chat,
    required this.entry,
    required this.color,
    required this.textStyle,
    required this.corners,
    this.header,
    this.footer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isSender = entry.mine;
    final content = entry.content as FileContent;
    final progress = entry.file;
    // Ours is here from the start, theirs once it has all come.
    final preview =
        content.path.isNotEmpty &&
            (isSender || progress?.state == FileState.done)
        ? imagePreview(
            content.path,
            size: (_previewSize * MediaQuery.devicePixelRatioOf(context))
                .round(),
          )
        : null;
    final transfer = progress?.transfer;

    // Where this device runs the transfer, it starts or stops it. Elsewhere
    // the home device does, once it has the answer.
    void answer({required bool accept}) {
      _logger.unawaited(
        'answer the file',
        ref
            .read(databaseProvider.future)
            .then(
              (db) => transfer != null
                  ? db.answerTransfer(transfer, accept: accept)
                  : db.addFileAnswer(
                      chat.profile,
                      chat.graph,
                      entry.event,
                      accepted: accept,
                    ),
            ),
      );
    }

    // A linked account's file, from its home device to here.
    Future<void> download(BlobId blob) async {
      final db = await ref.read(databaseProvider.future);
      final directory = await ref.read(attachmentsDirectoryProvider.future);
      await db.fetchFile(
        chat.profile,
        chat.graph,
        entry.event,
        content,
        blob,
        newAttachmentPath(directory, content.name),
      );
    }

    return ChatTextBubble(
      corners: corners,
      header: header,
      color: color,
      footer: preview == null ? footer : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preview != null)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PictureView(path: content.path),
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _previewSize,
                  maxHeight: _previewSize,
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: preview,
                    ),
                    if (footer case final footer?) footer.overMedia(),
                  ],
                ),
              ),
            )
          else ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file),
                const SizedBox(width: 8),
                Flexible(child: Text(content.name, style: textStyle)),
              ],
            ),
            Text(
              fileSizeText(content.size),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          switch (progress) {
            FileProgress(state: FileState.offered) when !isSender => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => answer(accept: true),
                  child: Text(l10n.acceptFile),
                ),
                TextButton(
                  onPressed: () => answer(accept: false),
                  child: Text(l10n.declineFile),
                ),
              ],
            ),
            // Indeterminate when the home device moves it.
            FileProgress(state: FileState.active, :final transferred) =>
              SizedBox(
                width: preview == null ? 160 : _previewSize,
                child: LinearProgressIndicator(
                  value: content.size == 0 || transferred == null
                      ? null
                      : transferred / content.size,
                ),
              ),
            FileProgress(state: FileState.cancelled) => Text(
              l10n.fileCancelled,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            FileProgress(state: FileState.paused) => Text(
              l10n.filePaused,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            FileProgress(state: FileState.done, :final blob?)
                when content.path.isEmpty =>
              TextButton(
                onPressed: () =>
                    _logger.unawaited('download the file', download(blob)),
                child: Text(l10n.downloadFile),
              ),
            _ => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}
