/// Canonical form used to compare two feed URLs for equality: drops the scheme,
/// lowercases the host, and trims a trailing slash so `http://x/feed` and
/// `https://X/feed/` count as the same source. Shared by every de-duplication
/// path (cloud add/seed, import, and the local mirror) so they can't drift.
String normalizeFeedUrl(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  final uri = Uri.tryParse(t);
  if (uri == null || uri.host.isEmpty) return t.toLowerCase();
  var path = uri.path;
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  final q = uri.query;
  return '${uri.host.toLowerCase()}$path${q.isEmpty ? '' : '?$q'}';
}
