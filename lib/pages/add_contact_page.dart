import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/widgets/friend_request_message_field.dart';
import 'package:btox/widgets/tox_id_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

const _logger = Logger(['AddContactPage']);

final class AddContactPage extends HookWidget {
  final String selfName;
  final Set<PublicKey> own;
  final Future<void> Function(ToxAddress, String) onAddContact;

  const AddContactPage({
    super.key,
    required this.selfName,
    required this.own,
    required this.onAddContact,
  });

  @override
  Widget build(BuildContext context) {
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final toxIdInputController = useTextEditingController();
    final messageInputController = useTextEditingController(
      text: AppLocalizations.of(context)!.defaultAddContactMessage(selfName),
    );

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      final failed = AppLocalizations.of(context)!.addContactFailed;
      Navigator.pop(context);
      try {
        await onAddContact(
          ToxAddress.fromString(toxIdInputController.text),
          messageInputController.text,
        );
      } on Exception catch (e) {
        _logger.e('Failed to add a contact: $e');
        messenger.showSnackBar(SnackBar(content: Text(failed)));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.addContact)),
      body: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            children: [
              ToxIdField(controller: toxIdInputController, own: own),
              FriendRequestMessageField(
                controller: messageInputController,
                onEditingComplete: submit,
              ),
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: submit,
                    child: Text(AppLocalizations.of(context)!.add),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
