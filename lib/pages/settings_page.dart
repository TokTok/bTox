import 'package:btox/attachments/attachments.dart';
import 'package:btox/db/database.dart';
import 'package:btox/ffi/tox_library.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/app_defaults.dart';
import 'package:btox/models/connection_status.dart';
import 'package:btox/models/profile_settings.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/services/backup.dart';
import 'package:btox/widgets/account_picker.dart';
import 'package:btox/widgets/chat_file_bubble.dart';
import 'package:btox/widgets/confirm_dialog.dart';
import 'package:btox/widgets/passphrase_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

const _logger = Logger(['SettingsPage']);

final class SettingsPage extends ConsumerWidget {
  final Database database;
  final Profile profile;

  const SettingsPage({
    super.key,
    required this.database,
    required this.profile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(profileProvider(profile.id)).value?.settings ??
        profile.settings;
    final network = settings.network;
    final status = ref.watch(connectionStatusProvider);
    final appSettings = ref.watch(appSettingsProvider).value;
    final l10n = AppLocalizations.of(context)!;

    void updateNetwork(NetworkSettings network) => database
        .updateProfileSettings(profile.id, settings.copyWith(network: network));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.menuSettings)),
      body: ListView(
        children: [
          _SectionHeader(l10n.appSettings),
          if (defaultTargetPlatform == TargetPlatform.android)
            SwitchListTile(
              title: Text(l10n.stayOnline),
              subtitle: Text(l10n.stayOnlineHint),
              value: appSettings?.stayOnline ?? true,
              onChanged: (value) => database.updateAppSettings(
                AppSettingsCompanion(stayOnline: Value(value)),
              ),
            ),
          if (filesSupported)
            ListTile(
              title: Text(l10n.autoAcceptFiles),
              subtitle: Text(
                _autoAcceptText(
                  l10n,
                  appSettings?.autoAcceptFileSize ?? defaultAutoAcceptFileSize,
                ),
              ),
              onTap: () async {
                final size = await showDialog<int>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: Text(l10n.autoAcceptFiles),
                    children: [
                      for (final megabytes in const [0, 1, 4, 16, 64, 256])
                        SimpleDialogOption(
                          onPressed: () =>
                              Navigator.pop(context, megabytes * 1024 * 1024),
                          child: Text(
                            _autoAcceptText(l10n, megabytes * 1024 * 1024),
                          ),
                        ),
                    ],
                  ),
                );
                if (size != null) {
                  await database.updateAppSettings(
                    AppSettingsCompanion(autoAcceptFileSize: Value(size)),
                  );
                }
              },
            ),
          ListTile(
            title: Text(l10n.exportData),
            subtitle: Text(l10n.exportDataHint),
            onTap: () => _export(context, ref),
          ),
          _SectionHeader(l10n.accountSettings(profile.settings.nickname)),
          ListTile(
            title: Text(l10n.deleteProfile),
            onTap: () async {
              final nickname = profile.settings.nickname;
              if (!await confirm(
                    context,
                    title: l10n.deleteProfile,
                    message: l10n.deleteProfileMessage(nickname),
                    action: l10n.delete,
                  ) ||
                  !context.mounted) {
                return;
              }
              _logger.i('Deleting profile ${profile.id}');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.profileDeleted(nickname))),
              );
              Navigator.pop(context);
              await database.deleteProfile(profile.id);
              _logger.i('Profile ${profile.id} deleted');
            },
          ),
          _SectionHeader(l10n.network),
          SwitchListTile(
            title: Text(l10n.udpEnabled),
            subtitle: Text(
              network.usesProxy ? l10n.offWithProxy : l10n.udpEnabledHint,
            ),
            value: network.udpEnabled && !network.usesProxy,
            onChanged: network.usesProxy
                ? null
                : (value) => updateNetwork(network.copyWith(udpEnabled: value)),
          ),
          SwitchListTile(
            title: Text(l10n.ipv6Enabled),
            value: network.ipv6Enabled,
            onChanged: (value) =>
                updateNetwork(network.copyWith(ipv6Enabled: value)),
          ),
          SwitchListTile(
            title: Text(l10n.localDiscoveryEnabled),
            subtitle: Text(
              network.usesProxy
                  ? l10n.offWithProxy
                  : l10n.localDiscoveryEnabledHint,
            ),
            value: network.localDiscoveryEnabled && !network.usesProxy,
            onChanged: network.usesProxy
                ? null
                : (value) => updateNetwork(
                    network.copyWith(localDiscoveryEnabled: value),
                  ),
          ),
          ListTile(
            title: Text(l10n.proxy),
            subtitle: status?.proxyProblem != null
                ? Text(
                    connectionStatusText(status),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                : Text(switch (network.proxyType) {
                    ProxyType.none => l10n.proxyNone,
                    final type =>
                      '${_proxyTypeName(type)} '
                          '${network.proxyHost}:${network.proxyPort}',
                  }),
            onTap: () async {
              final updated = await showDialog<NetworkSettings>(
                context: context,
                builder: (_) => _ProxyDialog(network: network),
              );
              if (updated != null) {
                updateNetwork(updated);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final profiles = await database.select(database.profiles).get();
    if (!context.mounted) {
      return;
    }
    final accounts = await showAccountPicker(
      context,
      title: l10n.exportData,
      action: l10n.export,
      accounts: {for (final p in profiles) p.id: p.settings.nickname},
    );
    if (accounts == null) {
      return;
    }
    final lib = await ref.read(toxFfiProvider.future);
    final backup = await exportBackup(database, accounts);
    if (!context.mounted) {
      return;
    }
    final encrypted = await showPassphraseDialog(
      context,
      title: l10n.exportData,
      action: l10n.export,
      run: (passphrase) => passEncrypt(lib, backup, passphrase),
      obscure: false,
    );
    if (encrypted == null) {
      return;
    }
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final path = await FilePicker.platform.saveFile(
      fileName: 'btox-$date.backup',
      bytes: encrypted,
    );
    // Desktop pickers only choose where to save.
    if (path != null && AnyPlatform.instance.isDesktop) {
      await XFile.fromData(encrypted).saveTo(path);
    }
  }
}

String _autoAcceptText(AppLocalizations l10n, int size) =>
    size == 0 ? l10n.never : fileSizeText(size);

final class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(
      title,
      style: TextStyle(color: Theme.of(context).colorScheme.primary),
    ),
    dense: true,
  );
}

