part of 'cli.dart';

/// Parsed arguments for `adk conformance record`.
class _ParsedConformanceRecordCommand {
  /// Creates parsed `conformance record` command arguments.
  _ParsedConformanceRecordCommand({
    required this.paths,
    required this.baseUri,
    required this.userId,
    this.streamingMode,
  });

  /// Input file or directory paths.
  final List<String> paths;

  /// Base conformance server URI.
  final Uri baseUri;

  /// User identifier for test sessions.
  final String userId;

  /// Optional streaming mode override.
  final StreamingMode? streamingMode;
}

/// Parsed arguments for `adk conformance test`.
class _ParsedConformanceTestCommand {
  /// Creates parsed `conformance test` command arguments.
  _ParsedConformanceTestCommand({
    required this.paths,
    required this.baseUri,
    required this.userId,
    required this.mode,
    required this.generateReport,
    this.reportDir,
    this.streamingMode,
  });

  /// Input file or directory paths.
  final List<String> paths;

  /// Base conformance server URI.
  final Uri baseUri;

  /// User identifier for test sessions.
  final String userId;

  /// Conformance mode (`recorded` or other supported values).
  final String mode;

  /// Whether to generate report output.
  final bool generateReport;

  /// Optional report output directory.
  final String? reportDir;

  /// Optional streaming mode override.
  final StreamingMode? streamingMode;
}

final List<StreamingMode> _supportedConformanceStreamingModes = <StreamingMode>[
  StreamingMode.none,
  StreamingMode.sse,
];

/// Normalized user message payload in conformance specs.
class _ConformanceUserMessage {
  /// Creates a conformance user message descriptor.
  _ConformanceUserMessage({this.text, this.content, this.stateDelta});

  /// Plain-text user message.
  final String? text;

  /// Structured content payload.
  final Object? content;

  /// Optional state delta to inject before sending.
  final Map<String, Object?>? stateDelta;
}

/// Parsed conformance test specification.
class _ConformanceTestSpec {
  /// Creates a conformance test specification.
  _ConformanceTestSpec({
    required this.description,
    required this.agent,
    required this.initialState,
    required this.userMessages,
  });

  /// Human-readable test description.
  final String description;

  /// Target agent name.
  final String agent;

  /// Initial state for the test session.
  final Map<String, Object?> initialState;

  /// Ordered user messages for the test.
  final List<_ConformanceUserMessage> userMessages;
}

/// Concrete conformance test case loaded from disk.
class _ConformanceTestCase {
  /// Creates a concrete conformance test case.
  _ConformanceTestCase({
    required this.category,
    required this.name,
    required this.dir,
    required this.spec,
  });

  /// Category/group name.
  final String category;

  /// Case name.
  final String name;

  /// Case directory location.
  final Directory dir;

  /// Parsed test specification.
  final _ConformanceTestSpec spec;
}

/// Result of running a single conformance case.
class _ConformanceCaseResult {
  /// Creates a conformance case result.
  _ConformanceCaseResult({
    required this.category,
    required this.name,
    required this.success,
    this.errorMessage,
    this.description,
  });

  /// Category/group name.
  final String category;

  /// Case name.
  final String name;

  /// Whether the case passed.
  final bool success;

  /// Optional failure message.
  final String? errorMessage;

  /// Optional human-readable description.
  final String? description;
}

/// Aggregated summary for a conformance test run.
class _ConformanceTestSummary {
  /// Creates a conformance run summary.
  _ConformanceTestSummary({
    required this.totalTests,
    required this.passedTests,
    required this.failedTests,
    required this.results,
    required this.streamingMode,
  });

  /// Total executed cases.
  final int totalTests;

  /// Number of passed cases.
  final int passedTests;

  /// Number of failed cases.
  final int failedTests;

  /// Per-case execution results.
  final List<_ConformanceCaseResult> results;

  /// Streaming mode used for this run.
  final StreamingMode streamingMode;

  /// Success rate in percentage.
  double get successRate {
    if (totalTests == 0) {
      return 0;
    }
    return (passedTests / totalTests) * 100;
  }
}

Future<int> _runConformanceCliCommand(
  List<String> args, {
  required IOSink out,
}) async {
  if (args.isEmpty) {
    throw CliUsageError(
      'Missing conformance subcommand. Supported: record, test.',
    );
  }

  final String subcommand = args.first;
  final List<String> commandArgs = args.skip(1).toList(growable: false);
  switch (subcommand) {
    case 'record':
      final _ParsedConformanceRecordCommand command =
          _parseConformanceRecordCommand(commandArgs);
      await _runConformanceRecord(command, out: out);
      return 0;
    case 'test':
      final _ParsedConformanceTestCommand command =
          _parseConformanceTestCommand(commandArgs);
      final List<_ConformanceTestSummary> summaries = await _runConformanceTest(
        command,
        out: out,
      );
      final int failedTests = summaries.fold<int>(
        0,
        (int total, _ConformanceTestSummary summary) =>
            total + summary.failedTests,
      );
      return failedTests == 0 ? 0 : 1;
    default:
      throw CliUsageError('Unknown conformance subcommand: $subcommand');
  }
}

