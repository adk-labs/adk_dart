import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../events/event.dart';
import '../events/event_actions.dart';
import '../types/content.dart';
import '../utils/vertex_ai_utils.dart';
import 'base_session_service.dart';
import 'session.dart';

abstract class VertexAiSessionApiClient {
  Future<Map<String, Object?>?> createSession({
    required String reasoningEngineId,
    required String userId,
    required Map<String, Object?> config,
  });

  Future<Map<String, Object?>?> getSession({
    required String reasoningEngineId,
    required String sessionId,
  });

  Stream<Map<String, Object?>> listSessions({
    required String reasoningEngineId,
    String? userId,
  });

  Future<void> deleteSession({
    required String reasoningEngineId,
    required String sessionId,
  });

  Stream<Map<String, Object?>> listEvents({
    required String reasoningEngineId,
    required String sessionId,
    double? afterTimestamp,
  });

  Future<void> appendEvent({
    required String reasoningEngineId,
    required String sessionId,
    required String author,
    required String invocationId,
    required double timestamp,
    required Map<String, Object?> config,
  });
}

typedef VertexAiSessionApiClientFactory =
    VertexAiSessionApiClient Function({
      String? project,
      String? location,
      String? apiKey,
    });

typedef VertexAiSessionAccessTokenProvider = Future<String?> Function();

typedef VertexAiSessionUriBuilder =
    Uri Function({
      required String operation,
      required String reasoningEngineId,
      required String? sessionId,
      required String? project,
      required String? location,
      required String apiVersion,
      required String? apiKey,
    });

VertexAiSessionApiClient _defaultSessionApiClientFactory({
  String? project,
  String? location,
  String? apiKey,
}) {
  final bool hasProjectAndLocation =
      (project?.isNotEmpty ?? false) && (location?.isNotEmpty ?? false);
  if (hasProjectAndLocation || (apiKey?.isNotEmpty ?? false)) {
    return VertexAiSessionHttpApiClient(
      project: project,
      location: location,
      apiKey: apiKey,
    );
  }
  throw ArgumentError(
    'VertexAiSessionService requires either project/location or '
    'expressModeApiKey.',
  );
}

class VertexAiSessionHttpApiClient implements VertexAiSessionApiClient {
  VertexAiSessionHttpApiClient({
    this.project,
    this.location,
    this.apiKey,
    String apiVersion = 'v1beta1',
    http.Client? httpClient,
    VertexAiSessionAccessTokenProvider? accessTokenProvider,
    VertexAiSessionUriBuilder? uriBuilder,
  }) : _apiVersion = apiVersion,
       _httpClient = httpClient ?? http.Client(),
       _accessTokenProvider =
           accessTokenProvider ?? _defaultVertexAiAccessTokenProvider,
       _uriBuilder = uriBuilder ?? _defaultVertexAiSessionUriBuilder;

  final String? project;
  final String? location;
  final String? apiKey;
  final String _apiVersion;
  final http.Client _httpClient;
  final VertexAiSessionAccessTokenProvider _accessTokenProvider;
  final VertexAiSessionUriBuilder _uriBuilder;

  @override
  Future<Map<String, Object?>?> createSession({
    required String reasoningEngineId,
    required String userId,
    required Map<String, Object?> config,
  }) async {
    final Map<String, Object?> response = await _requestJson(
      method: 'POST',
      operation: 'createSession',
      reasoningEngineId: reasoningEngineId,
      payload: <String, Object?>{'user_id': userId, 'config': config},
    );
    final Map<String, Object?>? session = _extractSessionFromCreateResponse(
      response,
    );
    return session;
  }

  @override
  Future<Map<String, Object?>?> getSession({
    required String reasoningEngineId,
    required String sessionId,
  }) async {
    return _requestJsonOrNull(
      method: 'GET',
      operation: 'getSession',
      reasoningEngineId: reasoningEngineId,
      sessionId: sessionId,
      allowNotFound: true,
    );
  }

