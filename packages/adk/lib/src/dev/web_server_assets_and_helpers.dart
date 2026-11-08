part of 'web_server.dart';

Future<bool> _handleWebUi(
  HttpRequest request,
  _AdkDevWebContext context,
  String routedPath,
) async {
  if (!context.enableWebUi || context.webAssetsDir == null) {
    return false;
  }

  if (request.method != 'GET' && request.method != 'HEAD') {
    return false;
  }

  final String prefix = context.urlPrefix ?? '';

  if (routedPath == '/') {
    await _redirect(request, context, '$prefix/dev-ui/');
    return true;
  }

  if (routedPath == '/dev-ui/assets/config/runtime-config.json') {
    final Map<String, Object?> config = <String, Object?>{
      'backendUrl': context.urlPrefix ?? '',
      'telemetry': readTelemetryConsent(),
    };
    if (context.logoText != null && context.logoText!.isNotEmpty) {
      config['logo'] = <String, Object?>{
        'text': context.logoText,
        'imageUrl': context.logoImageUrl,
      };
    }
    if (context.avatarConfig != null && context.avatarConfig!.isNotEmpty) {
      config['avatarConfig'] = context.avatarConfig;
    }
    request.response.headers.set('Cache-Control', 'no-store');
    await _writeJson(
      request,
      context,
      payload: config,
    );
    return true;
  }

  if (routedPath == '/dev-ui/config') {
    await _writeJson(
      request,
      context,
      payload: <String, Object?>{
        'logo_text': context.logoText,
        'logo_image_url': context.logoImageUrl,
        if (context.avatarConfig != null) 'avatar_config': context.avatarConfig,
      },
    );
    return true;
  }

  if (routedPath == '/dev-ui') {
    await _redirect(request, context, '$prefix/dev-ui/');
    return true;
  }

  if (!routedPath.startsWith('/dev-ui/')) {
    return false;
  }

  final String relativeRaw = routedPath.substring('/dev-ui/'.length);
  final String relative = Uri.decodeComponent(relativeRaw);

  if (relative.contains('..')) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Invalid path.',
    );
    return true;
  }

  final File file = relative.isEmpty
      ? File('${context.webAssetsDir!.path}${Platform.pathSeparator}index.html')
      : File('${context.webAssetsDir!.path}${Platform.pathSeparator}$relative');

  if (await file.exists()) {
    await _writeFile(request, context, file);
    return true;
  }

  final bool isLikelySpaRoute = !relative.contains('.');
  if (isLikelySpaRoute) {
    final File index = File(
      '${context.webAssetsDir!.path}${Platform.pathSeparator}index.html',
    );
    if (await index.exists()) {
      await _writeFile(request, context, index);
      return true;
    }
  }

  await _writeError(
    request,
    context,
    statusCode: HttpStatus.notFound,
    message: 'Not found.',
  );
  return true;
}

Future<void> _redirect(
  HttpRequest request,
  _AdkDevWebContext context,
  String location,
) async {
  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);
  response.statusCode = HttpStatus.movedTemporarily;
  response.headers.set(HttpHeaders.locationHeader, location);
  await response.close();
}

Future<void> _writeFile(
  HttpRequest request,
  _AdkDevWebContext context,
  File file,
) async {
  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);

  final ContentType contentType = _contentTypeForFile(file.path);

  response.statusCode = HttpStatus.ok;
  response.headers.contentType = contentType;
  await response.addStream(file.openRead());
  await response.close();
}

Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
  if (request.method == 'GET' || request.method == 'HEAD') {
    return <String, dynamic>{};
  }

  final String body = await utf8.decoder.bind(request).join();
  if (body.trim().isEmpty) {
    return <String, dynamic>{};
  }

  final Object? decoded = jsonDecode(body);
  if (decoded is Map) {
    return _toDynamicMap(decoded);
  }

  throw const FormatException('Request JSON body must be an object.');
}

Future<void> _writeError(
  HttpRequest request,
  _AdkDevWebContext context, {
  required int statusCode,
  required String message,
  String? detail,
}) async {
  await _writeJson(
    request,
    context,
    statusCode: statusCode,
    payload: <String, Object?>{
      'error': message,
      'detail': detail ?? message,
    },
  );
}

Future<void> _writeJson(
  HttpRequest request,
  _AdkDevWebContext context, {
  required Object payload,
  int statusCode = HttpStatus.ok,
}) async {
  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(payload));
  await response.close();
}

Future<void> _writeText(
  HttpRequest request,
  _AdkDevWebContext context, {
  required String text,
  int statusCode = HttpStatus.ok,
  bool includeCorsHeaders = true,
}) async {
  final HttpResponse response = request.response;
  if (includeCorsHeaders) {
    _setCorsHeaders(request, response, context);
  }
  response.statusCode = statusCode;
  response.headers.contentType = ContentType.text;
  response.write(text);
  await response.close();
}

void _setCorsHeaders(
  HttpRequest request,
  HttpResponse response,
  _AdkDevWebContext context,
) {
  if (context.allowOrigins.contains('*')) {
    response.headers.set('Access-Control-Allow-Origin', '*');
  } else {
    final String? origin = _firstHeaderValue(request, 'origin');
    if (origin != null && _originAllowed(origin, context.allowOrigins)) {
      response.headers.set('Access-Control-Allow-Origin', origin);
      response.headers.set('Vary', 'Origin');
    }
  }

  response.headers.set(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization',
  );
  response.headers.set(
    'Access-Control-Allow-Methods',
    'GET, POST, PATCH, DELETE, OPTIONS',
  );
}

bool _originAllowed(String origin, List<String> allowOrigins) {
  for (final String allowed in allowOrigins) {
    if (allowed == '*') {
      return true;
    }
    if (allowed == origin) {
      return true;
    }
    if (allowed.startsWith('regex:')) {
      final String pattern = allowed.substring('regex:'.length);
      if (pattern.isEmpty) {
        continue;
      }
      final RegExp regex = RegExp(pattern);
      final Match? match = regex.matchAsPrefix(origin);
      if (match != null && match.end == origin.length) {
        return true;
      }
    }
  }
  return false;
}

const Set<String> _safeHttpMethods = <String>{'GET', 'HEAD', 'OPTIONS'};

bool _shouldBlockCrossOriginRequest(
  HttpRequest request,
  _AdkDevWebContext context,
) {
  if (_safeHttpMethods.contains(request.method.toUpperCase())) {
    return false;
  }
  final String? origin = _firstHeaderValue(request, 'origin');
  if (origin == null) {
    return false;
  }
  return !_isRequestOriginAllowed(
    origin: origin,
    request: request,
    allowOrigins: context.allowOrigins,
    serverHost: context.serverHost,
  );
}

bool _isRequestOriginAllowed({
  required String origin,
  required HttpRequest request,
  required List<String> allowOrigins,
  String? serverHost,
}) {
  if (allowOrigins.isNotEmpty && _originAllowed(origin, allowOrigins)) {
    return true;
  }

  // DNS-rebinding guard: if the server is bound to a loopback address and no
  // explicit allow-origins list is configured, only permit origins whose
  // host is also loopback. This mirrors the protection used by the MCP
  // go-sdk SSEHandler and prevents an external page from DNS-rebinding to
  // 127.0.0.1 and then sending requests whose Origin/Host headers it
  // controls (e.g. Origin: http://evil.com while physically connecting to
  // the loopback-bound dev server).
  if (allowOrigins.isEmpty &&
      serverHost != null &&
      _isLoopbackAddress(serverHost)) {
    final String originHost = Uri.tryParse(origin)?.host ?? '';
    if (!_isLoopbackAddress(originHost)) {
      return false;
    }
  }

  final String? requestOrigin = _getRequestOrigin(request);
  return requestOrigin != null && requestOrigin == origin;
}

// Loopback hostnames recognized in addition to loopback IP literals.
const Set<String> _loopbackHostnames = <String>{'localhost'};

// Returns true if [host] (with or without a port, optionally
// IPv6-bracketed) refers to a loopback address.
//
// Handles the forms produced by browsers and Dart's HTTP stack:
//   - Plain IPv4:          "127.0.0.1"
//   - IPv4 with port:      "127.0.0.1:8000"
//   - Bracketed IPv6:      "[::1]"
//   - Bracketed IPv6+port: "[::1]:8000"
//   - Plain IPv6:          "::1"
//   - Hostname:            "localhost"
//   - Hostname with port:  "localhost:8000"
bool _isLoopbackAddress(String host) {
  String bare = host;
  if (bare.startsWith('[')) {
    final int end = bare.indexOf(']');
    if (end != -1) {
      bare = bare.substring(1, end);
    }
  } else if (bare.split(':').length == 2) {
    // IPv4:port or hostname:port (IPv6 without brackets has > 1 colon).
    bare = bare.substring(0, bare.lastIndexOf(':'));
  }
  if (_loopbackHostnames.contains(bare)) {
    return true;
  }
  try {
    final InternetAddress address = InternetAddress(bare);
    return address.isLoopback;
  } on ArgumentError {
    return false;
  }
}

