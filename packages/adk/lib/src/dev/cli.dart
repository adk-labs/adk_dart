/// Core CLI command parsing and execution for the `adk` executable.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';

import 'package:adk_dart/src/agents/base_agent.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/agents/run_config.dart' show StreamingMode;
import 'package:adk_dart/src/apps/app.dart';
import 'package:adk_dart/src/auth/credential_service/in_memory_credential_service.dart';
import '../cli/_cli_generate_agent_card.dart';
import '../cli/cli.dart'
    show collectPendingHitlFunctionCalls, promptForFunctionCall;
import '../cli/cli_create.dart' show validateAgentName;
import '../cli/cli_deploy.dart';
import '../cli/cli_eval.dart' as cli_eval;
import '../cli/conformance/adk_web_server_client.dart';
import 'package:adk_dart/src/runners/runner.dart';
import 'package:adk_dart/src/events/event.dart';
import 'package:adk_dart/src/events/interrupts.dart'
    show indexOpenInterrupts, OpenInterrupt;
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/sessions/schemas/v0.dart';
import 'package:adk_dart/src/sessions/migration/migration_runner.dart'
    as session_migration;
import 'package:adk_dart/src/types/content.dart';
import '../cli/service_registry.dart';
import '../cli/utils/agent_loader.dart';
import '../cli/utils/base_agent_loader.dart';
import '../cli/utils/evals.dart' as cli_evals;
import '../cli/utils/logs.dart' as cli_logs;
import '../cli/utils/service_factory.dart';
import 'package:adk_dart/src/evaluation/base_eval_service.dart';
import 'package:adk_dart/src/evaluation/conversation_scenarios.dart';
import 'package:adk_dart/src/evaluation/eval_case.dart';
import 'package:adk_dart/src/evaluation/eval_config.dart';
import 'package:adk_dart/src/evaluation/eval_metric.dart';
import 'package:adk_dart/src/evaluation/eval_result.dart';
import 'package:adk_dart/src/evaluation/eval_set.dart';
import 'package:adk_dart/src/evaluation/eval_set_results_manager.dart';
import 'package:adk_dart/src/evaluation/eval_sets_manager.dart';
import 'package:adk_dart/src/evaluation/in_memory_eval_set_results_manager.dart';
import 'package:adk_dart/src/evaluation/in_memory_eval_sets_manager.dart';
import 'package:adk_dart/src/evaluation/local_eval_service.dart';
import 'package:adk_dart/src/evaluation/local_eval_set_results_manager.dart';
import 'package:adk_dart/src/evaluation/local_eval_sets_manager.dart'
    show LocalEvalSetsManager, loadEvalSetFromFile;
import 'package:adk_dart/src/features/_feature_registry.dart';
import 'package:adk_dart/src/optimization/gepa_root_agent_prompt_optimizer.dart';
import 'package:adk_dart/src/optimization/local_eval_sampler.dart';
import 'package:adk_dart/src/utils/telemetry_config.dart';
import 'package:adk_dart/src/utils/yaml_utils.dart';
import '../system_info.dart';
import '../version.dart';
import 'project.dart';
import 'runtime.dart';
import 'web_server.dart';

part 'cli_eval_and_optimize.dart';
part 'cli_conformance_and_migrate.dart';
part 'cli_run_and_web.dart';

/// Usage text printed for `adk --help`.
const String adkUsage = '''
Usage: adk <command> [options]

Agent Development Kit CLI tools.

Commands:
  create <app_name>     Creates a new app in the current folder with prepopulated agent template.
  run <agent> [query]   Runs an interactive CLI or single-step query for a certain agent.
  test [folder]         Runs the test suite for an agent project.
  eval <agent_module_file_path> [eval_set_file_path_or_id...]
                        Evaluates an agent given the eval sets.
  eval_set              Manage Eval Sets (create, add_eval_case, generate_eval_cases).
  optimize <agent_module_file_path>
                        Optimizes the root agent instructions based on a local evaluation set.
  web [agents_dir]      Starts a web server with Web UI for agents.
  api_server [agents_dir]
                        Starts an API server for agents.
  deploy                Deploys agent to hosted environments (cloud_run, docker, agent_engine, gke).
  generate_agent_card <agent>
                        Generates an A2A AgentCard JSON file from an agent definition.
  conformance           Conformance testing tools for ADK (record, test).
  migrate               ADK migration commands (session).
  telemetry             Manage telemetry settings (enable/disable/status).
  doctor                Displays ADK Dart CLI environment diagnostics.

Create options:
      --app-name        Logical app name (default: directory name)
      --model           Optional. The model used for the root_agent.
      --api_key         Optional. The API Key needed to access the model.
      --project         Optional. The Google Cloud Project for VertexAI backend.
      --region          Optional. The Google Cloud Region for VertexAI backend.
      --type            Optional. Type of agent to create (CODE, CONFIG).

Run options:
      --user-id         User id (default: from adk.json or "user")
      --session_id      Reuse or save to a specific session ID
      --session_service_uri
      --artifact_service_uri
      --memory_service_uri
      --enable_features  Comma-separated features to force-enable
      --disable_features Comma-separated features to force-disable
      --use_local_storage / --no_use_local_storage
      --save_session    Whether to save the session to a json file on exit
      --resume          The file path to load a previously saved session
      --replay          The json file that contains the initial state of the session and user queries
      --state           Initial state for the run as a JSON object string
      --state_file      Path to a JSON file containing initial state for the run
  -m, --message         The message to send to the agent (skips interactive mode)
      --timeout         Execution timeout (e.g., 10s, 5m, 30)
      --in_memory       Force in-memory session, artifact, and memory storage
      --jsonl           Output events as structured JSONL lines to stdout
      --reload_agents / --no-reload_agents
                        Enable or disable live agent reload during interactive CLI runs
      --default_llm_model
                        Default LLM model name for agents that do not specify one
  -v, --verbose         Enable verbose (DEBUG) logging
      --log_level       Set the logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)

Web / API Server options:
   -p, --port            Port of the server (default: 8000)
      --host            Binding host of the server (default: 127.0.0.1)
      --user-id         User id used by default web session
      --allow_origins   Additional origins to allow for CORS (repeatable, supports regex: prefix)
      --url_prefix      Optional URL path prefix (example: /adk)
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
      --trigger_sources  Comma-separated trigger sources to enable (pubsub, eventarc)
      --trigger_oidc_audience
                        Expected OIDC audience for authenticating /apps/{app_name}/trigger/* requests
      --trigger_oidc_service_accounts
                        Comma-separated allowlist of service account emails permitted as OIDC subjects
      --enable_features  Comma-separated features to force-enable
      --disable_features Comma-separated features to force-disable
      --logo-text       Text to display in the header next to the logo
      --logo-image-url  URL of the image to display as the logo in the header
      --avatar_config   JSON object string or path to a .json file mapping agent names to avatar URLs
      --max_llm_calls   Maximum number of LLM calls allowed per invocation
      --default_llm_model
                        Default LLM model name for agents that do not specify one
      --with_ui         Enable the ADK Web UI alongside the API server
      --gemini_enterprise_app_name
                        Resource name of the Gemini Enterprise App to read settings from
      --express_mode    Enable Gemini Enterprise Express Mode (requires --gemini_enterprise_app_name)
  -v, --verbose         Enable verbose (DEBUG) logging
      --log_level       Set the logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
  -V, --version         Show the version and exit.
  -h, --help            Show this help message.
''';