  @override
  Stream<Map<String, Object?>> listSessions({
    required String reasoningEngineId,
    String? userId,
  }) async* {
    String? pageToken;
    while (true) {
      final Map<String, String> query = <String, String>{
        if (userId != null && userId.isNotEmpty) 'filter': 'user_id="$userId"',
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      };
      final Map<String, Object?> page =
          await _requestJson(
            method: 'GET',
            operation: 'listSessions',
            reasoningEngineId: reasoningEngineId,
            queryParameters: query,
          );
      final List<Object?> rows = _asList(
        page['sessions'] ?? page['items'] ?? page['data'],
      );
      for (final Object? row in rows) {
        final Map<String, Object?> mapped = _asStringMap(row);
        if (mapped.isNotEmpty) {
          yield mapped;
        }
      }
      pageToken = _readStringByKeys(page, const <String>[
        'next_page_token',
        'nextPageToken',
      ]);
      if (pageToken == null || pageToken.isEmpty) {
        break;
      }
    }
  }

  @override
  Future<void> deleteSession({
    required String reasoningEngineId,
    required String sessionId,
  }) async {
    await _requestJson(
      method: 'DELETE',
      operation: 'deleteSession',
      reasoningEngineId: reasoningEngineId,
      sessionId: sessionId,
      allowEmptyBody: true,
    );
  }

  @override
  Stream<Map<String, Object?>> listEvents({
    required String reasoningEngineId,
    required String sessionId,
    double? afterTimestamp,
  }) async* {
    String? pageToken;
    while (true) {
      final Map<String, String> query = <String, String>{
        if (afterTimestamp != null)
          'filter':
              'timestamp>="${DateTime.fromMillisecondsSinceEpoch((afterTimestamp * 1000).round(), isUtc: true).toIso8601String()}"',
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      };
      final Map<String, Object?> page =
          await _requestJson(
            method: 'GET',
            operation: 'listEvents',
            reasoningEngineId: reasoningEngineId,
            sessionId: sessionId,
            queryParameters: query,
          );
      final List<Object?> rows = _asList(
        page['events'] ?? page['items'] ?? page['data'],
      );
      for (final Object? row in rows) {
        final Map<String, Object?> mapped = _asStringMap(row);
        if (mapped.isNotEmpty) {
          yield mapped;
        }
      }
      pageToken = _readStringByKeys(page, const <String>[
        'next_page_token',
        'nextPageToken',
      ]);
      if (pageToken == null || pageToken.isEmpty) {
        break;
      }
    }
  }

  @override
  Future<void> appendEvent({
    required String reasoningEngineId,
    required String sessionId,
    required String author,
    required String invocationId,
    required double timestamp,
    required Map<String, Object?> config,
  }) async {
    await _requestJson(
      method: 'POST',
      operation: 'appendEvent',
      reasoningEngineId: reasoningEngineId,
      sessionId: sessionId,
      payload: <String, Object?>{
        'author': author,
        'invocation_id': invocationId,
        'timestamp': DateTime.fromMillisecondsSinceEpoch(
          (timestamp * 1000).round(),
          isUtc: true,
        ).toIso8601String(),
        'config': config,
      },
      allowEmptyBody: true,
    );
  }

  Future<Map<String, Object?>?> _requestJsonOrNull({
    required String method,
    required String operation,
    required String reasoningEngineId,
    String? sessionId,
    Map<String, Object?>? payload,
    Map<String, String>? queryParameters,
    bool allowNotFound = false,
    bool allowEmptyBody = false,
  }) async {
    final Uri baseUri = _uriBuilder(
      operation: operation,
      reasoningEngineId: reasoningEngineId,
      sessionId: sessionId,
      project: project,
      location: location,
      apiVersion: _apiVersion,
      apiKey: apiKey,
    );
    final Uri uri = (queryParameters == null || queryParameters.isEmpty)
        ? baseUri
        : baseUri.replace(
            queryParameters: <String, String>{
              ...baseUri.queryParameters,
              ...queryParameters,
            },
          );

    final String? accessToken = await _accessTokenProvider();
    final Map<String, String> headers = <String, String>{
      'accept': 'application/json',
      if (payload != null) 'content-type': 'application/json',
      if (accessToken != null && accessToken.isNotEmpty)
        HttpHeaders.authorizationHeader: 'Bearer $accessToken',
    };

    final http.Request request = http.Request(method, uri)
      ..headers.addAll(headers);
    if (payload != null) {
      request.body = jsonEncode(payload);
    }

    final http.StreamedResponse streamed = await _httpClient.send(request);
    final String body = await streamed.stream.bytesToString();
    if (allowNotFound && streamed.statusCode == 404) {
      return null;
    }
    if (streamed.statusCode >= 400) {
      throw HttpException(
        'Vertex Session API call failed (${streamed.statusCode}): $body',
      );
    }

    final String trimmed = body.trim();
    if (trimmed.isEmpty) {
      if (allowEmptyBody) {
        return <String, Object?>{};
      }
      return <String, Object?>{};
    }

    final Object? decoded = jsonDecode(trimmed);
    if (decoded is! Map) {
      return <String, Object?>{};
    }
    return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
  }

