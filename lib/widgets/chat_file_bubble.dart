import 'package:btox/attachments/attachments.dart';
import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/content.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/widgets/chat_text_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String fileSizeText(int bytes) => switch (bytes) {
  < 1024 => '$bytes B',
  < 1024 * 1024 => '${(bytes / 1024).toStringAsFixed(1)} KB',
  _ => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
};

final class ChatFileBubble extends ConsumerWidget {
  final Message message;
  final bool isSender;
  final Color color;
  final TextStyle textStyle;

  const ChatFileBubble({
    super.key,
    required this.message,
    required this.isSender,
    required this.color,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final content = message.content as FileContent;
    final preview = message.fileState == FileState.done
        ? imagePreview(content.path)
        : null;

    void setState(FileState state) =>
        ref.read(databaseProvider).value?.setFileState(message.id, state);

    return Align(
      alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
      child: ChatTextBubble(
        radius: 20,
        color: color,
        stateIcon: null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview != null)
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 240,
                  maxHeight: 240,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: preview,
                ),
              )
            else
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
            switch (message.fileState) {
              FileState.offered when !isSender => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => setState(FileState.active),
                    child: Text(l10n.acceptFile),
                  ),
                  TextButton(
                    onPressed: () => setState(FileState.cancelled),
                    child: Text(l10n.declineFile),
                  ),
                ],
              ),
              FileState.active => SizedBox(
                width: 160,
                child: LinearProgressIndicator(
                  value: content.size == 0
                      ? null
                      : (message.fileTransferred ?? 0) / content.size,
                ),
              ),
              FileState.cancelled => Text(
                l10n.fileCancelled,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _ => const SizedBox.shrink(),
            },
          ],
        ),
      ),
    );
  }
}
