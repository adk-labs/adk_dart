/// OpenAI `/v1/decisions` classifier integration for ADK.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../labs/classifiers/classifiers.dart';
import '../../types/content.dart';
import '../../utils/client_labels_utils.dart';
import 'openai.dart' show OpenAiApiKeyProvider;

const String _defaultDecisionsModel = 'gpt-6-luna';
const String _defaultOpenAiBaseUrl = 'https://api.openai.com/v1';
const int _maxChoices = 255;
const int _maxScoreLevels = 10;

/// HTTP transport interface for sending `/decisions` requests.
///
/// Allows injecting a fake client in tests without opening sockets.
abstract interface class OpenAIDecisionsClient {
  /// Sends [body] to `/decisions` and returns the decoded JSON map.
  Future<Map<String, Object?>> createDecision(
    Map<String, Object?> body, {
    double? timeout,
  });
}

/// Classifier backed by OpenAI's `/v1/decisions` endpoint (`gpt-6-luna`).
///
/// Translates all three ADK question types into a single `/v1/decisions` call:
/// - [Binary] -> `predicate`
/// - [Choice] -> `choice` (2 to 255 labels)
/// - [Score] -> `score` (2 to 10 rubric levels, labeled `"0"`..`"N-1"`)
///
/// When the endpoint declines a question (`"type": "refusal"`), the
/// corresponding entry in [ClassifierResponse.answers] is a [RefusalAnswer].
class OpenAIDecisionsClassifier extends BaseClassifier {
  /// Creates an [OpenAIDecisionsClassifier].
  OpenAIDecisionsClassifier({
    super.model = _defaultDecisionsModel,
    this.apiKey,
    this.apiKeyProvider,
    this.baseUrl,
    this.timeout = 30.0,
    OpenAIDecisionsClient? client,
    http.Client? httpClient,
    Map<String, String>? environment,
  }) : _client = client,
       _httpClient = httpClient,
       _environment = environment {
    if (apiKey != null && apiKeyProvider != null) {
      throw ArgumentError('Pass at most one of apiKey or apiKeyProvider.');
    }
    if (timeout <= 0 || timeout.isNaN || timeout.isInfinite) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'timeout must be a finite number greater than 0.',
      );
    }
  }

  /// Static OpenAI API key. Mutually exclusive with [apiKeyProvider].
  final String? apiKey;

  /// Per-request API key provider. Mutually exclusive with [apiKey].
  final OpenAiApiKeyProvider? apiKeyProvider;

  /// Optional OpenAI API base URL override.
  final String? baseUrl;

  /// Per-request timeout in seconds.
  final double timeout;

  final OpenAIDecisionsClient? _client;
  final http.Client? _httpClient;
  final Map<String, String>? _environment;

  @override
  String get clientLabelKind => 'openai';

  Map<String, String> get _env => _environment ?? Platform.environment;

  Future<String> _resolveApiKey() async {
    if (apiKeyProvider != null) {
      final String provided = await Future<String>.value(apiKeyProvider!());
      if (provided.isEmpty) {
        throw StateError('apiKeyProvider returned an empty API key.');
      }
      return provided;
    }
    final String? resolved = apiKey ?? _env['OPENAI_API_KEY'];
    if (resolved == null || resolved.isEmpty) {
      throw StateError(
        'OpenAI API key is required. Pass `apiKey`, `apiKeyProvider`, or set '
        '`OPENAI_API_KEY`.',
      );
    }
    return resolved;
  }

  String _resolveBaseUrl() {
    final String raw =
        baseUrl ?? _env['OPENAI_BASE_URL'] ?? _defaultOpenAiBaseUrl;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  @override
  Future<ClassifierResponse> classify({
    required Object input,
    required Map<String, ClassifierQuestion> questions,
  }) {
    return runWithClientLabelContext(() async {
      if (questions.isEmpty) {
        throw ArgumentError.value(
          questions,
          'questions',
          'questions must not be empty.',
        );
      }

      final List<Map<String, Object?>> payloadQuestions =
          <Map<String, Object?>>[];
      for (final MapEntry<String, ClassifierQuestion> entry
          in questions.entries) {
        payloadQuestions.add(_toDecisionQuestion(entry.key, entry.value));
      }

      final Map<String, Object?> payload = <String, Object?>{
        'model': model,
        'input': _inputToText(input),
        'questions': payloadQuestions,
      };

      final Map<String, Object?> rawResponse = await _postDecisions(payload);
      final Object? rawDecisions = rawResponse['decisions'];
      if (rawDecisions is! Map) {
        throw StateError(
          'OpenAI /decisions response missing "decisions" map: $rawResponse',
        );
      }

      final Map<String, ClassifierAnswer> answers = <String, ClassifierAnswer>{};
      for (final MapEntry<String, ClassifierQuestion> entry
          in questions.entries) {
        final Object? rawDecision = rawDecisions[entry.key];
        if (rawDecision is! Map) {
          throw StateError(
            'OpenAI /decisions response missing decision for question '
            '"${entry.key}".',
          );
        }
        final Map<String, Object?> decisionMap = <String, Object?>{
          for (final MapEntry<Object?, Object?> item in rawDecision.entries)
            '${item.key}': item.value,
        };
        answers[entry.key] = _parseAnswer(entry.key, entry.value, decisionMap);
      }

      final Object? rawModel = rawResponse['model'];
      final String resolvedModel =
          (rawModel is String && rawModel.isNotEmpty) ? rawModel : model;

      return ClassifierResponse(
        modelVersion: resolvedModel,
        answers: answers,
        usageMetadata: _extractUsage(rawResponse['usage']),
      );
    });
  }

  Future<Map<String, Object?>> _postDecisions(
    Map<String, Object?> payload,
  ) async {
    if (_client != null) {
      return _client.createDecision(payload, timeout: timeout);
    }

    final String key = await _resolveApiKey();
    final Uri uri = Uri.parse('${_resolveBaseUrl()}/decisions');
    final http.Client client = _httpClient ?? http.Client();
    final Duration requestTimeout = Duration(
      microseconds: (timeout * 1000000).round(),
    );
    try {
      final http.Response response = await client
          .post(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': getClientLabels().join(' '),
            },
            body: jsonEncode(payload),
          )
          .timeout(requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'OpenAI /decisions failed (${response.statusCode}): ${response.body}',
          uri: uri,
        );
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw StateError(
          'OpenAI /decisions response body must be a JSON object.',
        );
      }
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in decoded.entries)
          '${entry.key}': entry.value,
      };
    } finally {
      if (_httpClient == null) {
        client.close();
      }
    }
  }
}

