import 'package:btox/models/crypto.dart';

const _codeSize = 16;

final _link = RegExp(
  '^tox:([0-9a-fA-F]{${ToxAddress.kLength * 2}})'
  '\\?pair=([0-9a-fA-F]{${_codeSize * 2}})\$',
);

/// A home device's pairing link: `tox:<address>?pair=<code>`.
final class PairingLink {
  final ToxAddress home;
  final String code;

  const PairingLink(this.home, this.code);

  static PairingLink? parse(String link) {
    final match = _link.firstMatch(link.trim());
    if (match == null) {
      return null;
    }
    final home = ToxAddress.fromString(match[1]!);
    return home.hasValidChecksum
        ? PairingLink(home, match[2]!.toLowerCase())
        : null;
  }

  String get requestMessage => 'pair:$code';
}
