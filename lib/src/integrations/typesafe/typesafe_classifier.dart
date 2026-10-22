/// TypeSafe Jev decision-model classifier integration.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../labs/classifiers/base_classifier.dart';
import '../../labs/classifiers/types.dart';
import '../../types/content.dart';
import '../../utils/system_environment/system_environment.dart';

const String _apiKeyEnvVar = 'TYPESAFE_API_KEY';
const String _baseUrlEnvVar = 'TYPESAFE_BASE_URL';
const String _systemOnePath = '/v1/systemone';
const double _tolerance = 1e-6;

/// HTTP response returned by a [TypesafeHttpTransport].
class TypesafeHttpResponse {
  /// Creates a TypeSafe HTTP response.
  const TypesafeHttpResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  /// HTTP status code returned by the server.
  final int statusCode;

  /// Raw response body text.
  final String body;

  /// Response headers normalized as a string map.
  final Map<String, String> headers;
}

/// Function signature for sending POST requests to the TypeSafe API.
typedef TypesafeHttpTransport =
    Future<TypesafeHttpResponse> Function({
      required Uri url,
      required Map<String, String> headers,
      required Map<String, Object?> body,
      required Duration timeout,
    });

Object _serializeContentToMessage(Content content) {
  final StringBuffer buffer = StringBuffer();
  for (final Part part in content.parts) {
    if (part.text == null) {
      throw ArgumentError(
        'TypesafeClassifier accepts text and JSON input only; the input has '
        'a non-text part.',
      );
    }
    buffer.write(part.text!);
  }
  return buffer.toString();
}

Object _inputToState(Object input) {
  if (input is Content) {
    return _serializeContentToMessage(input);
  }
  if (input is List<Content>) {
    return input
        .map(
          (Content content) => <String, Object?>{
            'role': content.role ?? 'user',
            'content': _serializeContentToMessage(content),
          },
        )
        .toList(growable: false);
  }
  return input;
}

Map<String, Object?> _questionToJson(
  String name,
  ClassifierQuestion question,
) {
  if (question.instructions == null || question.instructions!.trim().isEmpty) {
    throw ArgumentError(
      "TypesafeClassifier needs instructions for question '$name'.",
    );
  }
  final Map<String, Object?> body = <String, Object?>{
    'instructions': question.instructions,
  };
  if (question is Choice) {
    body['type'] = 'choice';
    body['criteria'] = Map<String, Object?>.from(question.criteria);
  } else if (question is Binary) {
    body['type'] = 'noul';
    if (question.criteria != null) {
      body['criteria'] = <String, Object?>{'true': question.criteria};
    }
  } else if (question is Score) {
    body['type'] = 'score';
    body['criteria'] = List<Object?>.from(question.criteria);
  }
  return body;
}

double _readNumber(
  String name,
  String key,
  Object? value, {
  double high = 1.0,
}) {
  if (value is bool || value is! num) {
    throw FormatException(
      "TypeSafe returned $value for '$key' in '$name', not a number.",
    );
  }
  final double doubleValue = value.toDouble();
  if (!doubleValue.isFinite) {
    throw FormatException(
      "TypeSafe returned $value for '$key' in '$name', not a number.",
    );
  }
  if (doubleValue < -_tolerance || doubleValue > high + _tolerance) {
    throw FormatException(
      "TypeSafe returned $value for '$key' in '$name', outside [0, $high].",
    );
  }
  return doubleValue.clamp(0.0, high);
}

Map<String, double> _readProbabilities(
  String name,
  Map<Object?, Object?> raw,
  List<String> keys,
) {
  final Object? rawProbabilities = raw['probabilities'];
  if (rawProbabilities is! Map) {
    throw FormatException(
      "TypeSafe returned a malformed '${raw['type']}' answer to '$name', "
      'whose probabilities are not an object.',
    );
  }
  final Set<String> actualKeys = rawProbabilities.keys
      .map((Object? k) => '$k')
      .toSet();
  final Set<String> expectedKeys = keys.toSet();
  if (actualKeys.length != expectedKeys.length ||
      !actualKeys.containsAll(expectedKeys)) {
    final List<String> sortedActual = actualKeys.toList()..sort();
    throw FormatException(
      "TypeSafe returned probabilities for $sortedActual in '$name', "
      'expected $keys.',
    );
  }
  return <String, double>{
    for (final String key in keys)
      key: _readNumber(name, key, rawProbabilities[key]),
  };
}