  Future<Map<String, Object?>> _requestJson({
    required String method,
    required String operation,
    required String reasoningEngineId,
    String? sessionId,
    Map<String, Object?>? payload,
    Map<String, String>? queryParameters,
    bool allowNotFound = false,
    bool allowEmptyBody = false,
  }) async {
    final Map<String, Object?>? result = await _requestJsonOrNull(
      method: method,
      operation: operation,
      reasoningEngineId: reasoningEngineId,
      sessionId: sessionId,
      payload: payload,
      queryParameters: queryParameters,
      allowNotFound: allowNotFound,
      allowEmptyBody: allowEmptyBody,
    );
    return result ?? <String, Object?>{};
  }
}

Future<String?> _defaultVertexAiAccessTokenProvider() async {
  final Map<String, String> environment = Platform.environment;
  return environment['GOOGLE_OAUTH_ACCESS_TOKEN'] ??
      environment['GOOGLE_ACCESS_TOKEN'] ??
      environment['ACCESS_TOKEN'];
}

Uri _defaultVertexAiSessionUriBuilder({
  required String operation,
  required String reasoningEngineId,
  required String? sessionId,
  required String? project,
  required String? location,
  required String apiVersion,
  required String? apiKey,
}) {
  final bool hasProjectAndLocation =
      (project?.isNotEmpty ?? false) && (location?.isNotEmpty ?? false);
  final String baseUrl = (location?.isNotEmpty ?? false)
      ? 'https://$location-aiplatform.googleapis.com/'
      : 'https://aiplatform.googleapis.com/';
  final String engineResource = hasProjectAndLocation
      ? 'projects/$project/locations/$location/reasoningEngines/$reasoningEngineId'
      : 'reasoningEngines/$reasoningEngineId';

  late final String operationPath;
  switch (operation) {
    case 'createSession':
    case 'listSessions':
      operationPath = '$apiVersion/$engineResource/sessions';
      break;
    case 'getSession':
    case 'deleteSession':
      if (sessionId == null || sessionId.isEmpty) {
        throw ArgumentError('sessionId is required for $operation');
      }
      operationPath = '$apiVersion/$engineResource/sessions/$sessionId';
      break;
    case 'listEvents':
      if (sessionId == null || sessionId.isEmpty) {
        throw ArgumentError('sessionId is required for listEvents');
      }
      operationPath = '$apiVersion/$engineResource/sessions/$sessionId/events';
      break;
    case 'appendEvent':
      if (sessionId == null || sessionId.isEmpty) {
        throw ArgumentError('sessionId is required for appendEvent');
      }
      operationPath =
          '$apiVersion/$engineResource/sessions/$sessionId/events:append';
      break;
    default:
      throw ArgumentError.value(
        operation,
        'operation',
        'Unsupported Vertex session operation.',
      );
  }

  final Uri uri = Uri.parse(baseUrl).resolve(operationPath);
  final String? resolvedApiKey = apiKey?.trim();
  if (resolvedApiKey == null || resolvedApiKey.isEmpty) {
    return uri;
  }
  return uri.replace(
    queryParameters: <String, String>{
      ...uri.queryParameters,
      'key': resolvedApiKey,
    },
  );
}

