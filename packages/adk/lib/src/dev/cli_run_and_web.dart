part of 'cli.dart';

Future<int> _runTestCliCommand(
  List<String> args, {
  required IOSink out,
}) async {
  String folder = '.';
  bool seenFolder = false;
  bool rebuild = false;
  final List<String> testRunnerArgs = <String>[];
  bool passthrough = false;

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (passthrough) {
      testRunnerArgs.add(arg);
      continue;
    }
    if (arg == '--help' || arg == '-h') {
      throw CliUsageError('Usage: adk test [options] [agent_dir]');
    }
    if (arg == '--') {
      passthrough = true;
      continue;
    }
    if (arg == '--rebuild') {
      rebuild = true;
      continue;
    }
    if (arg.startsWith('-')) {
      testRunnerArgs.add(arg);
      continue;
    }
    if (!seenFolder) {
      folder = arg;
      seenFolder = true;
    } else {
      testRunnerArgs.add(arg);
    }
  }

  if (rebuild) {
    out.writeln('Rebuilding agent project at $folder...');
  }
  out.writeln('Running test suite for agent project...');
  final Process process = await Process.start(
    Platform.resolvedExecutable,
    <String>['test', ...testRunnerArgs],
    workingDirectory: folder,
    mode: ProcessStartMode.inheritStdio,
  );
  return await process.exitCode;
}


Future<int> _runCreateCommand(ParsedAdkCommand command, IOSink out) async {
  final String resolvedAgentName =
      (command.appName != null && command.appName!.trim().isNotEmpty)
      ? command.appName!.trim()
      : projectDirName(command.projectDir);
  validateAgentName(resolvedAgentName);
  await createDevProject(
    projectDirPath: command.projectDir,
    appName: command.appName,
    model: command.model,
    apiKey: command.apiKey,
    project: command.project,
    region: command.region,
    type: command.agentType,
  );
  out.writeln('Created ADK project at ${command.projectDir}');
  out.writeln('Next steps:');
  out.writeln('  cd ${command.projectDir}');
  out.writeln('  adk run .');
  out.writeln('  adk web --port 8000 .');
  return 0;
}

/// Runtime context for executing `adk run`.
class _RunCommandContext {
  /// Creates run command runtime context.
  _RunCommandContext({
    required this.runtime,
    required this.userId,
    required this.rootAgentName,
  });

  /// Runtime wrapper combining config and runner.
  final DevAgentRuntime runtime;

  /// User id used for the run session.
  final String userId;

  /// Root agent name used for prompt output.
  final String rootAgentName;
}

Future<_RunCommandContext> _loadRunCommandContext(
  ParsedAdkCommand command,
) async {
  if (command.defaultLlmModel != null &&
      command.defaultLlmModel!.trim().isNotEmpty) {
    LlmAgent.setDefaultModel(command.defaultLlmModel!.trim());
  }
  final Directory requestedDir = Directory(command.projectDir).absolute;
  final FileSystemEntityType entityType = await FileSystemEntity.type(
    requestedDir.path,
  );
  if (entityType == FileSystemEntityType.notFound) {
    throw FileSystemException(
      'Project directory does not exist.',
      requestedDir.path,
    );
  }
  if (entityType != FileSystemEntityType.directory) {
    throw FileSystemException(
      'Project path is not a directory.',
      requestedDir.path,
    );
  }
  final Directory agentDir = Directory(
    await requestedDir.resolveSymbolicLinks(),
  );

  await _migrateLegacyProjectToRootAgentYaml(agentDir.path);

  final String agentFolderName = projectDirName(agentDir.path);
  final Directory agentsParentDir = agentDir.parent.absolute;

  loadServicesModule(agentDir.path);
  final AgentLoader agentLoader =
      agentLoaderTestingOverride?.call(agentsParentDir.path) ??
      AgentLoader(
        agentsParentDir.path,
        enableDevProjectFallback: false,
      );
  final AgentOrApp loaded = agentLoader.loadAgent(agentFolderName);
  final BaseAgent rootAgent = asBaseAgent(loaded);

  final String sessionAppName = loaded is App ? loaded.name : agentFolderName;
  final Map<String, String>? appNameToDir =
      loaded is App && loaded.name != agentFolderName
      ? <String, String>{loaded.name: agentFolderName}
      : null;

  final bool effectiveUseLocalStorage =
      command.useLocalStorage && !command.inMemory;

  final Runner runner = loaded is App
      ? Runner(
          app: loaded,
          appName: sessionAppName,
          sessionService: createSessionServiceFromOptions(
            baseDir: agentsParentDir.path,
            sessionServiceUri: command.sessionServiceUri,
            appNameToDir: appNameToDir,
            useLocalStorage: effectiveUseLocalStorage,
          ),
          artifactService: createArtifactServiceFromOptions(
            baseDir: agentDir.path,
            artifactServiceUri: command.artifactServiceUri,
            useLocalStorage: effectiveUseLocalStorage,
          ),
          memoryService: createMemoryServiceFromOptions(
            baseDir: agentsParentDir.path,
            memoryServiceUri: command.memoryServiceUri,
          ),
          credentialService: InMemoryCredentialService(),
        )
      : Runner(
          appName: sessionAppName,
          agent: rootAgent,
          sessionService: createSessionServiceFromOptions(
            baseDir: agentsParentDir.path,
            sessionServiceUri: command.sessionServiceUri,
            appNameToDir: appNameToDir,
            useLocalStorage: effectiveUseLocalStorage,
          ),
          artifactService: createArtifactServiceFromOptions(
            baseDir: agentDir.path,
            artifactServiceUri: command.artifactServiceUri,
            useLocalStorage: effectiveUseLocalStorage,
          ),
          memoryService: createMemoryServiceFromOptions(
            baseDir: agentsParentDir.path,
            memoryServiceUri: command.memoryServiceUri,
          ),
          credentialService: InMemoryCredentialService(),
        );

  final DevProjectConfig config = DevProjectConfig(
    appName: sessionAppName,
    agentName: rootAgent.name,
    description: rootAgent.description,
    userId: command.userId ?? 'test_user',
  );

  return _RunCommandContext(
    runtime: DevAgentRuntime(config: config, runner: runner),
    userId: config.userId,
    rootAgentName: rootAgent.name,
  );
}

