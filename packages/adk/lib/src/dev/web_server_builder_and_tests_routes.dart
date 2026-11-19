part of 'web_server.dart';

/// Optional testing override for evaluating whether an HTTP request originates
/// from a local loopback client on Visual Agent Builder and Dev Test routes.
@visibleForTesting
bool Function(HttpRequest request)? isLocalAgentBuilderClientTestingOverride;

final RegExp _devValidIdentifierPattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

String _decodeRawSegmentOrThrow(String rawSegment) {
  try {
    return Uri.decodeComponent(rawSegment);
  } on ArgumentError {
    throw const FormatException('Malformed percent-encoding in URL path.');
  }
}

List<String> _rawNonEmptyPathSegments(String routedPath) {
  return routedPath
      .split('/')
      .where((String segment) => segment.isNotEmpty)
      .toList(growable: false);
}

bool _isDirectLoopbackClient(HttpRequest request, _AdkDevWebContext context) {
  if (isLocalAgentBuilderClientTestingOverride != null) {
    return isLocalAgentBuilderClientTestingOverride!(request);
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

Future<bool> _ensureLocalAgentBuilderClient(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final String? origin = _firstHeaderValue(request, 'origin');
  if (origin != null) {
    if (!_isRequestOriginAllowed(
      origin: origin,
      request: request,
      allowOrigins: context.allowOrigins,
      serverHost: context.serverHost,
    )) {
      await _writeText(
        request,
        context,
        statusCode: HttpStatus.forbidden,
        text: 'Forbidden: origin not allowed',
        includeCorsHeaders: false,
      );
      return false;
    }
    if (_requestHasForeignBrowserOrigin(request, context)) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.forbidden,
        message:
            "This endpoint writes agent files or starts runs, so it accepts "
            "browser requests only from this server's own origin or an origin "
            "listed literally in allow_origins.",
      );
      return false;
    }
  }

  final Map<String, String> effectiveEnv = <String, String>{
    ...Platform.environment,
    ...context.environment,
  };
  try {
    requireLocalAgentBuilderClient(
      isLocal: _isDirectLoopbackClient(request, context),
      environment: effectiveEnv,
    );
    return true;
  } on StateError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.forbidden,
      message: error.message,
    );
    return false;
  }
}

bool _isPathInsideRoot(String candidatePath, String rootPath) {
  final String normalizedRoot = Uri.directory(
    rootPath,
  ).toFilePath(windows: Platform.isWindows);
  final String normalizedCandidate = File(
    candidatePath,
  ).absolute.uri.toFilePath(windows: Platform.isWindows);
  final String rootNoTrailing = normalizedRoot.endsWith(Platform.pathSeparator)
      ? normalizedRoot.substring(
          0,
          normalizedRoot.length - Platform.pathSeparator.length,
        )
      : normalizedRoot;
  return normalizedCandidate == rootNoTrailing ||
      normalizedCandidate.startsWith(
        '$rootNoTrailing${Platform.pathSeparator}',
      );
}

Directory _getDevTestAgentDir(_AdkDevWebContext context, String appName) {
  if (appName.isEmpty ||
      appName.contains('/') ||
      appName.contains('\\') ||
      appName.contains('\x00')) {
    throw ArgumentError('Invalid app name.');
  }
  final List<String> parts = appName.split('.');
  if (parts.any((String p) => !_devValidIdentifierPattern.hasMatch(p))) {
    throw ArgumentError('Invalid app name.');
  }
  final Directory baseDir = Directory(context.agentsDir).absolute;
  final String resolvedBase = baseDir.existsSync()
      ? baseDir.resolveSymbolicLinksSync()
      : baseDir.path;
  final Directory agentDir = Directory(
    '${baseDir.path}${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}',
  ).absolute;
  if (!_isPathInsideRoot(agentDir.path, baseDir.path)) {
    throw ArgumentError('Invalid app path.');
  }
  if (agentDir.existsSync()) {
    final String resolvedAgent = agentDir.resolveSymbolicLinksSync();
    if (!_isPathInsideRoot(resolvedAgent, resolvedBase)) {
      throw ArgumentError('Invalid app path.');
    }
  }
  return agentDir;
}

