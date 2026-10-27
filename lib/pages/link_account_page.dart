import 'package:btox/db/database.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/tox.dart';
import 'package:btox/sync/pairing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _logger = Logger(['LinkAccountPage']);

// What the home device sees this device as.
const _deviceName = 'bTox';

final class LinkAccountPage extends HookConsumerWidget {
  const LinkAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final controller = useTextEditingController();
    final error = useState<String?>(null);
    final linking = useState(false);

    Future<void> link() async {
      final pairing = PairingLink.parse(controller.text);
      if (pairing == null) {
        error.value = l10n.invalidPairingLink;
        return;
      }
      linking.value = true;
      try {
        final (secretKey, publicKey) = await ref.read(
          newKeyPairProvider.future,
        );
        final database = await ref.read(databaseProvider.future);
        await database.transaction(() async {
          final id = await database.addProfile(
            ProfilesCompanion.insert(
              settings: ProfileSettings(
                nickname: _deviceName,
                statusMessage: '',
              ),
              secretKey: secretKey,
              publicKey: publicKey,
              nospam: ToxAddressNospam(0),
              home: Value(pairing.home),
              pairingMessage: Value(pairing.requestMessage),
            ),
          );
          await database.signIn(id);
        });
      } catch (e) {
        _logger.e('Failed to link an account: $e');
        error.value = l10n.linkFailed;
        linking.value = false;
        return;
      }
      if (context.mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.linkAccount)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Text(l10n.pairingLinkHelp),
            TextField(
              key: const Key('pairingLink'),
              controller: controller,
              decoration: InputDecoration(
                labelText: l10n.pairingLink,
                errorText: error.value,
              ),
              onChanged: (_) => error.value = null,
            ),
            FilledButton(
              onPressed: linking.value ? null : link,
              child: Text(l10n.link),
            ),
          ],
        ),
      ),
    );
  }
}