ClassifierAnswer _toAnswer(
  String name,
  ClassifierQuestion question,
  Object? raw,
) {
  if (raw is! Map) {
    throw FormatException("TypeSafe returned no answer to '$name'.");
  }
  final String expected = question is Binary ? 'noul' : question.type;
  final Object? rawType = raw['type'];
  if (rawType != null && rawType != expected && !(question is Binary && rawType == 'binary')) {
    throw FormatException(
      "TypeSafe returned a '$rawType' answer to '$name', which is a "
      "'$expected' question.",
    );
  }

  double? confidence;
  if (raw['confidence'] != null) {
    confidence = _readNumber(name, 'confidence', raw['confidence']);
  }

  if (question is Binary) {
    if (raw.containsKey('noul')) {
      return BinaryAnswer(
        probability: _readNumber(name, 'noul', raw['noul']),
        confidence: confidence,
      );
    }
    if (raw['probabilities'] is Map &&
        (raw['probabilities'] as Map).containsKey('true')) {
      return BinaryAnswer(
        probability: _readNumber(
          name,
          'true',
          (raw['probabilities'] as Map)['true'],
        ),
        confidence: confidence,
      );
    }
    throw FormatException(
      "TypeSafe returned a malformed 'noul' answer to '$name', missing ['noul'].",
    );
  }

  final List<String> requiredKeys = <String>[expected, 'probabilities'];
  final List<String> missing = <String>[
    for (final String key in requiredKeys)
      if (!raw.containsKey(key)) key,
  ];
  if (missing.isNotEmpty) {
    throw FormatException(
      "TypeSafe returned a malformed '$expected' answer to '$name', "
      'missing $missing.',
    );
  }

  if (question is Choice) {
    final Object? choice = raw['choice'];
    if (choice is! String || !question.criteria.containsKey(choice)) {
      throw FormatException(
        "TypeSafe chose '$choice' for '$name', which is not one of its labels.",
      );
    }
    return ChoiceAnswer(
      choice: choice,
      probabilities: _readProbabilities(
        name,
        raw,
        question.criteria.keys.toList(growable: false),
      ),
      confidence: confidence,
    );
  }

  final Score scoreQuestion = question as Score;
  final int top = scoreQuestion.criteria.length - 1;
  final Map<String, double> probabilities = _readProbabilities(
    name,
    raw,
    List<String>.generate(top + 1, (int level) => '$level', growable: false),
  );
  return ScoreAnswer(
    score: _readNumber(name, 'score', raw['score'], high: top.toDouble()),
    probabilities: <int, double>{
      for (final MapEntry<String, double> entry in probabilities.entries)
        int.parse(entry.key): entry.value,
    },
    confidence: confidence,
  );
}

String _resolveApiKey(String? apiKey, Map<String, String>? environment) {
  final Map<String, String> env = environment ?? readSystemEnvironment();
  final String resolved = (apiKey ?? env[_apiKeyEnvVar] ?? '').trim();
  if (resolved.isEmpty) {
    throw ArgumentError(
      'TypesafeClassifier needs an API key. Set $_apiKeyEnvVar or pass apiKey.',
    );
  }
  return resolved;
}

String _resolveBaseUrl(String baseUrl, Map<String, String>? environment) {
  final Map<String, String> env = environment ?? readSystemEnvironment();
  String resolved = baseUrl.trim();
  if (resolved == TypesafeClassifier.defaultBaseUrl) {
    final String? envBaseUrl = env[_baseUrlEnvVar]?.trim();
    if (envBaseUrl != null && envBaseUrl.isNotEmpty) {
      resolved = envBaseUrl;
    }
  }
  while (resolved.endsWith('/')) {
    resolved = resolved.substring(0, resolved.length - 1);
  }
  return resolved;
}

/// Classifier backed by TypeSafe's Jev decision models.
///
/// Jev returns calibrated probabilities from a single forward pass rather than
/// generating free-form text. Every question must include non-empty
/// [ClassifierQuestion.instructions]; [Binary] questions are sent as Jev `noul`
/// questions.
///
/// ```dart
/// final classifier = TypesafeClassifier(apiKey: 'ts-key');
/// final response = await classifier.classify(
///   input: 'My invoice was charged twice.',
///   questions: <String, ClassifierQuestion>{
///     'department': Choice(
///       instructions: 'Which team should handle this ticket?',
///       criteria: <String, Object?>{'billing': null, 'technical': null},
///     ),
///   },
/// );
/// ```
class TypesafeClassifier extends BaseClassifier {
  /// Default TypeSafe API base URL.
  static const String defaultBaseUrl = 'https://api.typesafe.ai';

  /// Default per-request timeout in seconds.
  static const double defaultTimeoutSeconds = 30.0;

  /// Default maximum number of retry attempts after an initial failure.
  static const int defaultMaxRetries = 5;

  /// HTTP status codes that trigger automatic backoff and retry.
  static const Set<int> retryableStatusCodes = <int>{429, 529};