/// Error thrown when CLI arguments do not satisfy command usage.
class CliUsageError implements Exception {
  /// Creates a usage error with a human-readable [message].
  CliUsageError(this.message);

  /// Description of the invalid usage condition.
  final String message;

  @override
  String toString() => message;
}

/// Top-level command categories supported by the ADK CLI.
enum AdkCommandType {
  /// `adk create`.
  create,

  /// `adk run`.
  run,

  /// `adk web` and `adk api_server`.
  web,
}

/// Parsed arguments for one ADK CLI invocation.
///
/// Use [ParsedAdkCommand.create], [ParsedAdkCommand.run], and
/// [ParsedAdkCommand.web] to build command-specific values.
class ParsedAdkCommand {
  /// Creates parsed arguments for the `create` command.
  ParsedAdkCommand.create({
    required this.projectDir,
    this.appName,
    this.model,
    this.apiKey,
    this.project,
    this.region,
    this.agentType = 'CODE',
  }) : type = AdkCommandType.create,
       port = null,
       host = null,
       userId = null,
       allowOrigins = const <String>[],
       sessionServiceUri = null,
       artifactServiceUri = null,
       memoryServiceUri = null,
       logLevel = null,
       evalStorageUri = null,
       useLocalStorage = true,
       urlPrefix = null,
       traceToCloud = false,
       otelToCloud = false,
       reload = true,
       a2a = false,
       reloadAgents = false,
       extraPlugins = const <String>[],
       triggerSources = const <String>[],
       triggerOidcAudience = null,
       triggerOidcServiceAccounts = const <String>[],
       logoText = null,
       logoImageUrl = null,
       avatarConfig = null,
       maxLlmCalls = null,
       defaultLlmModel = null,
       geminiEnterpriseAppName = null,
       expressMode = false,
       autoCreateSession = false,
       enableWebUi = true,
       sessionId = null,
       saveSession = false,
       resumeFilePath = null,
       replayFilePath = null,
       message = null,
       initialState = null,
       timeout = null,
       inMemory = false,
       jsonl = false,
       usedDeprecatedSessionDbUrl = false,
       usedDeprecatedArtifactStorageUri = false,
       enableFeatures = const <String>[],
       disableFeatures = const <String>[];