Future<void> _runConformanceRecord(
  _ParsedConformanceRecordCommand command, {
  required IOSink out,
}) async {
  out.writeln('Generating ADK conformance tests...');
  final List<_ConformanceTestCase> testCases = await _discoverConformanceCases(
    command.paths,
    out: out,
    replayMode: false,
    streamingMode: command.streamingMode ?? StreamingMode.none,
  );
  if (testCases.isEmpty) {
    out.writeln('No test specs found to process.');
    out.writeln('Conformance test generation complete!');
    return;
  }

  out.writeln('\nProcessing ${testCases.length} test cases...');

  final AdkWebServerClient client = AdkWebServerClient(command.baseUri);
  final List<StreamingMode> modesToRecord = command.streamingMode == null
      ? _supportedConformanceStreamingModes
      : <StreamingMode>[command.streamingMode!];
  try {
    for (final StreamingMode streamingMode in modesToRecord) {
      out.writeln(
        '\nRecording conformance fixtures for streaming mode ${_conformanceStreamingModeName(streamingMode)}...',
      );
      for (final _ConformanceTestCase testCase in testCases) {
        try {
          await _recordConformanceCase(
            client,
            testCase,
            userId: command.userId,
            streamingMode: streamingMode,
          );
          out.writeln(
            'Generated conformance test files for: ${testCase.category}/${testCase.name} (${_conformanceStreamingModeName(streamingMode)})',
          );
        } on Exception catch (error) {
          out.writeln(
            'Failed to generate ${testCase.category}/${testCase.name} (${_conformanceStreamingModeName(streamingMode)}): $error',
          );
        }
      }
    }
  } finally {
    await client.close();
  }

  out.writeln('\nConformance test generation complete!');
}

Future<void> _recordConformanceCase(
  AdkWebServerClient client,
  _ConformanceTestCase testCase, {
  required String userId,
  required StreamingMode streamingMode,
}) async {
  final File generatedSessionFile = File(
    '${testCase.dir.path}${Platform.pathSeparator}${_conformanceSessionFileName(streamingMode)}',
  );
  final File generatedRecordingsFile = File(
    '${testCase.dir.path}${Platform.pathSeparator}${_conformanceRecordingsFileName(streamingMode)}',
  );
  if (await generatedSessionFile.exists()) {
    await generatedSessionFile.delete();
  }
  if (await generatedRecordingsFile.exists()) {
    await generatedRecordingsFile.delete();
  }

  final Map<String, Object?> session = await client.createSession(
    appName: testCase.spec.agent,
    userId: userId,
    state: testCase.spec.initialState,
  );
  final String sessionId =
      _extractSessionIdFromCreateSession(session) ??
      (throw StateError('Failed to create session id for conformance record.'));

  final Map<String, String> functionCallNameToId = <String, String>{};
  for (
    int userMessageIndex = 0;
    userMessageIndex < testCase.spec.userMessages.length;
    userMessageIndex += 1
  ) {
    final _ConformanceUserMessage userMessage =
        testCase.spec.userMessages[userMessageIndex];
    final Map<String, Object?> stateDelta = <String, Object?>{
      if (userMessage.stateDelta != null) ...userMessage.stateDelta!,
      '_adk_recordings_config': <String, Object?>{
        'dir': testCase.dir.path,
        'user_message_index': userMessageIndex,
        'streaming_mode': _conformanceStreamingModeName(streamingMode),
      },
    };
    final List<Map<String, Object?>> events = await client.runAgentSse(
      appName: testCase.spec.agent,
      userId: userId,
      sessionId: sessionId,
      newMessage: _buildConformanceRunMessage(
        userMessage,
        functionCallNameToId,
      ),
      stateDelta: stateDelta,
      streaming: streamingMode == StreamingMode.sse,
    );
    _updateConformanceFunctionCallNameToIdMap(events, functionCallNameToId);
  }

  final Map<String, Object?> updatedSession = await client.getSession(
    appName: testCase.spec.agent,
    userId: userId,
    sessionId: sessionId,
  );

  final Map<String, Object?> sanitizedSession = _sanitizeConformanceSessionMap(
    updatedSession,
    keepEvents: true,
  );
  dumpPydanticToYaml(
    sanitizedSession,
    generatedSessionFile.path,
    sortKeys: false,
  );
}

Object? _buildConformanceRunMessage(
  _ConformanceUserMessage userMessage,
  Map<String, String> functionCallNameToId,
) {
  if (userMessage.content != null) {
    final Object? clonedContent = _deepCloneJsonValue(userMessage.content);
    if (clonedContent is! Map) {
      return userMessage.content;
    }
    final Map<String, Object?> content = clonedContent.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    if (content['parts'] is! List) {
      return content;
    }
    final List<Object?> parts = List<Object?>.from(content['parts']! as List);
    if (parts.isEmpty || parts.first is! Map) {
      return content;
    }
    final Map<String, Object?> firstPart = (parts.first as Map).map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    final Map<String, Object?> functionResponse = _asObjectMap(
      firstPart['function_response'] ?? firstPart['functionResponse'],
    );
    final String? functionName = _emptyToNull(
      '${functionResponse['name'] ?? ''}',
    );
    if (functionName == null) {
      return content;
    }
    final String? functionCallId = functionCallNameToId[functionName];
    if (functionCallId == null) {
      throw StateError(
        'Function response for $functionName does not match any pending function call.',
      );
    }
    functionResponse['id'] = functionCallId;
    firstPart['function_response'] = functionResponse;
    firstPart['functionResponse'] = functionResponse;
    parts[0] = firstPart;
    content['parts'] = parts;
    return content;
  }
  if (userMessage.text != null) {
    return userMessage.text;
  }
  return '';
}