class VertexAiSessionService extends BaseSessionService {
  VertexAiSessionService({
    String? project,
    String? location,
    String? agentEngineId,
    String? expressModeApiKey,
    VertexAiSessionApiClientFactory? clientFactory,
  }) : _project = project,
       _location = location,
       _agentEngineId = agentEngineId,
       _expressModeApiKey = getExpressModeApiKey(
         project: project,
         location: location,
         expressModeApiKey: expressModeApiKey,
       ),
       _clientFactory = clientFactory ?? _defaultSessionApiClientFactory;

  final String? _project;
  final String? _location;
  final String? _agentEngineId;
  final String? _expressModeApiKey;
  final VertexAiSessionApiClientFactory _clientFactory;

  String? get project => _project;
  String? get location => _location;
  String? get expressModeApiKey => _expressModeApiKey;

  VertexAiSessionApiClient _getApiClient() {
    return _clientFactory(
      project: _project,
      location: _location,
      apiKey: _expressModeApiKey,
    );
  }

  @override
  Future<Session> createSession({
    required String appName,
    required String userId,
    Map<String, Object?>? state,
    String? sessionId,
  }) async {
    if (sessionId != null && sessionId.isNotEmpty) {
      throw ArgumentError(
        'User-provided Session id is not supported for VertexAiSessionService.',
      );
    }

    final String reasoningEngineId = _getReasoningEngineId(appName);
    final VertexAiSessionApiClient apiClient = _getApiClient();
    final Map<String, Object?> config = <String, Object?>{
      if (state != null && state.isNotEmpty) 'session_state': state,
    };

    final Map<String, Object?>? created = await apiClient.createSession(
      reasoningEngineId: reasoningEngineId,
      userId: userId,
      config: config,
    );
    if (created == null || created.isEmpty) {
      throw StateError('Vertex session create response is empty.');
    }

    final String name = _readStringByKeys(created, const <String>['name']) ?? '';
    final String resolvedId = name.isEmpty ? '' : name.split('/').last;
    final Map<String, Object?> sessionState = _asStringMap(
      created['session_state'],
    );
    final double updateTime =
        _parseTimestamp(
          created['update_time'] ?? created['updateTime'],
        ) ??
        (DateTime.now().millisecondsSinceEpoch / 1000);

    return Session(
      id: resolvedId,
      appName: appName,
      userId: userId,
      state: sessionState,
      events: <Event>[],
      lastUpdateTime: updateTime,
    );
  }