File _getDevTestFilePath({
  required Directory agentDir,
  required String testName,
  bool forWrite = false,
}) {
  if (testName.isEmpty ||
      testName == '.' ||
      testName == '..' ||
      testName.contains('/') ||
      testName.contains('\\') ||
      testName.contains('\x00')) {
    throw ArgumentError('Invalid test name.');
  }
  final String normalizedName = testName.endsWith('.json')
      ? testName
      : '$testName.json';
  if (normalizedName == '.json' ||
      normalizedName == '..json' ||
      normalizedName == '...json') {
    throw ArgumentError('Invalid test name.');
  }

  final Directory testsDir = Directory(
    '${agentDir.path}${Platform.pathSeparator}tests',
  ).absolute;
  if (FileSystemEntity.typeSync(testsDir.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw ArgumentError('Tests directory must not be a symlink.');
  }
  final String canonicalTestsDir = testsDir.existsSync()
      ? testsDir.resolveSymbolicLinksSync()
      : testsDir.path;

  final File candidate = File(
    '${testsDir.path}${Platform.pathSeparator}$normalizedName',
  ).absolute;
  if (!_isPathInsideRoot(candidate.path, testsDir.path)) {
    throw ArgumentError('Invalid test path.');
  }
  final FileSystemEntityType candidateType = FileSystemEntity.typeSync(
    candidate.path,
    followLinks: false,
  );
  if (candidateType == FileSystemEntityType.link) {
    throw ArgumentError('Invalid test path.');
  }
  if (!forWrite && candidate.existsSync()) {
    final String resolvedCandidate = candidate.resolveSymbolicLinksSync();
    if (!_isPathInsideRoot(resolvedCandidate, canonicalTestsDir)) {
      throw ArgumentError('Invalid test path.');
    }
  }
  return candidate;
}

Object? _sortJsonKeysRecursively(Object? value) {
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? k) => '$k').toList()
      ..sort();
    final Map<String, Object?> sorted = <String, Object?>{};
    for (final String key in keys) {
      sorted[key] = _sortJsonKeysRecursively(value[key]);
    }
    return sorted;
  }
  if (value is List) {
    return value.map(_sortJsonKeysRecursively).toList(growable: false);
  }
  return value;
}

Object _loadAgentOrAppForTests(_AdkDevWebContext context, String appName) {
  try {
    return context.agentLoader.loadAgent(appName);
  } on Object {
    if (appName == context.defaultAppName) {
      return context.runtime.runner.agent;
    }
    rethrow;
  }
}