Future<List<_ConformanceTestSummary>> _runConformanceTest(
  _ParsedConformanceTestCommand command, {
  required IOSink out,
}) async {
  out.writeln('==================================================');
  out.writeln('Running ADK conformance tests in ${command.mode} mode...');
  out.writeln('==================================================');

  final List<StreamingMode> modesToRun = command.streamingMode == null
      ? _supportedConformanceStreamingModes
      : <StreamingMode>[command.streamingMode!];

  final AdkWebServerClient client = AdkWebServerClient(command.baseUri);
  final List<_ConformanceTestSummary> summaries = <_ConformanceTestSummary>[];
  Map<String, Object?> versionData = <String, Object?>{};
  try {
    for (final StreamingMode streamingMode in modesToRun) {
      final List<_ConformanceTestCase> testCases =
          await _discoverConformanceCases(
            command.paths,
            out: out,
            replayMode: command.mode == 'replay',
            streamingMode: streamingMode,
          );
      if (testCases.isEmpty) {
        out.writeln('No test cases found!');
        final _ConformanceTestSummary emptySummary = _ConformanceTestSummary(
          totalTests: 0,
          passedTests: 0,
          failedTests: 0,
          results: <_ConformanceCaseResult>[],
          streamingMode: streamingMode,
        );
        summaries.add(emptySummary);
        continue;
      }

      out.writeln(
        '\nFound ${testCases.length} test cases to run in ${command.mode} mode for streaming mode ${_conformanceStreamingModeName(streamingMode)}.',
      );

      final List<_ConformanceCaseResult> results = <_ConformanceCaseResult>[];
      for (final _ConformanceTestCase testCase in testCases) {
        out.write('Running ${testCase.category}/${testCase.name}...');
        late final _ConformanceCaseResult result;
        if (command.mode == 'replay') {
          result = await _runConformanceReplayCase(
            client,
            testCase,
            userId: command.userId,
            streamingMode: streamingMode,
          );
        } else if (command.mode == 'live') {
          result = await _runConformanceLiveCase(
            client,
            testCase,
            userId: command.userId,
            streamingMode: streamingMode,
          );
        } else {
          result = _ConformanceCaseResult(
            category: testCase.category,
            name: testCase.name,
            success: false,
            errorMessage: 'Unsupported conformance mode: ${command.mode}',
            description: testCase.spec.description,
          );
        }
        results.add(result);
        if (result.success) {
          out.writeln(' PASS');
        } else {
          out.writeln(' FAIL');
          if (result.errorMessage != null &&
              result.errorMessage!.trim().isNotEmpty) {
            out.writeln('Error: ${result.errorMessage}');
          }
        }
      }

      final int passed = results.where((item) => item.success).length;
      summaries.add(
        _ConformanceTestSummary(
          totalTests: results.length,
          passedTests: passed,
          failedTests: results.length - passed,
          results: results,
          streamingMode: streamingMode,
        ),
      );
    }
    try {
      versionData = await client.getVersionData();
    } on Exception {
      versionData = <String, Object?>{};
    }
  } finally {
    await client.close();
  }

  _printConformanceSummary(summaries, out: out);

  if (command.generateReport) {
    final String reportPath = await _writeConformanceMarkdownReport(
      summaries,
      reportDir: command.reportDir,
      versionData: versionData,
    );
    out.writeln('Conformance report written to $reportPath');
  }
  return summaries;
}

Future<_ConformanceCaseResult> _runConformanceLiveCase(
  AdkWebServerClient client,
  _ConformanceTestCase testCase, {
  required String userId,
  required StreamingMode streamingMode,
}) async {
  String? sessionId;
  try {
    final Map<String, Object?> session = await client.createSession(
      appName: testCase.spec.agent,
      userId: userId,
      state: testCase.spec.initialState,
    );
    sessionId =
        _extractSessionIdFromCreateSession(session) ??
        (throw StateError('Failed to create session id for conformance test.'));
    final Map<String, String> functionCallNameToId = <String, String>{};
    for (final _ConformanceUserMessage userMessage
        in testCase.spec.userMessages) {
      final Map<String, Object?> stateDelta = <String, Object?>{
        if (userMessage.stateDelta != null) ...userMessage.stateDelta!,
      };
      final List<Map<String, Object?>> events = await client.runAgentSse(
        appName: testCase.spec.agent,
        userId: userId,
        sessionId: sessionId,
        newMessage: _buildConformanceRunMessage(
          userMessage,
          functionCallNameToId,
        ),
        stateDelta: stateDelta.isEmpty ? null : stateDelta,
        streaming: streamingMode == StreamingMode.sse,
      );
      _updateConformanceFunctionCallNameToIdMap(events, functionCallNameToId);
    }

    return _ConformanceCaseResult(
      category: testCase.category,
      name: testCase.name,
      success: true,
      description: testCase.spec.description,
    );
  } on Exception catch (error) {
    return _ConformanceCaseResult(
      category: testCase.category,
      name: testCase.name,
      success: false,
      errorMessage: 'Live execution failed: $error',
      description: testCase.spec.description,
    );
  } finally {
    if (sessionId != null) {
      try {
        await client.deleteSession(
          appName: testCase.spec.agent,
          userId: userId,
          sessionId: sessionId,
        );
      } on Exception {
        // Best effort cleanup.
      }
    }
  }
}

