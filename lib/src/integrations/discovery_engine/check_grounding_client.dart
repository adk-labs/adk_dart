/// Client for the Discovery Engine CheckGrounding API.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../../tools/_google_access_token.dart';
import '../../version.dart';
import 'types.dart';

/// User-Agent / client label sent on CheckGrounding API requests.
const String checkGroundingUserAgent =
    'adk-check-grounding google-adk/$adkVersion';

const String _globalLocation = 'global';
const Duration _defaultTimeout = Duration(seconds: 20);
const Duration _defaultRetryInitial = Duration(seconds: 1);
const Duration _defaultRetryMaximum = Duration(seconds: 10);
const int _defaultMaxRetries = 3;

const Set<int> _transientHttpCodes = <int>{429, 503, 504};
const Set<String> _transientGrpcStatuses = <String>{
  'RESOURCE_EXHAUSTED',
  'UNAVAILABLE',
  'DEADLINE_EXCEEDED',
};

/// Exception thrown by a [CheckGroundingTransport] when the API returns an error.
class CheckGroundingApiException implements Exception {
  /// Creates a CheckGrounding API exception.
  const CheckGroundingApiException({
    required this.message,
    this.statusCode,
    this.status,
  });

  /// Human-readable error message from the backend.
  final String message;

  /// Optional HTTP status code (for example `400`, `429`, `503`, `504`).
  final int? statusCode;

  /// Optional RPC status string (for example `'INVALID_ARGUMENT'`).
  final String? status;

  /// Whether this error represents an `INVALID_ARGUMENT` / HTTP 400 response.
  bool get isInvalidArgument =>
      statusCode == 400 || status?.toUpperCase() == 'INVALID_ARGUMENT';

  /// Whether this error is transient (`429`, `503`, `504` / retryable gRPC status).
  bool get isTransient =>
      (statusCode != null && _transientHttpCodes.contains(statusCode)) ||
      (status != null && _transientGrpcStatuses.contains(status!.toUpperCase()));

  @override
  String toString() =>
      'CheckGroundingApiException(statusCode: $statusCode, status: $status, '
      'message: $message)';
}

/// Transport function for executing one Discovery Engine `checkGrounding` RPC.
typedef CheckGroundingTransport =
    Future<Map<String, Object?>> Function({
      required Uri endpoint,
      required Map<String, Object?> requestBody,
      required Map<String, String> headers,
      required Duration timeout,
    });

/// Provider for auth headers used by [CheckGroundingClient].
typedef CheckGroundingAuthHeadersProvider =
    Future<Map<String, String>> Function();

/// Verifies answers against facts with the Discovery Engine CheckGrounding API.
///
/// The API rejects answers longer than its token limit; such answers produce a
/// [GroundingStatus.rejectedTooLong] result rather than an exception.
class CheckGroundingClient {
  /// Initializes the client.
  ///
  /// Resolves [projectId] from the parameter or `GOOGLE_CLOUD_PROJECT` in
  /// [environment]. Throws an [ArgumentError] when no project ID is available
  /// or [citationThreshold] is outside `[0.0, 1.0]`.
  CheckGroundingClient({
    String? projectId,
    String location = _globalLocation,
    String groundingConfig = 'default_grounding_config',
    double citationThreshold = 0.6,
    bool enableClaimLevelScore = true,
    GroundingLimits? limits,
    CheckGroundingTransport? transport,
    CheckGroundingAuthHeadersProvider? authHeadersProvider,
    Map<String, String>? environment,
    Duration timeout = _defaultTimeout,
    int maxRetries = _defaultMaxRetries,
    Duration retryInitialDelay = _defaultRetryInitial,
  }) : _location = location,
       _groundingConfig = groundingConfig,
       _citationThreshold = citationThreshold,
       _enableClaimLevelScore = enableClaimLevelScore,
       _limits = limits ?? GroundingLimits(),
       _suppliedTransport = transport,
       _authHeadersProvider = authHeadersProvider,
       _timeout = timeout,
       _maxRetries = maxRetries,
       _retryInitialDelay = retryInitialDelay {
    final Map<String, String> env = environment ?? Platform.environment;
    final String? resolvedProject =
        (projectId != null && projectId.trim().isNotEmpty)
        ? projectId.trim()
        : env['GOOGLE_CLOUD_PROJECT']?.trim();
    if (resolvedProject == null || resolvedProject.isEmpty) {
      throw ArgumentError(
        'project_id is required; pass it or set GOOGLE_CLOUD_PROJECT.',
      );
    }
    if (!citationThreshold.isFinite ||
        citationThreshold < 0.0 ||
        citationThreshold > 1.0) {
      throw ArgumentError.value(
        citationThreshold,
        'citationThreshold',
        'citation_threshold must be between 0 and 1, got $citationThreshold.',
      );
    }
    _projectId = resolvedProject;
  }

