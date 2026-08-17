/// Scaffolding helpers for the `adk create` command.
library;

import '../dev/project.dart';

/// Supported runtime backends for newly created agent projects.
enum CreateBackend { geminiApi, vertexAi }

/// Supported starter agent templates for newly created projects.
enum CreateAgentType { basic, workflow }

/// Creates a new ADK project at [projectDir].
///
/// When [appName] is omitted, the project directory name is used.
Future<int> runCreateCommand({
  required String projectDir,
  String? appName,
}) async {
  await createDevProject(projectDirPath: projectDir, appName: appName);
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
      return CreateBackend.geminiApi;
    case 'vertex-ai':
    case 'vertex':
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
    default:
      throw ArgumentError('Unsupported agent type: $value');
  }
}
