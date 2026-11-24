/// A classifier backed by the Gemini Decisions API.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../types/content.dart';
import '../../utils/google_client_headers.dart';
import '../../utils/system_environment/system_environment.dart';
import 'base_classifier.dart';
import 'types.dart';

const String _defaultBaseUrl = 'https://generativelanguage.googleapis.com';
const List<String> _apiKeyEnvs = <String>['GOOGLE_API_KEY', 'GEMINI_API_KEY'];
const String _decisionsPath = '/v1beta/decisions';
// A classifier usually runs in the path of a turn, so it gives up sooner than
// a general-purpose HTTP client default would suggest.
const double _defaultTimeoutSeconds = 30.0;
// The Gemini Developer API reports blocked input as an HTTP 400 with one of
// these error codes. Vertex AI reports it as `prompt_feedback` instead.
const Set<String> _blockedCodes = <String>{
  'safety',
  'prohibited_content',
  'blocklist',
  'image_safety',
  'jailbreak',
  'model_armor',
  'content_blocked',
};
// Lets rounding in the API put a probability a hair outside [0, 1].
const double _tolerance = 1e-6;

sealed class _WireAnswer {
  const _WireAnswer({required this.confidence});

  final double confidence;

  factory _WireAnswer.fromJson(Object? raw) {
    if (raw is! Map) {
      throw FormatException('Gemini Decisions answer must be a JSON object.');
    }
    final Object? type = raw['type'];
    final double confidence = _readNumber(raw['confidence'], 'confidence');
    switch (type) {
      case 'noul':
        return _NoulAnswer(
          noul: _readNumber(raw['noul'], 'noul'),
          confidence: confidence,
        );
      case 'choice':
        final Object? choice = raw['choice'];
        if (choice is! String) {
          throw FormatException(
            'Gemini Decisions choice answer must include a String choice.',
          );
        }
        final Object? rawProbs = raw['probabilities'];
        if (rawProbs is! Map) {
          throw FormatException(
            'Gemini Decisions choice answer must include a probabilities map.',
          );
        }
        return _ChoiceAnswer(
          choice: choice,
          probabilities: <String, double>{
            for (final MapEntry<Object?, Object?> entry in rawProbs.entries)
              '${entry.key}': _readNumber(
                entry.value,
                'probabilities[${entry.key}]',
              ),
          },
          confidence: confidence,
        );
      case 'score':
        final Object? rawProbs = raw['probabilities'];
        if (rawProbs is! Map) {
          throw FormatException(
            'Gemini Decisions score answer must include a probabilities map.',
          );
        }
        return _ScoreAnswer(
          score: _readNumber(raw['score'], 'score'),
          probabilities: <int, double>{
            for (final MapEntry<Object?, Object?> entry in rawProbs.entries)
              _readIntKey(entry.key): _readNumber(
                entry.value,
                'probabilities[${entry.key}]',
              ),
          },
          confidence: confidence,
        );
      default:
        throw FormatException(
          'Unsupported Gemini Decisions answer type: $type.',
        );
    }
  }
}

final class _NoulAnswer extends _WireAnswer {
  const _NoulAnswer({required this.noul, required super.confidence});

  final double noul;
}

final class _ChoiceAnswer extends _WireAnswer {
  const _ChoiceAnswer({
    required this.choice,
    required this.probabilities,
    required super.confidence,
  });

  final String choice;
  final Map<String, double> probabilities;
}

final class _ScoreAnswer extends _WireAnswer {
  const _ScoreAnswer({
    required this.score,
    required this.probabilities,
    required super.confidence,
  });

  final double score;
  final Map<int, double> probabilities;
}

final class _DecisionsApiResponse {
  const _DecisionsApiResponse({required this.answers, this.promptFeedback});

  final Map<String, _WireAnswer> answers;
  final Map<String, Object?>? promptFeedback;

  factory _DecisionsApiResponse.fromJson(Object? raw) {
    if (raw is! Map) {
      throw FormatException(
        'Gemini Decisions response body must be a JSON object.',
      );
    }
    final Map<String, _WireAnswer> parsedAnswers = <String, _WireAnswer>{};
    final Object? rawAnswers = raw['answers'];
    if (rawAnswers != null) {
      if (rawAnswers is! Map) {
        throw FormatException(
          'Gemini Decisions response "answers" must be a JSON object.',
        );
      }
      for (final MapEntry<Object?, Object?> entry in rawAnswers.entries) {
        parsedAnswers['${entry.key}'] = _WireAnswer.fromJson(entry.value);
      }
    }
    Map<String, Object?>? promptFeedback;
    final Object? rawFeedback = raw['prompt_feedback'];
    if (rawFeedback is Map) {
      promptFeedback = <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in rawFeedback.entries)
          '${entry.key}': entry.value,
      };
    }
    return _DecisionsApiResponse(
      answers: parsedAnswers,
      promptFeedback: promptFeedback,
    );
  }
}