  late final String _projectId;
  final String _location;
  final String _groundingConfig;
  final double _citationThreshold;
  final bool _enableClaimLevelScore;
  final GroundingLimits _limits;
  final CheckGroundingTransport? _suppliedTransport;
  final CheckGroundingAuthHeadersProvider? _authHeadersProvider;
  final Duration _timeout;
  final int _maxRetries;
  final Duration _retryInitialDelay;
  HttpClient? _ownedHttpClient;

  /// Google Cloud project ID resolved for this client.
  String get projectId => _projectId;

  /// Discovery Engine location of the grounding config.
  String get location => _location;

  /// Grounding config resource name segment.
  String get groundingConfig => _groundingConfig;

  /// Grounding capacity limits enforced by this client.
  GroundingLimits get limits => _limits;

  /// Returns the REST endpoint URI for `groundingConfigs.check`.
  Uri get endpoint {
    final String host = _location == _globalLocation
        ? 'discoveryengine.googleapis.com'
        : '$_location-discoveryengine.googleapis.com';
    final String resource =
        'projects/$_projectId/locations/$_location'
        '/groundingConfigs/$_groundingConfig';
    return Uri.https(host, '/v1/$resource:check');
  }

  /// Closes any HTTP client created by this instance.
  ///
  /// A custom [CheckGroundingTransport] passed to the constructor is left open
  /// for its owner to close.
  Future<void> close() async {
    final HttpClient? client = _ownedHttpClient;
    _ownedHttpClient = null;
    client?.close(force: true);
  }

  /// Checks how well [facts] support [answerCandidate].
  ///
  /// Only the first `limits.maxFacts` chunks are sent. Errors returned by the
  /// API are reported through [GroundingResult.status] rather than thrown.
  Future<GroundingResult> checkGroundingAsync({
    required String answerCandidate,
    required List<FactChunk> facts,
  }) async {
    if (facts.isEmpty) {
      return const GroundingResult(
        status: GroundingStatus.skippedNoFacts,
        numFactsEvaluated: 0,
      );
    }
    final List<FactChunk> evaluatedFacts = facts.length > _limits.maxFacts
        ? facts.sublist(0, _limits.maxFacts)
        : facts;
    if (answerCandidate.trim().isEmpty) {
      return const GroundingResult(
        status: GroundingStatus.skippedEmpty,
        numFactsEvaluated: 0,
      );
    }

    final String groundingConfigResource =
        'projects/$_projectId/locations/$_location'
        '/groundingConfigs/$_groundingConfig';
    final Map<String, Object?> requestBody = <String, Object?>{
      'groundingConfig': groundingConfigResource,
      'answerCandidate': answerCandidate,
      'facts': evaluatedFacts.map(_toGroundingFact).toList(growable: false),
      'groundingSpec': <String, Object?>{
        'citationThreshold': _citationThreshold,
        'enableClaimLevelScore': _enableClaimLevelScore,
      },
    };

    // Resolve auth headers outside the API-error try block so missing
    // credentials surface directly instead of being reported as an API error.
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': checkGroundingUserAgent,
      'x-goog-api-client': checkGroundingUserAgent,
    };
    if (_authHeadersProvider != null) {
      headers.addAll(await _authHeadersProvider());
    } else if (_suppliedTransport == null) {
      final String token = await resolveDefaultGoogleAccessToken(
        scopes: const <String>[
          'https://www.googleapis.com/auth/cloud-platform',
        ],
      );
      headers['Authorization'] = 'Bearer $token';
    }