Future<_ConformanceCaseResult> _runConformanceReplayCase(
  AdkWebServerClient client,
  _ConformanceTestCase testCase, {
  required String userId,
  required StreamingMode streamingMode,
}) async {
  final File sessionFile = File(
    '${testCase.dir.path}${Platform.pathSeparator}${_conformanceSessionFileName(streamingMode)}',
  );
  if (!await sessionFile.exists()) {
    return _ConformanceCaseResult(
      category: testCase.category,
      name: testCase.name,
      success: false,
      errorMessage: 'No recorded session found for replay comparison',
      description: testCase.spec.description,
    );
  }

  String? sessionId;
  try {
    final Map<String, Object?> session = await client.createSession(
      appName: testCase.spec.agent,
      userId: userId,
      state: testCase.spec.initialState,
    );
    sessionId =
        _extractSessionIdFromCreateSession(session) ??
        (throw StateError('Failed to create session id for conformance test.'));
    final Map<String, String> functionCallNameToId = <String, String>{};
    for (
      int userMessageIndex = 0;
      userMessageIndex < testCase.spec.userMessages.length;
      userMessageIndex += 1
    ) {
      final _ConformanceUserMessage userMessage =
          testCase.spec.userMessages[userMessageIndex];
      final Map<String, Object?> stateDelta = <String, Object?>{
        if (userMessage.stateDelta != null) ...userMessage.stateDelta!,
        '_adk_replay_config': <String, Object?>{
          'dir': testCase.dir.path,
          'user_message_index': userMessageIndex,
          'streaming_mode': _conformanceStreamingModeName(streamingMode),
        },
      };
      final List<Map<String, Object?>> events = await client.runAgentSse(
        appName: testCase.spec.agent,
        userId: userId,
        sessionId: sessionId,
        newMessage: _buildConformanceRunMessage(
          userMessage,
          functionCallNameToId,
        ),
        stateDelta: stateDelta,
        streaming: streamingMode == StreamingMode.sse,
      );
      _updateConformanceFunctionCallNameToIdMap(events, functionCallNameToId);
    }

    final Map<String, Object?> finalSession = await client.getSession(
      appName: testCase.spec.agent,
      userId: userId,
      sessionId: sessionId,
    );
    final Object? recordedRaw = loadYamlFile(sessionFile.path);
    if (recordedRaw is! Map) {
      return _ConformanceCaseResult(
        category: testCase.category,
        name: testCase.name,
        success: false,
        errorMessage: 'Recorded session file format is invalid.',
        description: testCase.spec.description,
      );
    }
    final Map<String, Object?> recordedSession = recordedRaw.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );

    final List<Map<String, Object?>> actualEvents = _readMapList(
      finalSession['events'],
    );
    final List<Map<String, Object?>> recordedEvents = _readMapList(
      recordedSession['events'],
    );
    if (actualEvents.length != recordedEvents.length) {
      return _ConformanceCaseResult(
        category: testCase.category,
        name: testCase.name,
        success: false,
        errorMessage:
            'Event count mismatch - Actual: ${actualEvents.length}, Recorded: ${recordedEvents.length}',
        description: testCase.spec.description,
      );
    }

    for (int i = 0; i < actualEvents.length; i += 1) {
      final Map<String, Object?> normalizedActual =
          _sanitizeConformanceEventMap(actualEvents[i]);
      final Map<String, Object?> normalizedRecorded =
          _sanitizeConformanceEventMap(recordedEvents[i]);
      if (!_deepMapEquals(normalizedActual, normalizedRecorded)) {
        return _ConformanceCaseResult(
          category: testCase.category,
          name: testCase.name,
          success: false,
          errorMessage: _conformanceMismatchMessage(
            context: 'event $i',
            actual: normalizedActual,
            recorded: normalizedRecorded,
          ),
          description: testCase.spec.description,
        );
      }
    }

    final Map<String, Object?> normalizedSession =
        _sanitizeConformanceSessionMap(finalSession);
    final Map<String, Object?> normalizedRecordedSession =
        _sanitizeConformanceSessionMap(recordedSession);
    if (!_deepMapEquals(normalizedSession, normalizedRecordedSession)) {
      return _ConformanceCaseResult(
        category: testCase.category,
        name: testCase.name,
        success: false,
        errorMessage: _conformanceMismatchMessage(
          context: 'session',
          actual: normalizedSession,
          recorded: normalizedRecordedSession,
        ),
        description: testCase.spec.description,
      );
    }

    return _ConformanceCaseResult(
      category: testCase.category,
      name: testCase.name,
      success: true,
      description: testCase.spec.description,
    );
  } on Exception catch (error) {
    return _ConformanceCaseResult(
      category: testCase.category,
      name: testCase.name,
      success: false,
      errorMessage: 'Replay verification failed: $error',
      description: testCase.spec.description,
    );
  } finally {
    if (sessionId != null) {
      try {
        await client.deleteSession(
          appName: testCase.spec.agent,
          userId: userId,
          sessionId: sessionId,
        );
      } on Exception {
        // Best effort cleanup.
      }
    }
  }
}

void _printConformanceSummary(
  List<_ConformanceTestSummary> summaries, {
  required IOSink out,
}) {
  for (final _ConformanceTestSummary summary in summaries) {
    out.writeln('\n==================================================');
    out.writeln(
      'CONFORMANCE TEST SUMMARY FOR STREAMING MODE: ${_conformanceStreamingModeName(summary.streamingMode)}',
    );
    out.writeln('==================================================');
    if (summary.totalTests == 0) {
      out.writeln('No tests were run.');
      continue;
    }
    out.writeln('Total tests: ${summary.totalTests}');
    out.writeln('Passed: ${summary.passedTests}');
    out.writeln('Failed: ${summary.failedTests}');
    out.writeln('Success rate: ${summary.successRate.toStringAsFixed(1)}%');

    if (summary.failedTests == 0) {
      out.writeln('\nAll tests passed.');
      continue;
    }

    out.writeln('\nFailed tests:');
    for (final _ConformanceCaseResult result in summary.results) {
      if (result.success) {
        continue;
      }
      out.writeln('\n${result.category}/${result.name}');
      if (result.errorMessage != null &&
          result.errorMessage!.trim().isNotEmpty) {
        out.writeln(result.errorMessage!);
      }
    }
  }
}

