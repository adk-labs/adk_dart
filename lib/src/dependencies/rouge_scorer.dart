class RougeScore {
  const RougeScore({
    required this.precision,
    required this.recall,
    required this.fmeasure,
  });

  final double precision;
  final double recall;
  final double fmeasure;

  @override
  String toString() {
    return 'RougeScore('
        'precision: $precision, '
        'recall: $recall, '
        'fmeasure: $fmeasure'
        ')';
  }
}

class RougeScorer {
  RougeScorer({List<String>? metrics})
    : metrics = List<String>.unmodifiable(
        _validateMetrics(metrics ?? <String>['rouge1']),
      );

  final List<String> metrics;

  Map<String, RougeScore> score({
    required String target,
    required String prediction,
  }) {
    final RougeScore rouge1 = rouge1Score(
      target: target,
      prediction: prediction,
    );
    final Map<String, RougeScore> result = <String, RougeScore>{};
    for (final String metric in _validateMetrics(metrics)) {
      result[metric] = rouge1;
    }
    return result;
  }

  static List<String> _validateMetrics(List<String> metrics) {
    if (metrics.isEmpty) {
      throw ArgumentError.value(
        metrics,
        'metrics',
        'must contain at least one metric.',
      );
    }

    final List<String> normalizedMetrics = <String>[];
    for (final String metric in metrics) {
      final String normalized = _normalizeMetric(metric);
      if (normalized != _rouge1Metric) {
        throw ArgumentError.value(
          metric,
          'metrics',
          'Unsupported metric "$metric". Only rouge1 is supported.',
        );
      }
      normalizedMetrics.add(metric);
    }
    return normalizedMetrics;
  }
}

RougeScore rouge1Score({required String target, required String prediction}) {
  final List<String> targetTokens = _tokenize(target);
  final List<String> predictionTokens = _tokenize(prediction);
  if (targetTokens.isEmpty || predictionTokens.isEmpty) {
    return const RougeScore(precision: 0.0, recall: 0.0, fmeasure: 0.0);
  }

  final Map<String, int> targetCounts = _countTokens(targetTokens);
  final Map<String, int> predictionCounts = _countTokens(predictionTokens);

  int overlap = 0;
  for (final MapEntry<String, int> entry in targetCounts.entries) {
    final int predictedCount = predictionCounts[entry.key] ?? 0;
    overlap += predictedCount < entry.value ? predictedCount : entry.value;
  }

  final double precision = overlap / predictionTokens.length;
  final double recall = overlap / targetTokens.length;
  final double fmeasure = (precision + recall) == 0
      ? 0.0
      : (2 * precision * recall) / (precision + recall);
  return RougeScore(precision: precision, recall: recall, fmeasure: fmeasure);
}

const String _rouge1Metric = 'rouge1';

String _normalizeMetric(String metric) {
  final String compact = metric.trim().toLowerCase().replaceAll(
    RegExp(r'[\s_-]+'),
    '',
  );
  if (compact.isEmpty) {
    throw ArgumentError.value(metric, 'metrics', 'must not contain blanks.');
  }
  return compact;
}

List<String> _tokenize(String input) {
  final List<String> tokens = <String>[];
  final StringBuffer current = StringBuffer();

  for (final int rune in input.runes) {
    if (_isTokenRune(rune)) {
      current.write(String.fromCharCode(rune).toLowerCase());
      continue;
    }
    if (current.length > 0) {
      tokens.add(current.toString());
      current.clear();
    }
  }

  if (current.length > 0) {
    tokens.add(current.toString());
  }
  return tokens;
}

bool _isTokenRune(int rune) {
  if (_isWhitespaceRune(rune) || _isPunctuationRune(rune)) {
    return false;
  }
  if ((rune >= 0x2600 && rune <= 0x27BF) ||
      (rune >= 0x1F300 && rune <= 0x1FAFF)) {
    return false;
  }
  return true;
}

bool _isWhitespaceRune(int rune) {
  return rune == 0x09 ||
      rune == 0x0A ||
      rune == 0x0B ||
      rune == 0x0C ||
      rune == 0x0D ||
      rune == 0x20 ||
      rune == 0x85 ||
      rune == 0xA0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200A) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202F ||
      rune == 0x205F ||
      rune == 0x3000;
}

bool _isPunctuationRune(int rune) {
  if ((rune >= 0x21 && rune <= 0x2F) ||
      (rune >= 0x3A && rune <= 0x40) ||
      (rune >= 0x5B && rune <= 0x60) ||
      (rune >= 0x7B && rune <= 0x7E)) {
    return true;
  }
  return (rune >= 0x2000 && rune <= 0x206F) ||
      (rune >= 0x2E00 && rune <= 0x2E7F) ||
      (rune >= 0x3000 && rune <= 0x303F) ||
      (rune >= 0xFE10 && rune <= 0xFE1F) ||
      (rune >= 0xFE30 && rune <= 0xFE6F) ||
      (rune >= 0xFF00 && rune <= 0xFF65);
}

Map<String, int> _countTokens(List<String> tokens) {
  final Map<String, int> counts = <String, int>{};
  for (final String token in tokens) {
    counts[token] = (counts[token] ?? 0) + 1;
  }
  return counts;
}
