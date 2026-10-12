import 'package:btox/models/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // From qTox's tests.
  test('ToxAddress.hasValidChecksum', () {
    for (final address in [
      'A369865720756105C324F27C20093F26BEEB2655F803977D5C2EB6B408B8E404AFC201CC15D1',
      '76518406F6A9F2217E8DC487CC783C25CC16A15EB36FF32E335A235342C48A39218F515C39A6',
    ]) {
      expect(ToxAddress.fromString(address).hasValidChecksum, isTrue);
    }
    final corrupted = ToxAddress.fromString(
      'A369865720756105C324F27C20093F26BEEB2655F803977D5C2EB6B408B8E404AFC201CC15D2',
    );
    expect(corrupted.hasValidChecksum, isFalse);
  });
}
