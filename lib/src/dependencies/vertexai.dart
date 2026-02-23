class VertexAiEvaluationDataset {
  VertexAiEvaluationDataset({required this.evalDatasetRows});

  final List<Map<String, String?>> evalDatasetRows;
}

class VertexAiDependencySummaryMetric {
  VertexAiDependencySummaryMetric({this.meanScore});

  final double? meanScore;
}

class VertexAiDependencyEvalResult {
  VertexAiDependencyEvalResult({
    List<VertexAiDependencySummaryMetric>? summaryMetrics,
  }) : summaryMetrics = summaryMetrics ?? <VertexAiDependencySummaryMetric>[];

  final List<VertexAiDependencySummaryMetric> summaryMetrics;
}

class VertexAiEvalsApi {
  const VertexAiEvalsApi();

  Future<VertexAiDependencyEvalResult> evaluate({
    required VertexAiEvaluationDataset dataset,
    required List<String> metrics,
  }) async {
    if (dataset.evalDatasetRows.isEmpty) {
      return VertexAiDependencyEvalResult(
        summaryMetrics: <VertexAiDependencySummaryMetric>[
          VertexAiDependencySummaryMetric(meanScore: null),
        ],
      );
    }

    double total = 0.0;
    for (final Map<String, String?> row in dataset.evalDatasetRows) {
      final String reference = row['reference'] ?? row['prompt'] ?? '';
      final String response = row['response'] ?? '';
      total += _tokenOverlap(reference, response);
    }
    final double meanScore = total / dataset.evalDatasetRows.length;
    return VertexAiDependencyEvalResult(
      summaryMetrics: <VertexAiDependencySummaryMetric>[
        VertexAiDependencySummaryMetric(meanScore: meanScore),
      ],
    );
  }
}

class VertexAiClient {
  VertexAiClient({
    this.apiKey,
    this.project,
    this.location,
    VertexAiEvalsApi? evals,
  }) : evals = evals ?? const VertexAiEvalsApi();

  final String? apiKey;
  final String? project;
  final String? location;
  final VertexAiEvalsApi evals;
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

  String normalizeExampleId(String id) {
    return id.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  }
}

class VertexAiRag {
  const VertexAiRag();

  double lexicalRelevance({required String query, required String context}) {
    return _tokenOverlap(query, context);
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

const VertexAiModule vertexai = VertexAiModule();

double _tokenOverlap(String reference, String response) {
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
  return overlap / responseTokens.length;
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