    final CheckGroundingTransport transport =
        _suppliedTransport ?? _defaultTransport;
    final Uri targetUri = endpoint;

    Map<String, Object?> response;
    try {
      response = await _callWithRetry(
        () => transport(
          endpoint: targetUri,
          requestBody: requestBody,
          headers: headers,
          timeout: _timeout,
        ),
      );
    } on CheckGroundingApiException catch (e) {
      if (e.isInvalidArgument) {
        final GroundingStatus status = _isAnswerTooLong(e)
            ? GroundingStatus.rejectedTooLong
            : GroundingStatus.apiError;
        developer.log(
          'CheckGrounding rejected the request for $groundingConfigResource: $e',
          name: 'adk_dart.discovery_engine',
        );
        return GroundingResult(
          status: status,
          numFactsEvaluated: evaluatedFacts.length,
          error: e.message,
        );
      }
      developer.log(
        'CheckGrounding request for $groundingConfigResource failed: $e',
        name: 'adk_dart.discovery_engine',
      );
      return GroundingResult(
        status: GroundingStatus.apiError,
        numFactsEvaluated: evaluatedFacts.length,
        error: e.message,
      );
    }

    final double? supportScore = _readOptionalDouble(
      response,
      'supportScore',
      'support_score',
    );
    final List<Map<String, Object?>> claims = _readMapList(
      response['claims'],
    );
    final int numClaims = claims
        .where(
          (Map<String, Object?> c) =>
              (c['groundingCheckRequired'] ?? c['grounding_check_required']) ==
              true,
        )
        .length;

