import 'package:bastak_leads/scoring/keyword_scorer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('whole-word matching', () {
    const scorer = KeywordScorer();

    test('"mill" does not match "million" (facility false positive)', () {
      // "million" contains "mill" as a substring but not as a word.
      final s = scorer.score(
          title: 'Wheat prices hit a million dollar market outlook');
      expect(s.reasons.first, contains('No in-scope facility'));
    });

    test('a real facility phrase still scores', () {
      final s = scorer.score(
          title: 'New flour mill to be built with 500 tons/day capacity');
      expect(s.score, greaterThan(4));
      expect(s.isRelevant, isTrue);
    });

    test('"invest" does not match "investigation"', () {
      // Whole-word: an investigation article should not read as project intent.
      final s = scorer.score(
          title: 'Police investigation into flour mill fire in Lagos');
      expect(s.reasons.any((r) => r.startsWith('Project intent')), isFalse);
    });
  });

  group('capacity gate', () {
    test('rejects a stated capacity below the minimum', () {
      const scorer = KeywordScorer(ScoringConfig(minCapacityTpd: 200));
      final r = scorer.reject(
          title: 'Small flour mill with 50 tons per day opens', score: 6);
      expect(r, RejectReason.belowMinCapacity);
    });

    test('keeps a large stated capacity', () {
      const scorer = KeywordScorer(ScoringConfig(minCapacityTpd: 200));
      final r = scorer.reject(
          title: 'New flour mill with 800 tons/day capacity', score: 6);
      expect(r, isNull);
    });

    test('keeps items with no stated capacity', () {
      const scorer = KeywordScorer(ScoringConfig(minCapacityTpd: 200));
      final r = scorer.reject(title: 'New flour mill to open in Kenya', score: 6);
      expect(r, isNull);
    });
  });

  group('budget gate', () {
    test('rejects a small stated budget', () {
      const scorer = KeywordScorer(ScoringConfig(minBudgetUsd: 1000000));
      final r = scorer.reject(
          title: 'Flour mill upgrade worth \$200,000 announced', score: 6);
      expect(r, RejectReason.belowMinBudget);
    });

    test('keeps a large stated budget (\$2.5 million)', () {
      const scorer = KeywordScorer(ScoringConfig(minBudgetUsd: 1000000));
      final r = scorer.reject(
          title: 'Grain terminal: \$2.5 million investment', score: 6);
      expect(r, isNull);
    });

    test('does not read "20 million tons" as money', () {
      const scorer = KeywordScorer(ScoringConfig(minBudgetUsd: 1000000));
      // 20 million *tons* is capacity, not a sub-threshold budget → keep.
      final r = scorer.reject(
          title: 'Grain silo handles 20 million tons of wheat', score: 6);
      expect(r, isNull);
    });
  });

  group('blocked countries', () {
    test('rejects a blocked country detected in text', () {
      const scorer =
          KeywordScorer(ScoringConfig(blockedCountries: {'Russia'}));
      final r = scorer.reject(
          title: 'New flour mill opens in Moscow, Russia', score: 6);
      expect(r, RejectReason.countryBlocked);
    });
  });

  test('config round-trips through JSON including new fields', () {
    const c = ScoringConfig(
      minCapacityTpd: 150,
      minBudgetUsd: 500000,
      blockedCountries: {'Russia'},
    );
    final back = ScoringConfig.fromJson(c.toJson());
    expect(back.minCapacityTpd, 150);
    expect(back.minBudgetUsd, 500000);
    expect(back.blockedCountries, {'Russia'});
  });

  test('rule profile round-trips through JSON', () {
    const p = RuleProfile('Strict', ScoringConfig(minScoreToStore: 5));
    final back = RuleProfile.fromJson(p.toJson());
    expect(back.name, 'Strict');
    expect(back.config.minScoreToStore, 5);
  });
}
