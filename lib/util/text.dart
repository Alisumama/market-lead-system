/// Strips HTML tags and decodes the common entities that show up in RSS /
/// World-Bank feed summaries (e.g. the `&nbsp;&nbsp;` seen in raw snippets),
/// then collapses whitespace. Safe on already-clean text.
String cleanHtmlText(String? input) {
  if (input == null) return '';
  var t = input.replaceAll(RegExp(r'<[^>]+>'), ' ');

  // Numeric entities: &#160; and &#xA0;
  t = t.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m[1]!);
    return code == null ? m[0]! : String.fromCharCode(code);
  });
  t = t.replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m[1]!, radix: 16);
    return code == null ? m[0]! : String.fromCharCode(code);
  });

  const named = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
    '&mdash;': '—',
    '&ndash;': '–',
    '&hellip;': '…',
    '&rsquo;': '’',
    '&lsquo;': '‘',
    '&ldquo;': '“',
    '&rdquo;': '”',
    '&trade;': '™',
    '&copy;': '©',
    '&reg;': '®',
  };
  named.forEach((k, v) => t = t.replaceAll(k, v));

  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}