Future<void> _migrateLegacyProjectToRootAgentYaml(String projectDirPath) async {
  final String rootAgentPath =
      '$projectDirPath${Platform.pathSeparator}root_agent.yaml';
  final File rootAgentFile = File(rootAgentPath);
  if (await rootAgentFile.exists()) {
    return;
  }

  final File legacyConfig = File(
    '$projectDirPath${Platform.pathSeparator}adk.json',
  );
  if (!await legacyConfig.exists()) {
    return;
  }

  final DevProjectConfig config = await loadDevProjectConfig(projectDirPath);
  final String escapedName = _yamlScalar(config.agentName);
  final String escapedDescription = _yamlScalar(
    config.description.isEmpty
        ? 'A helpful assistant for user questions.'
        : config.description,
  );
  await rootAgentFile.writeAsString('''
name: $escapedName
description: $escapedDescription
instruction: Answer user questions to the best of your knowledge
model: gemini-2.5-flash
''');
}

String _yamlScalar(String value) {
  final String escaped = value.replaceAll("'", "''");
  return "'$escaped'";
}

Future<int> _runRunCommand(
  ParsedAdkCommand command,
  IOSink out, {
  IOSink? err,
  String? Function()? readLine,
}) async {
  if (command.logLevel != null) {
    cli_logs.setupAdkLogger(level: _toCliLogEnum(command.logLevel!));
  }
  final IOSink errSink = err ?? stderr;
  final _RunCommandContext context = await _loadRunCommandContext(command);
  final DevAgentRuntime runtime = context.runtime;
  final String userId = context.userId;
  final String rootAgentName = context.rootAgentName;

  if (command.replayFilePath != null) {
    final Session replaySession = await _runReplayFile(
      runtime: runtime,
      userId: userId,
      replayFilePath: command.replayFilePath!,
      out: out,
      jsonl: command.jsonl,
      timeout: command.timeout,
      err: errSink,
    );
    if (command.saveSession) {
      await _saveSessionSnapshot(
        runtime: runtime,
        session: replaySession,
        projectDir: command.projectDir,
        requestedSessionIdForSave: command.sessionId,
        out: out,
        readLine: readLine,
      );
    }
    await runtime.runner.close();
    return 0;
  }

  final Session session = await _prepareRunSession(
    runtime: runtime,
    userId: userId,
    requestedSessionId: command.sessionId,
    resumeFilePath: command.resumeFilePath,
    initialState: command.initialState,
  );

  Future<List<Event>?> sendMessageToSession(String msg) async {
    try {
      final Future<List<Event>> future = runtime.sendMessage(
        userId: userId,
        sessionId: session.id,
        message: msg,
      );
      if (command.timeout != null) {
        return await future.timeout(Duration(seconds: command.timeout!));
      }
      return await future;
    } on TimeoutException {
      errSink.writeln(
        'ERROR: Execution timed out after ${command.timeout} seconds.',
      );
      return null;
    }
  }

  if (command.message != null) {
    final Map<String, OpenInterrupt> openInterrupts =
        indexOpenInterrupts(session.events);
    String? activeInterruptId;
    for (final Event e in session.events.reversed) {
      final List<String> activeIds = <String>[
        for (final String id in e.longRunningToolIds ?? const <String>{})
          if (openInterrupts.containsKey(id)) id,
      ];
      if (activeIds.isNotEmpty) {
        activeInterruptId = activeIds.first;
        break;
      }
    }

    if (activeInterruptId != null && !command.jsonl) {
      out.writeln(
        'Auto-resuming interrupt $activeInterruptId with input: ${command.message}',
      );
    }

    final List<Event>? events = await sendMessageToSession(command.message!);
    if (events == null) {
      await runtime.runner.close();
      return 1;
    }
    _writeRunEvents(events, out: out, jsonl: command.jsonl, session: session);
    if (command.saveSession) {
      await _saveSessionSnapshot(
        runtime: runtime,
        session: session,
        projectDir: command.projectDir,
        requestedSessionIdForSave: command.sessionId,
        out: out,
        readLine: readLine,
      );
    }
    final bool pausedForInput = events.any(
      (Event event) => (event.longRunningToolIds?.isNotEmpty ?? false),
    );
    await runtime.runner.close();
    return pausedForInput ? 2 : 0;
  }

  if (command.resumeFilePath != null && session.events.isNotEmpty) {
    final Event lastEvent = session.events.last;
    if (lastEvent.author == 'user' &&
        lastEvent.content != null &&
        _textFromContent(lastEvent.content!).isNotEmpty) {
      final List<Event>? resumedEvents = await sendMessageToSession(
        _textFromContent(lastEvent.content!),
      );
      if (resumedEvents == null) {
        await runtime.runner.close();
        return 1;
      }
      _writeRunEvents(
        resumedEvents,
        out: out,
        jsonl: command.jsonl,
        session: session,
      );
    }
  }

  if (!command.jsonl) {
    out.writeln('Running agent $rootAgentName, type exit to exit.');
  }

  StreamSubscription<FileSystemEvent>? reloadWatchSubscription;
  if (command.reloadAgents) {
    try {
      final Directory watchDir = Directory(command.projectDir).absolute;
      reloadWatchSubscription = watchDir.watch(recursive: true).listen((
        FileSystemEvent event,
      ) {
        final String normalizedPath = event.path.replaceAll('\\', '/');
        if (normalizedPath.contains('/.adk/') ||
            normalizedPath.endsWith('/.adk')) {
          return;
        }
      });
    } on FileSystemException {
      // FileSystemEntity.watch is not supported on all platforms/filesystems.
    }
  }

  final String? Function() readLineFunc = _resolveCliReadLine(readLine);
  try {
    while (true) {
      if (!command.jsonl) {
        out.write('[user]: ');
        await out.flush();
      }

      final String? line = readLineFunc();
      if (line == null) {
        break;
      }
      final String input = line.trim();
      if (input.isEmpty) {
        continue;
      }
      if (input == 'exit' || input == 'quit') {
        break;
      }

      final List<Event>? events = await sendMessageToSession(input);
      if (events == null) {
        await runtime.runner.close();
        return 1;
      }
      _writeRunEvents(events, out: out, jsonl: command.jsonl, session: session);
    }
  } finally {
    await reloadWatchSubscription?.cancel();
  }

  if (command.saveSession) {
    await _saveSessionSnapshot(
      runtime: runtime,
      session: session,
      projectDir: command.projectDir,
      requestedSessionIdForSave: command.sessionId,
      out: out,
      readLine: readLine,
    );
  }

  await runtime.runner.close();
  return 0;
}