bool _isOriginAllowedForProtectedMutation({
  required String origin,
  required HttpRequest request,
  required List<String> allowOrigins,
}) {
  for (final String allowed in allowOrigins) {
    if (allowed == '*' || allowed.startsWith('regex:')) {
      continue;
    }
    if (allowed == origin) {
      return true;
    }
  }
  final String? requestOrigin = _getRequestOrigin(request);
  return requestOrigin != null && requestOrigin == origin;
}

bool _requestHasForeignBrowserOrigin(
  HttpRequest request,
  _AdkDevWebContext context,
) {
  final String? origin = _firstHeaderValue(request, 'origin');
  if (origin == null) {
    return false;
  }
  return !_isOriginAllowedForProtectedMutation(
    origin: origin,
    request: request,
    allowOrigins: context.allowOrigins,
  );
}

bool _isLocalDevDeployClient(HttpRequest request, _AdkDevWebContext context) {
  if (_requestHasForeignBrowserOrigin(request, context)) {
    return false;
  }
  final String allowRemote =
      (Platform.environment['ADK_ALLOW_REMOTE_AGENT_BUILDER'] ?? '')
          .trim()
          .toLowerCase();
  if (allowRemote == '1' || allowRemote == 'true' || allowRemote == 'yes') {
    return true;
  }
  for (final String header in const <String>[
    'forwarded',
    'x-forwarded-for',
    'x-forwarded-host',
  ]) {
    if (_firstHeaderValue(request, header) != null) {
      return false;
    }
  }
  if (context.serverHost != null && !_isLoopbackAddress(context.serverHost!)) {
    return false;
  }
  final HttpConnectionInfo? connInfo = request.connectionInfo;
  if (connInfo != null && !_isLoopbackAddress(connInfo.remoteAddress.address)) {
    return false;
  }
  return true;
}

String? _getRequestOrigin(HttpRequest request) {
  // Only trust the direct Host header (or requestedUri.authority), not
  // Forwarded or X-Forwarded-Host, which a cross-origin fetch can spoof.
  final String host =
      _firstHeaderValue(request, HttpHeaders.hostHeader) ??
      request.requestedUri.authority;
  if (host.isEmpty) {
    return null;
  }

  final String scheme = request.requestedUri.scheme;
  return '${_normalizeOriginScheme(scheme)}://$host';
}

String? _firstHeaderValue(HttpRequest request, String headerName) {
  final List<String>? values = request.headers[headerName];
  if (values == null || values.isEmpty) {
    return null;
  }
  return values.first.split(',').first.trim();
}

String _normalizeOriginScheme(String scheme) {
  switch (scheme.toLowerCase()) {
    case 'ws':
      return 'http';
    case 'wss':
      return 'https';
    default:
      return scheme.toLowerCase();
  }
}

