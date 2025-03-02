import 'package:btox/models/content.dart';
import 'package:btox/models/crypto.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Content encode and decode', () {
    final l1 = [
      DeleteContent(
        message: Sha256.fromDigest(sha256.convert('Hello'.codeUnits)),
      ),
      EditContent(
        message: Sha256.fromDigest(sha256.convert('Hello'.codeUnits)),
        text: 'Hallo',
      ),
      FileContent(url: 'https://example.com/file.txt'),
      LocationContent(latitude: 1.2, longitude: 2.3),
      MediaContent(url: 'https://example.com/image.jpg'),
      ReactionContent(
        message: Sha256.fromDigest(sha256.convert('Hello'.codeUnits)),
        emoji: '👍',
      ),
      TextContent(text: 'Hello'),
      UnknownContent(data: Uint8List.fromList([1, 2, 3, 0, 9, 8, 7])),
    ];
    final l2 =
        l1.map((c) => Content.decode(c.encode())).toList(growable: false);
    const converter = ContentConverter();
    final l3 = l1
        .map((c) => converter.fromSql(converter.toSql(c)))
        .toList(growable: false);

    expect(l1, l2);
    expect(l1, l3);
  }, tags: ['models']);
}
