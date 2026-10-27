final class TextLink {
  final int start;
  final int end;
  final Uri uri;

  const TextLink(this.start, this.end, this.uri);
}

// Like GitHub's autolinks: at the start of a word, or after an opening
// bracket, quote or emphasis mark.
final _candidates = RegExp(
  r'''(?<=^|[\s([{<"'*_~])(?:(?:https?://|www\.)[^\s<>"]+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+)''',
  caseSensitive: false,
);

final _web = RegExp(r'^(?:https?://|www\.)', caseSensitive: false);
final _scheme = RegExp(r'^https?://', caseSensitive: false);

// No underscores in the last two parts of the domain.
final _domain = RegExp(
  r'^(?:https?://)?(?:[\w-]+\.)*[a-z0-9-]+\.[a-z0-9-]+(?:[/?#:]|$)',
  caseSensitive: false,
);

// Dropped from the end of a link, as are unmatched closing brackets.
const _trailing = "?!.,:;*_~'";
const _openers = {')': '(', ']': '[', '}': '{'};

int _count(String text, String char) => char.allMatches(text).length;

String _trimmed(String link) {
  while (link.isNotEmpty) {
    final last = link[link.length - 1];
    final opener = _openers[last];
    if (!_trailing.contains(last) &&
        (opener == null || _count(link, last) <= _count(link, opener))) {
      break;
    }
    link = link.substring(0, link.length - 1);
  }
  return link;
}

TextLink? _link(int start, String candidate) {
  if (!_web.hasMatch(candidate)) {
    if (candidate.endsWith('-') || candidate.endsWith('_')) {
      return null;
    }
    final uri = Uri(scheme: 'mailto', path: candidate);
    return TextLink(start, start + candidate.length, uri);
  }
  final link = _trimmed(candidate);
  if (!_domain.hasMatch(link)) {
    return null;
  }
  final uri = Uri.tryParse(_scheme.hasMatch(link) ? link : 'https://$link');
  return uri == null ? null : TextLink(start, start + link.length, uri);
}

List<TextLink> findLinks(String text) => [
  for (final match in _candidates.allMatches(text))
    ?_link(match.start, match[0]!),
];
