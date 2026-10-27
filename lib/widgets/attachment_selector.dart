import 'package:btox/attachments/attachments.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/content.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/attachments.dart';
import 'package:btox/providers/geolocation.dart';
import 'package:btox/widgets/attachment_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';

const _logger = Logger(['AttachmentSelector']);

final class AttachmentSelector extends ConsumerWidget {
  // Pictures and files too, besides a location.
  final bool files;
  final void Function(List<Content>) onSelected;

  const AttachmentSelector({
    super.key,
    this.files = true,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    // Picking or copying can fail, as with the camera refused or no room.
    Future<void> attach(Future<List<XFile>?> Function() pick) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final picked = await pick();
        if (picked == null) {
          return;
        }
        final directory = await ref.read(attachmentsDirectoryProvider.future);
        final copied = <FileContent>[];
        try {
          for (final file in picked) {
            copied.add(await saveAttachment(directory, file));
          }
        } on Exception {
          for (final FileContent(:path) in copied) {
            _logger.unawaited('delete $path', deleteAttachment(path));
          }
          rethrow;
        }
        onSelected(copied);
      } on Exception catch (e) {
        _logger.e('Failed to attach: $e');
        messenger.showSnackBar(SnackBar(content: Text(l10n.attachFailed)));
      }
    }

    Future<void> pick([FileType type = FileType.any]) => attach(
      () async => (await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: type,
      ))?.files.map((file) => file.xFile).toList(),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Table(
        children: [
          TableRow(
            children: [
              if (files && filesSupported && AnyPlatform.instance.isMobile)
                AttachmentButton(
                  icon: Icons.camera_alt,
                  text: l10n.attachCamera,
                  onPressed: () => attach(
                    () async => switch (await ImagePicker().pickImage(
                      source: ImageSource.camera,
                    )) {
                      final image? => [image],
                      null => null,
                    },
                  ),
                ),
              if (files && filesSupported)
                AttachmentButton(
                  icon: Icons.photo,
                  text: l10n.attachGallery,
                  onPressed: () => pick(FileType.image),
                ),
              if (files && filesSupported)
                AttachmentButton(
                  icon: Icons.file_copy,
                  text: l10n.attachFile,
                  onPressed: pick,
                ),
              AttachmentButton(
                icon: Icons.location_on,
                text: l10n.attachLocation,
                onPressed: () async {
                  try {
                    final location = await geolocation();
                    onSelected([
                      LocationContent(
                        latitude: location.latitude,
                        longitude: location.longitude,
                      ),
                    ]);
                  } catch (e) {
                    _logger.e('Error adding location: $e');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