Future<bool> _handleDevReplayTestsRoutes(
  HttpRequest request,
  _AdkDevWebContext context,
  String routedPath,
) async {
  if (!context.enableWebUi) {
    return false;
  }

  final List<String> rawSegments = _rawNonEmptyPathSegments(routedPath);
  if (rawSegments.length < 4 ||
      rawSegments[0] != 'dev' ||
      rawSegments[1] != 'apps' ||
      rawSegments[3] != 'tests') {
    return false;
  }
  if (rawSegments.length > 5) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Invalid test path.',
    );
    return true;
  }

  final String appName = _decodeRawSegmentOrThrow(rawSegments[2]);
  final String method = request.method.toUpperCase();

  // GET /dev/apps/{app_name}/tests
  if (rawSegments.length == 4 && method == 'GET') {
    final Directory agentDir;
    try {
      agentDir = _getDevTestAgentDir(context, appName);
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    final Directory testsDir = Directory(
      '${agentDir.path}${Platform.pathSeparator}tests',
    );
    if (!testsDir.existsSync()) {
      await _writeJson(request, context, payload: const <String>[]);
      return true;
    }
    final List<String> names = <String>[];
    for (final FileSystemEntity entity in testsDir.listSync(
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.json')) {
        names.add(entity.uri.pathSegments.last);
      }
    }
    names.sort();
    await _writeJson(request, context, payload: names);
    return true;
  }

  if (rawSegments.length != 5) {
    return false;
  }

  final String tailSegment = _decodeRawSegmentOrThrow(rawSegments[4]);

  // POST /dev/apps/{app_name}/tests/rebuild
  if (tailSegment == 'rebuild' && method == 'POST') {
    if (!await _ensureLocalAgentBuilderClient(request, context)) {
      return true;
    }
    final Directory agentDir;
    File? targetTestFile;
    try {
      agentDir = _getDevTestAgentDir(context, appName);
      String? testName = request.uri.queryParameters['test_name'];
      if ((testName == null || testName.isEmpty) &&
          request.contentLength != 0) {
        final Map<String, dynamic> body = await _readJsonBody(request);
        final Object? bodyTestName = body['test_name'] ?? body['testName'];
        if (bodyTestName is String && bodyTestName.isNotEmpty) {
          testName = bodyTestName;
        }
      }
      if (testName != null && testName.isNotEmpty) {
        targetTestFile = _getDevTestFilePath(
          agentDir: agentDir,
          testName: testName,
        );
      }
    } on FormatException catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: error.message,
      );
      return true;
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    try {
      if (context.agentLoader is AgentLoader) {
        (context.agentLoader as AgentLoader).removeAgentFromCache(appName);
      }
      final Object loaded = _loadAgentOrAppForTests(context, appName);
      await rebuildTests(
        agentDir: agentDir.path,
        testFilePath: targetTestFile?.path,
        appName: appName,
        app: loaded is App ? loaded : null,
        rootAgent: loaded is App ? null : loaded,
      );
      await _writeJson(
        request,
        context,
        payload: const <String, Object?>{'status': 'success'},
      );
      return true;
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: '${error.message}',
      );
      return true;
    } on StateError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: error.message,
      );
      return true;
    } catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.internalServerError,
        message: 'Failed to rebuild tests: $error',
      );
      return true;
    }
  }

  // POST /dev/apps/{app_name}/tests/run
  if (tailSegment == 'run' && method == 'POST') {
    if (!await _ensureLocalAgentBuilderClient(request, context)) {
      return true;
    }
    final Directory agentDir;
    File? targetTestFile;
    try {
      agentDir = _getDevTestAgentDir(context, appName);
      final String? testName = request.uri.queryParameters['test_name'];
      if (testName != null && testName.isNotEmpty) {
        targetTestFile = _getDevTestFilePath(
          agentDir: agentDir,
          testName: testName,
        );
      }
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    final HttpResponse response = request.response;
    _setCorsHeaders(request, response, context);
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType(
      'text',
      'plain',
      charset: 'utf-8',
    );
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    response.headers.set('x-accel-buffering', 'no');
    response.bufferOutput = false;

    try {
      if (devTestRunnerProcessStarterTestingOverride != null) {
        final Process process =
            await devTestRunnerProcessStarterTestingOverride!(
              agentDir: agentDir.path,
              testFilePath: targetTestFile?.path,
            );
        await for (final String line in streamTestOutput(process)) {
          response.write(line);
          await response.flush();
        }
        await process.exitCode;
        await response.close();
        return true;
      }

      if (targetTestFile != null && !targetTestFile.existsSync()) {
        response.write(
          'ERROR: Test file not found: ${targetTestFile.uri.pathSegments.last}\n',
        );
        response.write('=== 0 passed, 1 failed ===\n');
        await response.flush();
        await response.close();
        return true;
      }

      final List<File> testFiles = targetTestFile != null
          ? <File>[targetTestFile]
          : getTestFiles(agentDir.path);
      if (testFiles.isEmpty) {
        response.write('No test files found for $appName.\n');
        response.write('=== 0 passed, 0 failed ===\n');
        await response.flush();
        await response.close();
        return true;
      }

      if (context.agentLoader is AgentLoader) {
        (context.agentLoader as AgentLoader).removeAgentFromCache(appName);
      }
      final Object loaded = _loadAgentOrAppForTests(context, appName);
      int passed = 0;
      int failed = 0;
      for (final File testFile in testFiles) {
        final String label = testFile.uri.pathSegments.last;
        response.write('Running $label...\n');
        await response.flush();
        try {
          await runAgentReplayTest(
            testFile: testFile,
            appName: appName,
            app: loaded is App ? loaded : null,
            rootAgent: loaded is App ? null : loaded,
            useMockModelWhenUnconfigured: true,
            environment: context.environment,
          );
          passed += 1;
          response.write('PASSED $label\n');
        } catch (error) {
          failed += 1;
          response.write('FAILED $label: $error\n');
        }
        await response.flush();
      }
      response.write('=== $passed passed, $failed failed ===\n');
      await response.flush();
    } catch (error) {
      response.write('\nError executing tests: $error\n');
      await response.flush();
    } finally {
      await response.close();
    }
    return true;
  }

  // GET /dev/apps/{app_name}/tests/{test_name}
  if (method == 'GET') {
    final File testFile;
    try {
      final Directory agentDir = _getDevTestAgentDir(context, appName);
      testFile = _getDevTestFilePath(agentDir: agentDir, testName: tailSegment);
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    if (!testFile.existsSync()) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: 'Test file not found',
      );
      return true;
    }

    final Object? decoded = jsonDecode(await testFile.readAsString());
    await _writeJson(
      request,
      context,
      payload: decoded ?? const <String, Object?>{},
    );
    return true;
  }

  // PUT /dev/apps/{app_name}/tests/{test_name}
  if (method == 'PUT') {
    if (!await _ensureLocalAgentBuilderClient(request, context)) {
      return true;
    }
    final File testFile;
    try {
      final Directory agentDir = _getDevTestAgentDir(context, appName);
      testFile = _getDevTestFilePath(
        agentDir: agentDir,
        testName: tailSegment,
        forWrite: true,
      );
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    final Map<String, Object?> body;
    try {
      final Map<String, dynamic> rawBody = await _readJsonBody(request);
      body = rawBody.map((String k, dynamic v) => MapEntry(k, v));
    } on FormatException catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: error.message,
      );
      return true;
    }

    final CreateTestRequest createReq = CreateTestRequest.fromJson(body);
    Map<String, Object?>? sessionPayload = createReq.sessionData;
    if (sessionPayload == null &&
        createReq.sessionId.isNotEmpty &&
        createReq.userId.isNotEmpty) {
      final Session? existingSession = await context.sessionService.getSession(
        appName: appName,
        userId: createReq.userId,
        sessionId: createReq.sessionId,
      );
      if (existingSession == null) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.notFound,
          message: 'Session not found: ${createReq.sessionId}',
        );
        return true;
      }
      sessionPayload = _sessionToApiJson(existingSession, includeEvents: true);
    }

    if (sessionPayload == null) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.unprocessableEntity,
        message:
            'CreateTestRequest requires "session_data" or both "session_id" and "user_id".',
      );
      return true;
    }

    try {
      testFile.parent.createSync(recursive: true);
      if (FileSystemEntity.typeSync(testFile.path, followLinks: false) ==
          FileSystemEntityType.link) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.badRequest,
          message: 'Invalid test path.',
        );
        return true;
      }
      final Object? sorted = _sortJsonKeysRecursively(sessionPayload);
      final String formatted =
          '${const JsonEncoder.withIndent('  ').convert(sorted)}\n';
      await testFile.writeAsString(formatted);
      await _writeJson(
        request,
        context,
        payload: <String, Object?>{
          'status': 'success',
          'file': testFile.uri.pathSegments.last,
        },
      );
      return true;
    } on FileSystemException catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.internalServerError,
        message: 'Failed to save test file: ${error.message}',
      );
      return true;
    }
  }

  // DELETE /dev/apps/{app_name}/tests/{test_name}
  if (method == 'DELETE') {
    if (!await _ensureLocalAgentBuilderClient(request, context)) {
      return true;
    }
    final File testFile;
    try {
      final Directory agentDir = _getDevTestAgentDir(context, appName);
      testFile = _getDevTestFilePath(agentDir: agentDir, testName: tailSegment);
    } on ArgumentError catch (error) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.badRequest,
        message: '${error.message}',
      );
      return true;
    }

    if (!testFile.existsSync()) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.notFound,
        message: 'Test file not found',
      );
      return true;
    }

    await testFile.delete();
    await _writeJson(
      request,
      context,
      payload: const <String, Object?>{'status': 'success'},
    );
    return true;
  }

  return false;
}

