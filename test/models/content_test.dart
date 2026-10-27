import 'package:btox/models/content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('old rows of the messages table read back', () {
    const converter = ContentConverter();
    for (final content in const [
      FileContent(name: 'file.txt', size: 3, path: '/tmp/file.txt'),
      LocationContent(latitude: 1.2, longitude: 2.3),
      TextContent(text: 'Hello'),
      CallContent(
        incoming: true,
        video: true,
        ended: true,
        duration: Duration(seconds: 5),
      ),
    ]) {
      expect(converter.fromSql(converter.toSql(content)), content);
    }
    expect(converter.fromSql('plain'), const TextContent(text: 'plain'));
  }, tags: ['models']);

  test("a draft's attachments read back, but those of a newer version", () {
    const converter = ContentListConverter();
    const location = LocationContent(latitude: 1.2, longitude: 2.3);
    final stored = converter
        .toSql([location])
        .replaceFirst('[', '[{"_type":"poll"},');
    expect(converter.fromSql(stored), [location]);
  }, tags: ['models']);

  test('plain text is what the message says', () {
    expect(const TextContent(text: 'Hi').plainText, 'Hi');
    expect(
      const FileContent(name: 'a.txt', size: 1, path: '/a').plainText,
      'a.txt',
    );
    expect(
      const LocationContent(latitude: 1.5, longitude: 2.5).plainText,
      'geo:1.5,2.5',
    );
    expect(const CallContent(incoming: false).plainText, '');
  }, tags: ['models']);

  test('only places on Earth are locations', () {
    expect(
      contentOfMessage('geo:52.37,-4.89'),
      const LocationContent(latitude: 52.37, longitude: -4.89),
    );
    for (final text in ['geo:91,0', 'geo:0,181', 'geo:${'9' * 400},0']) {
      expect(contentOfMessage(text), TextContent(text: text), reason: text);
    }
  }, tags: ['models']);
}
