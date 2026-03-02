import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../agents/base_agent.dart';
import '../apps/app.dart';
import '../auth/credential_service/in_memory_credential_service.dart';
import '../cli/cli_deploy.dart';
import '../cli/cli_eval.dart' as cli_eval;
import '../cli/conformance/adk_web_server_client.dart';
import '../runners/runner.dart';
import '../events/event.dart';
import '../sessions/session.dart';
import '../sessions/schemas/v0.dart';
import '../sessions/migration/migration_runner.dart' as session_migration;
import '../types/content.dart';
import '../cli/service_registry.dart';
import '../cli/utils/agent_loader.dart';
import '../cli/utils/base_agent_loader.dart';
import '../cli/utils/evals.dart' as cli_evals;
import '../cli/utils/service_factory.dart';
import '../evaluation/base_eval_service.dart';
import '../evaluation/conversation_scenarios.dart';
import '../evaluation/eval_case.dart';
import '../evaluation/eval_metric.dart';
import '../evaluation/eval_result.dart';
import '../evaluation/eval_set.dart';
import '../evaluation/eval_set_results_manager.dart';
import '../evaluation/eval_sets_manager.dart';
import '../evaluation/in_memory_eval_set_results_manager.dart';
import '../evaluation/in_memory_eval_sets_manager.dart';
import '../evaluation/local_eval_service.dart';
import '../evaluation/local_eval_set_results_manager.dart';
import '../evaluation/local_eval_sets_manager.dart'
    show LocalEvalSetsManager, loadEvalSetFromFile;
import '../utils/yaml_utils.dart';
import 'project.dart';
import 'runtime.dart';
import 'web_server.dart';

const String adkUsage = '''
Usage: adk <command> [options]

Commands:
  create <project_dir>  Create a new ADK Dart project scaffold.
  run <project_dir>     Run an interactive CLI chat session.
  web [project_dir]     Start the ADK dev web server.
  deploy                Deploy app using gcloud command execution.
  eval                  Evaluate an agent against eval sets.
  eval_set              Manage eval sets.
  conformance           Conformance record/test helpers.
  migrate session       Migrate session DB schema.
  api_server [project_dir]
                       Start the ADK API server (alias of `web`).

Create options:
      --app-name        Logical app name (default: directory name)

Run options:
      --user-id         User id (default: from adk.json or "user")
      --session_id      Reuse a session id (default: auto-generated)
      --session_service_uri
      --artifact_service_uri
      --memory_service_uri
      --use_local_storage / --no_use_local_storage
      --save_session    Save session snapshot on exit
      --resume          Resume from a saved session snapshot json file
      --replay          Replay session input file json (state + queries)
  -m, --message         Single message mode (no interactive prompt)

Web options:
  -p, --port            Port to bind (default: 8000)
      --host            Host to bind (default: 127.0.0.1)
      --user-id         User id used by default web session
      --allow_origins   CORS origins (repeatable, supports regex: prefix)
      --url_prefix      URL prefix (example: /adk)
      --session_service_uri
      --artifact_service_uri
      --memory_service_uri
      --eval_storage_uri
      --use_local_storage / --no_use_local_storage
      --auto_create_session
      --trace_to_cloud
      --otel_to_cloud
      --reload / --no-reload
      --reload_agents
      --a2a
      --extra_plugins
      --logo-text
      --logo-image-url
  -v, --verbose         Enable verbose logging (parsed for parity)
  -h, --help            Show this help message.
''';

class CliUsageError implements Exception {
  CliUsageError(this.message);

  final String message;

  @override
  String toString() => message;
}

enum AdkCommandType { create, run, web }

class ParsedAdkCommand {
  ParsedAdkCommand.create({required this.projectDir, this.appName})
    : type = AdkCommandType.create,
      port = null,
      host = null,
      userId = null,
      allowOrigins = const <String>[],
      sessionServiceUri = null,
      artifactServiceUri = null,
      memoryServiceUri = null,
      evalStorageUri = null,
      useLocalStorage = true,
      urlPrefix = null,
      traceToCloud = false,
      otelToCloud = false,
      reload = true,
      a2a = false,
      reloadAgents = false,
      extraPlugins = const <String>[],
      logoText = null,
      logoImageUrl = null,
      autoCreateSession = false,
      enableWebUi = true,
      sessionId = null,
      saveSession = false,
      resumeFilePath = null,
      replayFilePath = null,
      message = null,
      usedDeprecatedSessionDbUrl = false,
      usedDeprecatedArtifactStorageUri = false;

  ParsedAdkCommand.run({
    required this.projectDir,
    this.userId,
    this.sessionId,
    this.sessionServiceUri,
    this.artifactServiceUri,
    this.memoryServiceUri,
    required this.useLocalStorage,
    required this.saveSession,
    this.resumeFilePath,
    this.replayFilePath,
    this.message,
  }) : type = AdkCommandType.run,
       appName = null,
       port = null,
       host = null,
       allowOrigins = const <String>[],
       evalStorageUri = null,
       urlPrefix = null,
       traceToCloud = false,
       otelToCloud = false,
       reload = true,
       a2a = false,
       reloadAgents = false,
       extraPlugins = const <String>[],
       logoText = null,
       logoImageUrl = null,
       autoCreateSession = false,
       enableWebUi = true,
       usedDeprecatedSessionDbUrl = false,
       usedDeprecatedArtifactStorageUri = false;

  ParsedAdkCommand.web({
    required this.projectDir,
    required this.port,
    required this.host,
    this.userId,
    required this.allowOrigins,
    this.sessionServiceUri,
    this.artifactServiceUri,
    this.memoryServiceUri,
    this.evalStorageUri,
    required this.useLocalStorage,
    this.urlPrefix,
    required this.traceToCloud,
    required this.otelToCloud,
    required this.reload,
    required this.a2a,
    required this.reloadAgents,
    required this.extraPlugins,
    this.logoText,
    this.logoImageUrl,
    required this.autoCreateSession,
    required this.enableWebUi,
    required this.usedDeprecatedSessionDbUrl,
    required this.usedDeprecatedArtifactStorageUri,
  }) : type = AdkCommandType.web,
       appName = null,
       sessionId = null,
       saveSession = false,
       resumeFilePath = null,
       replayFilePath = null,
       message = null;

  final AdkCommandType type;
  final String projectDir;
  final String? appName;
  final int? port;
  final InternetAddress? host;
  final String? userId;
  final List<String> allowOrigins;
  final String? sessionServiceUri;
  final String? artifactServiceUri;
  final String? memoryServiceUri;
  final String? evalStorageUri;
  final bool useLocalStorage;
  final String? urlPrefix;
  final bool traceToCloud;
  final bool otelToCloud;
  final bool reload;
  final bool a2a;
  final bool reloadAgents;
  final List<String> extraPlugins;
  final String? logoText;
  final String? logoImageUrl;
  final bool autoCreateSession;
  final bool enableWebUi;
  final String? sessionId;
  final bool saveSession;
  final String? resumeFilePath;
  final String? replayFilePath;
  final String? message;
  final bool usedDeprecatedSessionDbUrl;
  final bool usedDeprecatedArtifactStorageUri;
}

ParsedAdkCommand parseAdkCliArgs(List<String> args) {
  if (args.isEmpty) {
    throw CliUsageError('Missing command.');
  }

  final String command = args.first;
  final List<String> commandArgs = args.skip(1).toList(growable: false);

  switch (command) {
    case 'create':
      return _parseCreateCommand(commandArgs);
    case 'run':
      return _parseRunCommand(commandArgs);
    case 'web':
      return _parseWebCommand(commandArgs, enableWebUi: true);
    case 'api_server':
      return _parseWebCommand(commandArgs, enableWebUi: false);
    default:
      throw CliUsageError('Unknown command: $command');
  }
}