double _readNumber(Object? value, String field) {
  if (value is num && value is! bool) {
    final double result = value.toDouble();
    if (result.isFinite) {
      return result;
    }
  }
  throw FormatException(
    'Gemini Decisions response field "$field" must be a finite number, '
    'got $value.',
  );
}

int _readIntKey(Object? key) {
  if (key is int) {
    return key;
  }
  if (key is String) {
    final int? parsed = int.tryParse(key);
    if (parsed != null) {
      return parsed;
    }
  }
  throw FormatException(
    'Gemini Decisions score probabilities key must be an integer, got $key.',
  );
}

String _render(Object? content) {
  if (content is String) {
    return content;
  }
  return jsonEncode(content);
}

Map<String, Object?> _mediaBlock(String? mimeType) {
  if (mimeType == null || mimeType.isEmpty) {
    throw ArgumentError(
      'GeminiDecisionsClassifier needs a MIME type on every inline data and '
      'file part.',
    );
  }
  final String normalized = mimeType.toLowerCase();
  final String prefix = normalized.split('/').first;
  final String type =
      (prefix == 'image' || prefix == 'audio' || prefix == 'video')
      ? prefix
      : 'document';
  return <String, Object?>{'type': type, 'mime_type': normalized};
}

Map<String, Object?> _partToJson(Part part) {
  if (part.text != null) {
    return <String, Object?>{'type': 'text', 'text': part.text};
  }
  final InlineData? blob = part.inlineData;
  if (blob != null) {
    return <String, Object?>{
      ..._mediaBlock(blob.mimeType),
      'data': base64Encode(blob.data),
    };
  }
  final FileData? file = part.fileData;
  if (file != null) {
    return <String, Object?>{..._mediaBlock(file.mimeType), 'uri': file.fileUri};
  }
  throw ArgumentError(
    'GeminiDecisionsClassifier accepts text, inline data and file parts only; '
    'the input has another kind of part.',
  );
}

Object _inputToJson(Object input) {
  if (input is! Content) {
    return _render(input);
  }
  return <Map<String, Object?>>[
    for (final Part part in input.parts)
      if (!part.thought) _partToJson(part),
  ];
}

Map<String, Object?> _questionToJson(String name, ClassifierQuestion question) {
  if (question.instructions == null) {
    throw ArgumentError(
      "GeminiDecisionsClassifier needs instructions for question '$name'.",
    );
  }
  final Map<String, Object?> body = <String, Object?>{
    'instructions': _render(question.instructions),
  };
  if (question is Choice) {
    body['type'] = 'choice';
    body['criteria'] = <String, String>{
      for (final MapEntry<String, Object?> entry in question.criteria.entries)
        entry.key: entry.value == null ? '' : _render(entry.value),
    };
  } else if (question is Binary) {
    body['type'] = 'noul';
    if (question.criteria != null) {
      body['criteria'] = <String, String>{
        'true_description': _render(question.criteria),
      };
    }
  } else if (question is Score) {
    body['type'] = 'score';
    body['criteria'] = <String>[
      for (final Object? level in question.criteria) _render(level),
    ];
  }
  return body;
}

bool _isBlocked(http.Response response) {
  if (response.statusCode != 400) {
    return false;
  }
  try {
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return false;
    }
    final Object? error = decoded['error'];
    if (error is! Map) {
      return false;
    }
    final Object? code = error['code'];
    return code is String && _blockedCodes.contains(code);
  } on FormatException {
    return false;
  }
}

double _inRange(String name, String field, double value, double high) {
  if (!value.isFinite || value < -_tolerance || value > high + _tolerance) {
    throw ArgumentError(
      "Gemini returned $field $value for '$name', outside [0, $high].",
    );
  }
  return value.clamp(0.0, high).toDouble();
}

Map<K, double> _probabilities<K extends Comparable<Object>>(
  String name,
  Map<K, double> raw,
  Iterable<K> keys,
) {
  final Set<K> expectedSet = keys.toSet();
  final Set<K> actualSet = raw.keys.toSet();
  if (actualSet.length != expectedSet.length ||
      !actualSet.containsAll(expectedSet)) {
    final List<K> sortedRaw = actualSet.toList()..sort();
    final List<K> sortedKeys = expectedSet.toList()..sort();
    throw ArgumentError(
      "Gemini returned probabilities for $sortedRaw in '$name', not for its "
      'options $sortedKeys.',
    );
  }
  return <K, double>{
    for (final K key in keys) key: _inRange(name, 'probability', raw[key]!, 1.0),
  };
}