  /// Creates parsed arguments for the `run` command.
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
    this.initialState,
    this.timeout,
    this.inMemory = false,
    this.jsonl = false,
    this.reloadAgents = false,
    this.defaultLlmModel,
    this.logLevel,
    required this.enableFeatures,
    required this.disableFeatures,
  }) : type = AdkCommandType.run,
       appName = null,
       model = null,
       apiKey = null,
       project = null,
       region = null,
       agentType = 'CODE',
       port = null,
       host = null,
       allowOrigins = const <String>[],
       evalStorageUri = null,
       urlPrefix = null,
       traceToCloud = false,
       otelToCloud = false,
       reload = true,
       a2a = false,
       extraPlugins = const <String>[],
       triggerSources = const <String>[],
       triggerOidcAudience = null,
       triggerOidcServiceAccounts = const <String>[],
       logoText = null,
       logoImageUrl = null,
       avatarConfig = null,
       maxLlmCalls = null,
       geminiEnterpriseAppName = null,
       expressMode = false,
       autoCreateSession = false,
       enableWebUi = true,
       usedDeprecatedSessionDbUrl = false,
       usedDeprecatedArtifactStorageUri = false;

  /// Creates parsed arguments for the `web` and `api_server` commands.
  ParsedAdkCommand.web({
    required this.projectDir,
    required this.port,
    required this.host,
    this.userId,
    required this.allowOrigins,
    this.sessionServiceUri,
    this.artifactServiceUri,
    this.memoryServiceUri,
    this.logLevel,
    this.evalStorageUri,
    required this.useLocalStorage,
    this.urlPrefix,
    required this.traceToCloud,
    required this.otelToCloud,
    required this.reload,
    required this.a2a,
    required this.reloadAgents,
    required this.extraPlugins,
    this.triggerSources = const <String>[],
    this.triggerOidcAudience,
    this.triggerOidcServiceAccounts = const <String>[],
    this.logoText,
    this.logoImageUrl,
    this.avatarConfig,
    this.maxLlmCalls,
    this.defaultLlmModel,
    this.geminiEnterpriseAppName,
    this.expressMode = false,
    required this.autoCreateSession,
    required this.enableWebUi,
    required this.usedDeprecatedSessionDbUrl,
    required this.usedDeprecatedArtifactStorageUri,
    required this.enableFeatures,
    required this.disableFeatures,
  }) : type = AdkCommandType.web,
       appName = null,
       model = null,
       apiKey = null,
       project = null,
       region = null,
       agentType = 'CODE',
       sessionId = null,
       saveSession = false,
       resumeFilePath = null,
       replayFilePath = null,
       message = null,
       initialState = null,
       timeout = null,
       inMemory = false,
       jsonl = false;

  /// Parsed command type.
  final AdkCommandType type;

  /// Project directory passed on the command line.
  final String projectDir;

  /// App name when a command targets a specific app.
  final String? appName;

  /// Optional model name for `adk create`.
  final String? model;

  /// Optional API key for `adk create`.
  final String? apiKey;

  /// Optional Google Cloud project for `adk create`.
  final String? project;

  /// Optional Google Cloud region for `adk create`.
  final String? region;

  /// Agent scaffold type for `adk create` (`CODE` or `CONFIG`).
  final String agentType;

  /// HTTP port for web and API server commands.
  final int? port;

  /// Host interface for web and API server commands.
  final InternetAddress? host;

  /// User id override used by runtime services.
  final String? userId;

  /// Allowed CORS origins for HTTP server commands.
  final List<String> allowOrigins;

  /// Session service URI override.
  final String? sessionServiceUri;

  /// Artifact service URI override.
  final String? artifactServiceUri;

  /// Memory service URI override.
  final String? memoryServiceUri;

  /// Log level override.
  final String? logLevel;

  /// Evaluation storage URI override.
  final String? evalStorageUri;

  /// Whether local storage-backed services are enabled.
  final bool useLocalStorage;

  /// URL prefix used when the app is mounted under a path.
  final String? urlPrefix;

  /// Whether trace data is exported to Google Cloud.
  final bool traceToCloud;

  /// Whether OpenTelemetry data is exported to Google Cloud.
  final bool otelToCloud;

  /// Whether file-watcher based hot reload is enabled.
  final bool reload;

  /// Whether A2A endpoint support is enabled.
  final bool a2a;

  /// Whether runtime agent definitions can be reloaded.
  final bool reloadAgents;

  /// Extra plugin specs passed from the command line.
  final List<String> extraPlugins;

  /// Event trigger sources (`pubsub`, `eventarc`) enabled on the server.
  final List<String> triggerSources;

  /// Expected OIDC audience for authenticating `/apps/{app_name}/trigger/*` requests.
  final String? triggerOidcAudience;

  /// Optional allowlist of service account emails permitted as OIDC token subjects.
  final List<String> triggerOidcServiceAccounts;

  /// Optional logo text for the web UI.
  final String? logoText;

  /// Optional logo image URL for the web UI.
  final String? logoImageUrl;

  /// Optional mapping of agent names to avatar URLs for the web UI.
  final Map<String, String>? avatarConfig;

  /// Optional maximum number of LLM calls per invocation.
  final int? maxLlmCalls;

  /// Optional default LLM model name for agents that do not specify one.
  final String? defaultLlmModel;

  /// Resource name of the Gemini Enterprise App to read settings from.
  final String? geminiEnterpriseAppName;

  /// Whether Gemini Enterprise Express Mode is enabled.
  final bool expressMode;

  /// Whether missing sessions are created automatically.
  final bool autoCreateSession;

  /// Whether the web UI is served.
  final bool enableWebUi;

  /// Existing session id used by CLI run mode.
  final String? sessionId;

  /// Whether CLI run mode persists a recording at exit.
  final bool saveSession;

  /// Input path for resuming a saved recording.
  final String? resumeFilePath;

  /// Input path for replaying a recording.
  final String? replayFilePath;

  /// Initial message passed to non-interactive run mode.
  final String? message;

  /// Optional initial session state parsed from `--state` or `--state_file`.
  final Map<String, Object?>? initialState;

  /// Optional timeout in seconds (parsed from e.g. `10s`, `5m`, `30`) for `adk run`.
  final int? timeout;

  /// Whether `adk run` forces in-memory session, artifact, and memory services.
  final bool inMemory;

  /// Whether `adk run` emits events as structured JSONL lines.
  final bool jsonl;

  /// Whether deprecated `--session_db_url` was used.
  final bool usedDeprecatedSessionDbUrl;

  /// Whether deprecated `--artifact_storage_uri` was used.
  final bool usedDeprecatedArtifactStorageUri;

  /// Feature flags forced to enabled.
  final List<String> enableFeatures;

  /// Feature flags forced to disabled.
  final List<String> disableFeatures;
}