Future<int> runAdkCli(
  List<String> args, {
  IOSink? outSink,
  IOSink? errSink,
}) async {
  final IOSink out = outSink ?? stdout;
  final IOSink err = errSink ?? stderr;

  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    out.writeln(adkUsage);
    return 0;
  }

  if (args.length > 1 && (args[1] == '-h' || args[1] == '--help')) {
    out.writeln(adkUsage);
    return 0;
  }

  if (args.first == 'deploy') {
    return runDeployCommand(
      args.skip(1).toList(growable: false),
      outSink: out,
      errSink: err,
      environment: Platform.environment,
    );
  }

  if (args.first == 'eval') {
    try {
      return await _runEvalCliCommand(
        args.skip(1).toList(growable: false),
        out: out,
      );
    } on CliUsageError catch (error) {
      err.writeln(error.message);
      err.writeln('');
      err.writeln(adkUsage);
      return 64;
    } on FileSystemException catch (error) {
      err.writeln('Filesystem error: $error');
      return 1;
    } on FormatException catch (error) {
      err.writeln('Config parse error: $error');
      return 1;
    } on StateError catch (error) {
      err.writeln('Runtime error: $error');
      return 1;
    } on ArgumentError catch (error) {
      err.writeln('Argument error: $error');
      return 1;
    }
  }

  if (args.first == 'eval_set') {
    try {
      return await _runEvalSetCliCommand(
        args.skip(1).toList(growable: false),
        out: out,
      );
    } on CliUsageError catch (error) {
      err.writeln(error.message);
      err.writeln('');
      err.writeln(adkUsage);
      return 64;
    } on FileSystemException catch (error) {
      err.writeln('Filesystem error: $error');
      return 1;
    } on FormatException catch (error) {
      err.writeln('Config parse error: $error');
      return 1;
    } on StateError catch (error) {
      err.writeln('Runtime error: $error');
      return 1;
    } on ArgumentError catch (error) {
      err.writeln('Argument error: $error');
      return 1;
    }
  }

  if (args.first == 'conformance') {
    try {
      return await _runConformanceCliCommand(
        args.skip(1).toList(growable: false),
        out: out,
      );
    } on CliUsageError catch (error) {
      err.writeln(error.message);
      err.writeln('');
      err.writeln(adkUsage);
      return 64;
    } on FileSystemException catch (error) {
      err.writeln('Filesystem error: $error');
      return 1;
    } on FormatException catch (error) {
      err.writeln('Config parse error: $error');
      return 1;
    } on StateError catch (error) {
      err.writeln('Runtime error: $error');
      return 1;
    } on ArgumentError catch (error) {
      err.writeln('Argument error: $error');
      return 1;
    }
  }

  if (args.first == 'migrate') {
    try {
      return await _runMigrateCliCommand(
        args.skip(1).toList(growable: false),
        out: out,
      );
    } on CliUsageError catch (error) {
      err.writeln(error.message);
      err.writeln('');
      err.writeln(adkUsage);
      return 64;
    } on FileSystemException catch (error) {
      err.writeln('Filesystem error: $error');
      return 1;
    } on FormatException catch (error) {
      err.writeln('Config parse error: $error');
      return 1;
    } on StateError catch (error) {
      err.writeln('Runtime error: $error');
      return 1;
    } on ArgumentError catch (error) {
      err.writeln('Argument error: $error');
      return 1;
    }
  }

  final ParsedAdkCommand parsed;
  try {
    parsed = parseAdkCliArgs(args);
  } on CliUsageError catch (error) {
    err.writeln(error.message);
    err.writeln('');
    err.writeln(adkUsage);
    return 64;
  }

  try {
    late final int exitCode;
    switch (parsed.type) {
      case AdkCommandType.create:
        exitCode = await _runCreateCommand(parsed, out);
        break;
      case AdkCommandType.run:
        exitCode = await _runRunCommand(parsed, out);
        break;
      case AdkCommandType.web:
        exitCode = await _runWebCommand(parsed, out, err);
        break;
    }
    return exitCode;
  } on FileSystemException catch (error) {
    err.writeln('Filesystem error: $error');
    return 1;
  } on SocketException catch (error) {
    err.writeln('Network error: $error');
    return 1;
  } on FormatException catch (error) {
    err.writeln('Config parse error: $error');
    return 1;
  } on StateError catch (error) {
    err.writeln('Runtime error: $error');
    return 1;
  } on ArgumentError catch (error) {
    err.writeln('Argument error: $error');
    return 1;
  }
}

class _EvalSelection {
  _EvalSelection({required this.source, required this.evalCaseIds});

  final String source;
  final Set<String> evalCaseIds;
}

class _EvalTarget {
  _EvalTarget({required this.evalSetId, required this.evalCaseIds});

  final String evalSetId;
  final Set<String> evalCaseIds;
}

class _ParsedEvalCliCommand {
  _ParsedEvalCliCommand({
    required this.agentPath,
    required this.selections,
    this.configFilePath,
    required this.printDetailedResults,
    this.evalStorageUri,
    this.logLevel,
  });

  final String agentPath;
  final List<_EvalSelection> selections;
  final String? configFilePath;
  final bool printDetailedResults;
  final String? evalStorageUri;
  final String? logLevel;
}

class _ParsedEvalSetCreateCommand {
  _ParsedEvalSetCreateCommand({
    required this.agentPath,
    required this.evalSetId,
    this.evalStorageUri,
    this.logLevel,
  });

  final String agentPath;
  final String evalSetId;
  final String? evalStorageUri;
  final String? logLevel;
}

class _ParsedEvalSetAddEvalCaseCommand {
  _ParsedEvalSetAddEvalCaseCommand({
    required this.agentPath,
    required this.evalSetId,
    required this.scenariosFilePath,
    required this.sessionInputFilePath,
    this.evalStorageUri,
    this.logLevel,
  });

  final String agentPath;
  final String evalSetId;
  final String scenariosFilePath;
  final String sessionInputFilePath;
  final String? evalStorageUri;
  final String? logLevel;
}

class _EvalManagers {
  _EvalManagers({
    required this.evalSetsManager,
    required this.evalSetResultsManager,
  });

  final EvalSetsManager evalSetsManager;
  final EvalSetResultsManager evalSetResultsManager;
}

class _LoadedCliAgent {
  _LoadedCliAgent({
    required this.rootAgent,
    required this.appName,
    required this.agentsParentDirPath,
  });

  final BaseAgent rootAgent;
  final String appName;
  final String agentsParentDirPath;
}

class _ParsedConformanceRecordCommand {
  _ParsedConformanceRecordCommand({
    required this.paths,
    required this.baseUri,
    required this.userId,
  });

  final List<String> paths;
  final Uri baseUri;
  final String userId;
}

class _ParsedConformanceTestCommand {
  _ParsedConformanceTestCommand({
    required this.paths,
    required this.baseUri,
    required this.userId,
    required this.mode,
    required this.generateReport,
    this.reportDir,
  });

  final List<String> paths;
  final Uri baseUri;
  final String userId;
  final String mode;
  final bool generateReport;
  final String? reportDir;
}

class _ConformanceUserMessage {
  _ConformanceUserMessage({this.text, this.content, this.stateDelta});

  final String? text;
  final Map<String, Object?>? content;
  final Map<String, Object?>? stateDelta;
}

class _ConformanceTestSpec {
  _ConformanceTestSpec({
    required this.description,
    required this.agent,
    required this.initialState,
    required this.userMessages,
  });

  final String description;
  final String agent;
  final Map<String, Object?> initialState;
  final List<_ConformanceUserMessage> userMessages;
}

class _ConformanceTestCase {
  _ConformanceTestCase({
    required this.category,
    required this.name,
    required this.dir,
    required this.spec,
  });

  final String category;
  final String name;
  final Directory dir;
  final _ConformanceTestSpec spec;
}

class _ConformanceCaseResult {
  _ConformanceCaseResult({
    required this.category,
    required this.name,
    required this.success,
    this.errorMessage,
    this.description,
  });

  final String category;
  final String name;
  final bool success;
  final String? errorMessage;
  final String? description;
}

class _ConformanceTestSummary {
  _ConformanceTestSummary({
    required this.totalTests,
    required this.passedTests,
    required this.failedTests,
    required this.results,
  });

  final int totalTests;
  final int passedTests;
  final int failedTests;
  final List<_ConformanceCaseResult> results;

  double get successRate {
    if (totalTests == 0) {
      return 0;
    }
    return (passedTests / totalTests) * 100;
  }
}