class _ReasoningEngineInputError implements Exception {
  const _ReasoningEngineInputError(this.message, {this.statusCode = 422});

  final String message;
  final int statusCode;
}

String _requireReasoningEngineString(
  Map<String, Object?> input,
  List<String> keys, {
  required String fieldLabel,
}) {
  for (final String key in keys) {
    if (!input.containsKey(key)) {
      continue;
    }
    final Object? val = input[key];
    if (val is String && val.trim().isNotEmpty) {
      return val.trim();
    }
    throw _ReasoningEngineInputError(
      'Invalid or empty "$fieldLabel" parameter.',
    );
  }
  throw _ReasoningEngineInputError('Missing required "$fieldLabel" parameter.');
}

String? _optionalReasoningEngineString(
  Map<String, Object?> input,
  List<String> keys, {
  required String fieldLabel,
}) {
  for (final String key in keys) {
    if (!input.containsKey(key) || input[key] == null) {
      continue;
    }
    final Object? val = input[key];
    if (val is String) {
      final String trimmed = val.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    throw _ReasoningEngineInputError('Parameter "$fieldLabel" must be a string.');
  }
  return null;
}

Content _parseReasoningEngineMessage(Map<String, Object?> input) {
  if (!input.containsKey('message') && !input.containsKey('new_message')) {
    throw const _ReasoningEngineInputError(
      'Missing required "message" parameter.',
    );
  }
  final Object? raw = input['message'] ?? input['new_message'];
  if (raw is String) {
    if (raw.trim().isEmpty) {
      throw const _ReasoningEngineInputError(
        'Parameter "message" must not be empty.',
      );
    }
    return Content.userText(raw);
  }
  if (raw is Map) {
    return _contentFromJson(_toDynamicMap(raw));
  }
  throw const _ReasoningEngineInputError(
    'Parameter "message" must be a string or Content object.',
  );
}

String _resolveReasoningEngineAppName(
  _AdkDevWebContext context,
  Map<String, Object?> input,
) {
  final String? enterprise = context.geminiEnterpriseAppName?.trim();
  if (enterprise != null && enterprise.isNotEmpty) {
    return enterprise;
  }
  final Object? fromInput = input['app_name'] ?? input['appName'];
  if (fromInput is String && fromInput.trim().isNotEmpty) {
    return fromInput.trim();
  }
  return context.defaultAppName;
}

Future<Session> _resolveOrCreateReasoningEngineSession({
  required _AdkDevWebContext context,
  required String appName,
  required String userId,
  required String? sessionId,
  required Object? rawSessionEvents,
}) async {
  if (sessionId != null && rawSessionEvents != null) {
    throw const _ReasoningEngineInputError(
      'Cannot specify both "session_id" and "session_events".',
      statusCode: HttpStatus.badRequest,
    );
  }
  if (rawSessionEvents != null && rawSessionEvents is! List) {
    throw const _ReasoningEngineInputError(
      'Parameter "session_events" must be a list of events.',
    );
  }

  if (sessionId != null) {
    final Session? existing = await context.sessionService.getSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
    if (existing != null) {
      return existing;
    }
    return context.sessionService.createSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  final Session created = await context.sessionService.createSession(
    appName: appName,
    userId: userId,
  );
  if (rawSessionEvents is List && rawSessionEvents.isNotEmpty) {
    final List<Event> initialEvents = _readEventsFromPayload(
      <String, dynamic>{'events': rawSessionEvents},
      appName: appName,
      userId: userId,
      sessionId: created.id,
    );
    for (final Event event in initialEvents) {
      await context.sessionService.appendEvent(session: created, event: event);
    }
  }
  return created;
}

Future<ReasoningEngineQueryRequest?> _parseAndValidateReasoningEngineRequest(
  HttpRequest request,
  _AdkDevWebContext context, {
  required bool expectStreaming,
}) async {
  final String rawBody = await utf8.decoder.bind(request).join();
  if (rawBody.trim().isEmpty) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Request body must not be empty.',
    );
    return null;
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(rawBody);
  } on FormatException catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Invalid JSON: ${error.message}',
    );
    return null;
  }

  if (decoded is! Map) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'Request body must be a JSON object.',
    );
    return null;
  }

  final ReasoningEngineQueryRequest parsed;
  try {
    parsed = ReasoningEngineQueryRequest.fromJson(
      Map<String, Object?>.from(decoded),
    );
  } on FormatException catch (error) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: error.message,
    );
    return null;
  }

  final bool? isStreamingMethod =
      allowedAgentEngineClassMethods[parsed.classMethod];
  if (isStreamingMethod == null || isStreamingMethod != expectStreaming) {
    await _writeError(
      request,
      context,
      statusCode: HttpStatus.badRequest,
      message: 'class_method ${parsed.classMethod} is not allowed',
    );
    return null;
  }

  return parsed;
}