/// Parsed replay payload for `adk run --replay`.
class _ReplayInput {
  /// Creates replay input with [state] and ordered [queries].
  _ReplayInput({required this.state, required this.queries});

  /// Initial session state snapshot.
  final Map<String, Object?> state;

  /// Ordered replay query list.
  final List<String> queries;

  /// Parses replay input from JSON.
  factory _ReplayInput.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> state = <String, Object?>{};
    final Object? rawState = json['state'];
    if (rawState is Map) {
      state.addAll(
        rawState.map((Object? key, Object? value) => MapEntry('$key', value)),
      );
    }

    final List<String> queries = <String>[];
    final Object? rawQueries = json['queries'];
    if (rawQueries is List) {
      for (final Object? query in rawQueries) {
        if (query == null) {
          continue;
        }
        final String text = '$query';
        if (text.trim().isEmpty) {
          continue;
        }
        queries.add(text);
      }
    }

    return _ReplayInput(state: state, queries: queries);
  }
}

Future<Session> _runReplayFile({
  required DevAgentRuntime runtime,
  required String userId,
  required String replayFilePath,
  required IOSink out,
  bool jsonl = false,
  int? timeout,
  IOSink? err,
}) async {
  final File replayFile = File(replayFilePath);
  if (!await replayFile.exists()) {
    throw FileSystemException('Replay file not found.', replayFile.path);
  }
  final Object? decoded = jsonDecode(await replayFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Invalid replay file: expected object.');
  }
  final Map<String, Object?> replayJson = decoded.map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );
  final _ReplayInput replayInput = _ReplayInput.fromJson(replayJson);
  replayInput.state['_time'] = DateTime.now().toIso8601String();

  final Session session = await runtime.createSessionWithState(
    userId: userId,
    state: replayInput.state,
  );

  for (final String query in replayInput.queries) {
    if (!jsonl) {
      out.writeln('[user]: $query');
    }
    Future<List<Event>> sendFuture = runtime.sendMessage(
      userId: userId,
      sessionId: session.id,
      message: query,
    );
    if (timeout != null) {
      sendFuture = sendFuture.timeout(Duration(seconds: timeout));
    }
    final List<Event> events = await sendFuture;
    if (jsonl) {
      _writeRunEvents(events, out: out, jsonl: true, session: session);
      continue;
    }
    for (final Event event in events) {
      final Content? content = event.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }
      final String text = content.parts
          .where((Part part) => part.text != null && part.text!.isNotEmpty)
          .map((Part part) => part.text!)
          .join();
      if (text.isEmpty) {
        continue;
      }
      out.writeln('[${event.author}]: $text');
    }
  }

  return session;
}

