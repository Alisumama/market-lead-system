import 'package:bastak_leads/collectors/url_unwrap.dart';
import 'package:bastak_leads/data/models/lead.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dedup key', () {
    test('same story from native feed and Google News collapses', () {
      final a = Lead.computeDedupKey('New flour mill opens in Kano');
      final b = Lead.computeDedupKey('New flour mill opens in Kano - World Grain');
      expect(a, b);
      expect(a.isNotEmpty, isTrue);
    });

    test('punctuation and case are normalized away', () {
      // Punctuation becomes a space and runs of whitespace collapse.
      expect(
        Lead.computeDedupKey('Acme Mills:  500 t/day PLANT!'),
        'acme mills 500 t day plant',
      );
    });

    test('does not strip a long tail that is not a publisher', () {
      final k = Lead.computeDedupKey(
          'Company signs deal - the largest grain terminal project in the region');
      // The long tail is kept, so it differs from just the head.
      expect(k, isNot(Lead.computeDedupKey('Company signs deal')));
    });

    test('non-latin titles still produce a key', () {
      expect(Lead.computeDedupKey('Мукомольный завод открылся'), isNotEmpty);
    });
  });

  group('url unwrap', () {
    test('extracts url= parameter from a Google redirect', () {
      final out = unwrapUrl(
          'https://news.google.com/__i/rss/rd/articles/xyz?oc=5&url=https://www.world-grain.com/articles/123');
      expect(out, 'https://www.world-grain.com/articles/123');
    });

    test('leaves non-Google URLs untouched', () {
      const u = 'https://www.millingandgrain.com/feed/story-42';
      expect(unwrapUrl(u), u);
    });

    test('returns original when a token cannot be decoded', () {
      const u = 'https://news.google.com/rss/articles/not-base64!';
      expect(unwrapUrl(u), u);
    });
  });
}