Future<String> _writeConformanceMarkdownReport(
  List<_ConformanceTestSummary> summaries, {
  required String? reportDir,
  required Map<String, Object?> versionData,
}) async {
  final Directory targetDir = Directory(
    reportDir ?? Directory.current.path,
  ).absolute;
  await targetDir.create(recursive: true);
  final String serverVersion =
      _emptyToNull('${versionData['server_version'] ?? ''}') ?? 'unknown';
  final String reportName =
      'python_${serverVersion.replaceAll('.', '_')}_report.md';
  final String outputPath =
      '${targetDir.path}${Platform.pathSeparator}$reportName';

  final StringBuffer out = StringBuffer();
  out.writeln('# ADK Conformance Report');
  out.writeln();
  if (versionData.isNotEmpty) {
    out.writeln('## Version');
    for (final MapEntry<String, Object?> entry in versionData.entries) {
      out.writeln('- ${entry.key}: ${entry.value}');
    }
    out.writeln();
  }
  out.writeln('## Summary');
  out.writeln('| Streaming Mode | Total | Passed | Failed | Success Rate |');
  out.writeln('| --- | --- | --- | --- | --- |');
  for (final _ConformanceTestSummary summary in summaries) {
    out.writeln(
      '| ${_conformanceStreamingModeName(summary.streamingMode)} | ${summary.totalTests} | ${summary.passedTests} | ${summary.failedTests} | ${summary.successRate.toStringAsFixed(1)}% |',
    );
  }
  out.writeln();
  out.writeln('## Results');
  final List<String> modeNames = summaries
      .map(
        (_ConformanceTestSummary summary) =>
            _conformanceStreamingModeName(summary.streamingMode),
      )
      .toList(growable: false);
  final Map<String, Map<String, _ConformanceCaseResult>> byCase =
      <String, Map<String, _ConformanceCaseResult>>{};
  for (final _ConformanceTestSummary summary in summaries) {
    final String modeName = _conformanceStreamingModeName(
      summary.streamingMode,
    );
    for (final _ConformanceCaseResult result in summary.results) {
      final String testName = '${result.category}/${result.name}';
      byCase.putIfAbsent(
        testName,
        () => <String, _ConformanceCaseResult>{},
      )[modeName] = result;
    }
  }
  out.writeln('| Test | Description | ${modeNames.join(' | ')} |');
  out.writeln(
    '| --- | --- | ${List<String>.filled(modeNames.length, '---').join(' | ')} |',
  );
  final List<String> sortedCaseNames = byCase.keys.toList()..sort();
  for (final String testName in sortedCaseNames) {
    final Map<String, _ConformanceCaseResult> resultsByMode = byCase[testName]!;
    final String description = (resultsByMode.values.first.description ?? '')
        .replaceAll('|', r'\|');
    final List<String> statuses = modeNames
        .map((String modeName) {
          final _ConformanceCaseResult? result = resultsByMode[modeName];
          if (result == null) {
            return 'N/A';
          }
          return result.success ? 'PASS' : 'FAIL';
        })
        .toList(growable: false);
    out.writeln('| $testName | $description | ${statuses.join(' | ')} |');
  }

  final bool hasFailures = summaries.any(
    (_ConformanceTestSummary summary) => summary.failedTests > 0,
  );
  if (hasFailures) {
    out.writeln();
    out.writeln('## Failed Test Details');
    for (final _ConformanceTestSummary summary in summaries) {
      final String modeName = _conformanceStreamingModeName(
        summary.streamingMode,
      );
      for (final _ConformanceCaseResult result in summary.results) {
        if (result.success) {
          continue;
        }
        out.writeln();
        out.writeln('### ${result.category}/${result.name} ($modeName)');
        if (result.description != null &&
            result.description!.trim().isNotEmpty) {
          out.writeln();
          out.writeln('Description: ${result.description}');
        }
        if (result.errorMessage != null &&
            result.errorMessage!.trim().isNotEmpty) {
          out.writeln();
          out.writeln('```');
          out.writeln(result.errorMessage!.replaceAll('```', r'\`\`\`'));
          out.writeln('```');
        }
      }
    }
  }

  await File(outputPath).writeAsString(out.toString().trimRight());
  return outputPath;
}

Object? _deepCloneJsonValue(Object? value) {
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) =>
          MapEntry('$key', _deepCloneJsonValue(item)),
    );
  }
  if (value is List) {
    return value
        .map((Object? item) => _deepCloneJsonValue(item))
        .toList(growable: false);
  }
  return value;
}

void _updateConformanceFunctionCallNameToIdMap(
  Iterable<Map<String, Object?>> events,
  Map<String, String> functionCallNameToId,
) {
  for (final Map<String, Object?> event in events) {
    final Map<String, Object?> content = _asObjectMap(event['content']);
    final Object? rawParts = content['parts'];
    if (rawParts is! List) {
      continue;
    }
    for (final Object? rawPart in rawParts) {
      if (rawPart is! Map) {
        continue;
      }
      final Map<String, Object?> part = rawPart.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final Map<String, Object?> functionCall = _asObjectMap(
        part['function_call'] ?? part['functionCall'],
      );
      final String? name = _emptyToNull('${functionCall['name'] ?? ''}');
      final String? id = _emptyToNull('${functionCall['id'] ?? ''}');
      if (name == null || id == null) {
        continue;
      }
      functionCallNameToId[name] = id;
    }
  }
}