Future<Session> _prepareRunSession({
  required DevAgentRuntime runtime,
  required String userId,
  required String? requestedSessionId,
  required String? resumeFilePath,
  Map<String, Object?>? initialState,
}) async {
  if (resumeFilePath == null) {
    if (requestedSessionId != null && requestedSessionId.trim().isNotEmpty) {
      final Session? existing = await runtime.getSession(
        userId: userId,
        sessionId: requestedSessionId.trim(),
      );
      if (existing != null) {
        if (initialState != null && initialState.isNotEmpty) {
          existing.state.addAll(initialState);
        }
        return existing;
      }
    }
    if (initialState != null) {
      return runtime.createSessionWithState(
        userId: userId,
        sessionId: requestedSessionId,
        state: Map<String, Object?>.from(initialState),
      );
    }
    return runtime.createSession(userId: userId, sessionId: requestedSessionId);
  }

  final Session loaded = await _loadSessionSnapshot(resumeFilePath);
  final Map<String, Object?>? mergedState = loaded.events.isEmpty
      ? <String, Object?>{
          ...loaded.state,
          ...?initialState,
        }
      : initialState == null
      ? null
      : Map<String, Object?>.from(initialState);
  final Session session = await runtime.createSessionWithState(
    userId: userId,
    sessionId: requestedSessionId,
    state: mergedState,
  );

  for (final Event event in loaded.events) {
    await runtime.runner.sessionService.appendEvent(
      session: session,
      event: event.copyWith(),
    );
  }

  final Session? reloaded = await runtime.getSession(
    userId: userId,
    sessionId: session.id,
  );
  return reloaded ?? session;
}

Future<Session> _loadSessionSnapshot(String filePath) async {
  final File file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException('Resume file not found.', file.path);
  }

  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw const FormatException('Invalid session snapshot: expected object.');
  }
  final Map<String, Object?> json = decoded.map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );

  final StorageSessionV0 storage = StorageSessionV0.fromJson(json);
  final List<Event> events = storage.storageEvents
      .map((StorageEventV0 item) => item.toEvent())
      .toList(growable: false);

  return storage.toSession(
    stateOverride: Map<String, Object?>.from(storage.state),
    events: events,
  );
}

Map<String, Object?> _sessionSnapshotJson(Session session) {
  final StorageSessionV0 storage = StorageSessionV0(
    appName: session.appName,
    userId: session.userId,
    id: session.id,
    state: Map<String, Object?>.from(session.state),
    storageEvents: session.events
        .map(
          (Event event) =>
              StorageEventV0.fromEvent(session: session, event: event),
        )
        .toList(growable: false),
  );
  return storage.toJson();
}

Future<void> _saveSessionSnapshot({
  required DevAgentRuntime runtime,
  required Session session,
  required String projectDir,
  required String? requestedSessionIdForSave,
  required IOSink out,
  String? Function()? readLine,
}) async {
  final Session? refreshed = await runtime.getSession(
    userId: session.userId,
    sessionId: session.id,
  );
  final Session target = refreshed ?? session;
  String? saveId = requestedSessionIdForSave?.trim();
  if (saveId == null || saveId.isEmpty) {
    out.write('Session ID to save: ');
    await out.flush();
    final String? Function() readLineFunc = _resolveCliReadLine(readLine);
    saveId = readLineFunc()?.trim();
    if (saveId == null || saveId.isEmpty) {
      saveId = target.id;
    }
  }
  final File output = File(
    '${Directory(projectDir).absolute.path}${Platform.pathSeparator}$saveId.session.json',
  );
  final String payload = const JsonEncoder.withIndent(
    '  ',
  ).convert(_sessionSnapshotJson(target));
  await output.writeAsString(payload);
  out.writeln('Session saved to ${output.path}');
}