  @override
  Future<Session?> getSession({
    required String appName,
    required String userId,
    required String sessionId,
    GetSessionConfig? config,
  }) async {
    final String reasoningEngineId = _getReasoningEngineId(appName);
    final VertexAiSessionApiClient apiClient = _getApiClient();

    final Future<Map<String, Object?>?> sessionFuture = apiClient.getSession(
      reasoningEngineId: reasoningEngineId,
      sessionId: sessionId,
    );
    final Future<List<Map<String, Object?>>> eventsFuture = () async {
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
      final double? afterTimestamp =
          (config != null && (config.numRecentEvents == null))
          ? config.afterTimestamp
          : null;
      await for (final Map<String, Object?> row in apiClient.listEvents(
        reasoningEngineId: reasoningEngineId,
        sessionId: sessionId,
        afterTimestamp: afterTimestamp,
      )) {
        rows.add(row);
      }
      return rows;
    }();

    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      sessionFuture,
      eventsFuture,
    ]);
    final Map<String, Object?>? sessionJson =
        results[0] as Map<String, Object?>?;
    if (sessionJson == null) {
      return null;
    }

    final String ownerUserId =
        _readStringByKeys(sessionJson, const <String>['user_id', 'userId']) ??
        '';
    if (ownerUserId.isNotEmpty && ownerUserId != userId) {
      throw ArgumentError('Session $sessionId does not belong to user $userId.');
    }

    final List<Map<String, Object?>> eventRows =
        (results[1] as List<Map<String, Object?>>)
            .toList(growable: false);
    final List<Event> events = eventRows
        .map(_eventFromApiJson)
        .where((Event? event) => event != null)
        .cast<Event>()
        .toList(growable: true);

    if (config?.numRecentEvents != null && config!.numRecentEvents! > 0) {
      final int n = config.numRecentEvents!;
      final int start = events.length > n ? events.length - n : 0;
      events
        ..clear()
        ..addAll(events.sublist(start));
    }

    final double updateTime =
        _parseTimestamp(
          sessionJson['update_time'] ?? sessionJson['updateTime'],
        ) ??
        0;

    return Session(
      id: sessionId,
      appName: appName,
      userId: userId,
      state: _asStringMap(sessionJson['session_state']),
      events: events,
      lastUpdateTime: updateTime,
    );
  }

  @override
  Future<ListSessionsResponse> listSessions({
    required String appName,
    String? userId,
  }) async {
    final String reasoningEngineId = _getReasoningEngineId(appName);
    final VertexAiSessionApiClient apiClient = _getApiClient();

    final List<Session> sessions = <Session>[];
    await for (final Map<String, Object?> row in apiClient.listSessions(
      reasoningEngineId: reasoningEngineId,
      userId: userId,
    )) {
      final String name = _readStringByKeys(row, const <String>['name']) ?? '';
      final String id = name.isEmpty ? '' : name.split('/').last;
      final String rowUserId =
          _readStringByKeys(row, const <String>['user_id', 'userId']) ?? '';
      final double updateTime =
          _parseTimestamp(row['update_time'] ?? row['updateTime']) ?? 0;
      sessions.add(
        Session(
          id: id,
          appName: appName,
          userId: rowUserId,
          state: _asStringMap(row['session_state']),
          events: <Event>[],
          lastUpdateTime: updateTime,
        ),
      );
    }

    return ListSessionsResponse(sessions: sessions);
  }

  @override
  Future<void> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    final String reasoningEngineId = _getReasoningEngineId(appName);
    final VertexAiSessionApiClient apiClient = _getApiClient();
    await apiClient.deleteSession(
      reasoningEngineId: reasoningEngineId,
      sessionId: sessionId,
    );
  }

  @override
  Future<Event> appendEvent({required Session session, required Event event}) async {
    await super.appendEvent(session: session, event: event);

    final String reasoningEngineId = _getReasoningEngineId(session.appName);
    final VertexAiSessionApiClient apiClient = _getApiClient();

    final Map<String, Object?> config = <String, Object?>{};
    if (event.content != null) {
      config['content'] = _contentToApiJson(event.content!);
    }
    final Map<String, Object?> actions = <String, Object?>{
      'skip_summarization': event.actions.skipSummarization,
      'state_delta': Map<String, Object?>.from(event.actions.stateDelta),
      'artifact_delta': Map<String, int>.from(event.actions.artifactDelta),
      'transfer_agent': event.actions.transferToAgent,
      'escalate': event.actions.escalate,
      'requested_auth_configs': Map<String, Object>.from(
        event.actions.requestedAuthConfigs,
      ),
      'requested_tool_confirmations': Map<String, Object>.from(
        event.actions.requestedToolConfirmations,
      ),
    };
    actions.removeWhere((String _, Object? value) => value == null);
    config['actions'] = actions;
    if (event.errorCode != null) {
      config['error_code'] = event.errorCode!;
    }
    if (event.errorMessage != null) {
      config['error_message'] = event.errorMessage!;
    }

    final Map<String, Object?> metadata = <String, Object?>{
      'partial': event.partial,
      'turn_complete': event.turnComplete,
      'interrupted': event.interrupted,
      'branch': event.branch,
      'custom_metadata': event.customMetadata,
      'long_running_tool_ids': event.longRunningToolIds?.toList(growable: false),
      'grounding_metadata': event.groundingMetadata,
    };
    metadata.removeWhere((String _, Object? value) => value == null);
    config['event_metadata'] = metadata;

    await apiClient.appendEvent(
      reasoningEngineId: reasoningEngineId,
      sessionId: session.id,
      author: event.author,
      invocationId: event.invocationId,
      timestamp: event.timestamp,
      config: config,
    );
    return event;
  }

  String _getReasoningEngineId(String appName) {
    if (_agentEngineId != null && _agentEngineId.isNotEmpty) {
      return _agentEngineId;
    }
    if (RegExp(r'^\d+$').hasMatch(appName)) {
      return appName;
    }
    final RegExp pattern = RegExp(
      r'^projects\/([a-zA-Z0-9-_]+)\/locations\/([a-zA-Z0-9-_]+)\/reasoningEngines\/(\d+)$',
    );
    final Match? match = pattern.firstMatch(appName);
    if (match == null) {
      throw ArgumentError(
        'App name $appName is not valid. It should either be the full '
        'ReasoningEngine resource name, or the reasoning engine id.',
      );
    }
    return match.group(3)!;
  }
}