Future<List<_ConformanceTestCase>> _discoverConformanceCases(
  List<String> rawPaths, {
  required IOSink out,
  required bool replayMode,
  required StreamingMode streamingMode,
}) async {
  final List<String> paths = rawPaths.isEmpty ? <String>['tests'] : rawPaths;
  final List<_ConformanceTestCase> testCases = <_ConformanceTestCase>[];

  for (final String rawPath in paths) {
    final String normalized = rawPath.trim();
    if (normalized.isEmpty) {
      continue;
    }
    final Directory dir = Directory(normalized).absolute;
    if (!await dir.exists()) {
      out.writeln('Invalid path: $normalized');
      continue;
    }

    await for (final FileSystemEntity entity in dir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final String fileName = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      if (fileName != 'spec.yaml') {
        continue;
      }
      final Directory caseDir = entity.parent.absolute;
      final String category = projectDirName(caseDir.parent.path);
      final String name = projectDirName(caseDir.path);
      if (replayMode) {
        final File recordingsFile = File(
          '${caseDir.path}${Platform.pathSeparator}${_conformanceRecordingsFileName(streamingMode)}',
        );
        if (!await recordingsFile.exists()) {
          out.writeln('Skipping $category/$name: no recordings');
          continue;
        }
      }
      try {
        final _ConformanceTestSpec spec = _loadConformanceSpec(entity.path);
        testCases.add(
          _ConformanceTestCase(
            category: category,
            name: name,
            dir: caseDir,
            spec: spec,
          ),
        );
        if (!replayMode) {
          out.writeln('Loaded test spec: $category/$name');
        }
      } on Exception catch (error) {
        out.writeln('Failed to load ${entity.path}: $error');
      }
    }
  }

  testCases.sort((a, b) {
    final int categoryCompare = a.category.compareTo(b.category);
    if (categoryCompare != 0) {
      return categoryCompare;
    }
    return a.name.compareTo(b.name);
  });
  return testCases;
}

_ConformanceTestSpec _loadConformanceSpec(String specFilePath) {
  final Object? decoded = loadYamlFile(specFilePath);
  if (decoded is! Map) {
    throw const FormatException('spec.yaml must contain a YAML mapping.');
  }
  final Map<String, Object?> map = decoded.map(
    (Object? key, Object? value) => MapEntry('$key', value),
  );
  final String description = (map['description'] ?? '').toString();
  final String agent = (map['agent'] ?? '').toString().trim();
  if (agent.isEmpty) {
    throw const FormatException('spec.yaml must include a non-empty `agent`.');
  }

  final Map<String, Object?> initialState = _asObjectMap(map['initial_state']);
  final List<_ConformanceUserMessage> userMessages =
      <_ConformanceUserMessage>[];
  final Object? rawMessages = map['user_messages'];
  if (rawMessages is List) {
    for (int i = 0; i < rawMessages.length; i += 1) {
      final Object? raw = rawMessages[i];
      if (raw is! Map) {
        throw FormatException('user_messages[$i] must be a map.');
      }
      final Map<String, Object?> message = raw.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final String? text = _emptyToNull('${message['text'] ?? ''}');
      final Map<String, Object?>? content = message['content'] is Map
          ? _asObjectMap(message['content'])
          : null;
      final Map<String, Object?>? stateDelta = message['state_delta'] is Map
          ? _asObjectMap(message['state_delta'])
          : null;
      if (text == null && (content == null || content.isEmpty)) {
        throw FormatException(
          'user_messages[$i] must have either `text` or `content`.',
        );
      }
      userMessages.add(
        _ConformanceUserMessage(
          text: text,
          content: content,
          stateDelta: stateDelta,
        ),
      );
    }
  }

  return _ConformanceTestSpec(
    description: description,
    agent: agent,
    initialState: initialState,
    userMessages: userMessages,
  );
}

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is! Map) {
    return <String, Object?>{};
  }
  return value.map((Object? key, Object? item) => MapEntry('$key', item));
}

List<Map<String, Object?>> _readMapList(Object? value) {
  if (value is! List) {
    return <Map<String, Object?>>[];
  }
  return value
      .whereType<Map>()
      .map(
        (Map item) =>
            item.map((Object? key, Object? value) => MapEntry('$key', value)),
      )
      .toList(growable: false);
}

Map<String, Object?> _sanitizeConformanceEventMap(Map<String, Object?> event) {
  final Map<String, Object?> normalized = _deepCopyMap(event);
  final List<String> eventFieldsToRemove = <String>[
    'id',
    'timestamp',
    'invocation_id',
    'invocationId',
    'session_id',
    'sessionId',
    'long_running_tool_ids',
    'longRunningToolIds',
  ];
  for (final String key in eventFieldsToRemove) {
    normalized.remove(key);
  }

  final Map<String, Object?> content = _asObjectMap(
    normalized['content'] ?? normalized['final_response'],
  );
  final List<Map<String, Object?>> parts = _readMapList(content['parts']);
  for (final Map<String, Object?> part in parts) {
    part.remove('thought_signature');
    part.remove('thoughtSignature');
    final Map<String, Object?> functionCall = _asObjectMap(
      part['function_call'] ?? part['functionCall'],
    );
    functionCall.remove('id');
    final List<Map<String, Object?>> partialArgs = _readMapList(
      functionCall['partial_args'] ?? functionCall['partialArgs'],
    );
    if (partialArgs.isEmpty) {
      functionCall.remove('partial_args');
      functionCall.remove('partialArgs');
    } else {
      functionCall['partial_args'] = partialArgs;
      functionCall['partialArgs'] = partialArgs;
    }
    if (functionCall.isNotEmpty) {
      part['function_call'] = functionCall;
      part['functionCall'] = functionCall;
    }
    final Map<String, Object?> functionResponse = _asObjectMap(
      part['function_response'] ?? part['functionResponse'],
    );
    functionResponse.remove('id');
    if (functionResponse.isNotEmpty) {
      part['function_response'] = functionResponse;
      part['functionResponse'] = functionResponse;
    }
  }
  if (parts.isNotEmpty) {
    content['parts'] = parts;
    normalized['content'] = content;
  }

  final Map<String, Object?> actions = _asObjectMap(normalized['actions']);
  final Map<String, Object?> stateDelta = _asObjectMap(
    actions['state_delta'] ?? actions['stateDelta'],
  );
  stateDelta.remove('_adk_recordings_config');
  stateDelta.remove('_adk_replay_config');
  if (stateDelta.isNotEmpty) {
    actions['state_delta'] = stateDelta;
    actions['stateDelta'] = stateDelta;
  } else {
    actions.remove('state_delta');
    actions.remove('stateDelta');
  }
  actions.remove('requested_auth_configs');
  actions.remove('requestedAuthConfigs');
  actions.remove('requested_tool_confirmations');
  actions.remove('requestedToolConfirmations');
  if (actions.isNotEmpty) {
    normalized['actions'] = actions;
  } else {
    normalized.remove('actions');
  }
  return normalized;
}

