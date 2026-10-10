/// Scaffolding helpers for the `adk create` command.
library;

import 'dart:io';

import '../dev/project.dart';

/// Supported runtime backends for newly created agent projects.
enum CreateBackend {
  /// Google AI Studio Gemini API backend.
  geminiApi,

  /// Google Cloud Vertex AI backend.
  vertexAi,
}

/// Supported starter agent templates for newly created projects.
enum CreateAgentType {
  /// Single-agent starter template.
  basic,

  /// Multi-step workflow agent starter template.
  workflow,

  /// Code-based agent project (`agent.dart` + `root_agent.yaml`).
  code,

  /// Declarative YAML configuration agent project (`root_agent.yaml`).
  config,
}

/// Creates a new ADK project at [projectDir].
///
/// When [appName] is omitted, the project directory name is used.
///
/// ```dart
/// final exitCode = await runCreateCommand(
///   projectDir: './my_agent',
///   appName: 'my_agent',
/// );
/// ```
Future<int> runCreateCommand({
  required String projectDir,
  String? appName,
  String? model,
  String? apiKey,
  String? project,
  String? region,
  String? type,
  IOSink? outSink,
}) async {
  await createDevProject(
    projectDirPath: projectDir,
    appName: appName,
    model: model,
    apiKey: apiKey,
    project: project,
    region: region,
    type: type,
  );
  final String resolvedAppName = (appName != null && appName.trim().isNotEmpty)
      ? appName.trim()
      : projectDirName(projectDir);
  final IOSink sink = outSink ?? stdout;
  sink.writeln('Agent created in ${projectDir.trim()}:');
  sink.writeln('  - $resolvedAppName');
  sink.writeln('');
  sink.writeln('Next steps:');
  sink.writeln('  1. Run in terminal:       adk run ${projectDir.trim()}');
  sink.writeln('  2. Launch web UI:         adk web');
  sink.writeln('  3. Serve as an API:       adk api_server');
  return 0;
}

/// Returns the resolved prompt value from [value] or [defaultValue].
///
/// Throws an [ArgumentError] when neither input provides a non-empty value.
String promptStr(String prompt, {String? defaultValue, String? value}) {
  final String chosen = (value ?? defaultValue ?? '').trim();
  if (chosen.isNotEmpty) {
    return chosen;
  }
  throw ArgumentError('Missing value for prompt: $prompt');
}

/// Parses [value] into a [CreateBackend] choice.
///
/// Defaults to `gemini-api` when [value] is `null`.
CreateBackend promptToChooseBackend({String? value}) {
  switch ((value ?? 'gemini-api').toLowerCase()) {
    case 'gemini-api':
    case 'gemini':
    case '1':
      return CreateBackend.geminiApi;
    case 'vertex-ai':
    case 'vertex':
    case '2':
      return CreateBackend.vertexAi;
    default:
      throw ArgumentError('Unsupported backend: $value');
  }
}

/// Parses [value] into a [CreateAgentType] choice.
///
/// Defaults to `basic` when [value] is `null`.
CreateAgentType promptToChooseType({String? value}) {
  switch ((value ?? 'basic').toLowerCase()) {
    case 'basic':
      return CreateAgentType.basic;
    case 'workflow':
      return CreateAgentType.workflow;
    case 'code':
    case '1':
      return CreateAgentType.code;
    case 'config':
    case '2':
      return CreateAgentType.config;
    default:
      throw ArgumentError('Unsupported agent type: $value');
  }
}
