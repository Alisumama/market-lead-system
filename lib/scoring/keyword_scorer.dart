import '../data/models/lead.dart';

/// The result of scoring one item.
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

/// The full, user-configurable rules engine config: scoring vocabulary +
/// weights + acceptance/rejection filters. Serializable so it can be exported,
/// shared and imported like a source registry.
class ScoringConfig {
  // ---- vocabulary ----
  final List<String> facilityTerms;
  final List<String> intentTerms;
  final List<String> negativeTerms;
  final List<String> requiredKeywords; // must contain at least one (if set)
  final List<String> blockedKeywords; // reject if any present

  // ---- scoring weights ----
  final int facilityWeight; // base when an in-scope facility is in the title
  final int intentWeight; // per project-intent signal
  final int capacityWeight; // stated capacity/volume
  final int budgetWeight; // stated budget/investment
  final int companyWeight; // named company
  final int negativeWeight; // penalty per generic/negative signal
  final int recencyBoost; // + when published within recencyDays
  final int recencyDays;
  final int tenderBoost; // + for tender/procurement sources (e.g. World Bank)
  final int relevanceCutoff; // isRelevant threshold

  // ---- acceptance / rejection filters ----
  final bool requireFacility; // reject items with no in-scope facility
  final int minScoreToStore; // reject below this score (0 = keep all)
  final int maxAgeDays; // reject older than N days (0 = no limit)
  final bool rejectUndated; // reject items with no detectable publish date
  final Set<String> allowedCountries; // empty = all
  final Set<String> blockedCountries; // reject these (applied after allow-list)
  final Set<String> allowedLanguages; // empty = all (e.g. en, tr, ru)
  final Set<String> allowedSourceKinds; // storage values; empty = all
  final int minCapacityTpd; // reject if a stated capacity is below this (0=off)
  final int minBudgetUsd; // reject if a stated budget is below this (0=off)

  const ScoringConfig({
    this.facilityTerms = defaultFacilityTerms,
    this.intentTerms = defaultIntentTerms,
    this.negativeTerms = defaultNegativeTerms,
    this.requiredKeywords = const [],
    this.blockedKeywords = const [],
    this.facilityWeight = 5,
    this.intentWeight = 2,
    this.capacityWeight = 2,
    this.budgetWeight = 2,
    this.companyWeight = 1,
    this.negativeWeight = 2,
    this.recencyBoost = 0,
    this.recencyDays = 30,
    this.tenderBoost = 0,
    this.relevanceCutoff = 4,
    this.requireFacility = false,
    this.minScoreToStore = 0,
    this.maxAgeDays = 0,
    this.rejectUndated = false,
    this.allowedCountries = const {},
    this.blockedCountries = const {},
    this.allowedLanguages = const {},
    this.allowedSourceKinds = const {},
    this.minCapacityTpd = 0,
    this.minBudgetUsd = 0,
  });

  ScoringConfig copyWith({
    List<String>? facilityTerms,
    List<String>? intentTerms,
    List<String>? negativeTerms,
    List<String>? requiredKeywords,
    List<String>? blockedKeywords,
    int? facilityWeight,
    int? intentWeight,
    int? capacityWeight,
    int? budgetWeight,
    int? companyWeight,
    int? negativeWeight,
    int? recencyBoost,
    int? recencyDays,
    int? tenderBoost,
    int? relevanceCutoff,
    bool? requireFacility,
    int? minScoreToStore,
    int? maxAgeDays,
    bool? rejectUndated,
    Set<String>? allowedCountries,
    Set<String>? blockedCountries,
    Set<String>? allowedLanguages,
    Set<String>? allowedSourceKinds,
    int? minCapacityTpd,
    int? minBudgetUsd,
  }) {
    return ScoringConfig(
      facilityTerms: facilityTerms ?? this.facilityTerms,
      intentTerms: intentTerms ?? this.intentTerms,
      negativeTerms: negativeTerms ?? this.negativeTerms,
      requiredKeywords: requiredKeywords ?? this.requiredKeywords,
      blockedKeywords: blockedKeywords ?? this.blockedKeywords,
      facilityWeight: facilityWeight ?? this.facilityWeight,
      intentWeight: intentWeight ?? this.intentWeight,
      capacityWeight: capacityWeight ?? this.capacityWeight,
      budgetWeight: budgetWeight ?? this.budgetWeight,
      companyWeight: companyWeight ?? this.companyWeight,
      negativeWeight: negativeWeight ?? this.negativeWeight,
      recencyBoost: recencyBoost ?? this.recencyBoost,
      recencyDays: recencyDays ?? this.recencyDays,
      tenderBoost: tenderBoost ?? this.tenderBoost,
      relevanceCutoff: relevanceCutoff ?? this.relevanceCutoff,
      requireFacility: requireFacility ?? this.requireFacility,
      minScoreToStore: minScoreToStore ?? this.minScoreToStore,
      maxAgeDays: maxAgeDays ?? this.maxAgeDays,
      rejectUndated: rejectUndated ?? this.rejectUndated,
      allowedCountries: allowedCountries ?? this.allowedCountries,
      blockedCountries: blockedCountries ?? this.blockedCountries,
      allowedLanguages: allowedLanguages ?? this.allowedLanguages,
      allowedSourceKinds: allowedSourceKinds ?? this.allowedSourceKinds,
      minCapacityTpd: minCapacityTpd ?? this.minCapacityTpd,
      minBudgetUsd: minBudgetUsd ?? this.minBudgetUsd,
    );
  }