Map<String, Object?> _sanitizeConformanceSessionMap(
  Map<String, Object?> session, {
  bool keepEvents = false,
}) {
  final Map<String, Object?> normalized = _deepCopyMap(session);
  normalized.remove('id');
  normalized.remove('last_update_time');
  normalized.remove('lastUpdateTime');
  if (keepEvents) {
    normalized['events'] = _readMapList(
      normalized['events'],
    ).map(_sanitizeConformanceEventMap).toList(growable: false);
  } else {
    normalized.remove('events');
  }

  final Map<String, Object?> state = _asObjectMap(normalized['state']);
  state.remove('_adk_recordings_config');
  state.remove('_adk_replay_config');
  if (state.isEmpty) {
    normalized.remove('state');
  } else {
    normalized['state'] = state;
  }
  return normalized;
}

Map<String, Object?> _deepCopyMap(Map<String, Object?> input) {
  final Object? normalized = _normalizeJsonForStableHash(input);
  return Map<String, Object?>.from(normalized as Map);
}

bool _deepMapEquals(Map<String, Object?> left, Map<String, Object?> right) {
  return jsonEncode(_normalizeJsonForStableHash(left)) ==
      jsonEncode(_normalizeJsonForStableHash(right));
}

String _conformanceMismatchMessage({
  required String context,
  required Map<String, Object?> actual,
  required Map<String, Object?> recorded,
}) {
  final String actualJson = const JsonEncoder.withIndent(
    '  ',
  ).convert(_normalizeJsonForStableHash(actual));
  final String recordedJson = const JsonEncoder.withIndent(
    '  ',
  ).convert(_normalizeJsonForStableHash(recorded));
  return '$context mismatch -\nActual:\n$actualJson\nRecorded:\n$recordedJson';
}

Future<int> _runMigrateCliCommand(
  List<String> args, {
  required IOSink out,
}) async {
  if (args.isEmpty) {
    throw CliUsageError('Missing migrate subcommand. Supported: session.');
  }
  final String subcommand = args.first;
  if (subcommand != 'session') {
    throw CliUsageError('Unknown migrate subcommand: $subcommand');
  }

  String? sourceDbUrl;
  String? destDbUrl;
  String? logLevel;
  bool verbose = false;
  bool allowUnsafeUnpickling = false;
  for (int i = 1; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--source_db_url') {
      sourceDbUrl = _nextArg(args, i, '--source_db_url');
      i += 1;
      continue;
    }
    if (arg.startsWith('--source_db_url=')) {
      sourceDbUrl = arg.substring('--source_db_url='.length);
      continue;
    }
    if (arg == '--dest_db_url') {
      destDbUrl = _nextArg(args, i, '--dest_db_url');
      i += 1;
      continue;
    }
    if (arg.startsWith('--dest_db_url=')) {
      destDbUrl = arg.substring('--dest_db_url='.length);
      continue;
    }
    if (arg == '--log_level' || arg == '--verbosity') {
      logLevel = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=') || arg.startsWith('--verbosity=')) {
      logLevel = arg.substring(arg.indexOf('=') + 1);
      continue;
    }
    if (arg == '-v' || arg == '--verbose') {
      verbose = true;
      continue;
    }
    if (arg == '--allow-unsafe-unpickling' ||
        arg == '--allow_unsafe_unpickling') {
      allowUnsafeUnpickling = true;
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for migrate session: $arg');
    }
    throw CliUsageError(
      'Unexpected positional argument for migrate session: $arg',
    );
  }

  final String resolvedLogLevel = _resolveCliLogLevel(
    explicit: _emptyToNull(logLevel),
    verbose: verbose,
  );
  cli_logs.setupAdkLogger(level: _toCliLogEnum(resolvedLogLevel));

  final String? normalizedSource = _emptyToNull(sourceDbUrl);
  final String? normalizedDest = _emptyToNull(destDbUrl);
  if (normalizedSource == null) {
    throw CliUsageError('Missing required option --source_db_url.');
  }
  if (normalizedDest == null) {
    throw CliUsageError('Missing required option --dest_db_url.');
  }

  await session_migration.upgrade(
    normalizedSource,
    normalizedDest,
    allowUnsafeUnpickling: allowUnsafeUnpickling,
  );
  out.writeln('Migration check and upgrade process finished.');
  return 0;
}