String _stripOptionalQuotes(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

String? _stripPrefix(String path, String? urlPrefix) {
  if (urlPrefix == null || urlPrefix.isEmpty) {
    return path;
  }
  if (path == urlPrefix) {
    return '/';
  }
  if (path.startsWith('$urlPrefix/')) {
    return path.substring(urlPrefix.length);
  }
  return null;
}

String? _normalizeUrlPrefix(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final String trimmed = value.trim();
  if (!trimmed.startsWith('/')) {
    throw ArgumentError.value(trimmed, 'urlPrefix', 'Must start with "/".');
  }
  if (trimmed == '/') {
    return null;
  }
  if (trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

bool _isTruthy(String? raw) {
  if (raw == null) {
    return false;
  }
  switch (raw.toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'y':
      return true;
    default:
      return false;
  }
}

Map<String, Object?> _sessionToLegacyJson(Session session) {
  return <String, Object?>{
    'id': session.id,
    'appName': session.appName,
    'userId': session.userId,
    'lastUpdateTime': session.lastUpdateTime,
  };
}

Map<String, Object?> _sessionToApiJson(
  Session session, {
  bool includeEvents = false,
}) {
  final Session public = publicSession(session);
  return <String, Object?>{
    'id': public.id,
    'app_name': public.appName,
    'appName': public.appName,
    'user_id': public.userId,
    'userId': public.userId,
    'state': public.state,
    'last_update_time': public.lastUpdateTime,
    'lastUpdateTime': public.lastUpdateTime,
    if (includeEvents)
      'events': public.events
          .map<Map<String, Object?>>(
            (Event event) => _eventToApiJson(
              event,
              appName: public.appName,
              userId: public.userId,
              sessionId: public.id,
            ),
          )
          .toList(growable: false),
  };
}

Map<String, Object?> _eventToApiJson(
  Event event, {
  required String appName,
  required String userId,
  required String sessionId,
}) {
  final Event pubEvent = publicEvent(event);
  final Session shadowSession = Session(
    id: sessionId,
    appName: appName,
    userId: userId,
  );
  final Map<String, Object?> snake = StorageEventV0.fromEvent(
    session: shadowSession,
    event: pubEvent,
  ).toJson();

  final Object? usageMeta = snake['usage_metadata'];
  final Object? customMeta = snake['custom_metadata'];
  Object? cacheCreationTokenCount = snake['cache_creation_token_count'];
  if (cacheCreationTokenCount == null && usageMeta is Map) {
    cacheCreationTokenCount =
        usageMeta['cache_creation_token_count'] ??
        usageMeta['cacheCreationTokenCount'] ??
        usageMeta['cache_creation_tokens'] ??
        usageMeta['cacheCreationTokens'];
  }
  if (cacheCreationTokenCount == null && customMeta is Map) {
    cacheCreationTokenCount =
        customMeta['cache_creation_token_count'] ??
        customMeta['cacheCreationTokenCount'];
  }

  return <String, Object?>{
    ...snake,
    'invocationId': snake['invocation_id'],
    'appName': snake['app_name'],
    'userId': snake['user_id'],
    'sessionId': snake['session_id'],
    'customMetadata': snake['custom_metadata'],
    'usageMetadata': snake['usage_metadata'],
    'cache_creation_token_count': cacheCreationTokenCount,
    'cacheCreationTokenCount': cacheCreationTokenCount,
    'citationMetadata': snake['citation_metadata'],
    'groundingMetadata': snake['grounding_metadata'],
    'turnComplete': snake['turn_complete'],
    'finishReason': snake['finish_reason'],
    'errorCode': snake['error_code'],
    'errorMessage': snake['error_message'],
    'inputTranscription': snake['input_transcription'],
    'outputTranscription': snake['output_transcription'],
    'modelVersion': snake['model_version'],
    'avgLogprobs': snake['avg_logprobs'],
    'logprobsResult': snake['logprobs_result'],
    'cacheMetadata': snake['cache_metadata'],
    'interactionId': snake['interaction_id'],
    'liveSessionId': snake['live_session_id'],
    'liveSessionResumptionUpdate': snake['live_session_resumption_update'],
    'goAway': snake['go_away'],
  };
}

Map<String, Object?> _eventToLegacyJson(Event event) {
  return <String, Object?>{
    'id': event.id,
    'invocationId': event.invocationId,
    'author': event.author,
    'timestamp': event.timestamp,
    'partial': event.partial,
    'content': _contentToLegacyJson(event.content),
    'actions': <String, Object?>{
      'transferToAgent': event.actions.transferToAgent,
      'escalate': event.actions.escalate,
      'skipSummarization': event.actions.skipSummarization,
      'endOfAgent': event.actions.endOfAgent,
      'rewindBeforeInvocationId': event.actions.rewindBeforeInvocationId,
      'stateDelta': event.actions.stateDelta,
      'artifactDelta': event.actions.artifactDelta,
      'renderUiWidgets': event.actions.renderUiWidgets
          .map((widget) => widget.toJson())
          .toList(growable: false),
    },
  };
}

Map<String, Object?>? _contentToLegacyJson(Content? content) {
  if (content == null) {
    return null;
  }

  return <String, Object?>{
    'role': content.role,
    'parts': content.parts
        .map<Map<String, Object?>>((Part part) {
          return <String, Object?>{
            'text': part.text,
            'thought': part.thought,
            'functionCall': part.functionCall == null
                ? null
                : <String, Object?>{
                    'name': part.functionCall!.name,
                    'args': part.functionCall!.args,
                    'id': part.functionCall!.id,
                  },
            'functionResponse': part.functionResponse == null
                ? null
                : <String, Object?>{
                    'name': part.functionResponse!.name,
                    'response': part.functionResponse!.response,
                    'id': part.functionResponse!.id,
                  },
          };
        })
        .toList(growable: false),
  };
}

String _extractReplyText(List<Event> events, {required String fallbackAuthor}) {
  for (int i = events.length - 1; i >= 0; i -= 1) {
    final Event event = events[i];
    if (event.author == 'user') {
      continue;
    }
    if (event.author != fallbackAuthor && fallbackAuthor.isNotEmpty) {
      // Keep best effort with arbitrary loaded agents.
    }
    final String text = _textFromContent(event.content);
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}

String _textFromContent(Content? content) {
  if (content == null) {
    return '';
  }

  final List<String> chunks = <String>[];
  for (final Part part in content.parts) {
    final String? text = part.text;
    if (text != null && text.trim().isNotEmpty) {
      chunks.add(text.trim());
    }
  }
  return chunks.join('\n');
}

Map<String, Object?> _artifactVersionToJson(ArtifactVersion value) {
  return <String, Object?>{
    'version': value.version,
    'canonical_uri': value.canonicalUri,
    'canonicalUri': value.canonicalUri,
    'custom_metadata': value.customMetadata,
    'customMetadata': value.customMetadata,
    'create_time': value.createTime,
    'createTime': value.createTime,
    'mime_type': value.mimeType,
    'mimeType': value.mimeType,
  };
}

Map<String, Object?> _partToJson(Part part) {
  final Map<String, Object?> json = <String, Object?>{};
  if (part.text != null) {
    json['text'] = part.text;
  }
  json['thought'] = part.thought;

  if (part.functionCall != null) {
    final Map<String, Object?> payload = <String, Object?>{
      'name': part.functionCall!.name,
      'args': part.functionCall!.args,
      'id': part.functionCall!.id,
    };
    json['function_call'] = payload;
    json['functionCall'] = payload;
  }

  if (part.functionResponse != null) {
    final Map<String, Object?> payload = <String, Object?>{
      'name': part.functionResponse!.name,
      'response': part.functionResponse!.response,
      'id': part.functionResponse!.id,
    };
    json['function_response'] = payload;
    json['functionResponse'] = payload;
  }

  if (part.inlineData != null) {
    final Map<String, Object?> payload = <String, Object?>{
      'mime_type': part.inlineData!.mimeType,
      'mimeType': part.inlineData!.mimeType,
      'data': base64Encode(part.inlineData!.data),
      'display_name': part.inlineData!.displayName,
      'displayName': part.inlineData!.displayName,
    };
    json['inline_data'] = payload;
    json['inlineData'] = payload;
  }

  if (part.fileData != null) {
    final Map<String, Object?> payload = <String, Object?>{
      'file_uri': part.fileData!.fileUri,
      'fileUri': part.fileData!.fileUri,
      'mime_type': part.fileData!.mimeType,
      'mimeType': part.fileData!.mimeType,
      'display_name': part.fileData!.displayName,
      'displayName': part.fileData!.displayName,
    };
    json['file_data'] = payload;
    json['fileData'] = payload;
  }

  return json;
}

Part _partFromJson(Map<String, dynamic> json) {
  final String? text = json['text'] as String?;
  final bool thought = json['thought'] as bool? ?? false;

  final Object? functionCallRaw = json['function_call'] ?? json['functionCall'];
  final Object? functionResponseRaw =
      json['function_response'] ?? json['functionResponse'];
  final Object? inlineDataRaw = json['inline_data'] ?? json['inlineData'];
  final Object? fileDataRaw = json['file_data'] ?? json['fileData'];

  if (functionCallRaw is Map) {
    final Map<String, dynamic> functionCall = _toDynamicMap(functionCallRaw);
    return Part.fromFunctionCall(
      name: '${functionCall['name'] ?? ''}',
      args: _toDynamicMap(
        functionCall['args'] as Object? ?? const <String, Object?>{},
      ),
      id: functionCall['id']?.toString(),
    );
  }

  if (functionResponseRaw is Map) {
    final Map<String, dynamic> functionResponse = _toDynamicMap(
      functionResponseRaw,
    );
    return Part.fromFunctionResponse(
      name: '${functionResponse['name'] ?? ''}',
      response: _toDynamicMap(
        functionResponse['response'] as Object? ?? const <String, Object?>{},
      ),
      id: functionResponse['id']?.toString(),
    );
  }

  if (inlineDataRaw is Map) {
    final Map<String, dynamic> inlineData = _toDynamicMap(inlineDataRaw);
    final Object? dataRaw = inlineData['data'];
    List<int> bytes = <int>[];
    if (dataRaw is String && dataRaw.isNotEmpty) {
      try {
        bytes = base64Decode(dataRaw);
      } on FormatException {
        bytes = utf8.encode(dataRaw);
      }
    } else if (dataRaw is List) {
      bytes = dataRaw.map((Object? item) => (item as num).toInt()).toList();
    }

    return Part.fromInlineData(
      mimeType:
          '${inlineData['mime_type'] ?? inlineData['mimeType'] ?? 'application/octet-stream'}',
      data: bytes,
      displayName: (inlineData['display_name'] ?? inlineData['displayName'])
          ?.toString(),
    );
  }

  if (fileDataRaw is Map) {
    final Map<String, dynamic> fileData = _toDynamicMap(fileDataRaw);
    return Part.fromFileData(
      fileUri: '${fileData['file_uri'] ?? fileData['fileUri'] ?? ''}',
      mimeType: (fileData['mime_type'] ?? fileData['mimeType'])?.toString(),
      displayName: (fileData['display_name'] ?? fileData['displayName'])
          ?.toString(),
    );
  }

  return Part(text: text, thought: thought);
}

Content _contentFromJson(Map<String, dynamic> json) {
  final String? role = (json['role'] as String?)?.trim();
  final Object? partsRaw = json['parts'];
  if (partsRaw is! List) {
    final String text = (json['text'] as String?) ?? '';
    if (text.isNotEmpty) {
      return Content(role: role, parts: <Part>[Part.text(text)]);
    }
    return Content(role: role, parts: <Part>[]);
  }

  final List<Part> parts = <Part>[];
  for (final Object? item in partsRaw) {
    if (item is! Map) {
      continue;
    }
    parts.add(_partFromJson(_toDynamicMap(item)));
  }
  return Content(role: role, parts: parts);
}

List<Event> _readEventsFromPayload(
  Map<String, dynamic> payload, {
  required String appName,
  required String userId,
  required String sessionId,
}) {
  final Object? eventsRaw = payload['events'];
  if (eventsRaw is! List) {
    return const <Event>[];
  }

  final List<Event> events = <Event>[];
  for (final Object? item in eventsRaw) {
    if (item is! Map) {
      continue;
    }
    final Map<String, dynamic> map = _toDynamicMap(item);
    final Map<String, Object?> enriched = <String, Object?>{
      ...map,
      'app_name': appName,
      'user_id': userId,
      'session_id': sessionId,
      'invocation_id':
          map['invocation_id'] ??
          map['invocationId'] ??
          'inv_${DateTime.now().microsecondsSinceEpoch}',
      'author': map['author'] ?? 'user',
    };
    events.add(StorageEventV0.fromJson(enriched).toEvent());
  }
  return events;
}

_RunRequest _parseRunRequest(
  Map<String, dynamic> payload,
  _AdkDevWebContext context,
) {
  final String appName = _readString(payload, const <String>[
    'app_name',
    'appName',
  ], fallback: context.defaultAppName);
  final String userId = _readString(payload, const <String>[
    'user_id',
    'userId',
  ], fallback: context.defaultUserId);
  final String sessionId = _readString(payload, const <String>[
    'session_id',
    'sessionId',
  ], required: true);
  final String validatedUserId = _validatePathIdentifier(userId, 'user_id');
  final String validatedSessionId = _validatePathIdentifier(
    sessionId,
    'session_id',
  );

  final Object? messageRaw = payload['new_message'] ?? payload['newMessage'];
  Content? newMessage;
  if (messageRaw is Map) {
    newMessage = _contentFromJson(_toDynamicMap(messageRaw));
  } else if (messageRaw is String && messageRaw.trim().isNotEmpty) {
    newMessage = Content.userText(messageRaw.trim());
  } else {
    final String text = _readString(payload, const <String>[
      'text',
    ], fallback: '');
    if (text.trim().isNotEmpty) {
      newMessage = Content.userText(text.trim());
    }
  }

  return _RunRequest(
    appName: appName,
    userId: validatedUserId,
    sessionId: validatedSessionId,
    newMessage: newMessage,
    streaming: payload['streaming'] as bool? ?? false,
    autoCreateSession: _readOptionalBool(payload, const <String>[
      'auto_create_session',
      'autoCreateSession',
    ]),
    stateDelta: _readObjectMap(payload, const <String>[
      'state_delta',
      'stateDelta',
    ]),
    invocationId: _nullableString(payload, const <String>[
      'invocation_id',
      'invocationId',
    ]),
  );
}

bool? _readOptionalBool(Map<String, dynamic> payload, List<String> keys) {
  for (final String key in keys) {
    if (!payload.containsKey(key)) {
      continue;
    }
    final Object? raw = payload[key];
    if (raw == null) {
      return null;
    }
    if (raw is bool) {
      return raw;
    }
    if (raw is num) {
      return raw != 0;
    }
    if (raw is String) {
      final String normalized = raw.trim().toLowerCase();
      switch (normalized) {
        case '1':
        case 'true':
        case 'yes':
        case 'y':
          return true;
        case '0':
        case 'false':
        case 'no':
        case 'n':
          return false;
      }
    }
  }
  return null;
}

String _readRequiredQuery(HttpRequest request, String key) {
  final String? raw = request.uri.queryParameters[key];
  if (raw == null || raw.trim().isEmpty) {
    throw FormatException('Missing required query parameter: $key');
  }
  return raw.trim();
}

String _validatePathIdentifier(String value, String fieldName) {
  final String trimmed = value.trim();
  if (trimmed == '.' ||
      trimmed == '..' ||
      trimmed.contains('/') ||
      trimmed.contains(r'\')) {
    throw FormatException('Invalid $fieldName: path traversal is not allowed.');
  }
  return trimmed;
}

bool? _readOptionalBoolQuery(HttpRequest request, String key) {
  final String? raw = request.uri.queryParameters[key];
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  final String normalized = raw.trim().toLowerCase();
  switch (normalized) {
    case '1':
    case 'true':
    case 'yes':
    case 'y':
      return true;
    case '0':
    case 'false':
    case 'no':
    case 'n':
      return false;
    default:
      throw FormatException('Invalid boolean query parameter for $key: $raw');
  }
}

List<String>? _parseModalities(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  final List<String> values = raw
      .split(',')
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);
  return values.isEmpty ? null : values;
}

void _validateLiveContentMap(Map<String, dynamic> contentMap) {
  final Object? role = contentMap['role'];
  if (role != null && role is! String) {
    throw const FormatException('Invalid live request: content.role must be a string.');
  }
  final Object? text = contentMap['text'];
  if (text != null && text is! String) {
    throw const FormatException('Invalid live request: content.text must be a string.');
  }
  final Object? partsRaw = contentMap['parts'];
  if (partsRaw != null) {
    if (partsRaw is! List) {
      throw const FormatException('Invalid live request: content.parts must be a list.');
    }
    for (final Object? item in partsRaw) {
      if (item is! Map) {
        throw const FormatException('Invalid live request: each content part must be an object.');
      }
      final Map<String, dynamic> partMap = _toDynamicMap(item);
      if (partMap['text'] != null && partMap['text'] is! String) {
        throw const FormatException('Invalid live request: part.text must be a string.');
      }
      if (partMap['thought'] != null && partMap['thought'] is! bool) {
        throw const FormatException('Invalid live request: part.thought must be a boolean.');
      }
      final Object? inlineData = partMap['inline_data'] ?? partMap['inlineData'];
      if (inlineData != null && inlineData is! Map) {
        throw const FormatException('Invalid live request: inline_data must be an object.');
      }
      final Object? functionCall = partMap['function_call'] ?? partMap['functionCall'];
      if (functionCall != null && functionCall is! Map) {
        throw const FormatException('Invalid live request: function_call must be an object.');
      }
      final Object? functionResponse =
          partMap['function_response'] ?? partMap['functionResponse'];
      if (functionResponse != null && functionResponse is! Map) {
        throw const FormatException('Invalid live request: function_response must be an object.');
      }
    }
  }
}

LiveRequest _liveRequestFromJson(Map<String, dynamic> payload) {
  if (payload.containsKey('close')) {
    final Object? closeVal = payload['close'];
    if (closeVal != null && closeVal is! bool) {
      throw const FormatException('Invalid live request: close must be a boolean.');
    }
    if (closeVal == true) {
      return LiveRequest(close: true);
    }
  }

  final Object? activityStartRaw =
      payload['activity_start'] ?? payload['activityStart'];
  if (activityStartRaw != null) {
    if (activityStartRaw is! bool && activityStartRaw is! Map) {
      throw const FormatException(
        'Invalid live request: activity_start must be a boolean or object.',
      );
    }
    if (activityStartRaw == true || activityStartRaw is Map) {
      return LiveRequest(activityStart: const LiveActivityStart());
    }
  }

  final Object? activityEndRaw =
      payload['activity_end'] ?? payload['activityEnd'];
  if (activityEndRaw != null) {
    if (activityEndRaw is! bool && activityEndRaw is! Map) {
      throw const FormatException(
        'Invalid live request: activity_end must be a boolean or object.',
      );
    }
    if (activityEndRaw == true || activityEndRaw is Map) {
      return LiveRequest(activityEnd: const LiveActivityEnd());
    }
  }

  if (payload.containsKey('content') && payload['content'] != null) {
    final Object? contentRaw = payload['content'];
    if (contentRaw is! Map) {
      throw const FormatException('Invalid live request: content must be an object.');
    }
    final Map<String, dynamic> contentMap = _toDynamicMap(contentRaw);
    _validateLiveContentMap(contentMap);
    return LiveRequest(content: _contentFromJson(contentMap));
  }

  if (payload.containsKey('blob') && payload['blob'] != null) {
    final Object? blobRaw = payload['blob'];
    if (blobRaw is Map) {
      final Map<String, dynamic> blobMap = _toDynamicMap(blobRaw);
      final Object? mimeType = blobMap['mime_type'] ?? blobMap['mimeType'];
      if (mimeType != null && mimeType is! String) {
        throw const FormatException('Invalid live request: blob.mime_type must be a string.');
      }
      final Object? dataRaw = blobMap['data'];
      if (dataRaw is String) {
        base64Decode(dataRaw);
      } else if (dataRaw != null && dataRaw is! List<int>) {
        throw const FormatException('Invalid live request: blob.data must be base64 string or bytes.');
      }
    } else if (blobRaw is! String && blobRaw is! List<int>) {
      throw const FormatException('Invalid live request: blob must be an object, string, or bytes.');
    }
    return LiveRequest(blob: blobRaw);
  }

  return LiveRequest();
}

String _readString(
  Map<String, dynamic> payload,
  List<String> keys, {
  String? fallback,
  bool required = false,
}) {
  for (final String key in keys) {
    final Object? value = payload[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }

  if (fallback != null) {
    return fallback;
  }
  if (required) {
    throw FormatException('Missing required field: ${keys.first}');
  }
  return '';
}

String? _nullableString(Map<String, dynamic> payload, List<String> keys) {
  for (final String key in keys) {
    final Object? value = payload[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

Map<String, Object?>? _readObjectMap(
  Map<String, dynamic> payload,
  List<String> keys,
) {
  for (final String key in keys) {
    final Object? value = payload[key];
    if (value is Map) {
      return value.map(
        (Object? mapKey, Object? mapValue) => MapEntry('$mapKey', mapValue),
      );
    }
  }
  return null;
}

Map<String, dynamic> _toDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((Object? key, Object? val) => MapEntry('$key', val));
  }
  return <String, dynamic>{};
}

Map<String, String> _buildAppNameToDir(
  Directory agentsRoot, {
  required String fallbackAppName,
}) {
  final Map<String, String> result = <String, String>{};

  if (agentsRoot.existsSync()) {
    for (final FileSystemEntity entity in agentsRoot.listSync(
      followLinks: false,
    )) {
      if (entity is! Directory) {
        continue;
      }
      final String name = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments[entity.uri.pathSegments.length - 2]
          : '';
      if (name.isEmpty || name.startsWith('.')) {
        continue;
      }
      result[name] = entity.path;
    }
  }

  if (_isSingleAppRoot(agentsRoot)) {
    result.putIfAbsent(fallbackAppName, () => agentsRoot.path);
  }
  result.putIfAbsent(fallbackAppName, () => agentsRoot.path);

  return result;
}

bool _isSingleAppRoot(Directory root) {
  final String path = root.path;
  final String sep = Platform.pathSeparator;
  return File('$path${sep}adk.json').existsSync() ||
      File('$path${sep}agent.dart').existsSync() ||
      File('$path${sep}root_agent.yaml').existsSync();
}

Future<Directory?> _resolveWebAssetsDir() async {
  final Uri? resolved = await Isolate.resolvePackageUri(
    Uri.parse('package:adk/src/cli/browser/index.html'),
  );
  if (resolved == null || resolved.scheme != 'file') {
    return null;
  }

  final File file = File.fromUri(resolved);
  if (!await file.exists()) {
    return null;
  }
  return file.parent;
}

/// Factory signature for dynamically added web-server plugins.
typedef ExtraPluginFactory =
    BasePlugin Function(String pluginSpec, {required String baseDir});

final Map<String, ExtraPluginFactory> _extraPluginFactories =
    <String, ExtraPluginFactory>{};

/// Registers a plugin factory for a CLI `--extra_plugins` [pluginSpec].
void registerExtraPluginFactory(String pluginSpec, ExtraPluginFactory factory) {
  final String trimmed = pluginSpec.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('pluginSpec must not be empty.');
  }
  _extraPluginFactories[trimmed] = factory;
  _extraPluginFactories[_normalizePluginName(trimmed)] = factory;
}

/// Clears registered extra plugin factories and related test caches.
void clearExtraPluginFactoriesForTest() {
  _extraPluginFactories.clear();
}

List<_ExtraPluginSpec> _parseExtraPluginSpecs(List<String> extraPlugins) {
  final List<_ExtraPluginSpec> specs = <_ExtraPluginSpec>[];
  for (final String raw in extraPlugins) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    specs.add(
      _ExtraPluginSpec(
        raw: trimmed,
        normalizedName: _normalizePluginName(trimmed),
      ),
    );
  }
  return specs;
}

String _normalizePluginName(String raw) {
  final String canonical = raw.toLowerCase().trim();
  final String base = canonical.split('.').last;
  final String left = base.split(':').first.split('=').first.trim();
  if (left.endsWith('contextfilterplugin') || left == 'context_filter_plugin') {
    return 'context_filter_plugin';
  }
  if (left.endsWith('debugloggingplugin') || left == 'debug_logging_plugin') {
    return 'debug_logging_plugin';
  }
  if (left.endsWith('globalinstructionplugin') ||
      left == 'global_instruction_plugin') {
    return 'global_instruction_plugin';
  }
  if (left.endsWith('loggingplugin') || left == 'logging_plugin') {
    return 'logging_plugin';
  }
  if (left.endsWith('multimodaltoolresultsplugin') ||
      left == 'multimodal_tool_results_plugin') {
    return 'multimodal_tool_results_plugin';
  }
  if (left.endsWith('reflectandretrytoolplugin') ||
      left == 'reflect_retry_tool_plugin') {
    return 'reflect_retry_tool_plugin';
  }
  if (left.endsWith('savefilesasartifactsplugin') ||
      left == 'save_files_as_artifacts_plugin') {
    return 'save_files_as_artifacts_plugin';
  }
  return left;
}

Future<List<BasePlugin>> _instantiateExtraPlugins(
  List<_ExtraPluginSpec> specs, {
  required String baseDir,
}) async {
  final List<BasePlugin> plugins = <BasePlugin>[];
  for (final _ExtraPluginSpec spec in specs) {
    BasePlugin? plugin = switch (spec.normalizedName) {
      'context_filter_plugin' => ContextFilterPlugin(),
      'debug_logging_plugin' => DebugLoggingPlugin(
        outputPath: '$baseDir${Platform.pathSeparator}adk_debug.yaml',
      ),
      'global_instruction_plugin' => GlobalInstructionPlugin(),
      'logging_plugin' => LoggingPlugin(),
      'multimodal_tool_results_plugin' => MultimodalToolResultsPlugin(),
      'reflect_retry_tool_plugin' => ReflectAndRetryToolPlugin(),
      'save_files_as_artifacts_plugin' => SaveFilesAsArtifactsPlugin(),
      _ => null,
    };

    if (plugin == null) {
      final ExtraPluginFactory? customFactory =
          _extraPluginFactories[spec.raw] ??
          _extraPluginFactories[spec.normalizedName];
      if (customFactory != null) {
        plugin = customFactory(spec.raw, baseDir: baseDir);
      }
    }

    if (plugin == null) {
      final Object? dynamicPlugin = instantiateRegisteredClassFactory(
        spec.raw,
        kwargs: <String, Object?>{
          'base_dir': baseDir,
          'agents_dir': baseDir,
          'plugin_spec': spec.raw,
        },
      );
      if (dynamicPlugin is BasePlugin) {
        plugin = dynamicPlugin;
      }
    }

    plugin ??= await _instantiatePluginUsingMirrors(spec.raw, baseDir: baseDir);

    if (plugin != null) {
      plugins.add(plugin);
    } else {
      stderr.writeln(
        'Unsupported extra plugin "${spec.raw}"; ignoring. '
        'Provide a registered plugin factory via registerExtraPluginFactory() '
        'or use built-in plugin names, or pass a loadable class spec like '
        '"package:your_pkg/path/to/plugin.dart:YourPlugin".',
      );
    }
  }
  return plugins;
}

Future<BasePlugin?> _instantiatePluginUsingMirrors(
  String pluginSpec, {
  required String baseDir,
}) async {
  return null;
}



void _configureCloudTelemetry({
  required bool traceToCloud,
  required bool otelToCloud,
  required Map<String, String> environment,
}) {
  final bool hasOtelEnv =
      _hasValue(environment, otelExporterOtlpEndpoint) ||
      _hasValue(environment, otelExporterOtlpTracesEndpoint) ||
      _hasValue(environment, otelExporterOtlpMetricsEndpoint) ||
      _hasValue(environment, otelExporterOtlpLogsEndpoint);

  if (!traceToCloud && !otelToCloud && !hasOtelEnv) {
    return;
  }

  final List<OTelHooks> hooks = <OTelHooks>[];
  OTelResource? resource;

  if (traceToCloud || otelToCloud) {
    final String? projectId = environment['GOOGLE_CLOUD_PROJECT'];
    final OTelHooks gcpHooks = getGcpExporters(
      enableCloudTracing: traceToCloud || otelToCloud,
      enableCloudMetrics: false,
      enableCloudLogging: otelToCloud,
      googleAuth: GoogleAuthResult(credentials: Object(), projectId: projectId),
      environment: environment,
    );
    if (gcpHooks.spanProcessors.isNotEmpty) {
      hooks.add(gcpHooks);
      resource = getGcpResource(projectId: projectId, environment: environment);
    }
  }

  maybeSetOtelProviders(
    otelHooksToSetup: hooks,
    otelResource: resource,
    environment: environment,
  );
}

bool _hasValue(Map<String, String> environment, String key) {
  final String? value = environment[key];
  return value != null && value.isNotEmpty;
}

ContentType _contentTypeForFile(String path) {
  final String extension = path.split('.').last.toLowerCase();
  return switch (extension) {
    'html' => ContentType.html,
    'js' => ContentType('application', 'javascript', charset: 'utf-8'),
    'css' => ContentType('text', 'css', charset: 'utf-8'),
    'svg' => ContentType('image', 'svg+xml'),
    'json' => ContentType.json,
    'png' => ContentType('image', 'png'),
    'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
    'webp' => ContentType('image', 'webp'),
    'woff2' => ContentType('font', 'woff2'),
    _ => ContentType.binary,
  };
}

/// Internal testing helper to parse a node status.
NodeStatus? parseNodeStatusForTesting(Object? value) => _parseNodeStatus(value);

/// Internal testing helper to parse a query boolean parameter.
bool? parseQueryBoolForTesting(Map<String, dynamic> payload, List<String> keys) =>
    _readOptionalBool(payload, keys);

/// Internal testing helper to check if a string is truthy.
bool isTruthyForTesting(String? raw) => _isTruthy(raw);

/// Internal testing helper to strip optional enclosing quotes.
String stripOptionalQuotesForTesting(String value) =>
    _stripOptionalQuotes(value);

/// Internal testing helper to normalize a URL prefix string.
String? normalizeUrlPrefixForTesting(String? prefix) =>
    _normalizeUrlPrefix(prefix);

/// Internal testing helper to determine the content type of a file.
ContentType contentTypeForFileTesting(String filename) =>
    _contentTypeForFile(filename);

/// Internal testing helper to resolve an evaluation metric from its name.
EvalMetric? evalMetricFromNameTesting(String raw) =>
    _evalMetricFromName(raw);

/// Internal testing helper to parse run eval metrics from a payload.
List<EvalMetric> parseRunEvalMetricsTesting(Map<String, dynamic> payload) =>
    _parseRunEvalMetrics(payload);

/// Internal testing helper to parse a content part from a JSON map.
Part parseContentPartTesting(Map<String, dynamic> json) =>
    _partFromJson(json);

/// Internal testing helper to convert a content part to JSON.
Map<String, Object?> contentPartToJsonTesting(Part part) =>
    _partToJson(part);

/// Internal testing helper to convert an A2A part to JSON.
Map<String, Object?> a2aPartToJsonTesting(A2aPart part) =>
    _a2aPartToJson(part);

/// Internal testing helper to parse an A2A part from JSON.
A2aPart a2aPartFromJsonTesting(Map<String, dynamic> json) =>
    _a2aPartFromJson(json);

/// Internal testing helper to check if an origin matches an allowlist.
bool originAllowedTesting(String origin, List<String> allowOrigins) =>
    _originAllowed(origin, allowOrigins);

/// Internal testing helper to resolve evaluation managers from storage URI.
Object? resolveEvalManagersTesting({
  required String baseDir,
  required String? evalStorageUri,
}) => _createEvalManagersFromOptions(baseDir: baseDir, evalStorageUri: evalStorageUri);

/// Internal testing helper to check if a host string represents a loopback address.
bool isLoopbackAddressTesting(String host) => _isLoopbackAddress(host);

/// Internal testing helper to parse a live request from JSON payload.
LiveRequest liveRequestFromJsonTesting(Map<String, dynamic> payload) =>
    _liveRequestFromJson(payload);

/// Internal testing helper to parse content from JSON payload.
Content contentFromJsonTesting(Map<String, dynamic> json) =>
    _contentFromJson(json);

/// Internal testing helper to generate an A2A fallback message for a task.
Map<String, Object?> a2aFallbackMessageTesting(Map<String, Object?> task) =>
    _a2aFallbackMessage(task);

/// Internal testing helper to parse A2aTaskState from wire string.
A2aTaskState a2aTaskStateFromWireTesting(String raw) =>
    _a2aTaskStateFromWire(raw);

/// Internal testing helper to convert A2aTaskState to wire string.
String a2aTaskStateToWireTesting(A2aTaskState state) =>
    _a2aTaskStateToWire(state);

/// Internal testing helper to construct an A2A JSON-RPC error map.
Map<String, Object?> a2aJsonRpcErrorTesting({
  required Object? id,
  required int code,
  required String message,
  Object? data,
}) => _a2aJsonRpcError(id: id, code: code, message: message, data: data);

/// Internal testing helper to convert a map or dynamic object to object map.
Map<String, Object?> toObjectMapTesting(Object? value) => _toObjectMap(value);

/// Internal testing helper to parse node statuses from agent state map.
Map<String, NodeStatus> nodeStatusesFromAgentStateTesting(
  Map<String, Object?>? state,
) => _nodeStatusesFromAgentState(state);

/// Internal testing helper to split node path string.
List<String> splitNodePathTesting(String? path) => _splitNodePath(path);

/// Internal testing helper to join node path segments.
String joinNodePathTesting(String base, String child) =>
    _joinNodePath(base, child);

/// Internal testing helper to extract function declarations from tool union.
Future<List<FunctionDeclaration>> declarationsFromToolUnionTesting(
  Object toolUnion,
) => _extractFunctionDeclarations(toolUnion);

/// Internal testing helper to read string with fallback and required flag.
String readStringTesting(
  Map<String, dynamic> payload,
  List<String> keys, {
  String? fallback,
  bool required = false,
}) => _readString(payload, keys, fallback: fallback, required: required);

/// Internal testing helper to resolve A2A push URL from push config.
String? resolveA2aPushUrlTesting(Map<String, Object?> pushConfig) =>
    _resolveA2aPushUrl(pushConfig);

/// Internal testing helper to resolve A2A push headers from push config.
Map<String, String> resolveA2aPushHeadersTesting(
  Map<String, Object?> pushConfig,
) => _resolveA2aPushHeaders(pushConfig);

/// Internal testing helper to resolve A2A push authorization from push config.
String? resolveA2aPushAuthorizationTesting(
  Map<String, Object?> pushConfig,
) => _resolveA2aPushAuthorization(pushConfig);

/// Internal testing helper to parse integer with bounds.
int parseA2aIntTesting(
  Object? value, {
  required int fallback,
  required int min,
  int? max,
}) => _readPositiveInt(value, fallback: fallback, min: min, max: max);

/// Internal testing helper to extract A2A scoped app name from path.
String? extractA2aScopedAppNameTesting(String routedPath) =>
    _extractA2aScopedAppName(routedPath);

/// Internal testing helper to normalize A2A RPC method name.
String normalizeA2aRpcMethodTesting(String raw) =>
    _normalizeA2aRpcMethod(raw);

/// Internal testing helper to normalize origin scheme string.
String normalizeOriginSchemeTesting(String raw) =>
    _normalizeOriginScheme(raw);

/// Internal testing helper for optional boolean query param parsing.
bool? readOptionalBoolQueryForTesting(HttpRequest request, String key) =>
    _readOptionalBoolQuery(request, key);

/// Internal testing helper for required query param parsing.
String readRequiredQueryForTesting(HttpRequest request, String key) =>
    _readRequiredQuery(request, key);

/// Internal testing helper for path identifier validation.
String validatePathIdentifierForTesting(String value, String fieldName) =>
    _validatePathIdentifier(value, fieldName);

/// Internal testing helper for dynamic map conversion.
Map<String, dynamic> toDynamicMapForTesting(Object? value) =>
    _toDynamicMap(value);

/// Internal testing helper to resolve eval storage directory.
String resolveEvalLocalBaseDirForTesting({
  required String baseDir,
  required String evalStorageUri,
}) => _resolveEvalLocalBaseDir(baseDir: baseDir, evalStorageUri: evalStorageUri);

/// Internal testing helper to format an A2A message part to text payload.
Map<String, Object?> a2aPartToJsonForTesting(A2aPart part) =>
    _a2aPartToJson(part);

/// Internal testing helper to format an A2A event to JSON.
Map<String, Object?> a2aEventToJsonForTesting(A2aEvent event) =>
    _a2aEventToJson(event);

/// Internal testing helper for tool function name inference.
String inferFunctionToolNameForTesting(Function function) =>
    _inferFunctionToolName(function);

/// Internal testing helper to find ComputerUseToolset.
ComputerUseToolset? findComputerUseToolsetForTesting(BaseAgent agent) =>
    _findComputerUseToolset(agent);

/// Internal testing helper to collect workflow graph targets.
Map<String, BaseAgent> collectWorkflowGraphTargetsForTesting(
  BaseAgent agent, {
  required String currentPath,
}) => _collectWorkflowGraphTargets(agent, currentPath: currentPath);

/// Internal testing helper to find graph target from path.
BaseAgent? findGraphTargetFromForTesting(
  BaseAgent agent,
  List<String> path,
) => _findGraphTargetFrom(agent, path);

/// Internal testing helper to extract eval case IDs from payload.
List<String> parseRunEvalCaseIdsForTesting(Map<String, dynamic> payload) =>
    _parseRunEvalCaseIds(payload);

/// Internal testing helper to extract eval metrics from payload.
List<EvalMetric> parseRunEvalMetricsForTesting(Map<String, dynamic> payload) =>
    _parseRunEvalMetrics(payload);

/// Internal testing helper to check if environment has key.
bool hasValueForTesting(Map<String, String> environment, String key) =>
    _hasValue(environment, key);

/// Internal testing helper to test mirror plugin instantiation.
Future<BasePlugin?> instantiatePluginUsingMirrorsForTesting(
  String spec, {
  required String baseDir,
}) => _instantiatePluginUsingMirrors(spec, baseDir: baseDir);

/// Internal testing helper for building live highlights.
Set<(String, String)> buildLiveHighlightsForTesting(Event event) =>
    _extractLiveHighlights(event);

/// Internal testing helper for parsing run request.
dynamic parseRunRequestForTesting(
  Map<String, dynamic> payload,
  dynamic context,
) => _parseRunRequest(payload, context as _AdkDevWebContext);

/// Internal testing helper for converting value to double.
double asDoubleForTesting(dynamic context, Object? value) =>
    (context as _AdkDevWebContext)._asDouble(value);

/// Internal testing helper for getting request origin.
String? getRequestOriginForTesting(HttpRequest request) =>
    _getRequestOrigin(request);

/// Internal testing helper for finding graph target.
BaseAgent? findGraphTargetForTesting(BaseAgent rootAgent, List<String> nodePath) =>
    _findGraphTarget(rootAgent, nodePath);

/// Internal testing helper to create an [_AdkDevWebContext].
Future<dynamic> createAdkDevWebContextForTesting({
  required DevAgentRuntime runtime,
  required DevProjectConfig project,
  String agentsDir = '.',
  bool enableWebUi = true,
  String? logoText,
  String? logoImageUrl,
  bool a2a = true,
  List<String> allowOrigins = const <String>[],
  String? evalStorageUri,
  Map<String, String>? environment,
  List<String> triggerSources = const <String>[],
  List<String> extraPlugins = const <String>[],
  bool reload = false,
  bool reloadAgents = false,
  TriggerRouter? triggerRouter,
  String? serverHost,
}) async {
  final _AdkDevWebContext context = await _AdkDevWebContext.create(
    runtime: runtime,
    project: project,
    agentsDir: agentsDir,
    sessionServiceUri: null,
    artifactServiceUri: null,
    memoryServiceUri: null,
    evalStorageUri: evalStorageUri,
    useLocalStorage: true,
    allowOrigins: allowOrigins,
    urlPrefix: '',
    autoCreateSession: true,
    enableWebUi: enableWebUi,
    logoText: logoText,
    logoImageUrl: logoImageUrl,
    reload: reload,
    reloadAgents: reloadAgents,
    traceToCloud: false,
    otelToCloud: false,
    a2a: a2a,
    extraPlugins: extraPlugins,
    triggerSources: triggerSources,
    customTriggerRouter: triggerRouter,
    environment: environment,
  );
  if (serverHost != null) {
    context.serverHost = serverHost;
  }
  return context;
}

/// Internal testing helper for trigger route handling.
@visibleForTesting
Future<void> handleTriggerRouteForTesting(
  HttpRequest request,
  dynamic context, {
  required String appName,
  required String triggerSource,
}) {
  final _AdkDevWebContext devContext = context as _AdkDevWebContext;
  return _handleTriggerRoute(
    request,
    devContext,
    triggerRouter: devContext.triggerRouter!,
    appName: appName,
    triggerSource: triggerSource,
  );
}


// Parsed request payload for the `/run` endpoint.
class _RunRequest {
  // Creates a normalized run request payload.
  _RunRequest({
    required this.appName,
    required this.userId,
    required this.sessionId,
    required this.newMessage,
    required this.streaming,
    required this.autoCreateSession,
    required this.stateDelta,
    required this.invocationId,
  });

  // App name to execute.
  final String appName;

  // User id for session lookup.
  final String userId;

  // Session id to continue or create.
  final String sessionId;

  // New incoming user/model content.
  final Content? newMessage;

  // Whether streaming output is requested.
  final bool streaming;

  // Optional per-request override for auto-creating sessions.
  final bool? autoCreateSession;

  // Optional state delta to apply before execution.
  final Map<String, Object?>? stateDelta;

  // Optional invocation id override.
  final String? invocationId;
}

/// Internal testing helper for resolving graph target root.
@visibleForTesting
BaseAgent resolveGraphTargetRootTesting(dynamic context, String? appName) =>
    (context as _AdkDevWebContext).getRootAgent(appName ?? '');

/// Internal testing helper for reading agent details.
@visibleForTesting
List<Map<String, Object?>> agentDetailsTesting(dynamic context) =>
    (context as _AdkDevWebContext).listAppDetails();

/// Internal testing helper for enqueueing A2A push delivery directly.
@visibleForTesting
Future<void> enqueueA2aPushDeliveryTesting(
  dynamic context, {
  required String appName,
  required String taskId,
  required Map<String, Object?> pushConfig,
  required Map<String, Object?> task,
  required List<Map<String, Object?>> updates,
}) => (context as _AdkDevWebContext).enqueueA2aPushNotifications(
  appName: appName,
  taskId: taskId,
  pushConfig: pushConfig,
  task: task,
  updates: updates,
);

/// Internal testing override for [AgentLoader] creation in web server.
@visibleForTesting
AgentLoader Function(String path)? webServerAgentLoaderTestingOverride;

/// Internal testing override for [BaseSessionService] creation in web server.
@visibleForTesting
BaseSessionService? webServerSessionServiceTestingOverride;

/// Internal testing override for [BaseArtifactService] creation in web server.
@visibleForTesting
BaseArtifactService? webServerArtifactServiceTestingOverride;

/// Internal testing helper for dispatching HTTP requests to the web server router.
@visibleForTesting
Future<void> handleDevWebServerRequestForTesting(
  HttpRequest request,
  dynamic context,
) => _handleRequest(request, context as _AdkDevWebContext);

/// Internal testing hook to simulate screencast initialization error.
@visibleForTesting
bool simulateScreencastInitErrorForTesting = false;

/// Internal testing hook for simulating SSE flush error.
@visibleForTesting
bool simulateSseFlushErrorForTesting = false;

/// Internal testing helper for reading in-memory traces by event id from context.
@visibleForTesting
Map<String, Map<String, Object?>> inMemoryTracesByEventIdForTesting(
  dynamic context,
) => (context as _AdkDevWebContext).inMemoryTracesByEventIdForTesting;

/// Internal testing helper for streaming A2A task updates.
@visibleForTesting
Future<void> writeA2aSseTaskReplayForTesting(
  HttpRequest request,
  dynamic context, {
  required Object? id,
  required bool jsonRpcEnvelope,
  required Map<String, Object?> task,
  required List<Map<String, Object?>> updates,
}) => _writeA2aSseTaskReplay(
  request,
  context as _AdkDevWebContext,
  id: id,
  jsonRpcEnvelope: jsonRpcEnvelope,
  task: task,
  updates: updates,
);

String _decodePathSegment(String rawSegment) {
  try {
    return Uri.decodeComponent(rawSegment);
  } on ArgumentError {
    return rawSegment;
  }
}

W3cTraceContext _extractRequestTraceContext(HttpRequest request) {
  final Map<String, String> headerMap = <String, String>{};
  request.headers.forEach((String name, List<String> values) {
    if (values.isNotEmpty) {
      headerMap[name] = values.join(', ');
    }
  });
  return extractW3cTraceContext(headerMap);
}

/// Builds an artifact request URL path with `encodeURIComponent(artifactName)`
/// matching `ArtifactService.getLatestArtifact` / `getArtifactVersion` in ADK Web.
String buildArtifactUrlPath({
  required String appName,
  required String userId,
  required String sessionId,
  required String artifactName,
  int? versionId,
}) {
  final String encodedArtifactName = Uri.encodeComponent(artifactName);
  final String base =
      '/apps/$appName/users/$userId/sessions/$sessionId/artifacts/$encodedArtifactName';
  if (versionId == null) {
    return base;
  }
  return '$base/versions/$versionId';
}

/// Line-buffered SSE stream decoder that carries partial lines across chunk
/// reads and flushes trailing lines on stream completion.
///
/// Mirrors `AgentService.runSse` in ADK Web (`60a516e`).
class SseLineFramer {
  /// Creates an [SseLineFramer].
  SseLineFramer();

  String _lastData = '';

  /// Unflushed partial line carried across chunk boundaries.
  String get pendingPartialLine => _lastData;

  /// Appends a UTF-8 text chunk, emitting parsed JSON objects for each complete
  /// `data:` SSE line and preserving any trailing incomplete line in [_lastData].
  List<Map<String, Object?>> addTextChunk(String chunk) {
    final List<String> lines = (_lastData + chunk).split(RegExp(r'\r?\n'));
    _lastData = lines.isEmpty ? '' : lines.removeLast();
    final List<Map<String, Object?>> emitted = <Map<String, Object?>>[];
    for (final String line in lines) {
      final Map<String, Object?>? parsed = _parseSseLine(line);
      if (parsed != null) {
        emitted.add(parsed);
      }
    }
    return emitted;
  }

  /// Flushes any remaining trailing line when the SSE stream completes (`done`).
  List<Map<String, Object?>> flush() {
    if (_lastData.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    final String remaining = _lastData;
    _lastData = '';
    final List<Map<String, Object?>> emitted = <Map<String, Object?>>[];
    for (final String line in remaining.split(RegExp(r'\r?\n'))) {
      final Map<String, Object?>? parsed = _parseSseLine(line);
      if (parsed != null) {
        emitted.add(parsed);
      }
    }
    return emitted;
  }

  Map<String, Object?>? _parseSseLine(String line) {
    if (!line.startsWith('data:')) {
      return null;
    }
    final String jsonStr = line.replaceFirst(RegExp(r'^data:\s*'), '');
    try {
      final Object? decoded = jsonDecode(jsonStr);
      if (decoded is Map) {
        return decoded.map(
          (Object? key, Object? value) => MapEntry('$key', value),
        );
      }
    } catch (_) {
      // Ignore malformed SSE data lines.
    }
    return null;
  }
}

final RegExp _anchorTagRegex = RegExp(
  r'<a\b([^>]*?\bhref\s*=\s*(?:"([^"]*)"|' "'" r"([^']*)'" r')[^>]*)>',
  caseSensitive: false,
);
final RegExp _externalHttpHrefRegex = RegExp(r'^https?:\/\/', caseSensitive: false);

/// Rewrites `<a href="...">` tags in rendered markdown [html] so that external
/// HTTP/HTTPS links open in a new tab with `target="_blank"` and
/// `rel="noopener noreferrer"`, while preserving relative, fragment (`#`),
/// `mailto:`, and non-HTTP links.
///
/// Mirrors `MarkdownComponent.openExternalLinksInNewTab` in ADK Web (`ae60fcd`).
String openExternalLinksInNewTabHtml(String html) {
  return html.replaceAllMapped(_anchorTagRegex, (Match match) {
    final String attrs = match.group(1)!;
    final String href = match.group(2) ?? match.group(3) ?? '';
    if (!_externalHttpHrefRegex.hasMatch(href)) {
      return match.group(0)!;
    }
    String updatedAttrs = attrs;
    if (!RegExp(r'\btarget\s*=', caseSensitive: false).hasMatch(updatedAttrs)) {
      updatedAttrs = '$updatedAttrs target="_blank"';
    }
    if (!RegExp(r'\brel\s*=', caseSensitive: false).hasMatch(updatedAttrs)) {
      updatedAttrs = '$updatedAttrs rel="noopener noreferrer"';
    }
    return '<a$updatedAttrs>';
  });
}

/// Computes per-span `systemInstructionChanged` flags scoped to each agent so
/// crossing an agent boundary does not falsely flag a system-instruction change.
///
/// Mirrors `TraceTabComponent.updateSystemInstructionFlags` in ADK Web (`f62b82a`).
List<Map<String, Object?>> computeSystemInstructionFlagsByAgent(
  List<Map<String, Object?>> spans, {
  Map<String, Map<String, Object?>> eventDataByEventId =
      const <String, Map<String, Object?>>{},
}) {
  final List<Map<String, Object?>> result = spans
      .map((Map<String, Object?> s) => Map<String, Object?>.from(s))
      .toList();
  final List<Map<String, Object?>> llmSpans = <Map<String, Object?>>[];
  for (final Map<String, Object?> span in result) {
    final String label =
        '${span['label'] ?? span['name'] ?? ''}'.toLowerCase();
    if (label == 'call_llm') {
      span['systemInstructionChanged'] = false;
      llmSpans.add(span);
    }
  }
  llmSpans.sort((Map<String, Object?> a, Map<String, Object?> b) {
    final num startA = (a['start_time'] ?? a['startTime'] ?? 0) as num;
    final num startB = (b['start_time'] ?? b['startTime'] ?? 0) as num;
    return startA.compareTo(startB);
  });

  final Map<String, List<Map<String, Object?>>> spansByAgent =
      <String, List<Map<String, Object?>>>{};
  for (final Map<String, Object?> span in llmSpans) {
    final String? eventId =
        (span['attrEventId'] ??
                (span['attributes'] is Map
                    ? (span['attributes'] as Map)['gcp.vertex.agent.event_id']
                    : null))
            ?.toString();
    final Map<String, Object?>? event =
        eventId != null ? eventDataByEventId[eventId] : null;
    final String agentName =
        '${event?['author'] ?? span['attrAgentName'] ?? (span['attributes'] is Map ? (span['attributes'] as Map)['gen_ai.agent.name'] : null) ?? ''}';
    spansByAgent.putIfAbsent(agentName, () => <Map<String, Object?>>[]).add(
      span,
    );
  }

  for (final List<Map<String, Object?>> agentSpans in spansByAgent.values) {
    for (int i = 1; i < agentSpans.length; i += 1) {
      final String prevSi = '${agentSpans[i - 1]['attrSystemInstruction'] ?? ''}';
      final String currSi = '${agentSpans[i]['attrSystemInstruction'] ?? ''}';
      if (prevSi.isNotEmpty && currSi.isNotEmpty && prevSi != currSi) {
        agentSpans[i]['systemInstructionChanged'] = true;
      }
    }
  }
  return result;
}

/// Computes session usage metadata totals and per-invocation rows, including
/// `cacheCreationTokenCount` (`Cache Creation Tokens` / `Total Cache Creation Tokens`).
///
/// Mirrors `sessionUsageMetadata` in `SessionTabComponent` in ADK Web (`9512e34`).
Map<String, Object?> computeSessionUsageMetadataSummary(
  List<Map<String, Object?>> events,
) {
  int totalPromptTokens = 0;
  int totalCandidatesTokens = 0;
  int totalCachedTokens = 0;
  int totalCacheCreationTokens = 0;
  int totalThinkingTokens = 0;
  int totalToolUseTokens = 0;
  int totalTokens = 0;
  bool hasUsage = false;

  final List<Map<String, Object?>> tableData = <Map<String, Object?>>[];
  for (final Map<String, Object?> event in events) {
    final Object? rawUsage = event['usageMetadata'] ?? event['usage_metadata'];
    if (rawUsage is! Map) {
      continue;
    }
    hasUsage = true;
    final int promptTokens =
        ((rawUsage['promptTokenCount'] ?? rawUsage['prompt_token_count'] ?? 0)
                as num)
            .toInt();
    final int candidatesTokens =
        ((rawUsage['candidatesTokenCount'] ??
                    rawUsage['candidates_token_count'] ??
                    0)
                as num)
            .toInt();
    final int cachedTokens =
        ((rawUsage['cachedContentTokenCount'] ??
                    rawUsage['cached_content_token_count'] ??
                    0)
                as num)
            .toInt();
    final int cacheCreationTokens =
        ((event['cacheCreationTokenCount'] ??
                    event['cache_creation_token_count'] ??
                    rawUsage['cacheCreationTokenCount'] ??
                    rawUsage['cache_creation_token_count'] ??
                    rawUsage['cacheCreationTokens'] ??
                    rawUsage['cache_creation_tokens'] ??
                    0)
                as num)
            .toInt();
    final int thinkingTokens =
        ((rawUsage['thoughtsTokenCount'] ??
                    rawUsage['thoughts_token_count'] ??
                    0)
                as num)
            .toInt();
    final int toolUseTokens =
        ((rawUsage['toolUsePromptTokenCount'] ??
                    rawUsage['tool_use_prompt_token_count'] ??
                    0)
                as num)
            .toInt();
    final int eventTotal =
        ((rawUsage['totalTokenCount'] ?? rawUsage['total_token_count'] ?? 0)
                as num)
            .toInt();

    totalPromptTokens += promptTokens;
    totalCandidatesTokens += candidatesTokens;
    totalCachedTokens += cachedTokens;
    totalCacheCreationTokens += cacheCreationTokens;
    totalThinkingTokens += thinkingTokens;
    totalToolUseTokens += toolUseTokens;
    totalTokens += eventTotal;

    tableData.add(<String, Object?>{
      'Invocation ID': event['invocationId'] ?? event['invocation_id'] ?? 'N/A',
      'Timestamp': event['timestamp'],
      'Model': event['modelVersion'] ?? event['model_version'] ?? 'N/A',
      'Prompt Tokens': promptTokens,
      'Cached Tokens': cachedTokens,
      'Cache Creation Tokens': cacheCreationTokens,
      'Thinking Tokens': thinkingTokens,
      'Tool Use Tokens': toolUseTokens,
      'Candidates Tokens': candidatesTokens,
      'Total Tokens': eventTotal,
    });
  }

  if (!hasUsage) {
    return <String, Object?>{
      'rows': const <Map<String, Object?>>[],
      'tableData': const <Map<String, Object?>>[],
      'displayedColumns': const <String>[],
    };
  }

  final List<Map<String, Object?>> rows = <Map<String, Object?>>[
    <String, Object?>{'key': 'Total Prompt Tokens', 'value': totalPromptTokens},
  ];
  if (totalCachedTokens > 0) {
    rows.add(<String, Object?>{
      'key': 'Total Cached Tokens',
      'value': totalCachedTokens,
    });
  }
  if (totalCacheCreationTokens > 0) {
    rows.add(<String, Object?>{
      'key': 'Total Cache Creation Tokens',
      'value': totalCacheCreationTokens,
    });
  }
  if (totalThinkingTokens > 0) {
    rows.add(<String, Object?>{
      'key': 'Total Thinking Tokens',
      'value': totalThinkingTokens,
    });
  }
  if (totalToolUseTokens > 0) {
    rows.add(<String, Object?>{
      'key': 'Total Tool Use Tokens',
      'value': totalToolUseTokens,
    });
  }
  rows.addAll(<Map<String, Object?>>[
    <String, Object?>{
      'key': 'Total Candidates Tokens',
      'value': totalCandidatesTokens,
    },
    <String, Object?>{'key': 'Total Tokens', 'value': totalTokens},
  ]);

  return <String, Object?>{
    'rows': rows,
    'tableData': tableData,
    'displayedColumns': const <String>[
      'Invocation ID',
      'Timestamp',
      'Model',
      'Prompt Tokens',
      'Cached Tokens',
      'Cache Creation Tokens',
      'Thinking Tokens',
      'Tool Use Tokens',
      'Candidates Tokens',
      'Total Tokens',
    ],
  };
}



