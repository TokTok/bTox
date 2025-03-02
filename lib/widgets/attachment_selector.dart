import 'package:btox/logger.dart';
import 'package:btox/models/content.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/geolocation.dart';
import 'package:btox/widgets/attachment_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const _logger = Logger(['AttachmentSelector']);

final class AttachmentSelector extends StatelessWidget {
  final void Function(List<Content>) onSelected;

  const AttachmentSelector({
    super.key,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Table(
        children: [
          TableRow(
            children: [
              if (AnyPlatform.instance.isMobile)
                AttachmentButton(
                  icon: Icons.camera_alt,
                  text: 'Camera',
                  onPressed: () async {
                    final image = await ImagePicker().pickImage(
                      source: ImageSource.camera,
                    );
                    if (image != null) {
                      onSelected([await _loadImage(image)]);
                    }
                  },
                ),
              AttachmentButton(
                icon: Icons.photo,
                text: 'Gallery',
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    allowMultiple: true,
                    type: FileType.image,
                  );
                  if (result != null) {
                    onSelected(await Future.wait(
                        result.files.map((file) => _loadImage(file.xFile))));
                  }
                },
              ),
              AttachmentButton(
                icon: Icons.file_copy,
                text: 'File',
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    allowMultiple: true,
                  );
                  if (result != null) {
                    onSelected(await Future.wait(
                        result.files.map((file) => _loadFile(file.xFile))));
                  }
                },
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

Future<Content> _loadImage(XFile file) async {
  final bytes = await file.readAsBytes();
  return MediaContent(
    url: 'path: ${file.path} name: ${file.name} bytes: ${bytes.length}',
  );
}

Future<Content> _loadFile(XFile file) async {
  final bytes = await file.readAsBytes();
  return FileContent(
    url: 'path: ${file.path} name: ${file.name} bytes: ${bytes.length}',
  );
}