  Map<String, dynamic> toJson() => {
        'facilityTerms': facilityTerms,
        'intentTerms': intentTerms,
        'negativeTerms': negativeTerms,
        'requiredKeywords': requiredKeywords,
        'blockedKeywords': blockedKeywords,
        'facilityWeight': facilityWeight,
        'intentWeight': intentWeight,
        'capacityWeight': capacityWeight,
        'budgetWeight': budgetWeight,
        'companyWeight': companyWeight,
        'negativeWeight': negativeWeight,
        'recencyBoost': recencyBoost,
        'recencyDays': recencyDays,
        'tenderBoost': tenderBoost,
        'relevanceCutoff': relevanceCutoff,
        'requireFacility': requireFacility,
        'minScoreToStore': minScoreToStore,
        'maxAgeDays': maxAgeDays,
        'rejectUndated': rejectUndated,
        'allowedCountries': allowedCountries.toList(),
        'blockedCountries': blockedCountries.toList(),
        'allowedLanguages': allowedLanguages.toList(),
        'allowedSourceKinds': allowedSourceKinds.toList(),
        'minCapacityTpd': minCapacityTpd,
        'minBudgetUsd': minBudgetUsd,
      };

  factory ScoringConfig.fromJson(Map<String, dynamic> m) {
    List<String> list(String k, List<String> d) =>
        (m[k] as List?)?.map((e) => e.toString()).toList() ?? d;
    Set<String> set(String k) =>
        (m[k] as List?)?.map((e) => e.toString()).toSet() ?? const {};
    int i(String k, int d) => (m[k] as num?)?.toInt() ?? d;
    bool b(String k, bool d) => m[k] as bool? ?? d;
    return ScoringConfig(
      facilityTerms: list('facilityTerms', defaultFacilityTerms),
      intentTerms: list('intentTerms', defaultIntentTerms),
      negativeTerms: list('negativeTerms', defaultNegativeTerms),
      requiredKeywords: list('requiredKeywords', const []),
      blockedKeywords: list('blockedKeywords', const []),
      facilityWeight: i('facilityWeight', 5),
      intentWeight: i('intentWeight', 2),
      capacityWeight: i('capacityWeight', 2),
      budgetWeight: i('budgetWeight', 2),
      companyWeight: i('companyWeight', 1),
      negativeWeight: i('negativeWeight', 2),
      recencyBoost: i('recencyBoost', 0),
      recencyDays: i('recencyDays', 30),
      tenderBoost: i('tenderBoost', 0),
      relevanceCutoff: i('relevanceCutoff', 4),
      requireFacility: b('requireFacility', false),
      minScoreToStore: i('minScoreToStore', 0),
      maxAgeDays: i('maxAgeDays', 0),
      rejectUndated: b('rejectUndated', false),
      allowedCountries: set('allowedCountries'),
      blockedCountries: set('blockedCountries'),
      allowedLanguages: set('allowedLanguages'),
      allowedSourceKinds: set('allowedSourceKinds'),
      minCapacityTpd: i('minCapacityTpd', 0),
      minBudgetUsd: i('minBudgetUsd', 0),
    );
  }

