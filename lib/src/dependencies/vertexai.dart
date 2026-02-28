class VertexAiEvaluationDataset {
  VertexAiEvaluationDataset({
    required List<Map<String, String?>> evalDatasetRows,
  }) : evalDatasetRows = List<Map<String, String?>>.unmodifiable(
         evalDatasetRows.map(
           (Map<String, String?> row) => Map<String, String?>.unmodifiable(row),
         ),
       );

  final List<Map<String, String?>> evalDatasetRows;
}

class VertexAiDependencySummaryMetric {
  VertexAiDependencySummaryMetric({this.meanScore});

  final double? meanScore;
}

class VertexAiDependencyEvalResult {
  VertexAiDependencyEvalResult({
    List<VertexAiDependencySummaryMetric>? summaryMetrics,
  }) : summaryMetrics = List<VertexAiDependencySummaryMetric>.unmodifiable(
         summaryMetrics ?? <VertexAiDependencySummaryMetric>[],
       );

  final List<VertexAiDependencySummaryMetric> summaryMetrics;
}

typedef VertexAiMetricScorer =
    double Function({
      required String reference,
      required String response,
      required List<String> metrics,
    });

class VertexAiEvalsApi {
  const VertexAiEvalsApi({this.metricScorer = _defaultMetricScorer});

  final VertexAiMetricScorer metricScorer;

  Future<VertexAiDependencyEvalResult> evaluate({
    required VertexAiEvaluationDataset dataset,
    required List<String> metrics,
  }) async {
    final List<String> normalizedMetrics = _normalizeMetrics(metrics);
    if (dataset.evalDatasetRows.isEmpty) {
      return VertexAiDependencyEvalResult(
        summaryMetrics: <VertexAiDependencySummaryMetric>[
          VertexAiDependencySummaryMetric(meanScore: null),
        ],
      );
    }

    double total = 0.0;
    int scoredRowCount = 0;
    for (final Map<String, String?> row in dataset.evalDatasetRows) {
      final String reference = _coalesceReference(row);
      final String response = _normalizeNullable(row['response']) ?? '';
      final double rawScore = metricScorer(
        reference: reference,
        response: response,
        metrics: normalizedMetrics,
      );
      if (!rawScore.isFinite || rawScore.isNaN) {
        continue;
      }
      total += rawScore.clamp(0.0, 1.0);
      scoredRowCount += 1;
    }

    final double? meanScore = scoredRowCount == 0
        ? null
        : total / scoredRowCount;
    return VertexAiDependencyEvalResult(
      summaryMetrics: <VertexAiDependencySummaryMetric>[
        VertexAiDependencySummaryMetric(meanScore: meanScore),
      ],
    );
  }
}

class VertexAiClient {
  VertexAiClient({
    String? apiKey,
    String? project,
    String? location,
    VertexAiEvalsApi? evals,
  }) : apiKey = _normalizeNullable(apiKey),
       project = _normalizeNullable(project),
       location = _normalizeNullable(location),
       evals = evals ?? const VertexAiEvalsApi();

  final String? apiKey;
  final String? project;
  final String? location;
  final VertexAiEvalsApi evals;

  bool get isConfigured {
    final bool hasApiKey = apiKey != null;
    final bool hasProjectAndLocation = project != null && location != null;
    return hasApiKey || hasProjectAndLocation;
  }
}

class VertexAiTypesNamespace {
  const VertexAiTypesNamespace();

  VertexAiEvaluationDataset evaluationDataset({
    required List<Map<String, String?>> evalDatasetRows,
  }) {
    return VertexAiEvaluationDataset(evalDatasetRows: evalDatasetRows);
  }
}

class VertexAiExampleStores {
  const VertexAiExampleStores();

  String normalizeExampleId(String id, {int maxLength = 63}) {
    final String normalized = id
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (normalized.isEmpty) {
      return 'example';
    }

    if (maxLength <= 0 || normalized.length <= maxLength) {
      return normalized;
    }

    final String truncated = normalized
        .substring(0, maxLength)
        .replaceAll(RegExp(r'_+$'), '');
    return truncated.isEmpty ? 'example' : truncated;
  }
}

