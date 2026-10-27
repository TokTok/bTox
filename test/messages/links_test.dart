import 'package:btox/messages/links.dart';
import 'package:flutter_test/flutter_test.dart';

List<(String, String)> _links(String text) => [
  for (final link in findLinks(text))
    (text.substring(link.start, link.end), link.uri.toString()),
];

void main() {
  test('finds web and email addresses', () {
    expect(
      _links('see https://example.com/a?b=c#d, www.example.org or me@x.co'),
      [
        ('https://example.com/a?b=c#d', 'https://example.com/a?b=c#d'),
        ('www.example.org', 'https://www.example.org'),
        ('me@x.co', 'mailto:me@x.co'),
      ],
    );
  });

  test('leaves out trailing punctuation and unmatched brackets', () {
    expect(_links('(at https://en.wikipedia.org/wiki/Tox_(protocol)).'), [
      (
        'https://en.wikipedia.org/wiki/Tox_(protocol)',
        'https://en.wikipedia.org/wiki/Tox_(protocol)',
      ),
    ]);
    expect(_links("'www.example.com/x'!"), [
      ('www.example.com/x', 'https://www.example.com/x'),
    ]);
  });

  test('links only web and email addresses that start a word', () {
    expect(
      findLinks(
        'awww.example.com xhttps://example.com file:///etc/passwd '
        'smb://host/share javascript:alert(1) https://localhost www. '
        'https://a_b.example_c.com www.example.com\'s me@x.co_',
      ),
      isEmpty,
    );
  });
}