  static const List<String> defaultFacilityTerms =
      KeywordScorer.defaultFacilityTerms;
  static const List<String> defaultIntentTerms =
      KeywordScorer.defaultIntentTerms;
  static const List<String> defaultNegativeTerms =
      KeywordScorer.defaultNegativeTerms;
}

/// A named, saveable rule set. Lets the user keep several tuned configs
/// (e.g. "Strict", "Wide net", "Tenders only") and switch between them.
class RuleProfile {
  final String name;
  final ScoringConfig config;
  const RuleProfile(this.name, this.config);

  Map<String, dynamic> toJson() => {'name': name, 'config': config.toJson()};

  factory RuleProfile.fromJson(Map<String, dynamic> m) => RuleProfile(
        (m['name'] ?? '').toString(),
        ScoringConfig.fromJson(
            (m['config'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );
}

/// Why an item was rejected (null when accepted).
enum RejectReason {
  noFacility,
  missingRequiredKeyword,
  blockedKeyword,
  tooOld,
  undated,
  countryNotAllowed,
  countryBlocked,
  languageNotAllowed,
  sourceNotAllowed,
  belowMinScore,
  belowMinCapacity,
  belowMinBudget,
}

extension RejectReasonX on RejectReason {
  String get label => switch (this) {
        RejectReason.noFacility => 'no in-scope facility',
        RejectReason.missingRequiredKeyword => 'missing required keyword',
        RejectReason.blockedKeyword => 'contains a blocked keyword',
        RejectReason.tooOld => 'older than allowed',
        RejectReason.undated => 'no publish date',
        RejectReason.countryNotAllowed => 'country not allowed',
        RejectReason.countryBlocked => 'country blocked',
        RejectReason.languageNotAllowed => 'language not allowed',
        RejectReason.sourceNotAllowed => 'source type not allowed',
        RejectReason.belowMinScore => 'below minimum score',
        RejectReason.belowMinCapacity => 'capacity below minimum',
        RejectReason.belowMinBudget => 'budget below minimum',
      };
}

/// Offline, transparent, fully-configurable scorer + acceptance gate.
class KeywordScorer {
  final ScoringConfig config;
  const KeywordScorer([this.config = const ScoringConfig()]);

  // --- default vocabulary ---
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
  static const List<String> defaultNegativeTerms = [
    'price', 'prices', 'futures', 'forecast', 'outlook', 'earnings',
    'quarterly results', 'share price', 'shares', 'stock', 'market report',
    'weather', 'harvest', 'crop yield', 'recipe', 'recall', 'obituary',
    'export ban', 'import duty', 'subsidy', 'inflation', 'shortage',
    'opinion', 'editorial', 'webinar', 'conference', 'appointment',
  ];

  static final RegExp _capacityRe = RegExp(
    r'\b\d[\d.,]*\s?(?:tons?|tonnes?|tpd|mt|metric tons?|t/day|tons per day|tonnes per day|bushels)\b',
    caseSensitive: false,
  );
  static final RegExp _moneyRe = RegExp(
    r'(?:[$€£]\s?\d[\d.,]*|\b\d[\d.,]*\s?(?:million|billion|mn|bn)\b|\b(?:usd|eur|pkr|try|kes|ngn|egp|rub)\s?\d)',
    caseSensitive: false,
  );

  // Value-extracting variants used by the min-capacity / min-budget filters.
  static final RegExp _capValueRe = RegExp(
    r'(\d[\d.,]*)\s?(?:tons?|tonnes?|tpd|mt|metric tons?|t/day|tons?\s?per\s?day|tonnes?\s?per\s?day)\b',
    caseSensitive: false,
  );
  static final RegExp _moneySymRe = RegExp(
    r'[$€£]\s?(\d[\d.,]*)\s?(billion|million|bn|mn|b|m)?',
    caseSensitive: false,
  );
  static final RegExp _moneyCodeRe = RegExp(
    r'\b(?:usd|eur|gbp|pkr|try|kes|ngn|egp|rub|inr)\s?(\d[\d.,]*)\s?'
    r'(billion|million|bn|mn|b|m)?',
    caseSensitive: false,
  );
  static final RegExp _moneyWordRe = RegExp(
    r'\b(\d[\d.,]*)\s?(billion|million|bn|mn)\s?'
    r'(?:usd|us\$|dollars?|euros?|eur|pounds?)\b',
    caseSensitive: false,
  );

  static final RegExp _wordCharRe = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Whole-word / whole-phrase containment: true only when [needle] appears in
  /// [haystack] not glued to surrounding letters or digits — so "mill" no
  /// longer matches "million" and "invest" no longer matches "investigation".
  /// [haystack] is expected already-lowercased; [needle] is trimmed+lowered.
  static bool _containsWord(String haystack, String needle) {
    final n = needle.trim().toLowerCase();
    if (n.isEmpty) return false;
    var from = 0;
    while (true) {
      final i = haystack.indexOf(n, from);
      if (i < 0) return false;
      final beforeOk = i == 0 || !_wordCharRe.hasMatch(haystack[i - 1]);
      final end = i + n.length;
      final afterOk =
          end >= haystack.length || !_wordCharRe.hasMatch(haystack[end]);
      if (beforeOk && afterOk) return true;
      from = i + 1;
    }
  }

  static double _parseNum(String s) =>
      double.tryParse(s.replaceAll(',', '')) ?? 0;

  /// Largest stated throughput in the text, in tons/day (0 if none found).
  /// Annual vs daily figures can't be told apart reliably, so this is a
  /// best-effort magnitude used only for the coarse min-capacity gate.
  static int _maxCapacity(String low) {
    var best = 0;
    for (final m in _capValueRe.allMatches(low)) {
      final v = _parseNum(m.group(1)!).round();
      if (v > best) best = v;
    }
    return best;
  }

  static int _mult(String? mag) => switch (mag?.toLowerCase()) {
        'billion' || 'bn' || 'b' => 1000000000,
        'million' || 'mn' || 'm' => 1000000,
        _ => 1,
      };

  /// Largest stated monetary figure in the text, in whole USD-equivalent
  /// units (0 if none found). Only figures with an explicit currency symbol,
  /// code or word count — so "20 million tons" is not read as money.
  static int _maxBudget(String low) {
    var best = 0;
    void scan(RegExp re) {
      for (final m in re.allMatches(low)) {
        final v = (_parseNum(m.group(1)!) * _mult(m.group(2))).round();
        if (v > best) best = v;
      }
    }

    scan(_moneySymRe);
    scan(_moneyCodeRe);
    scan(_moneyWordRe);
    return best;
  }

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
    'United States': ['united states', 'usa', 'u.s.', 'american'],
  };

  static final RegExp _companyRe = RegExp(
    r'([A-Z][A-Za-z&.\-]+(?:\s+[A-Z][A-Za-z&.\-]+){0,3}\s+'
    r'(?:Mills?|Milling|Flour|Grain|Foods?|Industries|Group|Holdings?|'
    r'Company|Co\.?|Ltd\.?|Limited|Inc\.?|LLC|Corporation|Corp\.?|'
    r'Agro|Commodities|Enterprises))',
  );

  // --- scoring ---
  ScoreResult score({
    required String title,
    String summary = '',
    String publishedDate = '',
    SourceKind? sourceKind,
  }) {
    final t = title.toLowerCase();
    final full = '$title\n$summary';
    final low = full.toLowerCase();
    final reasons = <String>[];

    final facilityInTitle =
        config.facilityTerms.where((k) => _containsWord(t, k)).toList();
    final facilityAnywhere =
        config.facilityTerms.where((k) => _containsWord(low, k)).toList();
    final hasFacility = facilityAnywhere.isNotEmpty;

    int score;
    if (facilityInTitle.isNotEmpty) {
      score = config.facilityWeight;
      reasons.add('In-scope facility in title (${facilityInTitle.first})');
    } else if (facilityAnywhere.isNotEmpty) {
      score = (config.facilityWeight - 1).clamp(0, 10);
      reasons.add('In-scope facility mentioned (${facilityAnywhere.first})');
    } else {
      score = 1;
      reasons.add('No in-scope facility mentioned');
    }

    final intentHits =
        config.intentTerms.where((k) => _containsWord(low, k)).toList();
    if (hasFacility && intentHits.isNotEmpty) {
      score += intentHits.length >= 2
          ? config.intentWeight + 1
          : config.intentWeight;
      reasons.add('Project intent (${intentHits.take(2).join(", ").trim()})');
    } else if (intentHits.isNotEmpty) {
      reasons.add('Intent words present but no facility — likely not a lead');
    }

    if (hasFacility && _capacityRe.hasMatch(low)) {
      score += config.capacityWeight;
      reasons.add('Stated capacity/volume');
    }
    if (hasFacility && _moneyRe.hasMatch(low)) {
      score += config.budgetWeight;
      reasons.add('Stated budget/investment figure');
    }

    final company = _detectCompany(full);
    if (hasFacility && company.isNotEmpty) {
      score += config.companyWeight;
      reasons.add('Named company ($company)');
    }

    if (config.tenderBoost > 0 &&
        sourceKind == SourceKind.worldBank &&
        hasFacility) {
      score += config.tenderBoost;
      reasons.add('Tender/procurement source');
    }

    if (config.recencyBoost > 0 &&
        hasFacility &&
        _isRecent(publishedDate, config.recencyDays)) {
      score += config.recencyBoost;
      reasons.add('Recent (≤ ${config.recencyDays}d)');
    }

    final negHits =
        config.negativeTerms.where((k) => _containsWord(low, k)).toList();
    if (negHits.isNotEmpty) {
      final penalty = config.negativeWeight * (negHits.length >= 2 ? 1.5 : 1);
      score -= penalty.round();
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

  /// Applies the acceptance/rejection filters. Returns the reason to reject, or
  /// null to accept. [country]/[language] default to the lead's tag; scoring
  /// detected country is passed in when available.
  RejectReason? reject({
    required String title,
    String summary = '',
    String publishedDate = '',
    String country = '',
    String language = '',
    SourceKind? sourceKind,
    required int score,
  }) {
    final full = '$title\n$summary';
    final low = full.toLowerCase();

    if (config.blockedKeywords.any((k) => _containsWord(low, k))) {
      return RejectReason.blockedKeyword;
    }
    if (config.requiredKeywords.isNotEmpty &&
        !config.requiredKeywords.any((k) => _containsWord(low, k))) {
      return RejectReason.missingRequiredKeyword;
    }
    if (config.requireFacility &&
        !config.facilityTerms.any((k) => _containsWord(low, k))) {
      return RejectReason.noFacility;
    }
    if (config.rejectUndated && publishedDate.trim().isEmpty) {
      return RejectReason.undated;
    }
    if (config.maxAgeDays > 0 && publishedDate.trim().isNotEmpty) {
      if (!_isRecent(publishedDate, config.maxAgeDays)) {
        return RejectReason.tooOld;
      }
    }
    if (config.allowedLanguages.isNotEmpty &&
        !config.allowedLanguages.contains(language)) {
      return RejectReason.languageNotAllowed;
    }
    if (config.allowedSourceKinds.isNotEmpty &&
        sourceKind != null &&
        !config.allowedSourceKinds.contains(sourceKind.storageValue)) {
      return RejectReason.sourceNotAllowed;
    }
    if (config.allowedCountries.isNotEmpty ||
        config.blockedCountries.isNotEmpty) {
      final detected = _detectCountry(low);
      bool hits(Set<String> s) =>
          s.contains(country) || (detected.isNotEmpty && s.contains(detected));
      if (config.blockedCountries.isNotEmpty && hits(config.blockedCountries)) {
        return RejectReason.countryBlocked;
      }
      if (config.allowedCountries.isNotEmpty &&
          !hits(config.allowedCountries)) {
        return RejectReason.countryNotAllowed;
      }
    }
    if (config.minCapacityTpd > 0) {
      final cap = _maxCapacity(low);
      if (cap > 0 && cap < config.minCapacityTpd) {
        return RejectReason.belowMinCapacity;
      }
    }
    if (config.minBudgetUsd > 0) {
      final bud = _maxBudget(low);
      if (bud > 0 && bud < config.minBudgetUsd) {
        return RejectReason.belowMinBudget;
      }
    }
    if (config.minScoreToStore > 0 && score < config.minScoreToStore) {
      return RejectReason.belowMinScore;
    }
    return null;
  }

  bool _isRecent(String publishedDate, int days) {
    if (publishedDate.trim().isEmpty) return false;
    final d = DateTime.tryParse(publishedDate);
    if (d == null) return false;
    return DateTime.now().difference(d).inDays <= days;
  }

  String _detectCompany(String text) {
    final m = _companyRe.firstMatch(text);
    if (m == null) return '';
    final raw = m.group(1)?.trim() ?? '';
    if (raw.split(RegExp(r'\s+')).length > 5) return '';
    return raw;
  }

  String _detectCountry(String low) {
    for (final entry in _countryAliases.entries) {
      for (final alias in entry.value) {
        if (_containsWord(low, alias)) return entry.key;
      }
    }
    return '';
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