Future<int> _runEvalCliCommand(List<String> args, {required IOSink out}) async {
  final _ParsedEvalCliCommand command = _parseEvalCliCommand(args);
  final _LoadedCliAgent loadedAgent = await _loadAgentForCli(command.agentPath);

  final bool usesFileTargets = _usesEvalSetFileTargets(command.selections);
  final _EvalManagers managers = _createEvalManagers(
    evalStorageUri: command.evalStorageUri,
    agentsDir: loadedAgent.agentsParentDirPath,
    useInMemory: usesFileTargets,
  );
  final List<_EvalTarget> evalTargets = await _resolveEvalTargets(
    command: command,
    appName: loadedAgent.appName,
    evalSetsManager: managers.evalSetsManager,
    usesFileTargets: usesFileTargets,
  );

  final List<EvalCaseResult> allResults = <EvalCaseResult>[];
  for (final _EvalTarget target in evalTargets) {
    final EvalSet? evalSet = await managers.evalSetsManager.getEvalSet(
      loadedAgent.appName,
      target.evalSetId,
    );
    if (evalSet == null) {
      throw StateError('Eval set `${target.evalSetId}` not found.');
    }

    final List<EvalCase> selectedCases = target.evalCaseIds.isEmpty
        ? List<EvalCase>.from(evalSet.evalCases)
        : evalSet.evalCases
              .where(
                (EvalCase item) => target.evalCaseIds.contains(item.evalId),
              )
              .toList(growable: false);
    if (selectedCases.isEmpty) {
      throw StateError('No matching eval IDs found in `${target.evalSetId}`.');
    }

    allResults.addAll(
      await _evaluateEvalSet(
        rootAgent: loadedAgent.rootAgent,
        appName: loadedAgent.appName,
        evalSetId: target.evalSetId,
        evalCases: selectedCases,
        evalSetResultsManager: managers.evalSetResultsManager,
      ),
    );
  }

  final Map<String, (int passed, int failed)> summaryByEvalSet =
      <String, (int, int)>{};
  for (final EvalCaseResult result in allResults) {
    final (int passed, int failed) current =
        summaryByEvalSet[result.evalSetId] ?? (0, 0);
    if (result.finalEvalStatus == EvalStatus.passed) {
      summaryByEvalSet[result.evalSetId] = (current.$1 + 1, current.$2);
    } else {
      summaryByEvalSet[result.evalSetId] = (current.$1, current.$2 + 1);
    }
  }

  out.writeln('Eval Run Summary');
  final List<String> evalSetIds = summaryByEvalSet.keys.toList(growable: false)
    ..sort();
  for (final String evalSetId in evalSetIds) {
    final (int passed, int failed) counts = summaryByEvalSet[evalSetId]!;
    out.writeln(
      '$evalSetId:\n  Tests passed: ${counts.$1}\n  Tests failed: ${counts.$2}',
    );
  }

  if (command.printDetailedResults) {
    for (final EvalCaseResult result in allResults) {
      out.writeln(
        '*********************************************************************',
      );
      out.writeln(cli_eval.prettyPrintEvalResult(result));
    }
  }
  return 0;
}

