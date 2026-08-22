/// KeywordScorer — a transparent, offline replacement for the old AI classifier.
///
/// It reproduces the *intent* of the original Claude prompt with weighted
/// keyword rules, so every score is explainable (see [ScoreResult.reasons])
/// and the user can tune the vocabulary from Settings. It answers one question:
/// how likely is this item a real SALES LEAD for a company selling grain/flour
/// lab QC equipment — i.e. someone building, expanding, or tendering for a
/// facility that would need those instruments?
///
/// Bands (mirroring the original guide):
///   8-10 = confirmed project / tender / expansion for an in-scope facility,
///          especially with a company, location, capacity, or budget.
///   4-7  = plausibly relevant but vague.
///   0-3  = generic commodity/price/policy news, vendor launches, earnings.
class ScoreResult {
  final int score; // 0..10
  final bool isRelevant;
  final String company;
  final String country;
  final String projectType;
  final List<String> reasons;

  const ScoreResult({
    required this.score,
    required this.isRelevant,
    this.company = '',
    this.country = '',
    this.projectType = '',
    this.reasons = const [],
  });

  String get reasonText => reasons.join(' · ');
}

/// User-tunable vocabulary. Defaults ship in the app; Settings can override.
class ScoringConfig {
  final List<String> facilityTerms;
  final List<String> intentTerms;
  final List<String> negativeTerms;
  final int relevanceCutoff;

  const ScoringConfig({
    this.facilityTerms = KeywordScorer.defaultFacilityTerms,
    this.intentTerms = KeywordScorer.defaultIntentTerms,
    this.negativeTerms = KeywordScorer.defaultNegativeTerms,
    this.relevanceCutoff = 4,
  });
}

class KeywordScorer {
  final ScoringConfig config;
  const KeywordScorer([this.config = const ScoringConfig()]);

  // --- Vocabulary ---------------------------------------------------------

  /// Facilities that buy grain/flour testing equipment. A hit here is what
  /// makes an item in-scope at all.
  static const List<String> defaultFacilityTerms = [
    'flour mill', 'grain mill', 'roller mill', 'milling plant',
    'milling complex', 'milling facility', 'feed mill', 'flour factory',
    'flour production', 'flour milling', 'grain milling', 'wheat milling',
    'maize mill', 'corn mill', 'rice mill', 'grain processing',
    'wheat processing', 'grain terminal', 'grain silo', 'grain elevator',
    'grain storage', 'grain handling', 'grain hub', 'semolina', 'pasta plant',
    'starch plant', 'cereal plant', 'food processing plant', 'silo complex',
    'un fabrikası', 'un değirmeni', 'değirmen tesisi',
    'мукомольный завод', 'мельничный комплекс', 'элеватор',
  ];

  /// Signals of a real project / buying event.
  static const List<String> defaultIntentTerms = [
    'tender', 'bid ', 'bidding', 'procurement', 'rfp', 'request for proposal',
    'contract awarded', 'contract signed', 'awarded contract', 'turnkey',
    'new plant', 'new mill', 'new factory', 'construction', 'constructing',
    'to build', 'will build', 'building a', 'commissioned', 'commission',
    'inaugurate', 'inaugurated', 'expansion', 'expand', 'expanding',
    'modernization', 'modernisation', 'modernize', 'upgrade', 'investment',
    'invest', 'greenfield', 'groundbreaking', 'ground-breaking',
    'supply and installation', 'installation of', 'to establish', 'establishing',
    'set up a', 'setting up', 'capacity of', 'production line', 'new facility',
  ];

  /// Generic/no-buy news that should pull the score down.
  static const List<String> defaultNegativeTerms = [
    'price', 'prices', 'futures', 'forecast', 'outlook', 'earnings',
    'quarterly results', 'share price', 'shares', 'stock', 'market report',
    'weather', 'harvest', 'crop yield', 'recipe', 'recall', 'obituary',
    'export ban', 'import duty', 'subsidy', 'inflation', 'shortage',
    'opinion', 'editorial', 'webinar', 'conference', 'appointment',
  ];

  // Capacity / money signals — the highest-intent evidence.
  static final RegExp _capacityRe = RegExp(
    r'\b\d[\d.,]*\s?(?:tons?|tonnes?|tpd|mt|metric tons?|t/day|tons per day|tonnes per day|bushels)\b',
    caseSensitive: false,
  );
  static final RegExp _moneyRe = RegExp(
    r'(?:[$€£]\s?\d[\d.,]*|\b\d[\d.,]*\s?(?:million|billion|mn|bn)\b|\b(?:usd|eur|pkr|try|kes|ngn|egp|rub)\s?\d)',
    caseSensitive: false,
  );

  // --- Country detection --------------------------------------------------

  static const Map<String, List<String>> _countryAliases = {
    'Pakistan': ['pakistan', 'karachi', 'lahore', 'punjab', 'sindh', 'pakistani'],
    'Turkey': ['turkey', 'türkiye', 'turkish', 'istanbul', 'ankara', 'izmir'],
    'Nigeria': ['nigeria', 'lagos', 'abuja', 'nigerian', 'kano'],
    'Kenya': ['kenya', 'nairobi', 'mombasa', 'kenyan'],
    'Egypt': ['egypt', 'cairo', 'egyptian', 'alexandria'],
    'Ethiopia': ['ethiopia', 'addis ababa', 'ethiopian'],
    'Tanzania': ['tanzania', 'dar es salaam', 'tanzanian'],
    'Uganda': ['uganda', 'kampala', 'ugandan'],
    'Mozambique': ['mozambique', 'maputo'],
    'Kazakhstan': ['kazakhstan', 'almaty', 'astana', 'kazakh'],
    'Russia': ['russia', 'russian', 'moscow'],
    'Ukraine': ['ukraine', 'ukrainian', 'kyiv', 'odesa', 'odessa'],
    'Saudi Arabia': ['saudi arabia', 'saudi', 'riyadh', 'jeddah'],
    'UAE': ['uae', 'united arab emirates', 'dubai', 'abu dhabi'],
    'India': ['india', 'indian', 'mumbai', 'delhi'],
    'Bangladesh': ['bangladesh', 'dhaka', 'bangladeshi'],
    'Morocco': ['morocco', 'casablanca', 'moroccan'],
    'Algeria': ['algeria', 'algiers', 'algerian'],
    'Ghana': ['ghana', 'accra', 'ghanaian'],
    'Iraq': ['iraq', 'baghdad', 'iraqi'],
    'United States': ['united states', ' usa ', ' u.s. ', 'american'],
  };

