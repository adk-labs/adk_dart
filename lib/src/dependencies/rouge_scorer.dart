class RougeScore {
  const RougeScore({
    required this.precision,
    required this.recall,
    required this.fmeasure,
  });

  final double precision;
  final double recall;
  final double fmeasure;
}

class RougeScorer {
  RougeScorer({List<String>? metrics})
    : metrics = metrics ?? <String>['rouge1'];

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
    for (final String metric in metrics) {
      final String normalized = metric.toLowerCase();
      if (normalized == 'rouge1' || normalized == 'rouge_1') {
        result[metric] = rouge1;
      }
    }
    return result;
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

List<String> _tokenize(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((String token) => token.isNotEmpty)
      .toList();
}

Map<String, int> _countTokens(List<String> tokens) {
  final Map<String, int> counts = <String, int>{};
  for (final String token in tokens) {
    counts[token] = (counts[token] ?? 0) + 1;
  }
  return counts;
}