Future<int> _runWebCommand(
  ParsedAdkCommand command,
  IOSink out,
  IOSink err, {
  Future<void>? stopSignal,
}) async {
  cli_logs.setupAdkLogger(level: _toCliLogEnum(command.logLevel ?? 'INFO'));

  if (command.usedDeprecatedSessionDbUrl) {
    err.writeln(
      'WARNING: Deprecated option --session_db_url is used. '
      'Please use --session_service_uri instead.',
    );
  }
  if (command.usedDeprecatedArtifactStorageUri) {
    err.writeln(
      'WARNING: Deprecated option --artifact_storage_uri is used. '
      'Please use --artifact_service_uri instead.',
    );
  }

  if (command.defaultLlmModel != null &&
      command.defaultLlmModel!.trim().isNotEmpty) {
    LlmAgent.setDefaultModel(command.defaultLlmModel!.trim());
  }

  final DevProjectConfig loadedConfig = await loadDevProjectConfig(
    command.projectDir,
    validateProjectDir: true,
  );
  final _LoadedCliAgent loadedAgent = await _loadAgentForCli(
    command.projectDir,
  );
  final Directory requestedDir = Directory(command.projectDir).absolute;
  final String agentFolderName = projectDirName(requestedDir.path);
  final DevProjectConfig config = DevProjectConfig(
    appName: loadedAgent.appName,
    agentName: loadedAgent.rootAgent.name,
    description: loadedAgent.rootAgent.description,
    userId: command.userId ?? loadedConfig.userId,
  );
  final DevAgentRuntime runtime = DevAgentRuntime(
    config: config,
    runner: Runner(
      appName: loadedAgent.appName,
      agent: loadedAgent.rootAgent,
      sessionService: createSessionServiceFromOptions(
        baseDir: loadedAgent.agentsParentDirPath,
        sessionServiceUri: command.sessionServiceUri,
        appNameToDir: <String, String>{loadedAgent.appName: agentFolderName},
        useLocalStorage: command.useLocalStorage,
      ),
      artifactService: createArtifactServiceFromOptions(
        baseDir: requestedDir.path,
        artifactServiceUri: command.artifactServiceUri,
        useLocalStorage: command.useLocalStorage,
      ),
      memoryService: createMemoryServiceFromOptions(
        baseDir: loadedAgent.agentsParentDirPath,
        memoryServiceUri: command.memoryServiceUri,
      ),
      credentialService: InMemoryCredentialService(),
    ),
  );

  final HttpServer server;
  try {
    server = await startAdkDevWebServer(
      runtime: runtime,
      project: config,
      agentsDir: loadedAgent.agentsParentDirPath,
      port: command.port!,
      host: command.host!,
      allowOrigins: command.allowOrigins,
      sessionServiceUri: command.sessionServiceUri,
      artifactServiceUri: command.artifactServiceUri,
      memoryServiceUri: command.memoryServiceUri,
      evalStorageUri: command.evalStorageUri,
      useLocalStorage: command.useLocalStorage,
      urlPrefix: command.urlPrefix,
      autoCreateSession: command.autoCreateSession,
      enableWebUi: command.enableWebUi,
      logoText: command.logoText,
      logoImageUrl: command.logoImageUrl,
      avatarConfig: command.avatarConfig,
      maxLlmCalls: command.maxLlmCalls,
      defaultLlmModel: command.defaultLlmModel,
      triggerOidcAudience: command.triggerOidcAudience,
      triggerOidcServiceAccounts: command.triggerOidcServiceAccounts,
      geminiEnterpriseAppName: command.geminiEnterpriseAppName,
      expressMode: command.expressMode,
      reload: command.reload,
      reloadAgents: command.reloadAgents,
      traceToCloud: command.traceToCloud,
      otelToCloud: command.otelToCloud,
      a2a: command.a2a,
      extraPlugins: command.extraPlugins,
      triggerSources: command.triggerSources,
      environment: Platform.environment,
    );
  } on SocketException catch (error) {
    err.writeln(
      'Failed to bind web server on ${command.host!.address}:${command.port}: $error',
    );
    await runtime.runner.close();
    return 1;
  }

  out.writeln(
    'ADK web server is running on '
    'http://${_displayHost(server.address)}:${server.port}${command.urlPrefix ?? ''}',
  );
  if (!command.enableWebUi) {
    out.writeln('UI is disabled for api_server mode.');
  }
  out.writeln('Press Ctrl+C to stop.');

  final List<StreamSubscription<dynamic>> signalSubscriptions =
      <StreamSubscription<dynamic>>[];
  final Completer<void> stopRequested = Completer<void>();
  if (stopSignal != null) {
    stopSignal.then((_) {
      if (!stopRequested.isCompleted) {
        stopRequested.complete();
      }
    });
  }

  if (webSignalStreamTestingOverride != null) {
    signalSubscriptions.add(
      webSignalStreamTestingOverride!.listen((_) {
        if (!stopRequested.isCompleted) {
          stopRequested.complete();
        }
      }),
    );
  } else {
    final List<ProcessSignal> signals =
        webSignalsTestingOverride ??
        <ProcessSignal>[
          ProcessSignal.sigint,
          if (!Platform.isWindows) ProcessSignal.sigterm,
        ];

    for (final ProcessSignal signal in signals) {
      try {
        if (simulateSignalUnsupportedForTesting) {
          throw UnsupportedError('Signal watch unsupported');
        }
        final Stream<dynamic> signalStream =
            signalWatchTestingOverride != null
                ? signalWatchTestingOverride!(signal)
                : signal.watch();
        signalSubscriptions.add(
          signalStream.listen((_) {
            if (!stopRequested.isCompleted) {
              stopRequested.complete();
            }
          }),
        );
      } on UnsupportedError {
        // Signal handling may not be available on all platforms.
      }
    }
  }

  if (signalSubscriptions.isEmpty) {
    out.writeln('Signal handling unavailable. Press Enter to stop.');
    final Stream<List<int>> input = _resolveWebStdin();
    await input.first;
  } else {
    await stopRequested.future;
  }

  await server.close(force: true);
  for (final StreamSubscription<dynamic> subscription
      in signalSubscriptions) {
    await subscription.cancel();
  }

  await runtime.runner.close();
  return 0;
}

String _resolveCliLogLevel({required String? explicit, required bool verbose}) {
  final String? normalizedExplicit = explicit == null
      ? null
      : _normalizeCliLogLevel(explicit);
  if (normalizedExplicit != null) {
    return normalizedExplicit;
  }
  if (verbose) {
    return 'DEBUG';
  }
  return 'INFO';
}

String _normalizeCliLogLevel(String raw) {
  final String upper = raw.trim().toUpperCase();
  const Set<String> supported = <String>{
    'DEBUG',
    'INFO',
    'WARNING',
    'ERROR',
    'CRITICAL',
  };
  if (!supported.contains(upper)) {
    throw CliUsageError(
      'Invalid log level: $raw. Supported: DEBUG, INFO, WARNING, ERROR, CRITICAL.',
    );
  }
  return upper;
}

cli_logs.Level _toCliLogEnum(String logLevel) {
  return switch (logLevel.toUpperCase()) {
    'DEBUG' => cli_logs.Level.debug,
    'INFO' => cli_logs.Level.info,
    'WARNING' => cli_logs.Level.warning,
    'ERROR' || 'CRITICAL' => cli_logs.Level.error,
    _ => cli_logs.Level.info,
  };
}

