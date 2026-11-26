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
const double _tolerance = 1e-6;

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
      final Object? rawAnswers = rawResponse['answers'];
      if (rawAnswers is! List) {
        throw StateError(
          'OpenAI /decisions response missing "answers" list: $rawResponse',
        );
      }

      final Map<String, Map<String, Object?>> answersByName =
          _indexAnswersByName(rawAnswers);
      final Map<String, ClassifierAnswer> answers = <String, ClassifierAnswer>{};
      for (final MapEntry<String, ClassifierQuestion> entry
          in questions.entries) {
        final Map<String, Object?>? rawAnswer = answersByName[entry.key];
        if (rawAnswer == null) {
          throw StateError(
            'OpenAI /decisions response returned no answer to "${entry.key}".',
          );
        }
        answers[entry.key] = _parseAnswer(entry.key, entry.value, rawAnswer);
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
              // OpenAI is a third party, so the hosting runtime is not sent.
              'User-Agent': getClientLabels(excludeRuntimeTag: true).join(' '),
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
  if (q.instructions == null) {
    throw ArgumentError.value(
      q.instructions,
      'instructions',
      'OpenAIDecisionsClassifier needs instructions for question "$name".',
    );
  }
  final String baseInstructions = q.instructions!;
  if (q is Binary) {
    String instructions = baseInstructions;
    if (q.criteria != null) {
      final String criteriaText = _criteriaToText(q.criteria);
      instructions =
          '$instructions\nTrue means: $criteriaText\nAnything else is false.';
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
      final Map<String, Object?> choice = <String, Object?>{
        'value': entry.key,
      };
      if (entry.value != null) {
        choice['description'] = _criteriaToText(entry.value);
      }
      choices.add(choice);
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

Map<String, Map<String, Object?>> _indexAnswersByName(
  List<Object?> rawAnswers,
) {
  final Map<String, Map<String, Object?>> answers =
      <String, Map<String, Object?>>{};
  for (final Object? item in rawAnswers) {
    if (item is! Map) {
      throw StateError('OpenAI returned an answer that names no question.');
    }
    final Object? name = item['name'];
    if (name is! String || name.isEmpty) {
      throw StateError('OpenAI returned an answer that names no question.');
    }
    if (answers.containsKey(name)) {
      throw StateError('OpenAI returned more than one answer to "$name".');
    }
    answers[name] = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in item.entries)
        '${entry.key}': entry.value,
    };
  }
  return answers;
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

  final String expectedType = q is Binary ? 'predicate' : q.type;
  if (rawType != expectedType) {
    throw StateError(
      'OpenAI returned a "$rawType" answer to "$name", '
      'which is a "$expectedType" question.',
    );
  }

  final List<String> required = expectedType == 'predicate'
      ? const <String>['probability']
      : <String>[expectedType, 'probabilities'];
  final List<String> missing = <String>[
    for (final String key in required)
      if (!raw.containsKey(key)) key,
  ];
  if (missing.isNotEmpty) {
    throw StateError(
      'OpenAI returned a malformed "$expectedType" answer to "$name", '
      'missing $missing.',
    );
  }

  final double? confidence = raw['confidence'] == null
      ? null
      : _readNumber(name, 'confidence', raw['confidence']);

  if (q is Binary) {
    return BinaryAnswer(
      probability: _readNumber(name, 'probability', raw['probability']),
      confidence: confidence,
    );
  }

  if (q is Choice) {
    final Object? choice = raw['choice'];
    if (choice is! String || !q.criteria.containsKey(choice)) {
      throw StateError(
        'OpenAI chose "$choice" for "$name", which is not one of its labels.',
      );
    }
    return ChoiceAnswer(
      choice: choice,
      probabilities: _readProbabilities<String>(
        name,
        expectedType,
        raw['probabilities'],
        q.criteria.keys.toList(growable: false),
        isExpectedKeyType: (Object? value) => value is String,
      ),
      confidence: confidence,
    );
  }

  if (q is Score) {
    final int top = q.criteria.length - 1;
    return ScoreAnswer(
      score: _readNumber(name, 'score', raw['score'], high: top.toDouble()),
      probabilities: _readProbabilities<int>(
        name,
        expectedType,
        raw['probabilities'],
        List<int>.generate(top + 1, (int i) => i, growable: false),
        isExpectedKeyType: (Object? value) => value is int,
      ),
      confidence: confidence,
    );
  }

  throw StateError('Unsupported question type: ${q.runtimeType}');
}

Map<K, double> _readProbabilities<K>(
  String name,
  String answerType,
  Object? rawItems,
  List<K> keys, {
  required bool Function(Object? value) isExpectedKeyType,
}) {
  if (rawItems is! List) {
    throw StateError(
      'OpenAI returned a malformed "$answerType" answer to "$name", '
      'whose probabilities are not a list of values and probabilities.',
    );
  }
  final Map<K, Object?> byValue = <K, Object?>{};
  for (final Object? item in rawItems) {
    if (item is! Map ||
        !item.containsKey('value') ||
        !item.containsKey('probability')) {
      throw StateError(
        'OpenAI returned a malformed "$answerType" answer to "$name", '
        'whose probabilities are not a list of values and probabilities.',
      );
    }
    final Object? value = item['value'];
    if (!isExpectedKeyType(value)) {
      throw StateError(
        'OpenAI returned probabilities for $rawItems in "$name", '
        'expected $keys.',
      );
    }
    final K typedKey = value as K;
    if (byValue.containsKey(typedKey)) {
      throw StateError(
        'OpenAI returned duplicate probability for "$typedKey" in "$name".',
      );
    }
    byValue[typedKey] = item['probability'];
  }
  if (byValue.length != keys.length || !keys.every(byValue.containsKey)) {
    throw StateError(
      'OpenAI returned probabilities for ${byValue.keys.toList()} in "$name", '
      'expected $keys.',
    );
  }
  return <K, double>{
    for (final K key in keys)
      key: _readNumber(name, '$key', byValue[key]),
  };
}

double _readNumber(
  String name,
  String key,
  Object? value, {
  double high = 1.0,
}) {
  if (value is bool || value is! num || !value.isFinite) {
    throw StateError(
      'OpenAI returned $value for "$key" in "$name", not a finite number.',
    );
  }
  final double d = value.toDouble();
  if (d < -_tolerance || d > high + _tolerance) {
    throw StateError(
      'OpenAI returned $d for "$key" in "$name", outside [0, $high].',
    );
  }
  return d.clamp(0.0, high).toDouble();
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
      if (part.text == null) {
        throw ArgumentError(
          'OpenAIDecisionsClassifier accepts text and JSON input only; '
          'the input has a non-text Part.',
        );
      }
      texts.add(part.text!);
    }
    return texts.join('');
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
