import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/pages/add_contact_page.dart';
import 'package:btox/pages/chat_page.dart';
import 'package:btox/providers/contacts.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/widgets/confirm_dialog.dart';
import 'package:btox/widgets/connection_status_icon.dart';
import 'package:btox/widgets/contact_list_item.dart';
import 'package:btox/widgets/friend_request_list_item.dart';
import 'package:btox/widgets/main_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logger = Logger(['ContactListPage']);

final class ContactListPage extends ConsumerWidget {
  const ContactListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final database = ref.watch(databaseProvider).asData?.value;

    if (profile == null || database == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final requests =
        ref.watch(friendRequestsForProfileProvider(profile.id)).value ??
        const [];
    final unread =
        ref.watch(unreadCountsProvider(profile.id)).value ?? const {};

    return Scaffold(
      drawer: MainMenu(profile: profile, database: database),
      appBar: AppBar(
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                height: 24,
                width: 24,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: const ConnectionStatusIcon(),
                ),
              ),
            ),
            Text(AppLocalizations.of(context)!.title),
          ],
        ),
      ),
      body: ref
          .watch(contactsForProfileProvider(profile.id))
          .when(
            data: (contacts) {
              return ListView.builder(
                itemCount: requests.length + contacts.length,
                itemBuilder: (context, index) {
                  if (index < requests.length) {
                    return FriendRequestListItem(
                      request: requests[index],
                      onAccept: database.acceptFriendRequest,
                      onReject: (request) =>
                          database.deleteFriendRequest(request.id),
                    );
                  }
                  final contact = contacts[index - requests.length];
                  return ContactListItem(
                    contact: contact,
                    unread: unread[contact.id] ?? 0,
                    onTap: (contact) {
                      _logger.d('Opening chat with contact: ${contact.id}');
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatPage(contactId: contact.id),
                        ),
                      );
                    },
                    onLongPress: (contact) =>
                        _confirmDelete(context, database, contact),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Error: $error')),
          ),
      floatingActionButton: FloatingActionButton(
        key: const Key('addContactButton'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddContactPage(
              onAddContact: (toxID, message) async {
                final address = ToxAddress.fromString(toxID);
                final id = await database.addContact(
                  ContactsCompanion.insert(
                    profileId: profile.id,
                    publicKey: address.publicKey,
                    friendRequestAddress: Value(address),
                    friendRequestMessage: Value(message),
                  ),
                );
                _logger.d('Added contact: $id');
              },
              selfName: profile.settings.nickname,
            ),
          ),
        ),
        tooltip: AppLocalizations.of(context)!.addContact,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Database database,
    Contact contact,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final name = contact.name ?? l10n.defaultContactName;
    if (!await confirm(
      context,
      title: l10n.deleteContact,
      message: l10n.deleteContactMessage(name),
      action: l10n.delete,
    )) {
      return;
    }
    _logger.i('Deleting contact ${contact.id}');
    await database.deleteContact(contact.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.contactDeleted(name))));
    }
  }
}