Future<int> _runEvalSetCliCommand(
  List<String> args, {
  required IOSink out,
}) async {
  if (args.isEmpty) {
    throw CliUsageError(
      'Missing eval_set subcommand. Supported: create, add_eval_case.',
    );
  }

  final String subcommand = args.first;
  final List<String> commandArgs = args.skip(1).toList(growable: false);
  switch (subcommand) {
    case 'create':
      final _ParsedEvalSetCreateCommand command = _parseEvalSetCreateCommand(
        commandArgs,
      );
      final Directory agentDir = Directory(command.agentPath).absolute;
      final String appName = projectDirName(agentDir.path);
      final _EvalManagers managers = _createEvalManagers(
        evalStorageUri: command.evalStorageUri,
        agentsDir: agentDir.parent.absolute.path,
        useInMemory: false,
      );
      await managers.evalSetsManager.createEvalSet(appName, command.evalSetId);
      out.writeln(
        "Eval set '${command.evalSetId}' created for app '$appName'.",
      );
      return 0;
    case 'add_eval_case':
      final _ParsedEvalSetAddEvalCaseCommand command =
          _parseEvalSetAddEvalCaseCommand(commandArgs);
      final Directory agentDir = Directory(command.agentPath).absolute;
      final String appName = projectDirName(agentDir.path);
      final _EvalManagers managers = _createEvalManagers(
        evalStorageUri: command.evalStorageUri,
        agentsDir: agentDir.parent.absolute.path,
        useInMemory: false,
      );
      final SessionInput sessionInput = SessionInput.fromJson(
        await _readJsonObjectFile(
          command.sessionInputFilePath,
          label: 'session input file',
        ),
      );
      final ConversationScenarios conversationScenarios =
          await _readConversationScenariosFile(command.scenariosFilePath);

      for (final ConversationScenario scenario
          in conversationScenarios.scenarios) {
        final String evalId = _stableScenarioId(scenario);
        final EvalCase? existing = await managers.evalSetsManager.getEvalCase(
          appName,
          command.evalSetId,
          evalId,
        );
        if (existing != null) {
          out.writeln(
            "Eval case '$evalId' already exists in eval set '${command.evalSetId}', skipped adding.",
          );
          continue;
        }

        await managers.evalSetsManager.addEvalCase(
          appName,
          command.evalSetId,
          EvalCase(
            evalId: evalId,
            conversationScenario: scenario,
            sessionInput: sessionInput,
            creationTimestamp: DateTime.now().millisecondsSinceEpoch / 1000,
          ),
        );
        out.writeln(
          "Eval case '$evalId' added to eval set '${command.evalSetId}'.",
        );
      }
      return 0;
    default:
      throw CliUsageError('Unknown eval_set subcommand: $subcommand');
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
      final _ConformanceTestSummary summary = await _runConformanceTest(
        command,
        out: out,
      );
      return summary.failedTests == 0 ? 0 : 1;
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
  );
  if (testCases.isEmpty) {
    out.writeln('No test specs found to process.');
    out.writeln('Conformance test generation complete!');
    return;
  }

  out.writeln('\nProcessing ${testCases.length} test cases...');

  final AdkWebServerClient client = AdkWebServerClient(command.baseUri);
  try {
    for (final _ConformanceTestCase testCase in testCases) {
      try {
        await _recordConformanceCase(client, testCase, userId: command.userId);
        out.writeln(
          'Generated conformance test files for: ${testCase.category}/${testCase.name}',
        );
      } on Exception catch (error) {
        out.writeln(
          'Failed to generate ${testCase.category}/${testCase.name}: $error',
        );
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
}) async {
  final File generatedSessionFile = File(
    '${testCase.dir.path}${Platform.pathSeparator}generated-session.yaml',
  );
  final File generatedRecordingsFile = File(
    '${testCase.dir.path}${Platform.pathSeparator}generated-recordings.yaml',
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

  final List<Map<String, Object?>> recordedEvents = <Map<String, Object?>>[];
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
      streaming: false,
    );
    recordedEvents.addAll(events);
    _updateConformanceFunctionCallNameToIdMap(events, functionCallNameToId);
  }

  final Map<String, Object?> updatedSession = await client.getSession(
    appName: testCase.spec.agent,
    userId: userId,
    sessionId: sessionId,
  );

  final Map<String, Object?> sanitizedSession = _sanitizeConformanceSessionMap(
    updatedSession,
  );
  final Map<String, Object?> sanitizedRecordings = <String, Object?>{
    'events': recordedEvents
        .map(
          (Map<String, Object?> event) => _sanitizeConformanceEventMap(event),
        )
        .toList(growable: false),
  };
  dumpPydanticToYaml(
    sanitizedSession,
    generatedSessionFile.path,
    sortKeys: false,
  );
  dumpPydanticToYaml(
    sanitizedRecordings,
    generatedRecordingsFile.path,
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

Future<_ConformanceTestSummary> _runConformanceTest(
  _ParsedConformanceTestCommand command, {
  required IOSink out,
}) async {
  out.writeln('==================================================');
  out.writeln('Running ADK conformance tests in ${command.mode} mode...');
  out.writeln('==================================================');

  final List<_ConformanceTestCase> testCases = await _discoverConformanceCases(
    command.paths,
    out: out,
    replayMode: command.mode == 'replay',
  );
  if (testCases.isEmpty) {
    out.writeln('No test cases found!');
    final _ConformanceTestSummary emptySummary = _ConformanceTestSummary(
      totalTests: 0,
      passedTests: 0,
      failedTests: 0,
      results: <_ConformanceCaseResult>[],
    );
    _printConformanceSummary(emptySummary, out: out);
    return emptySummary;
  }

  out.writeln(
    '\nFound ${testCases.length} test cases to run in ${command.mode} mode',
  );

  final AdkWebServerClient client = AdkWebServerClient(command.baseUri);
  final List<_ConformanceCaseResult> results = <_ConformanceCaseResult>[];
  Map<String, Object?> versionData = <String, Object?>{};
  try {
    for (final _ConformanceTestCase testCase in testCases) {
      out.write('Running ${testCase.category}/${testCase.name}...');
      late final _ConformanceCaseResult result;
      if (command.mode == 'replay') {
        result = await _runConformanceReplayCase(
          client,
          testCase,
          userId: command.userId,
        );
      } else {
        result = _ConformanceCaseResult(
          category: testCase.category,
          name: testCase.name,
          success: false,
          errorMessage: 'Live mode not yet implemented',
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
    try {
      versionData = await client.getVersionData();
    } on Exception {
      versionData = <String, Object?>{};
    }
  } finally {
    await client.close();
  }

  final int passed = results.where((item) => item.success).length;
  final _ConformanceTestSummary summary = _ConformanceTestSummary(
    totalTests: results.length,
    passedTests: passed,
    failedTests: results.length - passed,
    results: results,
  );
  _printConformanceSummary(summary, out: out);

  if (command.generateReport) {
    final String reportPath = await _writeConformanceMarkdownReport(
      summary,
      reportDir: command.reportDir,
      versionData: versionData,
    );
    out.writeln('Conformance report written to $reportPath');
  }
  return summary;
}

Future<_ConformanceCaseResult> _runConformanceReplayCase(
  AdkWebServerClient client,
  _ConformanceTestCase testCase, {
  required String userId,
}) async {
  final File sessionFile = File(
    '${testCase.dir.path}${Platform.pathSeparator}generated-session.yaml',
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

  final Map<String, Object?> session = await client.createSession(
    appName: testCase.spec.agent,
    userId: userId,
    state: testCase.spec.initialState,
  );
  final String sessionId =
      _extractSessionIdFromCreateSession(session) ??
      (throw StateError('Failed to create session id for conformance test.'));
  final Map<String, String> functionCallNameToId = <String, String>{};
  try {
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
        streaming: false,
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

void _printConformanceSummary(
  _ConformanceTestSummary summary, {
  required IOSink out,
}) {
  out.writeln('\n==================================================');
  out.writeln('CONFORMANCE TEST SUMMARY');
  out.writeln('==================================================');
  if (summary.totalTests == 0) {
    out.writeln('No tests were run.');
    return;
  }
  out.writeln('Total tests: ${summary.totalTests}');
  out.writeln('Passed: ${summary.passedTests}');
  out.writeln('Failed: ${summary.failedTests}');
  out.writeln('Success rate: ${summary.successRate.toStringAsFixed(1)}%');

  if (summary.failedTests == 0) {
    out.writeln('\nAll tests passed.');
    return;
  }

  out.writeln('\nFailed tests:');
  for (final _ConformanceCaseResult result in summary.results) {
    if (result.success) {
      continue;
    }
    out.writeln('\n${result.category}/${result.name}');
    if (result.errorMessage != null && result.errorMessage!.trim().isNotEmpty) {
      out.writeln(result.errorMessage!);
    }
  }
}

Future<String> _writeConformanceMarkdownReport(
  _ConformanceTestSummary summary, {
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
  out.writeln('- Total: ${summary.totalTests}');
  out.writeln('- Passed: ${summary.passedTests}');
  out.writeln('- Failed: ${summary.failedTests}');
  out.writeln('- Success rate: ${summary.successRate.toStringAsFixed(1)}%');
  out.writeln();
  out.writeln('## Results');
  out.writeln('| Test | Status | Description | Error |');
  out.writeln('| --- | --- | --- | --- |');
  for (final _ConformanceCaseResult result in summary.results) {
    final String testName = '${result.category}/${result.name}';
    final String status = result.success ? 'PASS' : 'FAIL';
    final String description = (result.description ?? '').replaceAll(
      '|',
      r'\|',
    );
    final String error = (result.errorMessage ?? '').replaceAll('|', r'\|');
    out.writeln('| $testName | $status | $description | $error |');
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
          '${caseDir.path}${Platform.pathSeparator}generated-recordings.yaml',
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
  Map<String, Object?> session,
) {
  final Map<String, Object?> normalized = _deepCopyMap(session);
  normalized.remove('id');
  normalized.remove('last_update_time');
  normalized.remove('lastUpdateTime');
  normalized.remove('events');

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
  if (normalized is Map<String, Object?>) {
    return normalized;
  }
  if (normalized is Map) {
    return normalized.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
  }
  return <String, Object?>{};
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
    if (arg == '--log_level') {
      _nextArg(args, i, '--log_level');
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=')) {
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for migrate session: $arg');
    }
    throw CliUsageError(
      'Unexpected positional argument for migrate session: $arg',
    );
  }

  final String? normalizedSource = _emptyToNull(sourceDbUrl);
  final String? normalizedDest = _emptyToNull(destDbUrl);
  if (normalizedSource == null) {
    throw CliUsageError('Missing required option --source_db_url.');
  }
  if (normalizedDest == null) {
    throw CliUsageError('Missing required option --dest_db_url.');
  }

  await session_migration.upgrade(normalizedSource, normalizedDest);
  out.writeln('Migration check and upgrade process finished.');
  return 0;
}

_ParsedEvalCliCommand _parseEvalCliCommand(List<String> args) {
  String? configFilePath;
  bool printDetailedResults = false;
  String? evalStorageUri;
  String? logLevel;
  final List<String> positionals = <String>[];

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--config_file_path') {
      configFilePath = _nextArg(args, i, '--config_file_path');
      i += 1;
      continue;
    }
    if (arg.startsWith('--config_file_path=')) {
      configFilePath = arg.substring('--config_file_path='.length);
      continue;
    }
    if (arg == '--print_detailed_results') {
      printDetailedResults = true;
      continue;
    }
    if (arg == '--eval_storage_uri') {
      evalStorageUri = _nextArg(args, i, '--eval_storage_uri');
      i += 1;
      continue;
    }
    if (arg.startsWith('--eval_storage_uri=')) {
      evalStorageUri = arg.substring('--eval_storage_uri='.length);
      continue;
    }
    if (arg == '--log_level') {
      logLevel = _nextArg(args, i, '--log_level');
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=')) {
      logLevel = arg.substring('--log_level='.length);
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for eval: $arg');
    }
    positionals.add(arg);
  }

  if (positionals.length < 2) {
    throw CliUsageError(
      'eval requires <project_dir> and at least one <eval_set_file_or_id>.',
    );
  }

  final List<_EvalSelection> selections = positionals
      .skip(1)
      .map(_parseEvalSelection)
      .toList(growable: false);
  return _ParsedEvalCliCommand(
    agentPath: positionals.first,
    selections: selections,
    configFilePath: _emptyToNull(configFilePath),
    printDetailedResults: printDetailedResults,
    evalStorageUri: _emptyToNull(evalStorageUri),
    logLevel: _emptyToNull(logLevel),
  );
}

_EvalSelection _parseEvalSelection(String rawValue) {
  final String value = rawValue.trim();
  if (value.isEmpty) {
    throw CliUsageError('Empty eval set target is not allowed.');
  }
  final int colonIndex = value.indexOf(':');
  if (colonIndex <= 0 || colonIndex >= value.length - 1) {
    return _EvalSelection(source: value, evalCaseIds: <String>{});
  }
  // Treat Windows drive roots like C:\path as plain file paths.
  if (colonIndex == 1 && RegExp(r'^[A-Za-z]$').hasMatch(value[0])) {
    return _EvalSelection(source: value, evalCaseIds: <String>{});
  }

  final String source = value.substring(0, colonIndex).trim();
  final String idsPart = value.substring(colonIndex + 1).trim();
  if (source.isEmpty || idsPart.isEmpty) {
    return _EvalSelection(source: value, evalCaseIds: <String>{});
  }
  final Set<String> ids = idsPart
      .split(',')
      .map((String item) => item.trim())
      .where((String item) => item.isNotEmpty)
      .toSet();
  return _EvalSelection(source: source, evalCaseIds: ids);
}

bool _usesEvalSetFileTargets(List<_EvalSelection> selections) {
  bool? usingFiles;
  for (final _EvalSelection selection in selections) {
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      selection.source,
    );
    final bool isExistingPath = type != FileSystemEntityType.notFound;
    if (usingFiles == null) {
      usingFiles = isExistingPath;
      continue;
    }
    if (usingFiles != isExistingPath) {
      throw CliUsageError(
        'Mixing eval set file paths with eval set ids is not supported.',
      );
    }
  }
  return usingFiles ?? false;
}

_EvalManagers _createEvalManagers({
  required String? evalStorageUri,
  required String agentsDir,
  required bool useInMemory,
}) {
  if (useInMemory) {
    return _EvalManagers(
      evalSetsManager: InMemoryEvalSetsManager(),
      evalSetResultsManager: InMemoryEvalSetResultsManager(),
    );
  }

  if (evalStorageUri != null) {
    final cli_evals.GcsEvalManagers gcsManagers = cli_evals
        .createGcsEvalManagersFromUri(evalStorageUri);
    return _EvalManagers(
      evalSetsManager: gcsManagers.evalSetsManager,
      evalSetResultsManager: gcsManagers.evalSetResultsManager,
    );
  }

  return _EvalManagers(
    evalSetsManager: LocalEvalSetsManager(agentsDir),
    evalSetResultsManager: LocalEvalSetResultsManager(agentsDir),
  );
}

Future<List<_EvalTarget>> _resolveEvalTargets({
  required _ParsedEvalCliCommand command,
  required String appName,
  required EvalSetsManager evalSetsManager,
  required bool usesFileTargets,
}) async {
  final List<_EvalTarget> targets = <_EvalTarget>[];
  if (usesFileTargets) {
    for (final _EvalSelection selection in command.selections) {
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        selection.source,
      );
      if (type != FileSystemEntityType.file) {
        throw CliUsageError(
          'Eval target `${selection.source}` must be a file path.',
        );
      }

      final EvalSet evalSet;
      try {
        evalSet = loadEvalSetFromFile(selection.source, selection.source);
      } on Exception catch (error) {
        throw CliUsageError(
          '`${selection.source}` should be a valid eval set file. $error',
        );
      }

      await evalSetsManager.createEvalSet(appName, evalSet.evalSetId);
      final List<EvalCase> selectedCases = selection.evalCaseIds.isEmpty
          ? evalSet.evalCases
          : evalSet.evalCases
                .where(
                  (EvalCase item) =>
                      selection.evalCaseIds.contains(item.evalId),
                )
                .toList(growable: false);
      for (final EvalCase evalCase in selectedCases) {
        await evalSetsManager.addEvalCase(appName, evalSet.evalSetId, evalCase);
      }
      _mergeEvalTarget(targets, evalSet.evalSetId, selection.evalCaseIds);
    }
    return targets;
  }

  for (final _EvalSelection selection in command.selections) {
    _mergeEvalTarget(targets, selection.source, selection.evalCaseIds);
  }
  return targets;
}

void _mergeEvalTarget(
  List<_EvalTarget> targets,
  String evalSetId,
  Set<String> evalCaseIds,
) {
  final int index = targets.indexWhere((item) => item.evalSetId == evalSetId);
  if (index == -1) {
    targets.add(
      _EvalTarget(
        evalSetId: evalSetId,
        evalCaseIds: Set<String>.from(evalCaseIds),
      ),
    );
    return;
  }

  final _EvalTarget existing = targets[index];
  if (existing.evalCaseIds.isEmpty || evalCaseIds.isEmpty) {
    targets[index] = _EvalTarget(evalSetId: evalSetId, evalCaseIds: <String>{});
    return;
  }
  targets[index] = _EvalTarget(
    evalSetId: evalSetId,
    evalCaseIds: <String>{...existing.evalCaseIds, ...evalCaseIds},
  );
}

Future<List<EvalCaseResult>> _evaluateEvalSet({
  required BaseAgent rootAgent,
  required String appName,
  required String evalSetId,
  required List<EvalCase> evalCases,
  required EvalSetResultsManager evalSetResultsManager,
}) async {
  final LocalEvalService evalService = LocalEvalService(
    rootAgent: rootAgent,
    appName: appName,
  );

  final List<InferenceResult> inferenceResults = await evalService
      .performInference(
        InferenceRequest(
          appName: appName,
          evalCases: evalCases,
          userId: 'eval_user',
        ),
      )
      .toList();

  final Map<String, EvalCase> evalCasesById = <String, EvalCase>{
    for (final EvalCase evalCase in evalCases) evalCase.evalId: evalCase,
  };
  final List<EvalMetric> evalMetrics = cli_eval.getDefaultMetricInfo();
  final List<EvalCaseResult> rawResults = await evalService
      .evaluate(
        EvaluateRequest(
          inferenceResults: inferenceResults,
          evalCasesById: evalCasesById,
          evaluateConfig: EvaluateConfig(evalMetrics: evalMetrics),
        ),
      )
      .toList();

  final Map<String, InferenceResult> inferenceByEvalCaseId =
      <String, InferenceResult>{
        for (final InferenceResult inference in inferenceResults)
          inference.evalCaseId: inference,
      };
  final List<EvalCaseResult> normalizedResults = rawResults
      .map((EvalCaseResult value) {
        final InferenceResult? inference =
            inferenceByEvalCaseId[value.evalCaseId];
        return EvalCaseResult(
          evalCaseId: value.evalCaseId,
          metrics: value.metrics,
          evalSetId: evalSetId,
          finalEvalStatus: _deriveEvalStatusFromMetrics(value.metrics),
          sessionId: inference?.sessionId ?? '',
          userId:
              evalCasesById[value.evalCaseId]?.sessionInput?.userId ??
              'eval_user',
          evalSetFile: '$evalSetId.evalset.json',
        );
      })
      .toList(growable: false);
  await evalSetResultsManager.saveEvalSetResult(
    appName,
    evalSetId,
    normalizedResults,
  );
  return normalizedResults;
}

EvalStatus _deriveEvalStatusFromMetrics(List<EvalMetricResult> metrics) {
  if (metrics.isEmpty) {
    return EvalStatus.notEvaluated;
  }
  final bool passed = metrics.every(
    (EvalMetricResult metric) => metric.evalStatus == EvalStatus.passed,
  );
  return passed ? EvalStatus.passed : EvalStatus.failed;
}

Future<_LoadedCliAgent> _loadAgentForCli(String projectDirPath) async {
  final Directory requestedDir = Directory(projectDirPath).absolute;
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
  final AgentLoader agentLoader = AgentLoader(
    agentsParentDir.path,
    enableDevProjectFallback: false,
  );
  final AgentOrApp loaded = agentLoader.loadAgent(agentFolderName);
  final BaseAgent rootAgent = asBaseAgent(loaded);
  final String appName = loaded is App ? loaded.name : agentFolderName;
  return _LoadedCliAgent(
    rootAgent: rootAgent,
    appName: appName,
    agentsParentDirPath: agentsParentDir.path,
  );
}

_ParsedEvalSetCreateCommand _parseEvalSetCreateCommand(List<String> args) {
  String? evalStorageUri;
  String? logLevel;
  final List<String> positionals = <String>[];
  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--eval_storage_uri') {
      evalStorageUri = _nextArg(args, i, '--eval_storage_uri');
      i += 1;
      continue;
    }
    if (arg.startsWith('--eval_storage_uri=')) {
      evalStorageUri = arg.substring('--eval_storage_uri='.length);
      continue;
    }
    if (arg == '--log_level') {
      logLevel = _nextArg(args, i, '--log_level');
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=')) {
      logLevel = arg.substring('--log_level='.length);
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for eval_set create: $arg');
    }
    positionals.add(arg);
  }
  if (positionals.length != 2) {
    throw CliUsageError(
      'eval_set create requires <project_dir> <eval_set_id>.',
    );
  }
  return _ParsedEvalSetCreateCommand(
    agentPath: positionals[0],
    evalSetId: positionals[1],
    evalStorageUri: _emptyToNull(evalStorageUri),
    logLevel: _emptyToNull(logLevel),
  );
}

_ParsedEvalSetAddEvalCaseCommand _parseEvalSetAddEvalCaseCommand(
  List<String> args,
) {
  String? evalStorageUri;
  String? logLevel;
  String? scenariosFilePath;
  String? sessionInputFilePath;
  final List<String> positionals = <String>[];
  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--eval_storage_uri') {
      evalStorageUri = _nextArg(args, i, '--eval_storage_uri');
      i += 1;
      continue;
    }
    if (arg.startsWith('--eval_storage_uri=')) {
      evalStorageUri = arg.substring('--eval_storage_uri='.length);
      continue;
    }
    if (arg == '--log_level') {
      logLevel = _nextArg(args, i, '--log_level');
      i += 1;
      continue;
    }
    if (arg.startsWith('--log_level=')) {
      logLevel = arg.substring('--log_level='.length);
      continue;
    }
    if (arg == '--scenarios_file') {
      scenariosFilePath = _nextArg(args, i, '--scenarios_file');
      i += 1;
      continue;
    }
    if (arg.startsWith('--scenarios_file=')) {
      scenariosFilePath = arg.substring('--scenarios_file='.length);
      continue;
    }
    if (arg == '--session_input_file') {
      sessionInputFilePath = _nextArg(args, i, '--session_input_file');
      i += 1;
      continue;
    }
    if (arg.startsWith('--session_input_file=')) {
      sessionInputFilePath = arg.substring('--session_input_file='.length);
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for eval_set add_eval_case: $arg');
    }
    positionals.add(arg);
  }
  if (positionals.length != 2) {
    throw CliUsageError(
      'eval_set add_eval_case requires <project_dir> <eval_set_id>.',
    );
  }
  if (_emptyToNull(scenariosFilePath) == null) {
    throw CliUsageError('eval_set add_eval_case requires --scenarios_file.');
  }
  if (_emptyToNull(sessionInputFilePath) == null) {
    throw CliUsageError(
      'eval_set add_eval_case requires --session_input_file.',
    );
  }
  return _ParsedEvalSetAddEvalCaseCommand(
    agentPath: positionals[0],
    evalSetId: positionals[1],
    scenariosFilePath: _emptyToNull(scenariosFilePath)!,
    sessionInputFilePath: _emptyToNull(sessionInputFilePath)!,
    evalStorageUri: _emptyToNull(evalStorageUri),
    logLevel: _emptyToNull(logLevel),
  );
}

Future<Map<String, Object?>> _readJsonObjectFile(
  String filePath, {
  required String label,
}) async {
  final File file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException('$label not found.', file.path);
  }
  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw FormatException('$label must contain a JSON object.');
  }
  return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
}