    return GroundingResult(
      status: GroundingStatus.ok,
      numFactsEvaluated: evaluatedFacts.length,
      metadata: _toGroundingMetadata(response, evaluatedFacts),
      supportScore: supportScore,
      numClaims: numClaims,
    );
  }

  Future<Map<String, Object?>> _callWithRetry(
    Future<Map<String, Object?>> Function() call,
  ) async {
    Duration delay = _retryInitialDelay;
    int attempt = 0;
    while (true) {
      try {
        return await call();
      } on TimeoutException catch (e) {
        final CheckGroundingApiException wrapped = CheckGroundingApiException(
          message: 'CheckGrounding request timed out: $e',
          statusCode: 504,
          status: 'DEADLINE_EXCEEDED',
        );
        if (attempt >= _maxRetries) {
          throw wrapped;
        }
        attempt += 1;
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
          final int nextMicros = delay.inMicroseconds * 2;
          delay = nextMicros > _defaultRetryMaximum.inMicroseconds
              ? _defaultRetryMaximum
              : Duration(microseconds: nextMicros);
        }
      } on SocketException catch (e) {
        final CheckGroundingApiException wrapped = CheckGroundingApiException(
          message: 'CheckGrounding network error: $e',
          statusCode: 503,
          status: 'UNAVAILABLE',
        );
        if (attempt >= _maxRetries) {
          throw wrapped;
        }
        attempt += 1;
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
          final int nextMicros = delay.inMicroseconds * 2;
          delay = nextMicros > _defaultRetryMaximum.inMicroseconds
              ? _defaultRetryMaximum
              : Duration(microseconds: nextMicros);
        }
      } on HttpException catch (e) {
        final CheckGroundingApiException wrapped = CheckGroundingApiException(
          message: 'CheckGrounding HTTP error: $e',
          statusCode: 503,
          status: 'UNAVAILABLE',
        );
        if (attempt >= _maxRetries) {
          throw wrapped;
        }
        attempt += 1;
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
          final int nextMicros = delay.inMicroseconds * 2;
          delay = nextMicros > _defaultRetryMaximum.inMicroseconds
              ? _defaultRetryMaximum
              : Duration(microseconds: nextMicros);
        }
      } on CheckGroundingApiException catch (e) {
        if (!e.isTransient || attempt >= _maxRetries) {
          rethrow;
        }
        attempt += 1;
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
          final int nextMicros = delay.inMicroseconds * 2;
          delay = nextMicros > _defaultRetryMaximum.inMicroseconds
              ? _defaultRetryMaximum
              : Duration(microseconds: nextMicros);
        }
      }
    }
  }

  Future<Map<String, Object?>> _defaultTransport({
    required Uri endpoint,
    required Map<String, Object?> requestBody,
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    final HttpClient client = _ownedHttpClient ??= HttpClient();
    final HttpClientResponse response;
    final String bodyText;
    try {
      final HttpClientRequest request = await client
          .postUrl(endpoint)
          .timeout(timeout);
      headers.forEach(request.headers.set);
      request.add(utf8.encode(jsonEncode(requestBody)));
      response = await request.close().timeout(timeout);
      bodyText = await utf8.decodeStream(response).timeout(timeout);
    } on TimeoutException catch (e) {
      throw CheckGroundingApiException(
        message: 'CheckGrounding request timed out: $e',
        statusCode: 504,
        status: 'DEADLINE_EXCEEDED',
      );
    } on SocketException catch (e) {
      throw CheckGroundingApiException(
        message: 'CheckGrounding network error: $e',
        statusCode: 503,
        status: 'UNAVAILABLE',
      );
    } on HttpException catch (e) {
      throw CheckGroundingApiException(
        message: 'CheckGrounding HTTP error: $e',
        statusCode: 503,
        status: 'UNAVAILABLE',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = bodyText;
      String? status;
      try {
        final Object? decoded = jsonDecode(bodyText);
        if (decoded is Map && decoded['error'] is Map) {
          final Map errorObj = decoded['error'] as Map;
          if (errorObj['message'] is String) {
            message = errorObj['message'] as String;
          }
          if (errorObj['status'] is String) {
            status = errorObj['status'] as String;
          }
        }
      } catch (_) {}
      throw CheckGroundingApiException(
        statusCode: response.statusCode,
        status: status,
        message: message,
      );
    }

    final Object? decoded = bodyText.trim().isEmpty
        ? <String, Object?>{}
        : jsonDecode(bodyText);
    if (decoded is! Map) {
      throw const CheckGroundingApiException(
        message: 'CheckGrounding API returned a non-object JSON payload.',
      );
    }
    return decoded.map(
      (Object? k, Object? v) => MapEntry<String, Object?>('$k', v),
    );
  }
}

bool _isAnswerTooLong(CheckGroundingApiException error) {
  return error.message.toLowerCase().contains('token limit');
}

Map<String, Object?> _toGroundingFact(FactChunk chunk) {
  final Map<String, String> attributes = Map<String, String>.from(
    chunk.attributes,
  );
  if (chunk.title != null && chunk.title!.isNotEmpty) {
    attributes.putIfAbsent('title', () => chunk.title!);
  }
  if (chunk.link != null && chunk.link!.isNotEmpty) {
    attributes.putIfAbsent('source', () => chunk.link!);
  }
  return <String, Object?>{
    'factText': chunk.text,
    'attributes': attributes,
  };
}

bool _isAsciiDigits(String value) {
  if (value.isEmpty) return false;
  for (int i = 0; i < value.length; i += 1) {
    final int code = value.codeUnitAt(i);
    if (code < 0x30 || code > 0x39) {
      return false;
    }
  }
  return true;
}

List<Map<String, Object?>> _toGroundingChunks(
  Map<String, Object?> response,
  List<FactChunk> facts,
) {
  final List<Map<String, Object?>> citedChunks = _readMapList(
    response['citedChunks'] ?? response['cited_chunks'],
  );
  final List<Map<String, Object?>> chunks = <Map<String, Object?>>[];
  for (final Map<String, Object?> cited in citedChunks) {
    FactChunk? fact;
    final String source = '${cited['source'] ?? ''}';
    if (_isAsciiDigits(source)) {
      final int idx = int.parse(source);
      if (idx < facts.length) {
        fact = facts[idx];
      }
    }

    final Map<String, String> sourceMeta = _readStringMap(
      cited['sourceMetadata'] ?? cited['source_metadata'],
    );
    final Map<String, String> attributes = sourceMeta.isNotEmpty
        ? sourceMeta
        : (fact?.attributes ?? const <String, String>{});

    final String? chunkText = _nonEmptyString(
      cited['chunkText'] ?? cited['chunk_text'],
    );
    final String? title = _nonEmptyString(cited['title']);
    final String? uri = _nonEmptyString(cited['uri']);

    final List<Map<String, Object?>> customMetadata = <Map<String, Object?>>[
      for (final MapEntry<String, String> entry in attributes.entries)
        <String, Object?>{'key': entry.key, 'string_value': entry.value},
    ];

    chunks.add(<String, Object?>{
      'retrieved_context': <String, Object?>{
        if ((chunkText ?? fact?.text) != null) 'text': chunkText ?? fact!.text,
        if ((title ?? fact?.title) != null) 'title': title ?? fact!.title,
        if ((uri ?? fact?.link) != null) 'uri': uri ?? fact!.link,
        if (customMetadata.isNotEmpty) 'custom_metadata': customMetadata,
      },
    });
  }
  return chunks;
}

Map<String, Object?> _toGroundingMetadata(
  Map<String, Object?> response,
  List<FactChunk> facts,
) {
  final List<Map<String, Object?>> chunks = _toGroundingChunks(response, facts);
  final double? responseSupportScore = _readOptionalDouble(
    response,
    'supportScore',
    'support_score',
  );
  final List<Map<String, Object?>> claims = _readMapList(response['claims']);
  final List<Map<String, Object?>> supports = <Map<String, Object?>>[];

  for (final Map<String, Object?> claim in claims) {
    if ((claim['groundingCheckRequired'] ??
            claim['grounding_check_required']) !=
        true) {
      continue;
    }
    final List<int> indices = _readIntList(
      claim['citationIndices'] ?? claim['citation_indices'],
    ).where((int i) => i >= 0 && i < chunks.length).toList(growable: false);
    if (indices.isEmpty) {
      continue;
    }

    final double? claimScore = _readOptionalDouble(claim, 'score', 'score');
    List<double>? confidenceScores;
    if (claimScore != null) {
      final double rounded = double.parse(claimScore.toStringAsFixed(4));
      confidenceScores = List<double>.filled(indices.length, rounded);
    } else if (responseSupportScore != null) {
      final double rounded = double.parse(
        responseSupportScore.toStringAsFixed(4),
      );
      confidenceScores = List<double>.filled(indices.length, rounded);
    }

    final int? startIndex = _readOptionalInt(claim, 'startPos', 'start_pos');
    final int? endIndex = _readOptionalInt(claim, 'endPos', 'end_pos');
    final String? claimText = _nonEmptyString(
      claim['claimText'] ?? claim['claim_text'],
    );

    supports.add(<String, Object?>{
      'segment': <String, Object?>{
        'start_index': ?startIndex,
        'end_index': ?endIndex,
        'text': ?claimText,
      },
      'grounding_chunk_indices': indices,
      'confidence_scores': ?confidenceScores,
    });
  }

  return <String, Object?>{
    if (chunks.isNotEmpty) 'grounding_chunks': chunks,
    if (supports.isNotEmpty) 'grounding_supports': supports,
  };
}

List<Map<String, Object?>> _readMapList(Object? raw) {
  if (raw is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final Object? item in raw)
      if (item is Map)
        item.map((Object? k, Object? v) => MapEntry<String, Object?>('$k', v)),
  ];
}

Map<String, String> _readStringMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  return <String, String>{
    for (final MapEntry<Object?, Object?> entry in raw.entries)
      if (entry.key != null && entry.value != null)
        '${entry.key}': '${entry.value}',
  };
}

List<int> _readIntList(Object? raw) {
  if (raw is! List) return const <int>[];
  return <int>[
    for (final Object? item in raw)
      if (item is int) item else if (item is num) item.toInt(),
  ];
}

double? _readOptionalDouble(
  Map<String, Object?> map,
  String camelKey,
  String snakeKey,
) {
  final Object? raw = map.containsKey(camelKey)
      ? map[camelKey]
      : map[snakeKey];
  if (raw is num && raw is! bool) {
    return raw.toDouble();
  }
  return null;
}

int? _readOptionalInt(
  Map<String, Object?> map,
  String camelKey,
  String snakeKey,
) {
  final Object? raw = map.containsKey(camelKey)
      ? map[camelKey]
      : map[snakeKey];
  if (raw is int) return raw;
  if (raw is num && raw is! bool) return raw.toInt();
  return null;
}

String? _nonEmptyString(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return raw;
  }
  return null;
}
