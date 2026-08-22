import 'package:flutter_test/flutter_test.dart';

import 'package:bastak_leads/scoring/keyword_scorer.dart';

void main() {
  const scorer = KeywordScorer();

  test('confirmed mill project with capacity scores hot', () {
    final r = scorer.score(
      title:
          'Acme Mills to build new 500 tons/day flour mill in Nigeria',
    );
    expect(r.score, greaterThanOrEqualTo(8));
    expect(r.isRelevant, isTrue);
    expect(r.country, 'Nigeria');
    expect(r.projectType, isNotEmpty);
  });

  test('generic commodity price news scores cold', () {
    final r = scorer.score(
      title: 'Wheat prices rise on weather forecast and export ban',
    );
    expect(r.score, lessThan(4));
    expect(r.isRelevant, isFalse);
  });

  test('grain silo tender is in scope even without a mill', () {
    final r = scorer.score(
      title: 'Tender: supply and installation of grain silo storage terminal',
    );
    expect(r.score, greaterThanOrEqualTo(4));
    expect(r.projectType, isNotEmpty);
  });
}
