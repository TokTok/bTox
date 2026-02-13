import 'package:btox/logger.dart';
import 'package:btox/pages/create_profile_page.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/profiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logger = Logger(['SelectProfilePage']);

final class SelectProfilePage extends ConsumerWidget {
  const SelectProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider).asData?.value ?? const [];
    final database = ref.watch(databaseProvider).asData?.value;

    if (database == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Select Profile')),
      body: ListView.builder(
        itemCount: profiles.length,
        itemBuilder: (context, index) {
          final profile = profiles[index];
          return ListTile(
            title: Text(profile.settings.nickname),
            subtitle: Text(profile.settings.statusMessage),
            onTap: () async {
              _logger.d('Selecting profile: ${profile.id}');
              await database.activateProfile(profile.id);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateProfilePage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