Future<ConversationScenarios> _readConversationScenariosFile(
  String filePath,
) async {
  final File file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException('scenarios file not found.', file.path);
  }
  final Object? decoded = jsonDecode(await file.readAsString());
  if (decoded is List) {
    return ConversationScenarios.fromJson(<String, Object?>{
      'scenarios': decoded,
    });
  }
  if (decoded is Map) {
    final Map<String, Object?> map = decoded.map(
      (Object? key, Object? value) => MapEntry('$key', value),
    );
    return ConversationScenarios.fromJson(map);
  }
  throw const FormatException(
    'scenarios file must contain a JSON array or object.',
  );
}

String _stableScenarioId(ConversationScenario scenario) {
  final String canonical = jsonEncode(
    _normalizeJsonForStableHash(scenario.toJson()),
  );
  final String digest = crypto.sha256
      .convert(utf8.encode(canonical))
      .toString();
  return digest.substring(0, 8);
}

Object? _normalizeJsonForStableHash(Object? value) {
  if (value is Map) {
    final List<String> keys =
        value.keys.map((Object? key) => '$key').toList(growable: false)..sort();
    final Map<String, Object?> normalized = <String, Object?>{};
    for (final String key in keys) {
      normalized[key] = _normalizeJsonForStableHash(value[key]);
    }
    return normalized;
  }
  if (value is List) {
    return value
        .map((Object? item) => _normalizeJsonForStableHash(item))
        .toList(growable: false);
  }
  return value;
}

