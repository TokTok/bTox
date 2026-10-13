import 'package:btox/api/toxcore/tox_constants.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

final class NicknameField extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String)? onChanged;

  const NicknameField({super.key, required this.controller, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          AppLocalizations.of(context)!.profileTextFieldNick,
          style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextFormField(
            key: const Key('nicknameField'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              value ??= '';
              if (value.isEmpty || value.length > toxMaxNameLength) {
                return AppLocalizations.of(context)!
                    .nickLengthError(toxMaxNameLength);
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