void _applyFeatureOverridesFromCli({
  required List<String> enableFeatures,
  required List<String> disableFeatures,
  required IOSink err,
}) {
  if (enableFeatures.isEmpty && disableFeatures.isEmpty) {
    return;
  }

  final Map<FeatureName, bool> overrides = <FeatureName, bool>{};
  for (final String rawFeature in enableFeatures) {
    final FeatureName? featureName = _featureNameFromCliValue(rawFeature);
    if (featureName == null) {
      _writeUnknownFeatureNameWarning(rawFeature, err);
      continue;
    }
    overrides[featureName] = true;
  }
  for (final String rawFeature in disableFeatures) {
    final FeatureName? featureName = _featureNameFromCliValue(rawFeature);
    if (featureName == null) {
      _writeUnknownFeatureNameWarning(rawFeature, err);
      continue;
    }
    overrides[featureName] = false;
  }

  for (final MapEntry<FeatureName, bool> entry in overrides.entries) {
    overrideFeatureEnabled(entry.key, entry.value);
  }
}

FeatureName? _featureNameFromCliValue(String rawFeature) {
  for (final FeatureName featureName in FeatureName.values) {
    if (featureName.value == rawFeature) {
      return featureName;
    }
  }
  return null;
}

void _writeUnknownFeatureNameWarning(String rawFeature, IOSink err) {
  final String validNames = FeatureName.values
      .map((FeatureName featureName) => featureName.value)
      .join(', ');
  err.writeln(
    "WARNING: Unknown feature name '$rawFeature'. Valid names are: $validNames",
  );
}

void _writeRunEvents(
  List<Event> events, {
  required IOSink out,
  bool jsonl = false,
  Session? session,
}) {
  if (jsonl) {
    final Session fallbackSession =
        session ??
        Session(appName: 'adk', userId: 'user', id: 'session');
    for (final Event event in events) {
      final Map<String, Object?> raw = StorageEventV0.fromEvent(
        session: fallbackSession,
        event: event,
      ).toJson();
      raw.remove('app_name');
      raw.remove('user_id');
      if (session == null) {
        raw.remove('session_id');
      }
      if (event.nodeInfo.path.isNotEmpty) {
        raw['node_path'] = event.nodeInfo.path;
      }
      final Object? actionsObj = raw['actions'];
      if (actionsObj is Map) {
        final Map<String, Object?> filteredActions = <String, Object?>{};
        actionsObj.forEach((Object? k, Object? v) {
          if (v != null &&
              !(v is Map && v.isEmpty) &&
              !(v is List && v.isEmpty)) {
            filteredActions['$k'] = v;
          }
        });
        if (filteredActions.isEmpty) {
          raw.remove('actions');
        } else {
          raw['actions'] = filteredActions;
        }
      }
      final Map<String, Object?> ordered = <String, Object?>{};
      for (final String key in const <String>[
        'author',
        'session_id',
        'node_path',
        'id',
      ]) {
        if (raw.containsKey(key)) {
          ordered[key] = raw[key];
        }
      }
      raw.forEach((String k, Object? v) {
        if (!ordered.containsKey(k)) {
          ordered[k] = v;
        }
      });
      out.writeln(jsonEncode(ordered));
    }
    return;
  }
  _writeEventTexts(events, out: out);
}

void _writeEventTexts(List<Event> events, {required IOSink out}) {
  bool emitted = false;
  for (final Event event in events) {
    if (event.content == null) {
      continue;
    }
    final String text = _textFromContent(event.content!);
    if (text.isNotEmpty) {
      final String author = event.author.trim().isEmpty
          ? 'system'
          : event.author;
      out.writeln('[$author]: $text');
      emitted = true;
    }
  }
  if (!emitted) {
    out.writeln('[system]: (no text response)');
  }
}

String _textFromContent(Content content) {
  final List<String> chunks = <String>[];
  for (final Part part in content.parts) {
    if (part.text != null && part.text!.trim().isNotEmpty) {
      chunks.add(part.text!.trim());
    }
  }
  return chunks.join('\n');
}

String _displayHost(InternetAddress address) {
  if (address.type == InternetAddressType.IPv6) {
    return '[${address.address}]';
  }
  return address.address;
}

/// Internal testing helper to format an internet address for display.
String displayHostForTesting(InternetAddress address) => _displayHost(address);

/// Internal testing helper to write run events to output.
void writeRunEventsForTesting(
  List<Event> events, {
  required IOSink out,
  bool jsonl = false,
  Session? session,
}) => _writeRunEvents(events, out: out, jsonl: jsonl, session: session);

/// Internal testing helper to escape a scalar string for YAML output.
String yamlScalarForTesting(String value) => _yamlScalar(value);

/// Internal testing helper to parse timeout string into seconds.
int parseTimeoutSecondsTesting(String raw) => _parseTimeoutSeconds(raw);

/// Internal testing helper to get streaming mode name.
String conformanceStreamingModeNameTesting(StreamingMode mode) =>
    _conformanceStreamingModeName(mode);

/// Internal testing helper to extract session ID from create session response.
String? extractSessionIdFromCreateSessionTesting(Map<String, Object?> response) =>
    _extractSessionIdFromCreateSession(response);