/// Idiomatic Dart alias for [OpenAIDecisionsClassifier].
typedef OpenAiDecisionsClassifier = OpenAIDecisionsClassifier;

Map<String, Object?> _toDecisionQuestion(String name, ClassifierQuestion q) {
  if (name.isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Question name must not be empty.',
    );
  }
  final String baseInstructions = q.instructions ?? '';
  if (q is Binary) {
    String instructions = baseInstructions;
    if (q.criteria != null) {
      final String criteriaText = _criteriaToText(q.criteria);
      final String suffix =
          'True means: $criteriaText\nAnything else is false.';
      instructions = instructions.isNotEmpty
          ? '$instructions\n$suffix'
          : suffix;
    }
    return <String, Object?>{
      'type': 'predicate',
      'name': name,
      'instructions': instructions,
    };
  }
  if (q is Choice) {
    if (q.criteria.length > _maxChoices) {
      throw ArgumentError.value(
        q.criteria.length,
        'criteria',
        'OpenAI /decisions supports at most $_maxChoices choices per question; '
            'question "$name" has ${q.criteria.length}.',
      );
    }
    final List<Map<String, Object?>> choices = <Map<String, Object?>>[];
    for (final MapEntry<String, Object?> entry in q.criteria.entries) {
      if (entry.key.isEmpty) {
        throw ArgumentError.value(
          entry.key,
          'criteria',
          'Choice label in question "$name" must not be empty.',
        );
      }
      choices.add(<String, Object?>{
        'value': entry.key,
        'description': _criteriaToText(entry.value),
      });
    }
    return <String, Object?>{
      'type': 'choice',
      'name': name,
      'instructions': baseInstructions,
      'choices': choices,
    };
  }
  if (q is Score) {
    if (q.criteria.length > _maxScoreLevels) {
      throw ArgumentError.value(
        q.criteria.length,
        'criteria',
        'OpenAI /decisions supports at most $_maxScoreLevels levels per score '
            'question; question "$name" has ${q.criteria.length}.',
      );
    }
    final List<Map<String, Object?>> levels = <Map<String, Object?>>[];
    for (int i = 0; i < q.criteria.length; i++) {
      levels.add(<String, Object?>{
        'label': '$i',
        'description': _criteriaToText(q.criteria[i]),
      });
    }
    return <String, Object?>{
      'type': 'score',
      'name': name,
      'instructions': baseInstructions,
      'levels': levels,
    };
  }
  throw ArgumentError('Unsupported ClassifierQuestion: ${q.runtimeType}');
}