ClassifierAnswer _toAnswer(
  String name,
  ClassifierQuestion question,
  _WireAnswer? raw,
) {
  if (question is Binary && raw is _NoulAnswer) {
    return BinaryAnswer(
      probability: _inRange(name, 'probability', raw.noul, 1.0),
      confidence: _inRange(name, 'confidence', raw.confidence, 1.0),
    );
  }
  if (question is Choice && raw is _ChoiceAnswer) {
    if (!question.criteria.containsKey(raw.choice)) {
      throw ArgumentError(
        "Gemini chose '${raw.choice}' for '$name', which is not one of its "
        'labels.',
      );
    }
    return ChoiceAnswer(
      choice: raw.choice,
      probabilities: _probabilities<String>(
        name,
        raw.probabilities,
        question.criteria.keys,
      ),
      confidence: _inRange(name, 'confidence', raw.confidence, 1.0),
    );
  }
  if (question is Binary || question is Choice || raw is! _ScoreAnswer) {
    throw ArgumentError(
      "Gemini returned ${raw.runtimeType} for '$name', which is a "
      "'${question.type}' question.",
    );
  }
  final Score scoreQuestion = question as Score;
  final double top = (scoreQuestion.criteria.length - 1).toDouble();
  return ScoreAnswer(
    score: _inRange(name, 'score', raw.score, top),
    probabilities: _probabilities<int>(
      name,
      raw.probabilities,
      List<int>.generate(scoreQuestion.criteria.length, (int i) => i),
    ),
    confidence: _inRange(name, 'confidence', raw.confidence, 1.0),
  );
}

/// Answers typed questions with the Gemini Decisions API.
///
/// The Decisions API scores every question about an input in one request and
/// returns calibrated probabilities instead of generated text. [Binary]
/// questions are sent as `noul` questions, and every question needs
/// `instructions`. Input can be text, JSON, or a [Content] with text, image,
/// audio, video, or document parts. If Gemini blocks the input, every answer
/// is a [RefusalAnswer].
///
/// The API is served by the Gemini Developer API only, so the classifier needs
/// an API key and does not use Vertex AI.
///
/// ```dart
/// final classifier = GeminiDecisionsClassifier(); // reads GOOGLE_API_KEY
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
class GeminiDecisionsClassifier extends BaseClassifier {
  /// Default Decisions API model name.
  static const String defaultModel = 'gemini-decision-1';

  /// Default Gemini Developer API base URL.
  static const String defaultBaseUrl = _defaultBaseUrl;

  /// Decisions API endpoint path.
  static const String decisionsPath = _decisionsPath;

  /// Default request timeout in seconds.
  static const double defaultTimeoutSeconds = _defaultTimeoutSeconds;

