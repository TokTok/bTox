import 'dart:typed_data';

import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/services/message_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'notifications name their account while several are signed in',
    () async {
      final named = <String?>[];
      final notifier = MessageNotifier(
        (_, _, _, account) async => named.add(account),
        (_) async {},
      );
      final chat = ChatRef(
        const Id(1),
        GraphId.account(PublicKey(Uint8List(32))),
      );
      final hi = (sender: null, text: 'hi', time: DateTime(2026));

      notifier.notify(chat, 'Bob', [hi], 'Me');
      notifier.signedInAccounts = 2;
      notifier.notify(chat, 'Bob', [hi], 'Me');
      await Future<void>.delayed(Duration.zero);
      expect(named, [null, 'Me']);
    },
  );
}
