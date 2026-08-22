/// Best-effort parse of an RSS/Atom date string into 'YYYY-MM-DD'.
/// Returns '' when nothing usable is found (mirrors parse_date_to_iso in the
/// original init_db.py). Never treats the scrape date as a publish date.
String parsePublishedDate(String? raw) {
  if (raw == null) return '';
  final s = raw.trim();
  if (s.isEmpty) return '';

  // ISO 8601 (Atom <published>/<updated>): 2015-06-15T10:30:00Z
  final iso = DateTime.tryParse(s.replaceFirst('Z', '').trim());
  if (iso != null) return _fmt(iso);

  // RFC 2822 (RSS <pubDate>): Mon, 15 Jun 2015 10:30:00 GMT
  final rfc = _parseRfc2822(s);
  if (rfc != null) return _fmt(rfc);

  // Bare YYYY-MM-DD prefix as a last resort.
  final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m != null) return '${m.group(1)}-${m.group(2)}-${m.group(3)}';

  return '';
}

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

DateTime? _parseRfc2822(String s) {
  // e.g. "Mon, 15 Jun 2015 10:30:00 GMT"  or  "15 Jun 2015 10:30:00 +0000"
  final m = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})',
  ).firstMatch(s);
  if (m == null) return null;
  final day = int.tryParse(m.group(1)!);
  final mon = _months[m.group(2)!.toLowerCase()];
  final year = int.tryParse(m.group(3)!);
  if (day == null || mon == null || year == null) return null;
  return DateTime(year, mon, day);
}