Map<String, Object?> _contentToApiJson(Content content) {
  final Map<String, Object?> payload = <String, Object?>{
    'parts': content.parts.map(_partToApiJson).toList(growable: false),
  };
  if (content.role != null) {
    payload['role'] = content.role!;
  }
  return payload;
}

Map<String, Object?> _partToApiJson(Part part) {
  final Map<String, Object?> payload = <String, Object?>{};
  if (part.text != null) {
    payload['text'] = part.text!;
  }
  if (part.thought) {
    payload['thought'] = true;
  }
  if (part.thoughtSignature != null) {
    payload['thought_signature'] = base64Encode(part.thoughtSignature!);
  }
  if (part.functionCall != null) {
    payload['function_call'] = <String, Object?>{
      'name': part.functionCall!.name,
      if (part.functionCall!.args.isNotEmpty)
        'args': Map<String, dynamic>.from(part.functionCall!.args),
      if (part.functionCall!.id != null) 'id': part.functionCall!.id!,
      if (part.functionCall!.partialArgs != null)
        'partial_args': part.functionCall!.partialArgs!
            .map((Map<String, Object?> row) => Map<String, Object?>.from(row))
            .toList(growable: false),
      if (part.functionCall!.willContinue != null)
        'will_continue': part.functionCall!.willContinue!,
    };
  }
  if (part.functionResponse != null) {
    payload['function_response'] = <String, Object?>{
      'name': part.functionResponse!.name,
      if (part.functionResponse!.response.isNotEmpty)
        'response': Map<String, dynamic>.from(part.functionResponse!.response),
      if (part.functionResponse!.id != null) 'id': part.functionResponse!.id!,
    };
  }
  if (part.inlineData != null) {
    payload['inline_data'] = <String, Object?>{
      'mime_type': part.inlineData!.mimeType,
      'data': base64Encode(part.inlineData!.data),
      if (part.inlineData!.displayName != null)
        'display_name': part.inlineData!.displayName!,
    };
  }
  if (part.fileData != null) {
    payload['file_data'] = <String, Object?>{
      'file_uri': part.fileData!.fileUri,
      if (part.fileData!.mimeType != null) 'mime_type': part.fileData!.mimeType!,
      if (part.fileData!.displayName != null)
        'display_name': part.fileData!.displayName!,
    };
  }
  if (part.executableCode != null) {
    payload['executable_code'] = part.executableCode;
  }
  if (part.codeExecutionResult != null) {
    payload['code_execution_result'] = part.codeExecutionResult;
  }
  return payload;
}