_ParsedConformanceRecordCommand _parseConformanceRecordCommand(
  List<String> args,
) {
  final List<String> paths = <String>[];
  String baseUrl = 'http://127.0.0.1:8000';
  String userId = 'adk_conformance_test_user';
  StreamingMode? streamingMode;
  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--base_url') {
      baseUrl = _nextArg(args, i, '--base_url');
      i += 1;
      continue;
    }
    if (arg.startsWith('--base_url=')) {
      baseUrl = arg.substring('--base_url='.length);
      continue;
    }
    if (arg == '--user_id') {
      userId = _nextArg(args, i, '--user_id');
      i += 1;
      continue;
    }
    if (arg.startsWith('--user_id=')) {
      userId = arg.substring('--user_id='.length);
      continue;
    }
    if (arg == '--streaming_mode' || arg == '--streaming-mode') {
      streamingMode = _parseConformanceStreamingMode(_nextArg(args, i, arg));
      i += 1;
      continue;
    }
    if (arg.startsWith('--streaming_mode=')) {
      streamingMode = _parseConformanceStreamingMode(
        arg.substring('--streaming_mode='.length),
      );
      continue;
    }
    if (arg.startsWith('--streaming-mode=')) {
      streamingMode = _parseConformanceStreamingMode(
        arg.substring('--streaming-mode='.length),
      );
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for conformance record: $arg');
    }
    paths.add(arg);
  }
  if (paths.isNotEmpty &&
      streamingMode == null &&
      _looksLikeConformanceStreamingMode(paths.last)) {
    streamingMode = _parseConformanceStreamingMode(paths.removeLast());
  }
  return _ParsedConformanceRecordCommand(
    paths: paths,
    baseUri: Uri.parse(baseUrl),
    userId: _emptyToNull(userId) ?? 'adk_conformance_test_user',
    streamingMode: streamingMode,
  );
}

_ParsedConformanceTestCommand _parseConformanceTestCommand(List<String> args) {
  final List<String> paths = <String>[];
  String baseUrl = 'http://127.0.0.1:8000';
  String userId = 'adk_conformance_test_user';
  String mode = 'replay';
  bool generateReport = false;
  String? reportDir;
  StreamingMode? streamingMode;

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--base_url') {
      baseUrl = _nextArg(args, i, '--base_url');
      i += 1;
      continue;
    }
    if (arg.startsWith('--base_url=')) {
      baseUrl = arg.substring('--base_url='.length);
      continue;
    }
    if (arg == '--user_id') {
      userId = _nextArg(args, i, '--user_id');
      i += 1;
      continue;
    }
    if (arg.startsWith('--user_id=')) {
      userId = arg.substring('--user_id='.length);
      continue;
    }
    if (arg == '--mode') {
      mode = _nextArg(args, i, '--mode');
      i += 1;
      continue;
    }
    if (arg.startsWith('--mode=')) {
      mode = arg.substring('--mode='.length);
      continue;
    }
    if (arg == '--generate_report') {
      generateReport = true;
      continue;
    }
    if (arg == '--streaming_mode' || arg == '--streaming-mode') {
      streamingMode = _parseConformanceStreamingMode(_nextArg(args, i, arg));
      i += 1;
      continue;
    }
    if (arg.startsWith('--streaming_mode=')) {
      streamingMode = _parseConformanceStreamingMode(
        arg.substring('--streaming_mode='.length),
      );
      continue;
    }
    if (arg.startsWith('--streaming-mode=')) {
      streamingMode = _parseConformanceStreamingMode(
        arg.substring('--streaming-mode='.length),
      );
      continue;
    }
    if (arg == '--report_dir') {
      reportDir = _nextArg(args, i, '--report_dir');
      i += 1;
      continue;
    }
    if (arg.startsWith('--report_dir=')) {
      reportDir = arg.substring('--report_dir='.length);
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for conformance test: $arg');
    }
    paths.add(arg);
  }
  final String normalizedMode = mode.trim().toLowerCase();
  if (normalizedMode != 'replay' && normalizedMode != 'live') {
    throw CliUsageError('Invalid conformance mode: $mode');
  }
  return _ParsedConformanceTestCommand(
    paths: paths,
    baseUri: Uri.parse(baseUrl),
    userId: _emptyToNull(userId) ?? 'adk_conformance_test_user',
    mode: normalizedMode,
    generateReport: generateReport,
    reportDir: _emptyToNull(reportDir),
    streamingMode: streamingMode,
  );
}

bool _looksLikeConformanceStreamingMode(String value) {
  final String normalized = value.trim().toLowerCase();
  return normalized == 'none' || normalized == 'sse';
}

StreamingMode _parseConformanceStreamingMode(String value) {
  switch (value.trim().toLowerCase()) {
    case 'none':
      return StreamingMode.none;
    case 'sse':
      return StreamingMode.sse;
    default:
      throw CliUsageError('Invalid conformance streaming mode: $value');
  }
}

String _conformanceStreamingModeName(StreamingMode mode) {
  switch (mode) {
    case StreamingMode.none:
      return 'none';
    case StreamingMode.sse:
      return 'sse';
    case StreamingMode.bidi:
      return 'bidi';
  }
}

String _conformanceSessionFileName(StreamingMode mode) {
  return mode == StreamingMode.sse
      ? 'generated-session-sse.yaml'
      : 'generated-session.yaml';
}

String _conformanceRecordingsFileName(StreamingMode mode) {
  return mode == StreamingMode.sse
      ? 'generated-recordings-sse.yaml'
      : 'generated-recordings.yaml';
}

String? _extractSessionIdFromCreateSession(Map<String, Object?> response) {
  final Object? nestedSession = response['session'];
  if (nestedSession is Map) {
    final Map<String, Object?> session = nestedSession.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    final String? fromNested = _extractSessionIdFromCreateSession(session);
    if (fromNested != null) {
      return fromNested;
    }
  }

  final Object? raw =
      response['id'] ?? response['session_id'] ?? response['sessionId'];
  if (raw == null) {
    return null;
  }
  final String value = '$raw'.trim();
  return value.isEmpty ? null : value;
}