/// Parses CLI [args] into a typed [ParsedAdkCommand].
///
/// Throws a [CliUsageError] when the command is missing or unknown.
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

/// Optional override for testing telemetry consent writes.
@visibleForTesting
void Function(bool consent)? writeTelemetryConsentTestingOverride;

/// Optional override for testing subcommand execution in runAdkCli.
@visibleForTesting
Future<int> Function(ParsedAdkCommand command)? runSubcommandTestingOverride;

/// Runs the ADK CLI command handler and returns an exit code.
///
/// Returns `0` for success, `64` for usage errors, and non-zero runtime exit
/// codes for command failures.
///
/// ```dart
/// final exitCode = await runAdkCli(['create', './my_agent']);
/// ```
Future<int> runAdkCli(
  List<String> args, {
  IOSink? outSink,
  IOSink? errSink,
  Future<void>? stopSignal,
  String? Function()? readLine,
}) async {
  final IOSink out = outSink ?? stdout;
  final IOSink err = errSink ?? stderr;

  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    out.writeln(adkUsage);
    return 0;
  }

  if (args.length == 1 &&
      (args.first == '--version' ||
          args.first == '-V' ||
          args.first == '-v' ||
          args.first == 'version')) {
    out.writeln('adk version $adkPackageVersion (spec $adkSpecVersion)');
    return 0;
  }

  if (args.first == 'doctor' || args.first == 'diag') {
    if (args.contains('-h') || args.contains('--help')) {
      out.writeln(adkUsage);
      return 0;
    }
    out.write(AdkSystemInfo.formatSummary());
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

  if (args.first == 'generate_agent_card' ||
      args.first == 'generate-agent-card') {
    return runGenerateAgentCardCommand(
      args.skip(1).toList(growable: false),
      outSink: out,
      errSink: err,
    );
  }

  if (args.first != 'test' &&
      (args.contains('-h') || args.contains('--help'))) {
    out.writeln(adkUsage);
    return 0;
  }

  try {
    if (args.first == 'eval') {
      return await _runEvalCliCommand(
        args.skip(1).toList(growable: false),
        out: out,
        err: err,
      );
    }

    if (args.first == 'eval_set') {
      return await _runEvalSetCliCommand(
        args.skip(1).toList(growable: false),
        out: out,
      );
    }

    if (args.first == 'conformance') {
      return await _runConformanceCliCommand(
        args.skip(1).toList(growable: false),
        out: out,
      );
    }

    if (args.first == 'optimize') {
      return await _runOptimizeCliCommand(
        args.skip(1).toList(growable: false),
        out: out,
        err: err,
      );
    }

    if (args.first == 'migrate') {
      return await _runMigrateCliCommand(
        args.skip(1).toList(growable: false),
        out: out,
      );
    }

    if (args.first == 'telemetry') {
      if (args.length < 2 || args[1] == 'status') {
        final bool? consent = readTelemetryConsent();
        if (consent == true) {
          out.writeln('Telemetry collection is enabled.');
        } else if (consent == false) {
          out.writeln('Telemetry collection is disabled.');
        } else {
          out.writeln(
            'Telemetry collection is not configured (defaults to OFF).',
          );
        }
        return 0;
      }
      final String sub = args[1].toLowerCase();
      if (sub == 'enable' || sub == 'on') {
        try {
          if (writeTelemetryConsentTestingOverride != null) {
            writeTelemetryConsentTestingOverride!(true);
          } else {
            writeTelemetryConsent(true);
          }
          out.writeln('Telemetry collection has been enabled.');
          return 0;
        } catch (e) {
          err.writeln('Failed to enable telemetry: $e');
          return 1;
        }
      } else if (sub == 'disable' || sub == 'off') {
        try {
          if (writeTelemetryConsentTestingOverride != null) {
            writeTelemetryConsentTestingOverride!(false);
          } else {
            writeTelemetryConsent(false);
          }
          out.writeln('Telemetry collection has been disabled.');
          return 0;
        } catch (e) {
          err.writeln('Failed to disable telemetry: $e');
          return 1;
        }
      } else {
        err.writeln(
          'Unknown telemetry command: $sub. Expected enable, disable, or status.',
        );
        return 64;
      }
    }

    if (args.first == 'test') {
      return await _runTestCliCommand(
        args.skip(1).toList(growable: false),
        out: out,
      );
    }

    final ParsedAdkCommand parsed = parseAdkCliArgs(args);
    _applyFeatureOverridesFromCli(
      enableFeatures: parsed.enableFeatures,
      disableFeatures: parsed.disableFeatures,
      err: err,
    );

    if (runSubcommandTestingOverride != null) {
      return await runSubcommandTestingOverride!(parsed);
    }

    late final int exitCode;
    switch (parsed.type) {
      case AdkCommandType.create:
        exitCode = await _runCreateCommand(parsed, out);
        break;
      case AdkCommandType.run:
        exitCode = await _runRunCommand(parsed, out, err: err, readLine: readLine);
        break;
      case AdkCommandType.web:
        exitCode = await _runWebCommand(parsed, out, err, stopSignal: stopSignal);
        break;
    }
    return exitCode;
  } on CliUsageError catch (error) {
    err.writeln(error.message);
    err.writeln('');
    err.writeln(adkUsage);
    return 64;
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

ParsedAdkCommand _parseCreateCommand(List<String> args) {
  String? projectDir;
  String? appName;
  String? model;
  String? apiKey;
  String? project;
  String? region;
  String? agentType;

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--app-name' || arg == '--app_name') {
      appName = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--app-name=') || arg.startsWith('--app_name=')) {
      appName = arg.substring(arg.indexOf('=') + 1).trim();
      continue;
    }
    if (arg == '--model' || arg == '-m') {
      model = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--model=')) {
      model = arg.substring('--model='.length).trim();
      continue;
    }
    if (arg == '--api_key' || arg == '--api-key') {
      apiKey = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--api_key=') || arg.startsWith('--api-key=')) {
      apiKey = arg.substring(arg.indexOf('=') + 1).trim();
      continue;
    }
    if (arg == '--project') {
      project = _nextArg(args, i, '--project');
      i += 1;
      continue;
    }
    if (arg.startsWith('--project=')) {
      project = arg.substring('--project='.length).trim();
      continue;
    }
    if (arg == '--region') {
      region = _nextArg(args, i, '--region');
      i += 1;
      continue;
    }
    if (arg.startsWith('--region=')) {
      region = arg.substring('--region='.length).trim();
      continue;
    }
    if (arg == '--type') {
      agentType = _nextArg(args, i, '--type').trim().toUpperCase();
      i += 1;
      continue;
    }
    if (arg.startsWith('--type=')) {
      agentType = arg.substring('--type='.length).trim().toUpperCase();
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

  final String? normalizedType = _emptyToNull(agentType);
  if (normalizedType != null &&
      normalizedType != 'CODE' &&
      normalizedType != 'CONFIG' &&
      normalizedType != 'BASIC' &&
      normalizedType != 'WORKFLOW') {
    throw CliUsageError(
      'Invalid value for --type: $normalizedType. Supported: CODE, CONFIG, BASIC, WORKFLOW.',
    );
  }

  return ParsedAdkCommand.create(
    projectDir: projectDir,
    appName: _emptyToNull(appName),
    model: _emptyToNull(model),
    apiKey: _emptyToNull(apiKey),
    project: _emptyToNull(project),
    region: _emptyToNull(region),
    agentType: normalizedType ?? 'CODE',
  );
}

int _parseTimeoutSeconds(String rawTimeout) {
  final String trimmed = rawTimeout.trim().toLowerCase();
  if (trimmed.isEmpty) {
    throw CliUsageError('Invalid value for --timeout: $rawTimeout');
  }
  final RegExpMatch? match = RegExp(r'^(\d+)([smh]?)$').firstMatch(trimmed);
  if (match == null) {
    throw CliUsageError('Invalid value for --timeout: $rawTimeout');
  }
  final int? value = int.tryParse(match.group(1)!);
  if (value == null || value <= 0) {
    throw CliUsageError('Invalid value for --timeout: $rawTimeout');
  }
  final String unit = match.group(2) ?? '';
  return switch (unit) {
    'm' => value * 60,
    'h' => value * 3600,
    _ => value,
  };
}

ParsedAdkCommand _parseRunCommand(List<String> args) {
  String? projectDir;
  String? positionalQuery;
  String? userId;
  String? sessionId;
  String? sessionServiceUri;
  String? artifactServiceUri;
  String? memoryServiceUri;
  final List<String> enableFeatures = <String>[];
  final List<String> disableFeatures = <String>[];
  String? resumeFilePath;
  String? replayFilePath;
  String? message;
  String? stateJson;
  String? stateFilePath;
  String? defaultLlmModel;
  String? logLevel;
  bool verbose = false;
  int? timeout;
  bool inMemory = false;
  bool jsonl = false;
  bool reloadAgents = false;
  bool saveSession = false;
  bool useLocalStorage = true;
  bool explicitUseLocalStorageFlag = false;
  final List<String> positionals = <String>[];

  for (int i = 0; i < args.length; i += 1) {
    final String arg = args[i];
    if (arg == '--user-id' || arg == '--user_id') {
      userId = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--user-id=') || arg.startsWith('--user_id=')) {
      userId = arg.substring(arg.indexOf('=') + 1);
      continue;
    }
    if (arg == '--session-id' || arg == '--session_id') {
      sessionId = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--session-id=') || arg.startsWith('--session_id=')) {
      sessionId = arg.substring(arg.indexOf('=') + 1);
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
    if (arg == '--enable_features') {
      enableFeatures.add(_nextArg(args, i, '--enable_features'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--enable_features=')) {
      enableFeatures.add(arg.substring('--enable_features='.length));
      continue;
    }
    if (arg == '--disable_features') {
      disableFeatures.add(_nextArg(args, i, '--disable_features'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--disable_features=')) {
      disableFeatures.add(arg.substring('--disable_features='.length));
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
    if (arg == '--in_memory' || arg == '--in-memory') {
      inMemory = true;
      useLocalStorage = false;
      continue;
    }
    if (arg == '--jsonl') {
      jsonl = true;
      continue;
    }
    if (arg == '--reload_agents' || arg == '--reload-agents') {
      reloadAgents = true;
      continue;
    }
    if (arg == '--no-reload_agents' ||
        arg == '--no_reload_agents' ||
        arg == '--no-reload-agents') {
      reloadAgents = false;
      continue;
    }
    if (arg == '--timeout') {
      timeout = _parseTimeoutSeconds(_nextArg(args, i, '--timeout'));
      i += 1;
      continue;
    }
    if (arg.startsWith('--timeout=')) {
      timeout = _parseTimeoutSeconds(arg.substring('--timeout='.length));
      continue;
    }
    if (arg == '--default_llm_model' || arg == '--default-llm-model') {
      defaultLlmModel = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--default_llm_model=') ||
        arg.startsWith('--default-llm-model=')) {
      defaultLlmModel = arg.substring(arg.indexOf('=') + 1);
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
    if (arg == '-m' || arg == '--message') {
      message = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--message=')) {
      message = arg.substring('--message='.length);
      continue;
    }
    if (arg == '--state') {
      stateJson = _nextArg(args, i, '--state');
      i += 1;
      continue;
    }
    if (arg.startsWith('--state=')) {
      stateJson = arg.substring('--state='.length);
      continue;
    }
    if (arg == '--state_file' || arg == '--state-file') {
      stateFilePath = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--state_file=')) {
      stateFilePath = arg.substring('--state_file='.length);
      continue;
    }
    if (arg.startsWith('--state-file=')) {
      stateFilePath = arg.substring('--state-file='.length);
      continue;
    }
    if (arg == '--save_session') {
      saveSession = true;
      continue;
    }
    if (arg == '--no-save_session' || arg == '--no_save_session') {
      saveSession = false;
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

    positionals.add(arg);
  }

  if (positionals.length > 2) {
    throw CliUsageError('run accepts <agent_dir> and optional [query].');
  }
  if (positionals.isNotEmpty) {
    projectDir = positionals[0];
  }
  if (positionals.length == 2) {
    positionalQuery = positionals[1];
  }

  if (stateJson != null && stateFilePath != null) {
    throw CliUsageError(
      "Options 'state' and 'state_file' cannot be set together.",
    );
  }
  Map<String, Object?>? initialState;
  if (stateFilePath != null) {
    final String normalizedStateFilePath = stateFilePath.trim();
    if (normalizedStateFilePath.isEmpty) {
      throw CliUsageError('Missing value for --state_file.');
    }
    final String rawState;
    try {
      rawState = File(normalizedStateFilePath).readAsStringSync();
    } on FileSystemException catch (error) {
      throw CliUsageError(
        "Failed to read --state_file '$normalizedStateFilePath': $error",
      );
    }
    initialState = _parseInitialStateJson(
      rawState,
      sourceLabel: "--state_file '$normalizedStateFilePath'",
    );
  } else if (stateJson != null) {
    initialState = _parseInitialStateJson(stateJson, sourceLabel: '--state');
  }

  if (_emptyToNull(message) != null && _emptyToNull(positionalQuery) != null) {
    throw CliUsageError(
      'Positional [query] and --message cannot be used together.',
    );
  }
  final String? effectiveMessage =
      _emptyToNull(message) ?? _emptyToNull(positionalQuery);

  if (_emptyToNull(resumeFilePath) != null &&
      _emptyToNull(replayFilePath) != null) {
    throw CliUsageError('--resume and --replay cannot be used together.');
  }
  if (effectiveMessage != null && _emptyToNull(replayFilePath) != null) {
    throw CliUsageError('--message/query and --replay cannot be used together.');
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
  if (inMemory &&
      (_emptyToNull(sessionServiceUri) != null ||
          _emptyToNull(artifactServiceUri) != null ||
          _emptyToNull(memoryServiceUri) != null)) {
    throw CliUsageError(
      '--in_memory cannot be used with --session_service_uri, '
      '--artifact_service_uri, or --memory_service_uri.',
    );
  }
  if (inMemory && saveSession) {
    throw CliUsageError('--in_memory cannot be used with --save_session.');
  }

  final String? resolvedLogLevel = (logLevel != null || verbose)
      ? _resolveCliLogLevel(explicit: _emptyToNull(logLevel), verbose: verbose)
      : null;

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
    message: effectiveMessage,
    initialState: initialState,
    enableFeatures: _normalizeCsvValues(enableFeatures),
    disableFeatures: _normalizeCsvValues(disableFeatures),
    defaultLlmModel: _emptyToNull(defaultLlmModel),
    logLevel: resolvedLogLevel,
    timeout: timeout,
    inMemory: inMemory,
    jsonl: jsonl,
    reloadAgents: reloadAgents,
  );
}

Map<String, Object?> _parseInitialStateJson(
  String rawJson, {
  required String sourceLabel,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(rawJson);
  } on FormatException catch (error) {
    throw CliUsageError('Invalid JSON for $sourceLabel: $error');
  }
  if (decoded is! Map) {
    throw CliUsageError(
      'Invalid JSON for $sourceLabel: expected a JSON object.',
    );
  }
  return decoded.map((Object? key, Object? value) => MapEntry('$key', value));
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
  final List<String> enableFeatures = <String>[];
  final List<String> disableFeatures = <String>[];
  String? logLevel;
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
  final List<String> triggerSources = <String>[];
  final List<String> triggerOidcServiceAccounts = <String>[];
  String? triggerOidcAudience;
  String? logoText;
  String? logoImageUrl;
  String? avatarConfigRaw;
  int maxLlmCalls = 500;
  String? defaultLlmModel;
  String? geminiEnterpriseAppName;
  bool expressMode = false;
  bool effectiveEnableWebUi = enableWebUi;
  bool autoCreateSession = false;
  bool verbose = false;
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
    if (arg == '--user-id' || arg == '--user_id') {
      userId = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--user-id=') || arg.startsWith('--user_id=')) {
      userId = arg.substring(arg.indexOf('=') + 1);
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
    if (arg == '--enable_features') {
      enableFeatures.add(_nextArg(args, i, '--enable_features').trim());
      i += 1;
      continue;
    }
    if (arg.startsWith('--enable_features=')) {
      enableFeatures.add(arg.substring('--enable_features='.length).trim());
      continue;
    }
    if (arg == '--disable_features') {
      disableFeatures.add(_nextArg(args, i, '--disable_features').trim());
      i += 1;
      continue;
    }
    if (arg.startsWith('--disable_features=')) {
      disableFeatures.add(arg.substring('--disable_features='.length).trim());
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
    if (arg == '--trigger_sources' || arg == '--trigger-sources') {
      triggerSources.add(_nextArg(args, i, arg).trim());
      i += 1;
      continue;
    }
    if (arg.startsWith('--trigger_sources=')) {
      triggerSources.add(arg.substring('--trigger_sources='.length).trim());
      continue;
    }
    if (arg.startsWith('--trigger-sources=')) {
      triggerSources.add(arg.substring('--trigger-sources='.length).trim());
      continue;
    }
    if (arg == '--trigger_oidc_audience' || arg == '--trigger-oidc-audience') {
      triggerOidcAudience = _nextArg(args, i, arg).trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--trigger_oidc_audience=') ||
        arg.startsWith('--trigger-oidc-audience=')) {
      triggerOidcAudience = arg.substring(arg.indexOf('=') + 1).trim();
      continue;
    }
    if (arg == '--trigger_oidc_service_accounts' ||
        arg == '--trigger-oidc-service-accounts') {
      triggerOidcServiceAccounts.add(_nextArg(args, i, arg).trim());
      i += 1;
      continue;
    }
    if (arg.startsWith('--trigger_oidc_service_accounts=') ||
        arg.startsWith('--trigger-oidc-service-accounts=')) {
      triggerOidcServiceAccounts.add(
        arg.substring(arg.indexOf('=') + 1).trim(),
      );
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
    if (arg == '--avatar_config' || arg == '--avatar-config') {
      avatarConfigRaw = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg.startsWith('--avatar_config=') ||
        arg.startsWith('--avatar-config=')) {
      avatarConfigRaw = arg.substring(arg.indexOf('=') + 1);
      continue;
    }
    if (arg == '--max_llm_calls' || arg == '--max-llm-calls') {
      final String rawMax = _nextArg(args, i, arg);
      final int? parsed = int.tryParse(rawMax.trim());
      if (parsed == null) {
        throw CliUsageError('Invalid value for --max_llm_calls: $rawMax');
      }
      maxLlmCalls = parsed;
      i += 1;
      continue;
    }
    if (arg.startsWith('--max_llm_calls=') ||
        arg.startsWith('--max-llm-calls=')) {
      final String rawMax = arg.substring(arg.indexOf('=') + 1);
      final int? parsed = int.tryParse(rawMax.trim());
      if (parsed == null) {
        throw CliUsageError('Invalid value for --max_llm_calls: $rawMax');
      }
      maxLlmCalls = parsed;
      continue;
    }
    if (arg == '--default_llm_model' || arg == '--default-llm-model') {
      defaultLlmModel = _nextArg(args, i, arg).trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--default_llm_model=') ||
        arg.startsWith('--default-llm-model=')) {
      defaultLlmModel = arg.substring(arg.indexOf('=') + 1).trim();
      continue;
    }
    if (arg == '--with_ui' || arg == '--with-ui') {
      effectiveEnableWebUi = true;
      continue;
    }
    if (arg == '--no-with_ui' ||
        arg == '--no_with_ui' ||
        arg == '--no-with-ui' ||
        arg == '--no-ui') {
      effectiveEnableWebUi = false;
      continue;
    }
    if (arg == '--gemini_enterprise_app_name' ||
        arg == '--gemini-enterprise-app-name') {
      geminiEnterpriseAppName = _nextArg(args, i, arg).trim();
      i += 1;
      continue;
    }
    if (arg.startsWith('--gemini_enterprise_app_name=') ||
        arg.startsWith('--gemini-enterprise-app-name=')) {
      geminiEnterpriseAppName = arg.substring(arg.indexOf('=') + 1).trim();
      continue;
    }
    if (arg == '--express_mode' || arg == '--express-mode') {
      expressMode = true;
      continue;
    }
    if (arg == '--no-express_mode' ||
        arg == '--no_express_mode' ||
        arg == '--no-express-mode') {
      expressMode = false;
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
    if (arg == '--no-reload' || arg == '--no_reload') {
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
    if (arg == '--log_level' ||
        arg == '--log-level' ||
        arg == '--verbosity') {
      logLevel = _nextArg(args, i, arg);
      i += 1;
      continue;
    }
    if (arg == '-v' || arg == '--verbose') {
      verbose = true;
      continue;
    }
    if (arg.startsWith('--log_level=') ||
        arg.startsWith('--log-level=') ||
        arg.startsWith('--verbosity=')) {
      logLevel = arg.substring(arg.indexOf('=') + 1);
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
  final String normalizedLogLevel = _resolveCliLogLevel(
    explicit: _emptyToNull(logLevel),
    verbose: verbose,
  );
  final String? normalizedEvalStorageUri = _emptyToNull(evalStorageUri);
  if (explicitUseLocalStorageFlag &&
      (normalizedSessionServiceUri != null ||
          normalizedArtifactServiceUri != null)) {
    throw CliUsageError(
      '--use_local_storage/--no_use_local_storage cannot be used with '
      '--session_service_uri or --artifact_service_uri.',
    );
  }

  final List<String> normalizedTriggerSources = _normalizeCsvValues(
    triggerSources,
  ).map((String item) => item.toLowerCase()).toList(growable: false);
  for (final String source in normalizedTriggerSources) {
    if (source != 'pubsub' && source != 'eventarc') {
      throw CliUsageError(
        'Invalid trigger source "$source". Supported: pubsub, eventarc.',
      );
    }
  }

  final String? normalizedOidcAudience = _emptyToNull(triggerOidcAudience);
  final List<String> normalizedOidcServiceAccounts = _normalizeCsvValues(
    triggerOidcServiceAccounts,
  );
  if (normalizedTriggerSources.isNotEmpty &&
      !host.isLoopback &&
      normalizedOidcAudience == null &&
      normalizedOidcServiceAccounts.isEmpty) {
    throw CliUsageError(
      'When --trigger_sources is used on a non-loopback host (${host.address}), '
      'at least one of --trigger_oidc_audience or '
      '--trigger_oidc_service_accounts must be specified.',
    );
  }

  final String? normalizedEnterpriseAppName = _emptyToNull(
    geminiEnterpriseAppName,
  );
  if (expressMode && normalizedEnterpriseAppName == null) {
    throw CliUsageError(
      '--express_mode requires --gemini_enterprise_app_name.',
    );
  }

  Map<String, String>? parsedAvatarConfig;
  if (_emptyToNull(avatarConfigRaw) != null) {
    final String rawAvatar = avatarConfigRaw!.trim();
    String jsonText = rawAvatar;
    final File avatarFile = File(rawAvatar);
    if (avatarFile.existsSync() ||
        FileSystemEntity.typeSync(rawAvatar) ==
            FileSystemEntityType.directory) {
      try {
        jsonText = avatarFile.readAsStringSync().trim();
      } on FileSystemException catch (error) {
        throw CliUsageError(
          "could not read avatar configuration file '$rawAvatar': $error",
        );
      }
    }
    if (jsonText.startsWith('{') || jsonText.startsWith('[')) {
      final Object? decoded;
      try {
        decoded = jsonDecode(jsonText);
      } on FormatException catch (error) {
        throw CliUsageError('Invalid JSON for --avatar_config: $error');
      }
      if (decoded is! Map) {
        throw CliUsageError(
          'Invalid --avatar_config: expected a JSON object mapping agent names to avatar configs.',
        );
      }
      parsedAvatarConfig = decoded.map(
        (Object? key, Object? value) => MapEntry('$key', '${value ?? ''}'),
      );
    } else {
      final Map<String, String> kvMap = <String, String>{};
      for (final String entry in jsonText.split(',')) {
        final String trimmed = entry.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        final int eqIdx = trimmed.indexOf('=');
        final int colonIdx = trimmed.indexOf(':');
        final int sepIdx = (eqIdx > 0 && (colonIdx <= 0 || eqIdx < colonIdx))
            ? eqIdx
            : colonIdx;
        if (sepIdx <= 0) {
          throw CliUsageError('Invalid --avatar_config entry: $trimmed');
        }
        final String k = trimmed.substring(0, sepIdx).trim();
        final String v = trimmed.substring(sepIdx + 1).trim();
        if (k.isEmpty || v.isEmpty) {
          throw CliUsageError('Invalid --avatar_config entry: $trimmed');
        }
        kvMap[k] = v;
      }
      parsedAvatarConfig = kvMap;
    }
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
    logLevel: normalizedLogLevel,
    evalStorageUri: normalizedEvalStorageUri,
    useLocalStorage: useLocalStorage,
    urlPrefix: _emptyToNull(urlPrefix),
    traceToCloud: traceToCloud,
    otelToCloud: otelToCloud,
    reload: reload,
    a2a: a2a,
    reloadAgents: reloadAgents,
    extraPlugins: _normalizeCsvValues(extraPlugins),
    triggerSources: normalizedTriggerSources,
    logoText: _emptyToNull(logoText),
    logoImageUrl: _emptyToNull(logoImageUrl),
    avatarConfig: parsedAvatarConfig,
    maxLlmCalls: maxLlmCalls,
    defaultLlmModel: _emptyToNull(defaultLlmModel),
    triggerOidcAudience: normalizedOidcAudience,
    triggerOidcServiceAccounts: normalizedOidcServiceAccounts,
    geminiEnterpriseAppName: normalizedEnterpriseAppName,
    expressMode: expressMode,
    autoCreateSession: autoCreateSession,
    enableWebUi: effectiveEnableWebUi,
    usedDeprecatedSessionDbUrl: usedDeprecatedSessionDbUrl,
    usedDeprecatedArtifactStorageUri: usedDeprecatedArtifactStorageUri,
    enableFeatures: _normalizeCsvValues(enableFeatures),
    disableFeatures: _normalizeCsvValues(disableFeatures),
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