String _proxyTypeName(ProxyType type) => switch (type) {
  ProxyType.none => '',
  ProxyType.http => 'HTTP',
  ProxyType.socks5 => 'SOCKS5',
};

final class _ProxyDialog extends HookWidget {
  final NetworkSettings network;

  const _ProxyDialog({required this.network});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final type = useState(network.proxyType);
    final host = useTextEditingController(text: network.proxyHost);
    final port = useTextEditingController(text: '${network.proxyPort}');
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final enabled = type.value != ProxyType.none;

    void save() {
      if (enabled && !formKey.currentState!.validate()) {
        return;
      }
      Navigator.pop(
        context,
        network.copyWith(
          proxyType: type.value,
          proxyHost: enabled ? host.text.trim() : network.proxyHost,
          proxyPort: enabled ? int.parse(port.text) : network.proxyPort,
        ),
      );
    }

    return AlertDialog(
      title: Text(l10n.proxy),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<ProxyType>(
              segments: [
                for (final type in ProxyType.values)
                  ButtonSegment(
                    value: type,
                    label: Text(
                      type == ProxyType.none
                          ? l10n.proxyNone
                          : _proxyTypeName(type),
                    ),
                  ),
              ],
              selected: {type.value},
              onSelectionChanged: (selected) => type.value = selected.single,
            ),
            TextFormField(
              controller: host,
              enabled: enabled,
              decoration: InputDecoration(labelText: l10n.proxyHost),
              validator: (value) =>
                  value!.trim().isEmpty ? l10n.invalidProxyHost : null,
            ),
            TextFormField(
              controller: port,
              enabled: enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l10n.proxyPort),
              validator: (value) {
                final port = int.tryParse(value!);
                return port == null || port < 1 || port > 65535
                    ? l10n.invalidProxyPort
                    : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: save, child: Text(l10n.save)),
      ],
    );
  }
}