_ParsedConformanceRecordCommand _parseConformanceRecordCommand(
  List<String> args,
) {
  final List<String> paths = <String>[];
  String baseUrl = 'http://127.0.0.1:8000';
  String userId = 'adk_conformance_test_user';
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
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for conformance record: $arg');
    }
    paths.add(arg);
  }
  return _ParsedConformanceRecordCommand(
    paths: paths,
    baseUri: Uri.parse(baseUrl),
    userId: _emptyToNull(userId) ?? 'adk_conformance_test_user',
  );
}

_ParsedConformanceTestCommand _parseConformanceTestCommand(List<String> args) {
  final List<String> paths = <String>[];
  String baseUrl = 'http://127.0.0.1:8000';
  String userId = 'adk_conformance_test_user';
  String mode = 'replay';
  bool generateReport = false;
  String? reportDir;

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
  );
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

ParsedAdkCommand _parseCreateCommand(List<String> args) {
  String? projectDir;
  String? appName;

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--app-name') {
      appName = _nextArg(args, i, '--app-name');
      i += 1;
      continue;
    }
    if (arg.startsWith('--app-name=')) {
      appName = arg.substring('--app-name='.length).trim();
      continue;
    }

    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for create: $arg');
    }

    if (projectDir != null) {
      throw CliUsageError('create accepts only one project directory.');
    }
    projectDir = arg;
  }

  if (projectDir == null || projectDir.trim().isEmpty) {
    throw CliUsageError('Missing project directory for create.');
  }

  return ParsedAdkCommand.create(
    projectDir: projectDir,
    appName: appName?.trim().isEmpty == true ? null : appName?.trim(),
  );
}

ParsedAdkCommand _parseRunCommand(List<String> args) {
  String? projectDir;
  String? userId;
  String? sessionId;
  String? sessionServiceUri;
  String? artifactServiceUri;
  String? memoryServiceUri;
  String? resumeFilePath;
  String? replayFilePath;
  String? message;
  bool saveSession = false;
  bool useLocalStorage = true;
  bool explicitUseLocalStorageFlag = false;
  bool seenProjectDir = false;

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--user-id') {
      userId = _nextArg(args, i, '--user-id');
      i += 1;
      continue;
    }
    if (arg.startsWith('--user-id=')) {
      userId = arg.substring('--user-id='.length);
      continue;
    }
    if (arg == '--session-id') {
      sessionId = _nextArg(args, i, '--session-id');
      i += 1;
      continue;
    }
    if (arg == '--session_id') {
      sessionId = _nextArg(args, i, '--session_id');
      i += 1;
      continue;
    }
    if (arg.startsWith('--session-id=')) {
      sessionId = arg.substring('--session-id='.length);
      continue;
    }
    if (arg.startsWith('--session_id=')) {
      sessionId = arg.substring('--session_id='.length);
      continue;
    }
    if (arg == '--session_service_uri') {
      sessionServiceUri = _nextArg(args, i, '--session_service_uri');
      i += 1;
      continue;
    }
    if (arg.startsWith('--session_service_uri=')) {
      sessionServiceUri = arg.substring('--session_service_uri='.length);
      continue;
    }
    if (arg == '--artifact_service_uri') {
      artifactServiceUri = _nextArg(args, i, '--artifact_service_uri');
      i += 1;
      continue;
    }
    if (arg.startsWith('--artifact_service_uri=')) {
      artifactServiceUri = arg.substring('--artifact_service_uri='.length);
      continue;
    }
    if (arg == '--memory_service_uri') {
      memoryServiceUri = _nextArg(args, i, '--memory_service_uri');
      i += 1;
      continue;
    }
    if (arg.startsWith('--memory_service_uri=')) {
      memoryServiceUri = arg.substring('--memory_service_uri='.length);
      continue;
    }
    if (arg == '--use_local_storage') {
      useLocalStorage = true;
      explicitUseLocalStorageFlag = true;
      continue;
    }
    if (arg == '--no-use_local_storage' || arg == '--no_use_local_storage') {
      useLocalStorage = false;
      explicitUseLocalStorageFlag = true;
      continue;
    }
    if (arg == '-m' || arg == '--message') {
      message = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--message=')) {
      message = arg.substring('--message='.length);
      continue;
    }
    if (arg == '--save_session') {
      saveSession = true;
      continue;
    }
    if (arg == '--resume') {
      resumeFilePath = _nextArg(args, i, '--resume');
      i += 1;
      continue;
    }
    if (arg.startsWith('--resume=')) {
      resumeFilePath = arg.substring('--resume='.length);
      continue;
    }
    if (arg == '--replay') {
      replayFilePath = _nextArg(args, i, '--replay');
      i += 1;
      continue;
    }
    if (arg.startsWith('--replay=')) {
      replayFilePath = arg.substring('--replay='.length);
      continue;
    }

    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for run: $arg');
    }

    if (seenProjectDir) {
      throw CliUsageError('run accepts only one project directory.');
    }
    projectDir = arg;
    seenProjectDir = true;
  }

  if (_emptyToNull(resumeFilePath) != null &&
      _emptyToNull(replayFilePath) != null) {
    throw CliUsageError('--resume and --replay cannot be used together.');
  }
  if (_emptyToNull(message) != null && _emptyToNull(replayFilePath) != null) {
    throw CliUsageError('--message and --replay cannot be used together.');
  }
  if (projectDir == null || projectDir.trim().isEmpty) {
    throw CliUsageError('Missing agent directory for run.');
  }
  if (explicitUseLocalStorageFlag &&
      (_emptyToNull(sessionServiceUri) != null ||
          _emptyToNull(artifactServiceUri) != null)) {
    throw CliUsageError(
      '--use_local_storage/--no-use_local_storage cannot be used with '
      '--session_service_uri or --artifact_service_uri.',
    );
  }

  return ParsedAdkCommand.run(
    projectDir: projectDir,
    userId: _emptyToNull(userId),
    sessionId: _emptyToNull(sessionId),
    sessionServiceUri: _emptyToNull(sessionServiceUri),
    artifactServiceUri: _emptyToNull(artifactServiceUri),
    memoryServiceUri: _emptyToNull(memoryServiceUri),
    useLocalStorage: useLocalStorage,
    saveSession: saveSession,
    resumeFilePath: _emptyToNull(resumeFilePath),
    replayFilePath: _emptyToNull(replayFilePath),
    message: _emptyToNull(message),
  );
}

