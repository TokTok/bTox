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
import 'package:btox/providers/chats.dart';
import 'package:btox/providers/connection_status.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/providers/message_formats.dart';
import 'package:btox/providers/profiles.dart';
import 'package:btox/services/backup.dart';
import 'package:btox/widgets/account_picker.dart';
import 'package:btox/widgets/chat_file_bubble.dart';
import 'package:btox/widgets/database_write.dart';
import 'package:btox/widgets/delete_profile.dart';
import 'package:btox/widgets/import_profile.dart';
import 'package:btox/widgets/passphrase_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

const _logger = Logger(['SettingsPage']);

final class SettingsPage extends ConsumerWidget {
  final Profile profile;

  const SettingsPage({super.key, required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(profileProvider(profile.id)).value?.settings ??
        profile.settings;
    final network = settings.network;
    final status = ref.watch(connectionStatusProvider);
    final appSettings = ref.watch(appSettingsProvider).value;
    final l10n = AppLocalizations.of(context)!;
    final name =
        ref.watch(profileIdentityProvider(profile)).name ?? l10n.linkedAccount;

    void save(Future<void> Function(Database db) change) =>
        ref.write(context, change);
    void updateSettings(ProfileSettings Function(ProfileSettings) change) =>
        save((db) => db.updateProfileSettings(profile.id, change));
    void updateNetwork(NetworkSettings Function(NetworkSettings) change) =>
        updateSettings((s) => s.copyWith(network: change(s.network)));

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
              onChanged: (value) => save(
                (db) => db.updateAppSettings(
                  AppSettingsCompanion(stayOnline: Value(value)),
                ),
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
                  save(
                    (db) => db.updateAppSettings(
                      AppSettingsCompanion(autoAcceptFileSize: Value(size)),
                    ),
                  );
                }
              },
            ),
          const _ExportTile(),
          ListTile(
            title: Text(l10n.importData),
            subtitle: Text(l10n.importDataHint),
            onTap: () => importProfileFile(context, ref),
          ),
          _SectionHeader(l10n.accountSettings(name)),
          for (final format in ref.watch(knownMessageFormatsProvider))
            SwitchListTile(
              title: Text(format.title(l10n)),
              subtitle: Text(format.description(l10n)),
              value: !settings.messageFormatsOff.contains(format.id),
              onChanged: (on) => updateSettings(
                (s) => s.copyWith(
                  messageFormatsOff: [
                    for (final id in s.messageFormatsOff)
                      if (id != format.id) id,
                    if (!on) format.id,
                  ],
                ),
              ),
            ),
          SwitchListTile(
            title: Text(l10n.udpEnabled),
            subtitle: Text(
              network.usesProxy ? l10n.offWithProxy : l10n.udpEnabledHint,
            ),
            value: network.udpEnabled && !network.usesProxy,
            onChanged: network.usesProxy
                ? null
                : (value) =>
                      updateNetwork((n) => n.copyWith(udpEnabled: value)),
          ),
          SwitchListTile(
            title: Text(l10n.ipv6Enabled),
            value: network.ipv6Enabled,
            onChanged: (value) =>
                updateNetwork((n) => n.copyWith(ipv6Enabled: value)),
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
                    (n) => n.copyWith(localDiscoveryEnabled: value),
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
                updateNetwork((_) => updated);
              }
            },
          ),
          ListTile(
            title: Text(
              l10n.deleteProfile,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => deleteProfileIfConfirmed(
              context,
              ref,
              profile,
              name,
              confirmed: () {
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Exports all accounts, saying how it went.
final class _ExportTile extends HookConsumerWidget {
  const _ExportTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final busy = useState(false);
    return ListTile(
      title: Text(l10n.exportData),
      subtitle: Text(l10n.exportDataHint),
      enabled: !busy.value,
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        busy.value = true;
        try {
          if (await _export(context, ref)) {
            messenger.showSnackBar(SnackBar(content: Text(l10n.exported)));
          }
        } on Exception catch (e) {
          _logger.e('Failed to export: $e');
          messenger.showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
        } finally {
          if (context.mounted) {
            busy.value = false;
          }
        }
      },
    );
  }

  /// Whether the data was saved, rather than the user cancelling.
  Future<bool> _export(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final database = await ref.read(databaseProvider.future);
    final names = {
      for (final p in await database.select(database.profiles).get())
        p.id: p.home == null
            ? p.settings.nickname
            : switch (await linkedAccountName(database, p)) {
                final name? => l10n.linkedAccountName(name),
                null => l10n.linkedAccount,
              },
    };
    if (!context.mounted) {
      return false;
    }
    final accounts = await showAccountPicker(
      context,
      title: l10n.exportData,
      action: l10n.export,
      accounts: names,
    );
    if (accounts == null) {
      return false;
    }
    final lib = await ref.read(toxFfiProvider.future);
    final backup = await exportBackup(database, accounts);
    if (!context.mounted) {
      return false;
    }
    final encrypted = await showPassphraseDialog(
      context,
      title: l10n.exportData,
      action: l10n.export,
      run: (passphrase) => passEncrypt(lib, backup, passphrase),
      obscure: false,
    );
    if (encrypted == null) {
      return false;
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
    return path != null;
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
              // A check mark leaves "SOCKS5" no room on a phone.
              showSelectedIcon: false,
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