class VertexAiRag {
  const VertexAiRag();

  double lexicalRelevance({required String query, required String context}) {
    return _tokenRecall(query, context);
  }
}

class VertexAiPreviewNamespace {
  const VertexAiPreviewNamespace({
    this.exampleStores = const VertexAiExampleStores(),
    this.rag = const VertexAiRag(),
  });

  final VertexAiExampleStores exampleStores;
  final VertexAiRag rag;
}

class VertexAiModule {
  const VertexAiModule({
    this.types = const VertexAiTypesNamespace(),
    this.preview = const VertexAiPreviewNamespace(),
  });

  final VertexAiTypesNamespace types;
  final VertexAiPreviewNamespace preview;

  VertexAiClient client({String? apiKey, String? project, String? location}) {
    return VertexAiClient(apiKey: apiKey, project: project, location: location);
  }
}

const VertexAiExampleStores exampleStores = VertexAiExampleStores();
const VertexAiRag rag = VertexAiRag();
const VertexAiPreviewNamespace preview = VertexAiPreviewNamespace(
  exampleStores: exampleStores,
  rag: rag,
);
const VertexAiModule vertexai = VertexAiModule(preview: preview);

List<String> _normalizeMetrics(List<String> metrics) {
  if (metrics.isEmpty) {
    throw ArgumentError.value(
      metrics,
      'metrics',
      'must contain at least one metric.',
    );
  }

  final List<String> normalized = <String>[];
  for (final String metric in metrics) {
    final String trimmed = metric.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        metric,
        'metrics',
        'must not contain blank metric names.',
      );
    }
    normalized.add(trimmed.toLowerCase());
  }
  return List<String>.unmodifiable(normalized);
}

String _coalesceReference(Map<String, String?> row) {
  final String? reference = _normalizeNullable(row['reference']);
  if (reference != null) {
    return reference;
  }
  return _normalizeNullable(row['prompt']) ?? '';
}

String? _normalizeNullable(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double _defaultMetricScorer({
  required String reference,
  required String response,
  required List<String> metrics,
}) {
  final double precision = _tokenPrecision(reference, response);
  final double recall = _tokenRecall(reference, response);
  final double fmeasure = (precision + recall) == 0.0
      ? 0.0
      : (2 * precision * recall) / (precision + recall);

  double total = 0.0;
  for (final String metric in metrics) {
    if (metric.contains('ground')) {
      total += precision;
    } else if (metric.contains('recall') || metric.contains('completeness')) {
      total += recall;
    } else if (metric.contains('precision')) {
      total += precision;
    } else {
      total += fmeasure;
    }
  }
  return total / metrics.length;
}

double _tokenPrecision(String reference, String response) {
  final List<String> referenceTokens = _tokenize(reference);
  final List<String> responseTokens = _tokenize(response);
  if (referenceTokens.isEmpty || responseTokens.isEmpty) {
    return 0.0;
  }

  final Map<String, int> referenceCounts = _countTokens(referenceTokens);
  final Map<String, int> responseCounts = _countTokens(responseTokens);
  int overlap = 0;
  for (final MapEntry<String, int> entry in responseCounts.entries) {
    final int count = referenceCounts[entry.key] ?? 0;
    overlap += count < entry.value ? count : entry.value;
  }
  return overlap / responseTokens.length;
}

double _tokenRecall(String reference, String response) {
  final List<String> referenceTokens = _tokenize(reference);
  final List<String> responseTokens = _tokenize(response);
  if (referenceTokens.isEmpty || responseTokens.isEmpty) {
    return 0.0;
  }

  final Map<String, int> referenceCounts = _countTokens(referenceTokens);
  final Map<String, int> responseCounts = _countTokens(responseTokens);
  int overlap = 0;
  for (final MapEntry<String, int> entry in referenceCounts.entries) {
    final int count = responseCounts[entry.key] ?? 0;
    overlap += count < entry.value ? count : entry.value;
  }
  return overlap / referenceTokens.length;
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