  /// Creates a [GeminiDecisionsClassifier].
  ///
  /// - [model]: The Decisions model. Defaults to [defaultModel].
  /// - [apiKey]: The Gemini API key. Defaults to `GOOGLE_API_KEY`, then
  ///   `GEMINI_API_KEY` from the environment.
  /// - [baseUrl]: Optional API base URL override. Defaults to [defaultBaseUrl].
  /// - [timeout]: Seconds to wait for each request. Defaults to
  ///   [defaultTimeoutSeconds] (30 seconds).
  /// - [httpClient]: Optional [http.Client] to send requests with (for example,
  ///   a client configured with a proxy or a mock client in tests).
  /// - [httpClientFactory]: Optional factory used to create the reused default
  ///   [http.Client] when [httpClient] is not provided.
  /// - [environment]: Optional environment map override for reading API keys
  ///   and tracking headers.
  GeminiDecisionsClassifier({
    super.model = defaultModel,
    this.apiKey,
    this.baseUrl,
    this.timeout,
    http.Client? httpClient,
    http.Client Function()? httpClientFactory,
    Map<String, String>? environment,
  }) : _httpClient = httpClient,
       _httpClientFactory = httpClientFactory,
       _environment = environment {
    if (timeout != null &&
        (timeout! <= 0 || timeout!.isNaN || timeout!.isInfinite)) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'timeout must be a finite number greater than 0.',
      );
    }
  }

  /// The API key. Defaults to `GOOGLE_API_KEY`, then `GEMINI_API_KEY`.
  final String? apiKey;

  /// The API base URL. Defaults to [defaultBaseUrl].
  final String? baseUrl;

  /// Seconds to wait for each request. Defaults to [defaultTimeoutSeconds].
  final double? timeout;

  final http.Client? _httpClient;
  final http.Client Function()? _httpClientFactory;
  final Map<String, String>? _environment;
  http.Client? _defaultHttpClient;

  @override
  String get clientLabelKind => 'gemini';

  http.Client _getClient() {
    if (_httpClient != null) {
      return _httpClient;
    }
    return _defaultHttpClient ??= (_httpClientFactory ?? http.Client.new)();
  }

  Uri _buildUrl() {
    final String rawBase = baseUrl ?? _defaultBaseUrl;
    final String trimmed = rawBase.endsWith('/')
        ? rawBase.replaceFirst(RegExp(r'/+$'), '')
        : rawBase;
    return Uri.parse('$trimmed$_decisionsPath');
  }

  Map<String, String> _headers() {
    final Map<String, String> env = _environment ?? readSystemEnvironment();
    String? resolvedKey = apiKey;
    if (resolvedKey == null || resolvedKey.isEmpty) {
      for (final String name in _apiKeyEnvs) {
        final String? value = env[name];
        if (value != null && value.isNotEmpty) {
          resolvedKey = value;
          break;
        }
      }
    }
    if (resolvedKey == null || resolvedKey.isEmpty) {
      throw ArgumentError(
        'GeminiDecisionsClassifier needs an API key. Set GOOGLE_API_KEY or '
        'pass apiKey.',
      );
    }
    return <String, String>{
      'content-type': 'application/json',
      'x-goog-api-key': resolvedKey,
      ...getTrackingHeaders(environment: env),
    };
  }

  Duration get _requestTimeout {
    final double seconds = timeout ?? _defaultTimeoutSeconds;
    return Duration(microseconds: (seconds * 1000000).round());
  }

  /// Closes the internally created default [http.Client], if any.
  ///
  /// Does not close a caller-supplied `httpClient`.
  void close() {
    _defaultHttpClient?.close();
    _defaultHttpClient = null;
  }

  /// Asks Gemini every question in [questions] in one Decisions request.
  ///
  /// - [input]: What the questions are about: text, JSON, or a [Content] whose
  ///   parts are text, inline data, or file URIs. Thought parts are skipped.
  /// - [questions]: Maps a name to each question. Every question needs
  ///   `instructions`.
  ///
  /// Returns one answer per question, keyed by the question's name. If Gemini
  /// blocked the input, every answer is a [RefusalAnswer].
  ///
  /// Throws an [ArgumentError] if [questions] is empty, no API key is set, a
  /// question has no instructions, the input has an unsupported part or a media
  /// part without a MIME type, or an answer does not match its question.
  /// Throws a [StateError] if the HTTP request fails.
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
          'classify() needs at least one question.',
        );
      }

      final Map<String, Object?> body = <String, Object?>{
        'model': model,
        'input': _inputToJson(input),
        'questions': <String, Object?>{
          for (final MapEntry<String, ClassifierQuestion> entry
              in questions.entries)
            entry.key: _questionToJson(entry.key, entry.value),
        },
      };
      final Map<String, String> headers = _headers();
      final http.Client client = _getClient();
      final Uri uri = _buildUrl();
      final http.Response response = await client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_requestTimeout);

      if (_isBlocked(response)) {
        return ClassifierResponse(
          answers: <String, ClassifierAnswer>{
            for (final String name in questions.keys) name: RefusalAnswer(),
          },
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String snippet = response.body.length > 500
            ? response.body.substring(0, 500)
            : response.body;
        throw StateError(
          'Gemini Decisions request failed with ${response.statusCode}: '
          '$snippet',
        );
      }

      final Object? decoded = jsonDecode(response.body);
      final _DecisionsApiResponse data = _DecisionsApiResponse.fromJson(
        decoded,
      );
      final Object? blockReason = data.promptFeedback?['block_reason'];
      if (blockReason != null && blockReason != false && blockReason != '') {
        return ClassifierResponse(
          answers: <String, ClassifierAnswer>{
            for (final String name in questions.keys) name: RefusalAnswer(),
          },
        );
      }

      return ClassifierResponse(
        answers: <String, ClassifierAnswer>{
          for (final MapEntry<String, ClassifierQuestion> entry
              in questions.entries)
            entry.key: _toAnswer(
              entry.key,
              entry.value,
              data.answers[entry.key],
            ),
        },
      );
    });
  }
}