/// Internal testing helper to map raw CLI feature string to FeatureName.
FeatureName? featureNameFromCliValueTesting(String raw) =>
    _featureNameFromCliValue(raw);

/// Internal testing helper to write unknown feature name warning.
void writeUnknownFeatureNameWarningTesting(String raw, IOSink err) =>
    _writeUnknownFeatureNameWarning(raw, err);

/// Internal testing helper to convert empty string to null.
String? emptyToNullTesting(String? value) => _emptyToNull(value);

/// Internal testing helper for deep cloning JSON value.
Object? deepCloneJsonValueForTesting(Object? value) =>
    _deepCloneJsonValue(value);

/// Internal testing helper for sanitizing conformance event map.
Map<String, Object?> sanitizeConformanceEventMapForTesting(
  Map<String, Object?> raw,
) => _sanitizeConformanceEventMap(raw);

/// Internal testing helper for converting value to object map.
Map<String, Object?> asObjectMapForTesting(Object? value) => _asObjectMap(value);

/// Internal testing helper for parsing host.
InternetAddress parseHostForTesting(String raw) => _parseHost(raw);

/// Internal testing helper for building conformance run messages.
Object? buildConformanceRunMessageForTesting(
  Object? content,
  Map<String, String> functionCallNameToId, {
  String? text,
}) {
  return _buildConformanceRunMessage(
    _ConformanceUserMessage(
      text: text,
      content: content,
    ),
    functionCallNameToId,
  );
}

/// Internal testing helper for sanitizing conformance session maps.
Map<String, Object?> sanitizeConformanceSessionMapForTesting(
  Map<String, Object?> session, {
  bool keepEvents = false,
}) => _sanitizeConformanceSessionMap(session, keepEvents: keepEvents);

/// Internal testing helper for deep copying maps.
Map<String, Object?> deepCopyMapForTesting(Map<String, Object?> input) =>
    _deepCopyMap(input);

/// Internal testing helper for parsing eval selection.
Object parseEvalSelectionForTesting(String value) => _parseEvalSelection(value);

/// Internal testing helper for creating eval managers.
dynamic createEvalManagersForTesting({
  required String? evalStorageUri,
  required String agentsDir,
  required bool useInMemory,
  Map<String, String>? environment,
}) => _createEvalManagers(
  evalStorageUri: evalStorageUri,
  agentsDir: agentsDir,
  useInMemory: useInMemory,
  environment: environment,
);

/// Internal testing helper for merging eval targets.
void mergeEvalTargetsForTesting(
  List<dynamic> targets,
  String evalSetId,
  Set<String> evalCaseIds,
) {
  _mergeEvalTarget(targets.cast<_EvalTarget>(), evalSetId, evalCaseIds);
}

/// Internal testing helper for best optimized agent index.
int bestOptimizedAgentIndexForTesting(
  GepaRootAgentPromptOptimizerResult result,
) => _bestOptimizedAgentIndex(result);

/// Internal testing helper for loading conformance spec.
dynamic loadConformanceSpecForTesting(String specFilePath) =>
    _loadConformanceSpec(specFilePath);

/// Internal testing helper for parsing conformance record command.
dynamic parseConformanceRecordCommandForTesting(List<String> args) =>
    _parseConformanceRecordCommand(args);

/// Internal testing helper for creating parsed conformance record command.
@visibleForTesting
dynamic createParsedConformanceRecordCommandForTesting({
  required List<String> paths,
  required Uri baseUri,
  required String userId,
  StreamingMode? streamingMode,
}) => _ParsedConformanceRecordCommand(
  paths: paths,
  baseUri: baseUri,
  userId: userId,
  streamingMode: streamingMode,
);

/// Internal testing helper for running conformance record.
@visibleForTesting
Future<void> runConformanceRecordForTesting(
  dynamic command, {
  required IOSink out,
}) => _runConformanceRecord(
  command as _ParsedConformanceRecordCommand,
  out: out,
);

/// Internal testing helper for parsing conformance test command.
dynamic parseConformanceTestCommandForTesting(List<String> args) =>
    _parseConformanceTestCommand(args);

/// Internal testing helper for creating parsed conformance test command.
@visibleForTesting
dynamic createParsedConformanceTestCommandForTesting({
  required List<String> paths,
  required Uri baseUri,
  required String userId,
  required String mode,
  bool generateReport = false,
  String? reportDir,
  StreamingMode? streamingMode,
}) => _ParsedConformanceTestCommand(
  paths: paths,
  baseUri: baseUri,
  userId: userId,
  mode: mode,
  generateReport: generateReport,
  reportDir: reportDir,
  streamingMode: streamingMode,
);

/// Internal testing helper for running conformance test.
@visibleForTesting
Future<List<dynamic>> runConformanceTestForTesting(
  dynamic command, {
  required IOSink out,
}) => _runConformanceTest(
  command as _ParsedConformanceTestCommand,
  out: out,
);

/// Internal testing helper for parsing eval_set create command.
dynamic parseEvalSetCreateCommandForTesting(List<String> args) =>
    _parseEvalSetCreateCommand(args);

/// Internal testing helper for parsing eval_set add_eval_case command.
dynamic parseEvalSetAddEvalCaseCommandForTesting(List<String> args) =>
    _parseEvalSetAddEvalCaseCommand(args);

