import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/pages/add_contact_page.dart';
import 'package:btox/pages/chat_page.dart';
import 'package:btox/providers/contacts.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/widgets/connection_status_icon.dart';
import 'package:btox/widgets/contact_list_item.dart';
import 'package:btox/widgets/main_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logger = Logger(['ContactListPage']);

final class ContactListPage extends ConsumerWidget {
  const ContactListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeProfileProvider);
    final constants = ref.watch(toxConstantsProvider).asData?.value;
    final database = ref.watch(databaseProvider).asData?.value;

    if (profile == null || constants == null || database == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      drawer: MainMenu(
        constants: constants,
        profile: profile,
        database: database,
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
            );
          },
        ),
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SizedBox(
                height: 24,
                width: 24,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConnectionStatusIcon(profile: profile),
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
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  return ContactListItem(
                    contact: contacts[index],
                    onTap: (contact) {
                      _logger.d('Opening chat with contact: ${contact.id}');
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatPage(contactId: contact.id),
                        ),
                      );
                    },
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
              constants: constants,
              onAddContact: (toxID, message) async {
                final id = await database.addContact(
                  ContactsCompanion.insert(
                    profileId: profile.id,
                    publicKey: PublicKey.fromJson(
                      toxID.substring(0, toxID.length - 12),
                    ),
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
}