Future<void> _handleReasoningEngine(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final ReasoningEngineQueryRequest? queryReq =
      await _parseAndValidateReasoningEngineRequest(
        request,
        context,
        expectStreaming: false,
      );
  if (queryReq == null) {
    return;
  }

  final Map<String, Object?> input = queryReq.input;
  final String targetApp = _resolveReasoningEngineAppName(context, input);

  try {
    switch (queryReq.classMethod) {
      case 'create_session':
      case 'async_create_session':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final Object? rawState = input['state'];
        if (rawState != null && rawState is! Map) {
          throw const _ReasoningEngineInputError(
            'Parameter "state" must be a JSON object.',
          );
        }
        final Session created = await context.sessionService.createSession(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          state: rawState == null
              ? null
              : Map<String, Object?>.from(rawState as Map),
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': _sessionToApiJson(created, includeEvents: true),
          },
        );
        return;

      case 'list_sessions':
      case 'async_list_sessions':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final ListSessionsResponse listed = await context.sessionService
            .listSessions(appName: targetApp, userId: userId);
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': <String, Object?>{
              'sessions': listed.sessions
                  .map(
                    (Session s) => _sessionToApiJson(s, includeEvents: false),
                  )
                  .toList(growable: false),
            },
          },
        );
        return;

      case 'get_session':
      case 'async_get_session':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String sessionId = _requireReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final Session? session = await context.sessionService.getSession(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': session == null
                ? null
                : _sessionToApiJson(session, includeEvents: true),
          },
        );
        return;

      case 'delete_session':
      case 'async_delete_session':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String sessionId = _requireReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        await context.sessionService.deleteSession(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
        );
        await _writeJson(
          request,
          context,
          payload: const <String, Object?>{'output': null},
        );
        return;

      case 'query':
      case 'async_query':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final Content newMessage = _parseReasoningEngineMessage(input);
        final Object? rawStateDelta = input['state_delta'] ?? input['stateDelta'];
        if (rawStateDelta != null && rawStateDelta is! Map) {
          throw const _ReasoningEngineInputError(
            'Parameter "state_delta" must be a JSON object.',
          );
        }
        final Runner runner = await context.getRunner(
          targetApp,
          request: request,
        );
        final Session session = await _resolveOrCreateReasoningEngineSession(
          context: context,
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          rawSessionEvents: input['session_events'] ?? input['sessionEvents'],
        );
        final List<Map<String, Object?>> serializedEvents =
            <Map<String, Object?>>[];
        await for (final Event event in runner.runAsync(
          userId: userId,
          sessionId: session.id,
          newMessage: newMessage,
          stateDelta: rawStateDelta is Map
              ? Map<String, Object?>.from(rawStateDelta)
              : null,
        )) {
          serializedEvents.add(
            _eventToApiJson(
              event,
              appName: targetApp,
              userId: userId,
              sessionId: session.id,
            ),
          );
        }
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{'output': serializedEvents},
        );
        return;

      case 'async_add_session_to_memory':
        final Object? rawSession = input['session'];
        Session? resolvedSession;
        if (rawSession is Map) {
          final Map<String, dynamic> map = _toDynamicMap(rawSession);
          final String sid = '${map['id'] ?? map['session_id'] ?? ''}';
          final String uid = '${map['user_id'] ?? map['userId'] ?? ''}';
          if (sid.isEmpty || uid.isEmpty) {
            throw const _ReasoningEngineInputError(
              'Session map must include "id" and "user_id".',
            );
          }
          resolvedSession = Session(
            id: sid,
            appName: '${map['app_name'] ?? map['appName'] ?? targetApp}',
            userId: uid,
            state: map['state'] is Map
                ? Map<String, Object?>.from(map['state'] as Map)
                : <String, Object?>{},
            events: _readEventsFromPayload(
              map,
              appName: targetApp,
              userId: uid,
              sessionId: sid,
            ),
          );
        } else {
          final String userId = _requireReasoningEngineString(
            input,
            const <String>['user_id', 'userId'],
            fieldLabel: 'user_id',
          );
          final String sessionId = _requireReasoningEngineString(
            input,
            const <String>['session_id', 'sessionId'],
            fieldLabel: 'session_id',
          );
          resolvedSession = await context.sessionService.getSession(
            appName: targetApp,
            userId: userId,
            sessionId: sessionId,
          );
        }
        if (resolvedSession == null) {
          throw const _ReasoningEngineInputError('Session not found.');
        }
        await context.memoryService.addSessionToMemory(resolvedSession);
        await _writeJson(
          request,
          context,
          payload: const <String, Object?>{'output': null},
        );
        return;

      case 'async_search_memory':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String query = _requireReasoningEngineString(
          input,
          const <String>['query'],
          fieldLabel: 'query',
        );
        final SearchMemoryResponse searchRes = await context.memoryService
            .searchMemory(appName: targetApp, userId: userId, query: query);
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': <String, Object?>{
              'memories': searchRes.memories
                  .map(
                    (MemoryEntry entry) => <String, Object?>{
                      'content': _contentToLegacyJson(entry.content),
                      if (entry.author != null) 'author': entry.author,
                      if (entry.timestamp != null) 'timestamp': entry.timestamp,
                      'custom_metadata': entry.customMetadata,
                    },
                  )
                  .toList(growable: false),
            },
          },
        );
        return;

      case 'async_save_artifact':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        final Object? rawArtifact = input['artifact'];
        if (rawArtifact is! Map) {
          throw const _ReasoningEngineInputError(
            'Parameter "artifact" must be a Part JSON object.',
          );
        }
        final Part artifactPart = _partFromJson(_toDynamicMap(rawArtifact));
        final int version = await context.artifactService.saveArtifact(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          filename: filename,
          artifact: artifactPart,
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{'output': version},
        );
        return;

      case 'async_load_artifact':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        final int? version = (input['version'] as num?)?.toInt();
        final Part? loaded = await context.artifactService.loadArtifact(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          filename: filename,
          version: version,
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': loaded == null ? null : _partToJson(loaded),
          },
        );
        return;

      case 'async_list_artifact_keys':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final List<String> keys = await context.artifactService.listArtifactKeys(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{'output': keys},
        );
        return;

      case 'async_delete_artifact':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        await context.artifactService.deleteArtifact(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          filename: filename,
        );
        await _writeJson(
          request,
          context,
          payload: const <String, Object?>{'output': null},
        );
        return;

      case 'async_list_versions':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        final List<int> versions = await context.artifactService.listVersions(
          appName: targetApp,
          userId: userId,
          sessionId: sessionId,
          filename: filename,
        );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{'output': versions},
        );
        return;

      case 'async_list_artifact_versions':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        final List<ArtifactVersion> versions = await context.artifactService
            .listArtifactVersions(
              appName: targetApp,
              userId: userId,
              sessionId: sessionId,
              filename: filename,
            );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': versions.map(_artifactVersionToJson).toList(),
          },
        );
        return;

      case 'async_get_artifact_version':
        final String userId = _requireReasoningEngineString(
          input,
          const <String>['user_id', 'userId'],
          fieldLabel: 'user_id',
        );
        final String? sessionId = _optionalReasoningEngineString(
          input,
          const <String>['session_id', 'sessionId'],
          fieldLabel: 'session_id',
        );
        final String filename = _requireReasoningEngineString(
          input,
          const <String>['filename'],
          fieldLabel: 'filename',
        );
        final int? version = (input['version'] as num?)?.toInt();
        final ArtifactVersion? artifactVersion = await context.artifactService
            .getArtifactVersion(
              appName: targetApp,
              userId: userId,
              sessionId: sessionId,
              filename: filename,
              version: version,
            );
        await _writeJson(
          request,
          context,
          payload: <String, Object?>{
            'output': artifactVersion == null
                ? null
                : _artifactVersionToJson(artifactVersion),
          },
        );
        return;
    }
  } on _ReasoningEngineInputError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: error.statusCode,
      message: error.message,
    );
  }
}

