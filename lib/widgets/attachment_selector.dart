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
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';

const _logger = Logger(['AttachmentSelector']);

final class AttachmentSelector extends HookConsumerWidget {
  // Pictures and files too, besides a location.
  final bool files;
  // Camera and gallery pictures as QOI.
  final bool picturesAsQoi;
  final void Function(List<Content>) onSelected;

  const AttachmentSelector({
    super.key,
    this.files = true,
    this.picturesAsQoi = false,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final locating = useState(false);

    Future<void> shareLocation() async {
      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
      locating.value = true;
      try {
        final location = await geolocation();
        onSelected([
          LocationContent(
            latitude: location.latitude,
            longitude: location.longitude,
          ),
        ]);
      } on Exception catch (e) {
        _logger.e('Error adding location: $e');
        final problem = switch (e) {
          LocationUnavailable(:final problem) => problem,
          _ => null,
        };
        messenger.showSnackBar(
          SnackBar(
            content: Text(switch (problem) {
              LocationProblem.off => l10n.locationOff,
              LocationProblem.denied ||
              LocationProblem.refused => l10n.locationDenied,
              null => l10n.locationFailed,
            }),
            action: switch (problem) {
              final problem? when problem != LocationProblem.refused =>
                SnackBarAction(
                  label: l10n.openSettings,
                  onPressed: () => _logger.unawaited(
                    'open the location settings',
                    fixLocation(problem),
                  ),
                ),
              _ => null,
            },
          ),
        );
      } finally {
        if (context.mounted) {
          locating.value = false;
        }
      }
    }

    // Picking or copying can fail, as with the camera refused or no room.
    Future<void> attach(
      Future<List<XFile>?> Function() pick, {
      bool pictures = false,
    }) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final picked = await pick();
        if (picked == null) {
          return;
        }
        final directory = await ref.read(attachmentsDirectoryProvider.future);
        final copy = pictures && picturesAsQoi
            ? savePictureAsQoi
            : saveAttachment;
        final copied = <FileContent>[];
        try {
          for (final file in picked) {
            copied.add(await copy(directory, file));
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
      pictures: type == FileType.image,
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
                    pictures: true,
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
                onPressed: locating.value ? null : shareLocation,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
