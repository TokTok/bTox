import 'package:btox/api/toxcore/tox_constants.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/crypto.dart';
import 'package:flutter/material.dart';

final _hex = RegExp(r'^[0-9A-Fa-f]*$');

final class ToxIdField extends StatelessWidget {
  final TextEditingController controller;

  const ToxIdField({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextFormField(
        key: const Key('toxId'),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (value) {
          value ??= '';
          if (value.length != toxAddressSize * 2 || !_hex.hasMatch(value)) {
            final msg = AppLocalizations.of(context)!
                .toxIdLengthError(toxAddressSize * 2);
            return '$msg (${value.length}/${toxAddressSize * 2})';
          }
          if (!ToxAddress.fromString(value).hasValidChecksum) {
            return AppLocalizations.of(context)!.toxIdChecksumError;
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