Event? _eventFromApiJson(Map<String, Object?> apiEvent) {
  final String invocationId =
      _readStringByKeys(apiEvent, const <String>['invocation_id', 'invocationId']) ??
      '';
  final String author = _readStringByKeys(apiEvent, const <String>['author']) ?? '';
  final String id =
      _extractEventId(apiEvent) ??
      (invocationId.isNotEmpty ? invocationId : Event.newId());
  final double timestamp =
      _parseTimestamp(apiEvent['timestamp']) ??
      (DateTime.now().millisecondsSinceEpoch / 1000);

  final Map<String, Object?> actionsJson = _asStringMap(apiEvent['actions']);
  final Map<String, Object?> metadata = _asStringMap(apiEvent['event_metadata']);
  final Content? content = _contentFromApiJson(_asStringMap(apiEvent['content']));

  return Event(
    id: id,
    invocationId: invocationId,
    author: author,
    timestamp: timestamp,
    content: content,
    actions: EventActions(
      skipSummarization: _asBool(actionsJson['skip_summarization']),
      stateDelta: _asObjectMap(actionsJson['state_delta']),
      artifactDelta: _asIntMap(actionsJson['artifact_delta']),
      transferToAgent: _readStringByKeys(actionsJson, const <String>[
        'transfer_agent',
      ]),
      escalate: _asBool(actionsJson['escalate']),
      requestedAuthConfigs: _asStrictObjectMap(actionsJson['requested_auth_configs']),
      requestedToolConfirmations: _asStrictObjectMap(
        actionsJson['requested_tool_confirmations'],
      ),
    ),
    errorCode: _readStringByKeys(apiEvent, const <String>['error_code', 'errorCode']),
    errorMessage: _readStringByKeys(
      apiEvent,
      const <String>['error_message', 'errorMessage'],
    ),
    partial: _asBool(metadata['partial']),
    turnComplete: _asBool(metadata['turn_complete'] ?? metadata['turnComplete']),
    interrupted: _asBool(metadata['interrupted']),
    branch: _readStringByKeys(metadata, const <String>['branch']),
    customMetadata: _asDynamicMap(metadata['custom_metadata']),
    groundingMetadata: metadata['grounding_metadata'],
    longRunningToolIds: _asStringSet(metadata['long_running_tool_ids']),
  );
}

Content? _contentFromApiJson(Map<String, Object?> json) {
  if (json.isEmpty) {
    return null;
  }
  final List<Object?> partsRaw = _asList(json['parts']);
  final List<Part> parts = <Part>[];
  for (final Object? row in partsRaw) {
    final Map<String, Object?> partJson = _asStringMap(row);
    if (partJson.isEmpty) {
      continue;
    }
    parts.add(
      Part(
        text: _readStringByKeys(partJson, const <String>['text']),
        thought: _asBool(partJson['thought']) ?? false,
        thoughtSignature: _decodeBytes(partJson['thought_signature']),
        functionCall: _functionCallFromJson(_asStringMap(partJson['function_call'])),
        functionResponse: _functionResponseFromJson(
          _asStringMap(partJson['function_response']),
        ),
        inlineData: _inlineDataFromJson(_asStringMap(partJson['inline_data'])),
        fileData: _fileDataFromJson(_asStringMap(partJson['file_data'])),
        executableCode: partJson['executable_code'],
        codeExecutionResult: partJson['code_execution_result'],
      ),
    );
  }
  return Content(
    role: _readStringByKeys(json, const <String>['role']),
    parts: parts,
  );
}

FunctionCall? _functionCallFromJson(Map<String, Object?> json) {
  if (json.isEmpty) {
    return null;
  }
  final String? name = _readStringByKeys(json, const <String>['name']);
  if (name == null || name.isEmpty) {
    return null;
  }
  return FunctionCall(
    name: name,
    args: _asDynamicMap(json['args']),
    id: _readStringByKeys(json, const <String>['id']),
    partialArgs: _asList(json['partial_args'])
        .map(_asStringMap)
        .where((Map<String, Object?> row) => row.isNotEmpty)
        .toList(growable: false),
    willContinue: _asBool(json['will_continue']),
  );
}

FunctionResponse? _functionResponseFromJson(Map<String, Object?> json) {
  if (json.isEmpty) {
    return null;
  }
  final String? name = _readStringByKeys(json, const <String>['name']);
  if (name == null || name.isEmpty) {
    return null;
  }
  return FunctionResponse(
    name: name,
    response: _asDynamicMap(json['response']),
    id: _readStringByKeys(json, const <String>['id']),
  );
}

InlineData? _inlineDataFromJson(Map<String, Object?> json) {
  if (json.isEmpty) {
    return null;
  }
  final String? mimeType =
      _readStringByKeys(json, const <String>['mime_type', 'mimeType']);
  if (mimeType == null || mimeType.isEmpty) {
    return null;
  }
  final List<int>? data = _decodeBytes(json['data']);
  if (data == null) {
    return null;
  }
  return InlineData(
    mimeType: mimeType,
    data: data,
    displayName: _readStringByKeys(json, const <String>[
      'display_name',
      'displayName',
    ]),
  );
}