ClassifierAnswer _parseAnswer(
  String name,
  ClassifierQuestion q,
  Map<String, Object?> raw,
) {
  final Object? rawType = raw['type'];
  if (rawType == 'refusal') {
    return RefusalAnswer();
  }

  if (q is Binary) {
    if (rawType != 'predicate') {
      throw StateError(
        'Question "$name" expected a "predicate" decision, got "$rawType".',
      );
    }
    final double prob = _requireProbability(
      raw['probability_true'],
      'decisions[$name].probability_true',
    );
    return BinaryAnswer(probability: prob);
  }

  if (q is Choice) {
    if (rawType != 'choice') {
      throw StateError(
        'Question "$name" expected a "choice" decision, got "$rawType".',
      );
    }
    final Object? selected = raw['selected'];
    if (selected is! String || !q.criteria.containsKey(selected)) {
      throw StateError(
        'Question "$name" returned unknown selected choice "$selected".',
      );
    }
    final Object? rawProbs = raw['probabilities'];
    if (rawProbs is! Map) {
      throw StateError(
        'Question "$name" choice decision is missing "probabilities" map.',
      );
    }
    final Map<String, Object?> probMap = <String, Object?>{
      for (final MapEntry<Object?, Object?> item in rawProbs.entries)
        '${item.key}': item.value,
    };
    if (probMap.length != q.criteria.length ||
        !q.criteria.keys.every(probMap.containsKey)) {
      throw StateError(
        'Question "$name" probabilities keys ${probMap.keys.toList()} do not '
        'match choice labels ${q.criteria.keys.toList()}.',
      );
    }
    final Map<String, double> probabilities = <String, double>{
      for (final String label in q.criteria.keys)
        label: _requireProbability(
          probMap[label],
          'decisions[$name].probabilities[$label]',
        ),
    };
    return ChoiceAnswer(choice: selected, probabilities: probabilities);
  }

  if (q is Score) {
    if (rawType != 'score') {
      throw StateError(
        'Question "$name" expected a "score" decision, got "$rawType".',
      );
    }
    final int n = q.criteria.length;
    final Object? rawProbs = raw['probabilities'];
    if (rawProbs is! Map) {
      throw StateError(
        'Question "$name" score decision is missing "probabilities" map.',
      );
    }
    final Map<String, Object?> probMap = <String, Object?>{
      for (final MapEntry<Object?, Object?> item in rawProbs.entries)
        '${item.key}': item.value,
    };
    final Set<String> expectedKeys = <String>{
      for (int i = 0; i < n; i++) '$i',
    };
    if (probMap.length != expectedKeys.length ||
        !expectedKeys.every(probMap.containsKey)) {
      throw StateError(
        'Question "$name" score probabilities keys ${probMap.keys.toList()} '
        'do not match expected level labels ${expectedKeys.toList()}.',
      );
    }
    final Map<int, double> probabilities = <int, double>{
      for (int i = 0; i < n; i++)
        i: _requireProbability(
          probMap['$i'],
          'decisions[$name].probabilities[$i]',
        ),
    };
    final Object? rawExpected = raw['expected_score'];
    if (rawExpected is! num || rawExpected is bool) {
      throw StateError(
        'decisions[$name].expected_score must be a finite number, '
        'got $rawExpected.',
      );
    }
    final double expected = rawExpected.toDouble();
    if (!expected.isFinite || expected < 0.0 || expected > n - 1) {
      throw StateError(
        'decisions[$name].expected_score must be in [0, ${n - 1}], '
        'got $expected.',
      );
    }
    return ScoreAnswer(score: expected, probabilities: probabilities);
  }

  throw StateError('Unsupported question type: ${q.runtimeType}');
}

double _requireProbability(Object? value, String fieldName) {
  if (value is! num || value is bool) {
    throw StateError('$fieldName must be a finite probability, got $value.');
  }
  final double d = value.toDouble();
  if (!d.isFinite || d < 0.0 || d > 1.0) {
    throw StateError('$fieldName must be in [0.0, 1.0], got $d.');
  }
  return d;
}

String _criteriaToText(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  return jsonEncode(_toJsonEncodable(value));
}

String _inputToText(Object input) {
  if (input is String) {
    return input;
  }
  if (input is Content) {
    final List<String> texts = <String>[];
    for (final Part part in input.parts) {
      if (part.thought) {
        continue;
      }
      if (part.text != null) {
        texts.add(part.text!);
      } else {
        throw ArgumentError(
          'OpenAI classifiers only support text Content parts; '
          'got non-text Part.',
        );
      }
    }
    return texts.join('\n');
  }
  return jsonEncode(_toJsonEncodable(input));
}

Object? _toJsonEncodable(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        '${entry.key}': _toJsonEncodable(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_toJsonEncodable).toList(growable: false);
  }
  try {
    final Object? dumped = (value as dynamic).toJson();
    return _toJsonEncodable(dumped);
  } catch (_) {
    return '$value';
  }
}

Map<String, Object?>? _extractUsage(Object? usage) {
  if (usage is! Map) {
    return null;
  }
  final int? inputTokens = _asInt(usage['input_tokens']);
  final int? outputTokens = _asInt(usage['output_tokens']);
  final int? totalTokens = _asInt(usage['total_tokens']);
  final Object? inputDetails = usage['input_tokens_details'];
  final Object? outputDetails = usage['output_tokens_details'];
  final int? cachedTokens = inputDetails is Map
      ? _asInt(inputDetails['cached_tokens'])
      : null;
  final int? reasoningTokens = outputDetails is Map
      ? _asInt(outputDetails['reasoning_tokens'])
      : null;
  if (inputTokens == null &&
      outputTokens == null &&
      totalTokens == null &&
      cachedTokens == null &&
      reasoningTokens == null) {
    return null;
  }
  return <String, Object?>{
    'prompt_token_count': ?inputTokens,
    'candidates_token_count': ?outputTokens,
    'total_token_count': ?totalTokens,
    'cached_content_token_count': ?cachedTokens,
    'thoughts_token_count': ?reasoningTokens,
  };
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value is! bool) {
    return value.toInt();
  }
  return null;
}