  /// Creates a [TypesafeClassifier] for [model].
  ///
  /// Resolves [apiKey] from the parameter or `TYPESAFE_API_KEY` in
  /// [environment]. Throws an [ArgumentError] when the API key is missing,
  /// [timeout] is not positive, or [maxRetries] is negative.
  TypesafeClassifier({
    super.model = 'jev-latest',
    String? apiKey,
    String baseUrl = defaultBaseUrl,
    this.timeout = defaultTimeoutSeconds,
    this.maxRetries = defaultMaxRetries,
    TypesafeHttpTransport? httpTransport,
    Map<String, String>? environment,
  }) : _apiKey = _resolveApiKey(apiKey, environment),
       baseUrl = _resolveBaseUrl(baseUrl, environment),
       _httpTransport = httpTransport {
    if (timeout <= 0 || timeout.isNaN) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'timeout must be greater than 0.',
      );
    }
    if (maxRetries < 0) {
      throw ArgumentError.value(
        maxRetries,
        'maxRetries',
        'maxRetries must be non-negative.',
      );
    }
  }

  final String _apiKey;

  /// Base URL of the TypeSafe API without trailing slash.
  final String baseUrl;

  /// Request timeout in seconds.
  final double timeout;

  /// Maximum number of retries on rate-limited (`429`) or overloaded (`529`) responses.
  final int maxRetries;

  final TypesafeHttpTransport? _httpTransport;

  Duration _retryDelay(int retryIndex, Map<String, String> headers) {
    for (final MapEntry<String, String> entry in headers.entries) {
      if (entry.key.toLowerCase() == 'retry-after') {
        final double? seconds = double.tryParse(entry.value.trim());
        if (seconds != null && seconds >= 0 && seconds.isFinite) {
          return Duration(milliseconds: (seconds * 1000).round());
        }
      }
    }
    final double expSeconds = math.min(8.0, 0.5 * math.pow(2, retryIndex));
    return Duration(milliseconds: (expSeconds * 1000).round());
  }

  Future<TypesafeHttpResponse> _defaultSend({
    required Uri url,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required Duration timeout,
  }) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request = await client
          .postUrl(url)
          .timeout(timeout);
      headers.forEach(request.headers.set);
      request.add(utf8.encode(jsonEncode(body)));
      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );
      final String responseBody = await utf8.decodeStream(response).timeout(
        timeout,
      );
      final Map<String, String> responseHeaders = <String, String>{};
      response.headers.forEach((String name, List<String> values) {
        responseHeaders[name] = values.join(', ');
      });
      return TypesafeHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
        headers: responseHeaders,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<TypesafeHttpResponse> _send(Map<String, Object?> body) async {
    final Uri url = Uri.parse('$baseUrl$_systemOnePath');
    final Map<String, String> headers = <String, String>{
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
    };
    final Duration timeoutDuration = Duration(
      milliseconds: (timeout * 1000).round(),
    );
    final TypesafeHttpTransport transport = _httpTransport ?? _defaultSend;

    TypesafeHttpResponse? lastResponse;
    for (int attempt = 0; attempt <= maxRetries; attempt += 1) {
      try {
        final TypesafeHttpResponse response = await transport(
          url: url,
          headers: headers,
          body: body,
          timeout: timeoutDuration,
        );
        lastResponse = response;
        if (!retryableStatusCodes.contains(response.statusCode)) {
          return response;
        }
        if (attempt < maxRetries) {
          final Duration delay = _retryDelay(attempt, response.headers);
          if (_httpTransport == null && delay > Duration.zero) {
            await Future<void>.delayed(delay);
          }
        }
      } on TimeoutException {
        if (attempt >= maxRetries) {
          rethrow;
        }
      } on SocketException {
        if (attempt >= maxRetries) {
          rethrow;
        }
      } on HttpException {
        if (attempt >= maxRetries) {
          rethrow;
        }
      }
    }
    return lastResponse!;
  }

  @override
  Future<ClassifierResponse> classify({
    required Object input,
    required Map<String, ClassifierQuestion> questions,
  }) async {
    final Map<String, Object?> body = <String, Object?>{
      'model': model,
      'state': _inputToState(input),
      'questions': <String, Object?>{
        for (final MapEntry<String, ClassifierQuestion> entry
            in questions.entries)
          entry.key: _questionToJson(entry.key, entry.value),
      },
    };

    if (questions.isEmpty) {
      return ClassifierResponse(
        answers: const <String, ClassifierAnswer>{},
        modelVersion: model,
      );
    }

    final TypesafeHttpResponse response = await _send(body);
    if (response.statusCode >= 400) {
      final String snippet = response.body.length > 500
          ? response.body.substring(0, 500)
          : response.body;
      throw StateError(
        'TypeSafe request failed with ${response.statusCode}: $snippet',
      );
    }

    final Object? data = jsonDecode(response.body);
    if (data is! Map) {
      throw const FormatException('TypeSafe did not return a JSON object.');
    }
    final Object? rawAnswers = data['answers'];
    if (rawAnswers is! Map) {
      throw const FormatException('TypeSafe returned no answers.');
    }

    final Map<String, ClassifierAnswer> answers = <String, ClassifierAnswer>{
      for (final MapEntry<String, ClassifierQuestion> entry
          in questions.entries)
        entry.key: _toAnswer(entry.key, entry.value, rawAnswers[entry.key]),
    };

    return ClassifierResponse(
      answers: answers,
      modelVersion: (data['model'] ?? data['model_version']) as String?,
    );
  }
}