Future<void> _handleStreamReasoningEngine(
  HttpRequest request,
  _AdkDevWebContext context,
) async {
  final ReasoningEngineQueryRequest? queryReq =
      await _parseAndValidateReasoningEngineRequest(
        request,
        context,
        expectStreaming: true,
      );
  if (queryReq == null) {
    return;
  }

  Map<String, Object?> effectiveInput = queryReq.input;
  if (queryReq.classMethod == 'streaming_agent_run_with_events') {
    final Object? requestJsonRaw = effectiveInput['request_json'];
    if (requestJsonRaw is String && requestJsonRaw.trim().isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(requestJsonRaw);
        if (decoded is Map) {
          effectiveInput = Map<String, Object?>.from(decoded);
        } else {
          await _writeError(
            request,
            context,
            statusCode: HttpStatus.badRequest,
            message: 'request_json must decode to a JSON object.',
          );
          return;
        }
      } on FormatException catch (error) {
        await _writeError(
          request,
          context,
          statusCode: HttpStatus.badRequest,
          message: 'Invalid request_json: ${error.message}',
        );
        return;
      }
    } else if (requestJsonRaw != null) {
      await _writeError(
        request,
        context,
        statusCode: HttpStatus.unprocessableEntity,
        message: 'request_json must be a non-empty JSON string.',
      );
      return;
    }
  }

  final String targetApp = _resolveReasoningEngineAppName(
    context,
    effectiveInput,
  );

  final String userId;
  final String? sessionId;
  final Content newMessage;
  final Map<String, Object?>? stateDelta;
  final Runner runner;
  final Session session;

  try {
    userId = _requireReasoningEngineString(
      effectiveInput,
      const <String>['user_id', 'userId'],
      fieldLabel: 'user_id',
    );
    sessionId = _optionalReasoningEngineString(
      effectiveInput,
      const <String>['session_id', 'sessionId'],
      fieldLabel: 'session_id',
    );
    newMessage = _parseReasoningEngineMessage(effectiveInput);
    final Object? rawStateDelta =
        effectiveInput['state_delta'] ?? effectiveInput['stateDelta'];
    if (rawStateDelta != null && rawStateDelta is! Map) {
      throw const _ReasoningEngineInputError(
        'Parameter "state_delta" must be a JSON object.',
      );
    }
    stateDelta = rawStateDelta is Map
        ? Map<String, Object?>.from(rawStateDelta)
        : null;
    runner = await context.getRunner(targetApp, request: request);
    session = await _resolveOrCreateReasoningEngineSession(
      context: context,
      appName: targetApp,
      userId: userId,
      sessionId: sessionId,
      rawSessionEvents:
          effectiveInput['session_events'] ?? effectiveInput['sessionEvents'],
    );
  } on _ReasoningEngineInputError catch (error) {
    await _writeError(
      request,
      context,
      statusCode: error.statusCode,
      message: error.message,
    );
    return;
  }

  final String acceptHeader =
      (request.headers.value(HttpHeaders.acceptHeader) ?? '').toLowerCase();
  final bool emitSse = acceptHeader.contains('text/event-stream');

  final HttpResponse response = request.response;
  _setCorsHeaders(request, response, context);
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = emitSse
      ? ContentType('text', 'event-stream', charset: 'utf-8')
      : ContentType.json;
  response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  response.headers.set('x-accel-buffering', 'no');
  response.bufferOutput = false;

  try {
    await for (final Event event in runner.runAsync(
      userId: userId,
      sessionId: session.id,
      newMessage: newMessage,
      stateDelta: stateDelta,
      runConfig: RunConfig(streamingMode: StreamingMode.sse),
    )) {
      final Map<String, Object?> eventJson = _eventToApiJson(
        event,
        appName: targetApp,
        userId: userId,
        sessionId: session.id,
      );
      if (emitSse) {
        response.write('data: ${jsonEncode(eventJson)}\n\n');
      } else {
        response.write('${jsonEncode(eventJson)}\n');
      }
      await response.flush();
    }
  } finally {
    await response.close();
  }
}