ParsedAdkCommand _parseWebCommand(
  List<String> args, {
  required bool enableWebUi,
}) {
  int port = 8000;
  InternetAddress host = InternetAddress.loopbackIPv4;
  String projectDir = '.';
  String? userId;
  final List<String> allowOrigins = <String>[];
  String? sessionServiceUri;
  String? artifactServiceUri;
  String? memoryServiceUri;
  String? evalStorageUri;
  String? deprecatedSessionDbUrl;
  String? deprecatedArtifactStorageUri;
  bool useLocalStorage = true;
  bool explicitUseLocalStorageFlag = false;
  String? urlPrefix;
  bool traceToCloud = false;
  bool otelToCloud = false;
  bool reload = true;
  bool a2a = false;
  bool reloadAgents = false;
  final List<String> extraPlugins = <String>[];
  String? logoText;
  String? logoImageUrl;
  bool autoCreateSession = false;
  bool seenProjectDir = false;

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--port' || arg == '-p') {
      port = _parsePort(_nextArg(args, i, arg));
      i += 1;
      continue;
    }
    if (arg.startsWith('--port=')) {
      port = _parsePort(arg.substring('--port='.length));
      continue;
    }
    if (arg == '--host') {
      host = _parseHost(_nextArg(args, i, '--host'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--host=')) {
      host = _parseHost(arg.substring('--host='.length));
      continue;
    }
    if (arg == '--user-id') {
      userId = _nextArg(args, i, '--user-id');
      i += 1;
      continue;
    }
    if (arg.startsWith('--user-id=')) {
      userId = arg.substring('--user-id='.length);
      continue;
    }
    if (arg == '--allow_origins') {
      allowOrigins.add(_nextArg(args, i, '--allow_origins').trim());
      i += 1;
      continue;
    }
    if (arg.startsWith('--allow_origins=')) {
      allowOrigins.add(arg.substring('--allow_origins='.length).trim());
      continue;
    }
    if (arg == '--session_service_uri') {
      sessionServiceUri = _nextArg(args, i, '--session_service_uri').trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--session_service_uri=')) {
      sessionServiceUri = arg.substring('--session_service_uri='.length).trim();
      continue;
    }
    if (arg == '--artifact_service_uri') {
      artifactServiceUri = _nextArg(args, i, '--artifact_service_uri').trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--artifact_service_uri=')) {
      artifactServiceUri = arg
          .substring('--artifact_service_uri='.length)
          .trim();
      continue;
    }
    if (arg == '--memory_service_uri') {
      memoryServiceUri = _nextArg(args, i, '--memory_service_uri').trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--memory_service_uri=')) {
      memoryServiceUri = arg.substring('--memory_service_uri='.length).trim();
      continue;
    }
    if (arg == '--session_db_url') {
      deprecatedSessionDbUrl = _nextArg(args, i, '--session_db_url').trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--session_db_url=')) {
      deprecatedSessionDbUrl = arg.substring('--session_db_url='.length).trim();
      continue;
    }
    if (arg == '--artifact_storage_uri') {
      deprecatedArtifactStorageUri = _nextArg(
        args,
        i,
        '--artifact_storage_uri',
      ).trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--artifact_storage_uri=')) {
      deprecatedArtifactStorageUri = arg
          .substring('--artifact_storage_uri='.length)
          .trim();
      continue;
    }
    if (arg == '--url_prefix') {
      urlPrefix = _normalizeUrlPrefix(_nextArg(args, i, '--url_prefix'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--url_prefix=')) {
      urlPrefix = _normalizeUrlPrefix(arg.substring('--url_prefix='.length));
      continue;
    }
    if (arg == '--extra_plugins') {
      extraPlugins.add(_nextArg(args, i, '--extra_plugins').trim());
      i += 1;
      continue;
    }
    if (arg.startsWith('--extra_plugins=')) {
      extraPlugins.add(arg.substring('--extra_plugins='.length).trim());
      continue;
    }
    if (arg == '--logo_text' || arg == '--logo-text') {
      logoText = _nextArg(args, i, arg).trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--logo_text=')) {
      logoText = arg.substring('--logo_text='.length).trim();
      continue;
    }
    if (arg.startsWith('--logo-text=')) {
      logoText = arg.substring('--logo-text='.length).trim();
      continue;
    }
    if (arg == '--logo_image_url' || arg == '--logo-image-url') {
      logoImageUrl = _nextArg(args, i, arg).trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--logo_image_url=')) {
      logoImageUrl = arg.substring('--logo_image_url='.length).trim();
      continue;
    }
    if (arg.startsWith('--logo-image-url=')) {
      logoImageUrl = arg.substring('--logo-image-url='.length).trim();
      continue;
    }
    if (arg == '--use_local_storage') {
      useLocalStorage = true;
      explicitUseLocalStorageFlag = true;
      continue;
    }
    if (arg == '--no-use_local_storage' || arg == '--no_use_local_storage') {
      useLocalStorage = false;
      explicitUseLocalStorageFlag = true;
      continue;
    }
    if (arg == '--trace_to_cloud') {
      traceToCloud = true;
      continue;
    }
    if (arg == '--otel_to_cloud') {
      otelToCloud = true;
      continue;
    }
    if (arg == '--reload') {
      reload = true;
      continue;
    }
    if (arg == '--no-reload') {
      reload = false;
      continue;
    }
    if (arg == '--a2a') {
      a2a = true;
      continue;
    }
    if (arg == '--reload_agents') {
      reloadAgents = true;
      continue;
    }
    if (arg == '--auto_create_session') {
      autoCreateSession = true;
      continue;
    }
    if (arg == '--eval_storage_uri') {
      evalStorageUri = _nextArg(args, i, '--eval_storage_uri').trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--eval_storage_uri=')) {
      evalStorageUri = arg.substring('--eval_storage_uri='.length).trim();
      continue;
    }
    if (arg == '--log_level' || arg == '--verbosity') {
      _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg == '-v' || arg == '--verbose') {
      continue;
    }
    if (arg.startsWith('--log_level=') || arg.startsWith('--verbosity=')) {
      continue;
    }
    if (arg.startsWith('-')) {
      throw CliUsageError('Unknown option for web: $arg');
    }
    if (seenProjectDir) {
      throw CliUsageError('web accepts only one project directory.');
    }
    projectDir = arg;
    seenProjectDir = true;
  }

  final bool usedDeprecatedSessionDbUrl =
      _emptyToNull(deprecatedSessionDbUrl) != null;
  final bool usedDeprecatedArtifactStorageUri =
      _emptyToNull(deprecatedArtifactStorageUri) != null;
  sessionServiceUri ??= deprecatedSessionDbUrl;
  artifactServiceUri ??= deprecatedArtifactStorageUri;

  final String? normalizedSessionServiceUri = _emptyToNull(sessionServiceUri);
  final String? normalizedArtifactServiceUri = _emptyToNull(artifactServiceUri);
  final String? normalizedMemoryServiceUri = _emptyToNull(memoryServiceUri);
  final String? normalizedEvalStorageUri = _emptyToNull(evalStorageUri);
  if (explicitUseLocalStorageFlag &&
      (normalizedSessionServiceUri != null ||
          normalizedArtifactServiceUri != null)) {
    throw CliUsageError(
      '--use_local_storage/--no_use_local_storage cannot be used with '
      '--session_service_uri or --artifact_service_uri.',
    );
  }

  return ParsedAdkCommand.web(
    projectDir: projectDir,
    port: port,
    host: host,
    userId: _emptyToNull(userId),
    allowOrigins: _normalizeCsvValues(allowOrigins),
    sessionServiceUri: normalizedSessionServiceUri,
    artifactServiceUri: normalizedArtifactServiceUri,
    memoryServiceUri: normalizedMemoryServiceUri,
    evalStorageUri: normalizedEvalStorageUri,
    useLocalStorage: useLocalStorage,
    urlPrefix: _emptyToNull(urlPrefix),
    traceToCloud: traceToCloud,
    otelToCloud: otelToCloud,
    reload: reload,
    a2a: a2a,
    reloadAgents: reloadAgents,
    extraPlugins: _normalizeCsvValues(extraPlugins),
    logoText: _emptyToNull(logoText),
    logoImageUrl: _emptyToNull(logoImageUrl),
    autoCreateSession: autoCreateSession,
    enableWebUi: enableWebUi,
    usedDeprecatedSessionDbUrl: usedDeprecatedSessionDbUrl,
    usedDeprecatedArtifactStorageUri: usedDeprecatedArtifactStorageUri,
  );
}

String _nextArg(List<String> args, int index, String option) {
  if (index + 1 >= args.length) {
    throw CliUsageError('Missing value for $option.');
  }
  return args[index + 1];
}

String? _emptyToNull(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

int _parsePort(String rawPort) {
  final int? port = int.tryParse(rawPort);
  if (port == null || port < 0 || port > 65535) {
    throw CliUsageError('Invalid port: $rawPort');
  }
  return port;
}

InternetAddress _parseHost(String rawHost) {
  if (rawHost == 'localhost') {
    return InternetAddress.loopbackIPv4;
  }

  final InternetAddress? host = InternetAddress.tryParse(rawHost);
  if (host == null) {
    throw CliUsageError('Invalid host: $rawHost');
  }
  return host;
}

List<String> _normalizeCsvValues(List<String> values) {
  final List<String> expanded = <String>[];
  for (final String value in values) {
    final List<String> parts = value
        .split(',')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
    if (parts.isNotEmpty) {
      expanded.addAll(parts);
    }
  }
  return expanded;
}

String _normalizeUrlPrefix(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (!trimmed.startsWith('/')) {
    throw CliUsageError('url_prefix must start with "/": $trimmed');
  }
  if (trimmed.length > 1 && trimmed.endsWith('/')) {
    return trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

Future<int> _runCreateCommand(ParsedAdkCommand command, IOSink out) async {
  await createDevProject(
    projectDirPath: command.projectDir,
    appName: command.appName,
  );
  out.writeln('Created ADK project at ${command.projectDir}');
  out.writeln('Next steps:');
  out.writeln('  cd ${command.projectDir}');
  out.writeln('  adk run .');
  out.writeln('  adk web --port 8000 .');
  return 0;
}

class _RunCommandContext {
  _RunCommandContext({
    required this.runtime,
    required this.userId,
    required this.rootAgentName,
  });

  final DevAgentRuntime runtime;
  final String userId;
  final String rootAgentName;
}

Future<_RunCommandContext> _loadRunCommandContext(
  ParsedAdkCommand command,
) async {
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
  final AgentLoader agentLoader = AgentLoader(
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

  final Runner runner = loaded is App
      ? Runner(
          app: loaded,
          appName: sessionAppName,
          sessionService: createSessionServiceFromOptions(
            baseDir: agentsParentDir.path,
            sessionServiceUri: command.sessionServiceUri,
            appNameToDir: appNameToDir,
            useLocalStorage: command.useLocalStorage,
          ),
          artifactService: createArtifactServiceFromOptions(
            baseDir: agentDir.path,
            artifactServiceUri: command.artifactServiceUri,
            useLocalStorage: command.useLocalStorage,
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
            useLocalStorage: command.useLocalStorage,
          ),
          artifactService: createArtifactServiceFromOptions(
            baseDir: agentDir.path,
            artifactServiceUri: command.artifactServiceUri,
            useLocalStorage: command.useLocalStorage,
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

Future<int> _runRunCommand(ParsedAdkCommand command, IOSink out) async {
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
    );
    if (command.saveSession) {
      await _saveSessionSnapshot(
        runtime: runtime,
        session: replaySession,
        projectDir: command.projectDir,
        requestedSessionIdForSave: command.sessionId,
        out: out,
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
  );

  if (command.message != null) {
    final List<Event> events = await runtime.sendMessage(
      userId: userId,
      sessionId: session.id,
      message: command.message!,
    );
    _writeEventTexts(events, out: out);
    if (command.saveSession) {
      await _saveSessionSnapshot(
        runtime: runtime,
        session: session,
        projectDir: command.projectDir,
        requestedSessionIdForSave: command.sessionId,
        out: out,
      );
    }
    await runtime.runner.close();
    return 0;
  }

  out.writeln('Running agent $rootAgentName, type exit to exit.');

  while (true) {
    out.write('[user]: ');
    await out.flush();

    final String? line = stdin.readLineSync();
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

    final List<Event> events = await runtime.sendMessage(
      userId: userId,
      sessionId: session.id,
      message: input,
    );
    _writeEventTexts(events, out: out);
  }

  if (command.saveSession) {
    await _saveSessionSnapshot(
      runtime: runtime,
      session: session,
      projectDir: command.projectDir,
      requestedSessionIdForSave: command.sessionId,
      out: out,
    );
  }

  await runtime.runner.close();
  return 0;
}

class _ReplayInput {
  _ReplayInput({required this.state, required this.queries});

  final Map<String, Object?> state;
  final List<String> queries;

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
    out.writeln('[user]: $query');
    final List<Event> events = await runtime.sendMessage(
      userId: userId,
      sessionId: session.id,
      message: query,
    );
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
}) async {
  if (resumeFilePath == null) {
    return runtime.createSession(userId: userId, sessionId: requestedSessionId);
  }

  final Session loaded = await _loadSessionSnapshot(resumeFilePath);
  final Session session = await runtime.createSessionWithState(
    userId: userId,
    sessionId: requestedSessionId,
    state: loaded.events.isEmpty
        ? Map<String, Object?>.from(loaded.state)
        : null,
  );

  for (final Event event in loaded.events) {
    await runtime.runner.sessionService.appendEvent(
      session: session,
      event: event.copyWith(),
    );
  }

  return session;
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
    saveId = stdin.readLineSync()?.trim();
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
  IOSink err,
) async {
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

  final DevProjectConfig loadedConfig = await loadDevProjectConfig(
    command.projectDir,
    validateProjectDir: true,
  );
  final DevProjectConfig config = command.userId == null
      ? loadedConfig
      : loadedConfig.copyWith(userId: command.userId);
  final DevAgentRuntime runtime = DevAgentRuntime(config: config);

  final HttpServer server;
  try {
    server = await startAdkDevWebServer(
      runtime: runtime,
      project: config,
      agentsDir: command.projectDir,
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
      reload: command.reload,
      reloadAgents: command.reloadAgents,
      traceToCloud: command.traceToCloud,
      otelToCloud: command.otelToCloud,
      a2a: command.a2a,
      extraPlugins: command.extraPlugins,
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

  final List<StreamSubscription<ProcessSignal>> signalSubscriptions =
      <StreamSubscription<ProcessSignal>>[];
  final Completer<void> stopRequested = Completer<void>();

  final List<ProcessSignal> signals = <ProcessSignal>[
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ];

  for (final ProcessSignal signal in signals) {
    try {
      signalSubscriptions.add(
        signal.watch().listen((_) {
          if (!stopRequested.isCompleted) {
            stopRequested.complete();
          }
        }),
      );
    } on UnsupportedError {
      // Signal handling may not be available on all platforms.
    }
  }

  if (signalSubscriptions.isEmpty) {
    out.writeln('Signal handling unavailable. Press Enter to stop.');
    await stdin.first;
  } else {
    await stopRequested.future;
  }

  await server.close(force: true);
  for (final StreamSubscription<ProcessSignal> subscription
      in signalSubscriptions) {
    await subscription.cancel();
  }

  await runtime.runner.close();
  return 0;
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