/// Internal testing helper for writing conformance report markdown.
Future<String> writeConformanceReportMarkdownForTesting({
  required List<dynamic> summaries,
  required String? reportDir,
  required Map<String, Object?> versionData,
}) => _writeConformanceMarkdownReport(
  summaries.cast<_ConformanceTestSummary>(),
  reportDir: reportDir,
  versionData: versionData,
);

/// Internal testing helper for loading agent for CLI.
Future<dynamic> loadAgentForCliForTesting(String agentPath) =>
    _loadAgentForCli(agentPath);

/// Internal testing helper for running eval CLI command.
Future<int> runEvalCliCommandForTesting(
  List<String> args, {
  required IOSink out,
  IOSink? err,
}) => _runEvalCliCommand(args, out: out, err: err);

/// Internal testing helper for running optimize CLI command.
Future<int> runOptimizeCliCommandForTesting(
  List<String> args, {
  required IOSink out,
  IOSink? err,
}) => _runOptimizeCliCommand(args, out: out, err: err);

/// Internal testing helper for loading scenarios file.
Future<dynamic> loadScenariosFileForTesting(File file) =>
    _readConversationScenariosFile(file.path);

/// Internal testing helper for recording a conformance case.
Future<void> recordConformanceCaseForTesting(
  AdkWebServerClient client,
  dynamic testCase, {
  required String userId,
  required StreamingMode streamingMode,
}) => _recordConformanceCase(
  client,
  testCase as _ConformanceTestCase,
  userId: userId,
  streamingMode: streamingMode,
);

/// Internal testing helper for running a conformance test case.
Future<dynamic> runConformanceTestCaseForTesting(
  AdkWebServerClient client,
  dynamic testCase, {
  required String userId,
  required StreamingMode streamingMode,
  required String mode,
}) => mode == 'live'
    ? _runConformanceLiveCase(
        client,
        testCase as _ConformanceTestCase,
        userId: userId,
        streamingMode: streamingMode,
      )
    : _runConformanceReplayCase(
        client,
        testCase as _ConformanceTestCase,
        userId: userId,
        streamingMode: streamingMode,
      );

/// Internal testing helper for discovering conformance cases.
Future<List<dynamic>> discoverConformanceCasesForTesting(
  List<String> paths, {
  required IOSink out,
  required bool replayMode,
  required StreamingMode streamingMode,
}) => _discoverConformanceCases(
  paths,
  out: out,
  replayMode: replayMode,
  streamingMode: streamingMode,
);
/// Internal testing override for [AgentLoader] creation in CLI.
@visibleForTesting
AgentLoader Function(String path)? agentLoaderTestingOverride;

/// Internal testing override for web command signals.
@visibleForTesting
List<ProcessSignal>? webSignalsTestingOverride;

/// Internal testing override for web signal stream.
@visibleForTesting
Stream<void>? webSignalStreamTestingOverride;

/// Internal testing override for web stdin stream.
@visibleForTesting
Stream<List<int>>? webStdinTestingOverride;

/// Internal testing flag to simulate signal watch throwing [UnsupportedError].
@visibleForTesting
bool simulateSignalUnsupportedForTesting = false;

/// Internal testing helper for printing optimization results.
@visibleForTesting
void printOptimizationResultsForTesting(
  GepaRootAgentPromptOptimizerResult result, {
  required bool printDetailedResults,
  required IOSink out,
}) {
  final _ParsedOptimizeCliCommand command = _ParsedOptimizeCliCommand(
    agentPath: '',
    samplerConfigFilePath: '',
    optimizerConfigFilePath: null,
    printDetailedResults: printDetailedResults,
    logLevel: 'INFO',
  );
  _printOptimizationResults(result, command: command, out: out);
}

/// Internal testing override for interactive cli readLineSync.
@visibleForTesting
String? Function()? cliReadLineTestingOverride;

/// Internal testing override for signal watch streams.
@visibleForTesting
Stream<dynamic> Function(ProcessSignal signal)? signalWatchTestingOverride;

String? Function() _resolveCliReadLine(String? Function()? readLine) {
  if (readLine != null) {
    return readLine;
  }
  if (cliReadLineTestingOverride != null) {
    return cliReadLineTestingOverride!;
  }
  return stdin.readLineSync;
}

Stream<List<int>> _resolveWebStdin() {
  if (webStdinTestingOverride != null) {
    return webStdinTestingOverride!;
  }
  return stdin;
}

/// Internal testing helper for resolving CLI readLine function.
@visibleForTesting
String? Function() resolveCliReadLineForTesting(String? Function()? readLine) =>
    _resolveCliReadLine(readLine);

/// Internal testing helper for resolving web stdin stream.
@visibleForTesting
Stream<List<int>> resolveWebStdinForTesting() => _resolveWebStdin();

/// Internal testing helper for running the run command directly.
@visibleForTesting
Future<int> runRunCommandForTesting(
  ParsedAdkCommand command,
  IOSink out, {
  IOSink? err,
  String? Function()? readLine,
}) => _runRunCommand(command, out, err: err, readLine: readLine);

/// Internal testing helper for applying feature overrides.
@visibleForTesting
void applyFeatureOverridesFromCliForTesting({
  required List<String> enableFeatures,
  required List<String> disableFeatures,
  required IOSink err,
}) => _applyFeatureOverridesFromCli(
  enableFeatures: enableFeatures,
  disableFeatures: disableFeatures,
  err: err,
);