FileData? _fileDataFromJson(Map<String, Object?> json) {
  if (json.isEmpty) {
    return null;
  }
  final String? fileUri =
      _readStringByKeys(json, const <String>['file_uri', 'fileUri']);
  if (fileUri == null || fileUri.isEmpty) {
    return null;
  }
  return FileData(
    fileUri: fileUri,
    mimeType: _readStringByKeys(json, const <String>['mime_type', 'mimeType']),
    displayName: _readStringByKeys(json, const <String>[
      'display_name',
      'displayName',
    ]),
  );
}

Map<String, Object?>? _extractSessionFromCreateResponse(
  Map<String, Object?> response,
) {
  final Map<String, Object?> direct = _asStringMap(response);
  if (_readStringByKeys(direct, const <String>['name']) != null &&
      (direct.containsKey('session_state') || direct.containsKey('update_time'))) {
    return direct;
  }
  final Map<String, Object?> nestedResponse = _asStringMap(response['response']);
  if (nestedResponse.isNotEmpty) {
    return nestedResponse;
  }
  return direct.isEmpty ? null : direct;
}

String? _extractEventId(Map<String, Object?> apiEvent) {
  final String? id = _readStringByKeys(apiEvent, const <String>['id']);
  if (id != null && id.isNotEmpty) {
    return id;
  }
  final String? name = _readStringByKeys(apiEvent, const <String>['name']);
  if (name == null || name.isEmpty) {
    return null;
  }
  return name.split('/').last;
}

Map<String, Object?> _asStringMap(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, Object?>{};
}

Map<String, dynamic> _asDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map<String, Object?>) {
    return value.map((String key, Object? item) => MapEntry(key, item));
  }
  if (value is Map) {
    return value.map((Object? key, Object? item) => MapEntry('$key', item));
  }
  return <String, dynamic>{};
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return List<Object?>.from(value);
  }
  return const <Object?>[];
}

Map<String, Object?> _asObjectMap(Object? value) {
  final Map<String, Object?> mapped = _asStringMap(value);
  return Map<String, Object?>.from(mapped);
}

Map<String, int> _asIntMap(Object? value) {
  final Map<String, Object?> mapped = _asStringMap(value);
  final Map<String, int> result = <String, int>{};
  mapped.forEach((String key, Object? row) {
    if (row is num) {
      result[key] = row.toInt();
    }
  });
  return result;
}

Map<String, Object> _asStrictObjectMap(Object? value) {
  final Map<String, Object?> mapped = _asStringMap(value);
  final Map<String, Object> out = <String, Object>{};
  mapped.forEach((String key, Object? row) {
    if (row != null) {
      out[key] = row;
    }
  });
  return out;
}

Set<String>? _asStringSet(Object? value) {
  if (value is! List) {
    return null;
  }
  final Set<String> out = <String>{};
  for (final Object? item in value) {
    if (item == null) {
      continue;
    }
    out.add('$item');
  }
  return out.isEmpty ? null : out;
}

String? _readStringByKeys(Map<String, Object?> json, List<String> keys) {
  for (final String key in keys) {
    final Object? value = json[key];
    if (value == null) {
      continue;
    }
    final String text = '$value';
    if (text.isNotEmpty) {
      return text;
    }
  }
  return null;
}

bool? _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    if (value.toLowerCase() == 'true') {
      return true;
    }
    if (value.toLowerCase() == 'false') {
      return false;
    }
  }
  return null;
}

double? _parseTimestamp(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String && value.isNotEmpty) {
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toUtc().millisecondsSinceEpoch / 1000;
    }
    return double.tryParse(value);
  }
  return null;
}

List<int>? _decodeBytes(Object? value) {
  if (value is String && value.isNotEmpty) {
    try {
      return base64Decode(value);
    } on FormatException {
      return null;
    }
  }
  if (value is List<int>) {
    return List<int>.from(value);
  }
  if (value is List) {
    return value.map((Object? row) => (row as num).toInt()).toList();
  }
  return null;
}
