import 'dart:convert';

/// Turns a Google News RSS redirect link into the real publisher URL, so
/// "Open source" lands on the article (not a Google interstitial) and the same
/// story from different feeds deduplicates by URL too.
///
/// Two deterministic, network-free strategies:
///   1. Older links carry the target in a `?url=` query parameter.
///   2. Newer `.../articles/CBMi…` links base64-encode a protobuf that embeds
///      the target URL as a plain substring — we decode and extract it.
/// If neither works (some newest formats need a network round-trip), the
/// original Google URL is returned unchanged — it still opens in a browser.
String unwrapUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  if (!uri.host.contains('news.google.')) return url;

  // 1) ?url= parameter (older redirect style)
  final q = uri.queryParameters['url'];
  if (q != null && q.startsWith('http')) return q;

  // 2) decode the articles/<token> segment
  final segs = uri.pathSegments;
  final i = segs.indexOf('articles');
  if (i != -1 && i + 1 < segs.length) {
    final decoded = _decodeArticleToken(segs[i + 1]);
    if (decoded != null) return decoded;
  }
  return url;
}

String? _decodeArticleToken(String token) {
  try {
    var b = token.replaceAll('-', '+').replaceAll('_', '/');
    while (b.length % 4 != 0) {
      b += '=';
    }
    final bytes = base64.decode(b);
    // Bytes are a protobuf; the URL sits inside as an ASCII substring.
    final text = String.fromCharCodes(bytes);
    final m = RegExp(r'https?://[^\x00-\x1f\x7f-\xff"\\]+').firstMatch(text);
    if (m != null) {
      final found = m.group(0)!;
      if (!found.contains('google.com') && Uri.tryParse(found) != null) {
        return found;
      }
    }
  } catch (_) {
    // Not a decodable token — fall back to the original URL.
  }
  return null;
}