  static final RegExp _companyRe = RegExp(
    r'([A-Z][A-Za-z&.\-]+(?:\s+[A-Z][A-Za-z&.\-]+){0,3}\s+'
    r'(?:Mills?|Milling|Flour|Grain|Foods?|Industries|Group|Holdings?|'
    r'Company|Co\.?|Ltd\.?|Limited|Inc\.?|LLC|Corporation|Corp\.?|'
    r'Agro|Commodities|Enterprises))',
  );

  // --- Scoring ------------------------------------------------------------

  ScoreResult score({required String title, String summary = ''}) {
    // The Title is authoritative; the summary may contain unrelated snippet
    // text, so it contributes at a discount and never alone.
    final t = title.toLowerCase();
    final full = '$title\n$summary';
    final low = full.toLowerCase();
    final reasons = <String>[];

    // 1. Facility match (title weighted higher than summary-only).
    final facilityInTitle =
        config.facilityTerms.where((k) => t.contains(k)).toList();
    final facilityAnywhere =
        config.facilityTerms.where((k) => low.contains(k)).toList();
    final hasFacility = facilityAnywhere.isNotEmpty;

    int score;
    if (facilityInTitle.isNotEmpty) {
      score = 5;
      reasons.add('In-scope facility in title (${facilityInTitle.first})');
    } else if (facilityAnywhere.isNotEmpty) {
      score = 4;
      reasons.add('In-scope facility mentioned (${facilityAnywhere.first})');
    } else {
      // No facility at all -> generic grain/commodity news at best.
      score = 1;
      reasons.add('No in-scope facility mentioned');
    }

    // 2. Intent signals (project/tender/expansion).
    final intentHits =
        config.intentTerms.where((k) => low.contains(k)).toList();
    if (hasFacility && intentHits.isNotEmpty) {
      score += intentHits.length >= 2 ? 3 : 2;
      reasons.add('Project intent (${intentHits.take(2).join(", ").trim()})');
    } else if (intentHits.isNotEmpty) {
      reasons.add('Intent words present but no facility — likely not a lead');
    }

    // 3. Capacity / budget — strongest buying evidence.
    if (hasFacility && _capacityRe.hasMatch(low)) {
      score += 2;
      reasons.add('Stated capacity/volume');
    }
    if (hasFacility && _moneyRe.hasMatch(low)) {
      score += 2;
      reasons.add('Stated budget/investment figure');
    }

    // 4. Company detected -> higher confidence it's a concrete project.
    final company = _detectCompany(full);
    if (hasFacility && company.isNotEmpty) {
      score += 1;
      reasons.add('Named company ($company)');
    }

    // 5. Negative signals.
    final negHits =
        config.negativeTerms.where((k) => low.contains(k)).toList();
    if (negHits.isNotEmpty) {
      final penalty = negHits.length >= 2 ? 3 : 2;
      score -= penalty;
      reasons.add('Generic/commodity signals (${negHits.take(2).join(", ")})');
    }

    score = score.clamp(0, 10);

    final country = _detectCountry(low);
    final projectType = _projectType(intentHits, hasFacility);

    return ScoreResult(
      score: score,
      isRelevant: hasFacility && score >= config.relevanceCutoff,
      company: company,
      country: country,
      projectType: projectType,
      reasons: reasons,
    );
  }

  String _detectCompany(String text) {
    final m = _companyRe.firstMatch(text);
    if (m == null) return '';
    final raw = m.group(1)?.trim() ?? '';
    // Guard against catching a sentence start like "The New Mills".
    if (raw.split(RegExp(r'\s+')).length > 5) return '';
    return raw;
  }

  String _detectCountry(String low) {
    final padded = ' $low ';
    String? best;
    for (final entry in _countryAliases.entries) {
      for (final alias in entry.value) {
        if (padded.contains(alias)) {
          best = entry.key;
          break;
        }
      }
      if (best != null) break;
    }
    return best ?? '';
  }

  String _projectType(List<String> intent, bool hasFacility) {
    if (!hasFacility) return '';
    bool any(List<String> ks) => intent.any((h) => ks.contains(h));
    if (any(['tender', 'bid ', 'bidding', 'procurement', 'rfp',
        'request for proposal'])) {
      return 'tender';
    }
    if (any(['contract awarded', 'contract signed', 'awarded contract',
        'turnkey'])) {
      return 'contract';
    }
    if (any(['expansion', 'expand', 'expanding', 'modernization',
        'modernisation', 'modernize', 'upgrade'])) {
      return 'expansion';
    }
    if (any(['new plant', 'new mill', 'new factory', 'construction',
        'constructing', 'to build', 'will build', 'greenfield',
        'groundbreaking', 'new facility'])) {
      return 'new plant';
    }
    if (any(['investment', 'invest'])) return 'investment';
    return intent.isNotEmpty ? 'project' : '';
  }
}
