import '../dev/project.dart';

enum CreateBackend { geminiApi, vertexAi }

enum CreateAgentType { basic, workflow }

Future<int> runCreateCommand({
  required String projectDir,
  String? appName,
}) async {
  await createDevProject(projectDirPath: projectDir, appName: appName);
  return 0;
}

String promptStr(String prompt, {String? defaultValue, String? value}) {
  final String chosen = (value ?? defaultValue ?? '').trim();
  if (chosen.isNotEmpty) {
    return chosen;
  }
  throw ArgumentError('Missing value for prompt: $prompt');
}

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
