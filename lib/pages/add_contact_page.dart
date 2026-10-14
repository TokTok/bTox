import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/widgets/friend_request_message_field.dart';
import 'package:btox/widgets/tox_id_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

final class AddContactPage extends HookWidget {
  final String selfName;
  final Function(String, String) onAddContact;

  const AddContactPage({
    super.key,
    required this.selfName,
    required this.onAddContact,
  });

  @override
  Widget build(BuildContext context) {
    final formKey = useMemoized(() => GlobalKey<FormState>());
    final toxIdInputController = useTextEditingController();
    final messageInputController = useTextEditingController(
      text: AppLocalizations.of(context)!.defaultAddContactMessage(selfName),
    );

    void submit() {
      if (formKey.currentState!.validate()) {
        onAddContact(toxIdInputController.text, messageInputController.text);
        Navigator.pop(context);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.addContact)),
      body: SingleChildScrollView(
        child: Form(
          key: formKey,
          child: Column(
            children: [
              ToxIdField(controller: toxIdInputController),
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
