import 'dart:math';

import 'package:btox/db/shared.dart';
import 'package:btox/logger.dart';
import 'package:btox/platform/any_platform.dart';
import 'package:convert/convert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'secure_storage.g.dart';

const _logger = Logger(['SecureStorage']);

const _storage = FlutterSecureStorage(
  // Resetting would replace the key, and the database couldn't be opened.
  aOptions: AndroidOptions(resetOnError: false),
  // The background service may need the key while the phone is locked.
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  // The data protection keychain needs a provisioning profile.
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);

@riverpod
Future<String> databaseKey(Ref ref) async {
  // The web database isn't encrypted.
  if (AnyPlatform.instance.isWeb) {
    return '';
  }
  // Whichever holds the key keeps it, so bTox never switches and loses it.
  if (await readDatabaseKeyFile() case final key?) {
    return key;
  }
  if (await _readKeyring() case final key?) {
    return key;
  }
  final random = Random.secure();
  final key = hex.encode(List.generate(32, (_) => random.nextInt(256)));
  try {
    await _storage.write(key: 'databaseKey', value: key);
  } on PlatformException catch (e) {
    if (!AnyPlatform.instance.isDesktop) {
      rethrow;
    }
    _logger.w('No keyring, keeping the database key in a file: ${e.message}');
    await writeDatabaseKeyFile(key);
  }
  return key;
}

Future<String?> _readKeyring() async {
  try {
    return await _storage.read(key: 'databaseKey');
  } on PlatformException catch (e) {
    // Without a Secret Service running, it can't hold the key.
    if (e.message?.startsWith('secret_service_get_sync') ?? false) {
      return null;
    }
    rethrow;
  }
}
