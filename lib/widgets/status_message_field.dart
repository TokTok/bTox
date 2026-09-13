import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

final class StatusMessageField extends StatelessWidget {
  final ToxConstants constants;
  final TextEditingController controller;
  final void Function(String)? onChanged;

  const StatusMessageField({
    super.key,
    required this.constants,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          AppLocalizations.of(context)!.profileTextFieldUserStatusMessage,
          style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextFormField(
            key: const Key('statusMessageField'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              value ??= '';
              if (value.length > constants.maxStatusMessageLength) {
                return AppLocalizations.of(context)!
                    .statusMessageLengthError(constants.maxStatusMessageLength);
              }

              return null;
            },
            controller: controller,
            textInputAction: TextInputAction.next,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
