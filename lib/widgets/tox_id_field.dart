import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

final class ToxIdField extends StatelessWidget {
  final ToxConstants constants;
  final TextEditingController controller;

  const ToxIdField({
    super.key,
    required this.constants,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextFormField(
        key: const Key('toxId'),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (value) {
          value ??= '';
          if (value.length != constants.addressSize * 2) {
            final msg = AppLocalizations.of(context)!
                .toxIdLengthError(constants.addressSize * 2);
            return '$msg (${value.length}/76)';
          }
          return null;
        },
        decoration: InputDecoration(
          border: UnderlineInputBorder(),
          labelText: AppLocalizations.of(context)!.toxId,
        ),
        controller: controller,
        textInputAction: TextInputAction.next,
        autofocus: true,
      ),
    );
  }
}
