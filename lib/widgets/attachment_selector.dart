import 'package:btox/attachments/attachments.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/content.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/attachments.dart';
import 'package:btox/providers/geolocation.dart';
import 'package:btox/widgets/attachment_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

const _logger = Logger(['AttachmentSelector']);

final class AttachmentSelector extends ConsumerWidget {
  final void Function(List<Content>) onSelected;

  const AttachmentSelector({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> save(Iterable<XFile> files) async {
      final directory = await ref.read(attachmentsDirectoryProvider.future);
      onSelected(
        await Future.wait(files.map((f) => saveAttachment(directory, f))),
      );
    }

    Future<void> pick([FileType type = FileType.any]) async {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: type,
      );
      if (result != null) {
        await save(result.files.map((file) => file.xFile));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Table(
        children: [
          TableRow(
            children: [
              if (filesSupported && AnyPlatform.instance.isMobile)
                AttachmentButton(
                  icon: Icons.camera_alt,
                  text: 'Camera',
                  onPressed: () async {
                    final image = await ImagePicker().pickImage(
                      source: ImageSource.camera,
                    );
                    if (image != null) {
                      await save([image]);
                    }
                  },
                ),
              if (filesSupported)
                AttachmentButton(
                  icon: Icons.photo,
                  text: 'Gallery',
                  onPressed: () => pick(FileType.image),
                ),
              if (filesSupported)
                AttachmentButton(
                  icon: Icons.file_copy,
                  text: 'File',
                  onPressed: pick,
                ),
              AttachmentButton(
                icon: Icons.location_on,
                text: 'Location',
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
