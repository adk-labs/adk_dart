/// Utilities for ADK CLI onboarding flow.
library;

import 'dart:io';

import 'envs.dart';
import 'gcp_utils.dart' as gcp_utils;

/// Informational message linking to Google AI Studio API key creation.
const String googleApiMsg = '''
Don't have API Key? Create one in AI Studio: https://aistudio.google.com/apikey
''';

/// Informational message linking to Google Cloud Vertex AI setup documentation.
const String googleCloudSetupMsg = '''
You need an existing Google Cloud account and project, check out this link for details:
https://google.github.io/adk-docs/get-started/quickstart/#gemini---google-cloud-vertex-ai
''';

/// Terms of service message displayed before Express Mode project signup.
const String expressTosMsg = '''
Google Cloud Express Mode Terms of Service: https://cloud.google.com/terms/google-cloud-express
By using this application, you agree to the Google Cloud Express Mode terms of service and any
applicable services and APIs: https://console.cloud.google.com/terms. You also agree to only use
this application for your trade, business, craft, or profession.
''';

/// Error message displayed when the user is ineligible for Express Mode.
const String notEligibleMsg = '''
You are not eligible for Express Mode.
Please follow these instructions to set up a full Google Cloud project:
https://google.github.io/adk-docs/get-started/quickstart/#gemini---google-cloud-vertex-ai
''';

/// Exception thrown when the CLI onboarding flow is aborted by the user or an error.
class OnboardingAbortException implements Exception {
  /// Creates an onboarding abort exception.
  const OnboardingAbortException([this.message = 'Aborted!']);

  /// Optional abort reason.
  final String message;

  @override
  String toString() => 'OnboardingAbortException: $message';
}

/// Base class for resolved CLI onboarding authentication configurations.
sealed class OnboardingAuth {
  /// Creates an onboarding authentication model.
  const OnboardingAuth();
}

/// Google AI Studio API key authentication model.
class GoogleAIAuth extends OnboardingAuth {
  /// Creates a Google AI authentication model.
  const GoogleAIAuth({required this.apiKey});

  /// Google AI Studio API key.
  final String apiKey;
}

/// Google Cloud Vertex AI authentication model.
class VertexAIAuth extends OnboardingAuth {
  /// Creates a Vertex AI authentication model.
  const VertexAIAuth({required this.projectId, required this.region});

  /// Google Cloud project identifier.
  final String projectId;

  /// Google Cloud region.
  final String region;
}

/// Google Cloud Express Mode authentication model.
class ExpressModeAuth extends OnboardingAuth {
  /// Creates an Express Mode authentication model.
  const ExpressModeAuth({
    required this.apiKey,
    required this.projectId,
    required this.region,
  });

  /// Optional Express Mode default API key.
  final String? apiKey;

  /// Express Mode project identifier.
  final String projectId;

  /// Express Mode region.
  final String region;
}

/// Shared metadata store for recording the last onboarding telemetry action.
final Map<String, Object?> onboardingTelemetryContextMeta =
    <String, Object?>{};

/// Uses `gcloud` to get the default project ID.
String getGcpProjectFromGcloud({
  gcp_utils.GcloudProcessRunner? processRunner,
}) {
  final gcp_utils.GcloudProcessRunner runner =
      processRunner ?? Process.runSync;
  try {
    final ProcessResult result = runner('gcloud', <String>[
      'config',
      'get-value',
      'project',
    ]);
    if (result.exitCode != 0) {
      return '';
    }
    return '${result.stdout}'.trim();
  } on Object {
    return '';
  }
}

/// Uses `gcloud` to get the default compute region.
String getGcpRegionFromGcloud({
  gcp_utils.GcloudProcessRunner? processRunner,
}) {
  final gcp_utils.GcloudProcessRunner runner =
      processRunner ?? Process.runSync;
  try {
    final ProcessResult result = runner('gcloud', <String>[
      'config',
      'get-value',
      'compute/region',
    ]);
    if (result.exitCode != 0) {
      return '';
    }
    return '${result.stdout}'.trim();
  } on Object {
    return '';
  }
}

/// Prompts the user for a non-empty string with [promptPrefix].
String promptStr(
  String promptPrefix, {
  String? priorMsg,
  String? defaultValue,
  String? Function(String promptPrefix, {String? defaultValue})? promptInput,
  void Function(String message)? echo,
}) {
  final void Function(String) out = echo ?? stdout.writeln;
  if (priorMsg != null && priorMsg.isNotEmpty) {
    out(priorMsg);
  }
  while (true) {
    final String? rawValue;
    if (promptInput != null) {
      rawValue = promptInput(
        promptPrefix,
        defaultValue: (defaultValue != null && defaultValue.isNotEmpty)
            ? defaultValue
            : null,
      );
    } else {
      final String suffix =
          (defaultValue != null && defaultValue.isNotEmpty)
              ? ' [$defaultValue]: '
              : ': ';
      stdout.write('$promptPrefix$suffix');
      final String? line = stdin.readLineSync();
      if (line == null) {
        rawValue = defaultValue;
      } else if (line.trim().isEmpty &&
          defaultValue != null &&
          defaultValue.isNotEmpty) {
        rawValue = defaultValue;
      } else {
        rawValue = line;
      }
    }
    if (rawValue != null && rawValue.trim().isNotEmpty) {
      return rawValue.trim();
    }
  }
}

/// Prompts the user for a Google Cloud project ID.
String promptForGoogleCloud(
  String? googleCloudProject, {
  Map<String, String>? environment,
  gcp_utils.GcloudProcessRunner? processRunner,
  String? Function(String promptPrefix, {String? defaultValue})? promptInput,
  void Function(String message)? echo,
}) {
  final String? envProject =
      environment?['GOOGLE_CLOUD_PROJECT'] ??
      getCliEnvironmentValue('GOOGLE_CLOUD_PROJECT');
  final String resolvedDefault =
      (googleCloudProject != null && googleCloudProject.isNotEmpty)
          ? googleCloudProject
          : (envProject != null && envProject.isNotEmpty
                ? envProject
                : getGcpProjectFromGcloud(processRunner: processRunner));

  return promptStr(
    'Enter Google Cloud project ID',
    defaultValue: resolvedDefault.isEmpty ? null : resolvedDefault,
    promptInput: promptInput,
    echo: echo,
  );
}

/// Prompts the user for a Google Cloud region.
String promptForGoogleCloudRegion(
  String? googleCloudRegion, {
  Map<String, String>? environment,
  gcp_utils.GcloudProcessRunner? processRunner,
  String? Function(String promptPrefix, {String? defaultValue})? promptInput,
  void Function(String message)? echo,
}) {
  final String? envRegion =
      environment?['GOOGLE_CLOUD_LOCATION'] ??
      getCliEnvironmentValue('GOOGLE_CLOUD_LOCATION');
  final String candidate =
      (googleCloudRegion != null && googleCloudRegion.isNotEmpty)
          ? googleCloudRegion
          : (envRegion != null && envRegion.isNotEmpty
                ? envRegion
                : getGcpRegionFromGcloud(processRunner: processRunner));

  return promptStr(
    'Enter Google Cloud region',
    defaultValue: candidate.isNotEmpty ? candidate : 'us-central1',
    promptInput: promptInput,
    echo: echo,
  );
}

/// Prompts the user for a Google API key.
String promptForGoogleApiKey(
  String? googleApiKey, {
  Map<String, String>? environment,
  String? Function(String promptPrefix, {String? defaultValue})? promptInput,
  void Function(String message)? echo,
}) {
  final String? resolvedDefault =
      (googleApiKey != null && googleApiKey.isNotEmpty)
          ? googleApiKey
          : (environment?['GOOGLE_API_KEY'] ??
                getCliEnvironmentValue('GOOGLE_API_KEY'));

  return promptStr(
    'Enter Google API key',
    priorMsg: googleApiMsg,
    defaultValue: resolvedDefault,
    promptInput: promptInput,
    echo: echo,
  );
}

/// Records the onboarding choice for the CLI telemetry event.
void recordExpressAction(
  String actionName, {
  Map<String, Object?>? contextMeta,
}) {
  final Map<String, Object?> target =
      contextMeta ?? onboardingTelemetryContextMeta;
  target['express_mode_action'] = actionName;
}

/// Handles the "Login with Google" onboarding flow.
OnboardingAuth handleLoginWithGoogle({
  Map<String, String>? environment,
  Map<String, Object?>? contextMeta,
  gcp_utils.GcloudProcessRunner? processRunner,
  gcp_utils.VertexExpressHttpTransport? httpTransport,
  bool Function()? checkAdcFn,
  void Function()? loginAdcFn,
  Map<String, Object?>? Function()? retrieveExpressProjectFn,
  List<(String, String)> Function(int limit)? listGcpProjectsFn,
  bool Function()? checkExpressEligibilityFn,
  Map<String, Object?> Function(String location)? signUpExpressFn,
  String? Function(String promptPrefix, {String? defaultValue})? promptInput,
  bool Function(String promptPrefix, {required bool defaultValue})?
  confirmInput,
  void Function(String message)? echo,
}) {
  final void Function(String) out = echo ?? stdout.writeln;
  final bool hasAdc =
      checkAdcFn != null
          ? checkAdcFn()
          : gcp_utils.checkAdc(
              environment: environment,
              processRunner: processRunner,
            );
  if (!hasAdc) {
    out(
      'No Application Default Credentials found. '
      'Opening browser for login...',
    );
    try {
      if (loginAdcFn != null) {
        loginAdcFn();
      } else {
        gcp_utils.loginAdc(processRunner: processRunner);
      }
    } on StateError catch (e) {
      out(e.message);
      throw const OnboardingAbortException();
    }
  }

  final Map<String, Object?>? expressProject =
      retrieveExpressProjectFn != null
          ? retrieveExpressProjectFn()
          : gcp_utils.retrieveExpressProject(
              environment: environment,
              processRunner: processRunner,
              httpTransport: httpTransport,
            );
  if (expressProject != null) {
    final String? apiKey = expressProject['api_key'] as String?;
    final String? projectId = expressProject['project_id'] as String?;
    final String region =
        (expressProject['region'] as String?) ?? 'us-central1';
    if (projectId != null && projectId.isNotEmpty) {
      out('Using existing Express project: $projectId');
      recordExpressAction('EXISTING_EXPRESS', contextMeta: contextMeta);
      return ExpressModeAuth(
        apiKey: apiKey,
        projectId: projectId,
        region: region,
      );
    }
  }

  List<(String, String)> projects;
  try {
    projects =
        listGcpProjectsFn != null
            ? listGcpProjectsFn(20)
            : gcp_utils.listGcpProjects(
                limit: 20,
                processRunner: processRunner,
              );
  } on StateError catch (e) {
    out(e.message);
    projects = <(String, String)>[];
  }

  if (projects.isNotEmpty) {
    out('Recently created Google Cloud projects found:');
    out('0. Enter project ID manually');
    for (int i = 0; i < projects.length; i += 1) {
      final (String pId, String pName) = projects[i];
      out('${i + 1}. $pName ($pId)');
    }

    final int projectIndex = _promptIntRange(
      'Select a project',
      min: 0,
      max: projects.length,
      promptInput: promptInput,
    );
    final String selectedProjectId;
    if (projectIndex == 0) {
      recordExpressAction('MANUAL_PROJECT', contextMeta: contextMeta);
      selectedProjectId = promptForGoogleCloud(
        null,
        environment: environment,
        processRunner: processRunner,
        promptInput: promptInput,
        echo: echo,
      );
    } else {
      selectedProjectId = projects[projectIndex - 1].$1;
    }
    final String region = promptForGoogleCloudRegion(
      null,
      environment: environment,
      processRunner: processRunner,
      promptInput: promptInput,
      echo: echo,
    );
    return VertexAIAuth(projectId: selectedProjectId, region: region);
  }

  out(
    'A Google Cloud project is required to continue. You can enter an '
    'existing project ID or create an Express Mode project. Learn more: '
    'https://cloud.google.com/resources/cloud-express-faqs',
  );
  final String action = _promptChoice(
    '1. Enter an existing Google Cloud project ID\n'
    '2. Create a new project (Express Mode)\n'
    '3. Abandon\n'
    'Choose an action',
    choices: const <String>['1', '2', '3'],
    promptInput: promptInput,
  );

  if (action == '3') {
    recordExpressAction('ABANDON', contextMeta: contextMeta);
    throw const OnboardingAbortException();
  }

  if (action == '1') {
    recordExpressAction('MANUAL_PROJECT', contextMeta: contextMeta);
    final String googleCloudProject = promptForGoogleCloud(
      null,
      environment: environment,
      processRunner: processRunner,
      promptInput: promptInput,
      echo: echo,
    );
    final String googleCloudRegion = promptForGoogleCloudRegion(
      null,
      environment: environment,
      processRunner: processRunner,
      promptInput: promptInput,
      echo: echo,
    );
    return VertexAIAuth(
      projectId: googleCloudProject,
      region: googleCloudRegion,
    );
  }

  final bool eligible =
      checkExpressEligibilityFn != null
          ? checkExpressEligibilityFn()
          : gcp_utils.checkExpressEligibility(
              environment: environment,
              processRunner: processRunner,
              httpTransport: httpTransport,
            );
  if (eligible) {
    out(expressTosMsg);
    final bool accepted = _promptConfirm(
      'Do you accept the Terms of Service?',
      defaultValue: false,
      confirmInput: confirmInput,
      promptInput: promptInput,
    );
    if (accepted) {
      final String selectedRegion = _promptChoice(
        'Choose a region for Express Mode:\n'
        '1. us-central1\n'
        '2. europe-west1\n'
        '3. asia-southeast1\n'
        'Choose region',
        choices: const <String>['1', '2', '3'],
        defaultValue: '1',
        promptInput: promptInput,
      );
      const Map<String, String> regionMap = <String, String>{
        '1': 'us-central1',
        '2': 'europe-west1',
        '3': 'asia-southeast1',
      };
      final String chosenRegion = regionMap[selectedRegion]!;
      final Map<String, Object?> expressInfo =
          signUpExpressFn != null
              ? signUpExpressFn(chosenRegion)
              : gcp_utils.signUpExpress(
                  location: chosenRegion,
                  environment: environment,
                  processRunner: processRunner,
                  httpTransport: httpTransport,
                );
      final String? apiKey = expressInfo['api_key'] as String?;
      final String projectId = '${expressInfo['project_id'] ?? ''}';
      final String region =
          (expressInfo['region'] as String?) ?? chosenRegion;
      out('Express Mode project created: $projectId');

      final String currentProj = getGcpProjectFromGcloud(
        processRunner: processRunner,
      );
      if (currentProj.isNotEmpty && currentProj != projectId) {
        out(
          "Warning: Your default gcloud project is set to '$currentProj'. "
          'This might conflict with or override your Express Mode project '
          "'$projectId'. We recommend unsetting it.",
        );
        final bool shouldUnset = _promptConfirm(
          "Run 'gcloud config unset project'?",
          defaultValue: true,
          confirmInput: confirmInput,
          promptInput: promptInput,
        );
        if (shouldUnset) {
          final gcp_utils.GcloudProcessRunner runner =
              processRunner ?? Process.runSync;
          try {
            final ProcessResult unsetRes = runner('gcloud', <String>[
              'config',
              'unset',
              'project',
            ]);
            if (unsetRes.exitCode == 0) {
              out('Unset default gcloud project.');
            } else {
              out('Failed to unset project. Please do it manually.');
            }
          } on Object {
            out('Failed to unset project. Please do it manually.');
          }
        }
      }
      recordExpressAction('CREATE_EXPRESS', contextMeta: contextMeta);
      return ExpressModeAuth(
        apiKey: apiKey,
        projectId: projectId,
        region: region,
      );
    }
  }

  recordExpressAction('ABANDON', contextMeta: contextMeta);
  out(notEligibleMsg);
  throw const OnboardingAbortException();
}

/// Prompts the user to choose a backend (`Google AI`, `Vertex AI`, or `Login with Google`).
OnboardingAuth promptToChooseBackend(
  String? googleApiKey,
  String? googleCloudProject,
  String? googleCloudRegion, {
  Map<String, String>? environment,
  Map<String, Object?>? contextMeta,
  gcp_utils.GcloudProcessRunner? processRunner,
  gcp_utils.VertexExpressHttpTransport? httpTransport,
  String? Function(String promptPrefix, {String? defaultValue})? promptInput,
  bool Function(String promptPrefix, {required bool defaultValue})?
  confirmInput,
  void Function(String message)? echo,
  OnboardingAuth Function()? loginWithGoogleHandler,
}) {
  final void Function(String) out = echo ?? stdout.writeln;
  final String backendChoice = _promptChoice(
    '1. Google AI\n2. Vertex AI\n3. Login with Google\nChoose a backend',
    choices: const <String>['1', '2', '3'],
    promptInput: promptInput,
  );
  if (backendChoice == '1') {
    final String resolvedKey = promptForGoogleApiKey(
      googleApiKey,
      environment: environment,
      promptInput: promptInput,
      echo: echo,
    );
    return GoogleAIAuth(apiKey: resolvedKey);
  }
  if (backendChoice == '2') {
    out(googleCloudSetupMsg);
    final String resolvedProject = promptForGoogleCloud(
      googleCloudProject,
      environment: environment,
      processRunner: processRunner,
      promptInput: promptInput,
      echo: echo,
    );
    final String resolvedRegion = promptForGoogleCloudRegion(
      googleCloudRegion,
      environment: environment,
      processRunner: processRunner,
      promptInput: promptInput,
      echo: echo,
    );
    return VertexAIAuth(projectId: resolvedProject, region: resolvedRegion);
  }
  if (loginWithGoogleHandler != null) {
    return loginWithGoogleHandler();
  }
  return handleLoginWithGoogle(
    environment: environment,
    contextMeta: contextMeta,
    processRunner: processRunner,
    httpTransport: httpTransport,
    promptInput: promptInput,
    confirmInput: confirmInput,
    echo: echo,
  );
}

int _promptIntRange(
  String promptPrefix, {
  required int min,
  required int max,
  String? Function(String promptPrefix, {String? defaultValue})? promptInput,
}) {
  while (true) {
    final String raw = promptStr(promptPrefix, promptInput: promptInput);
    final int? parsed = int.tryParse(raw);
    if (parsed != null && parsed >= min && parsed <= max) {
      return parsed;
    }
  }
}

String _promptChoice(
  String promptPrefix, {
  required List<String> choices,
  String? defaultValue,
  String? Function(String promptPrefix, {String? defaultValue})? promptInput,
}) {
  while (true) {
    final String raw = promptStr(
      promptPrefix,
      defaultValue: defaultValue,
      promptInput: promptInput,
    );
    if (choices.contains(raw)) {
      return raw;
    }
  }
}

bool _promptConfirm(
  String promptPrefix, {
  required bool defaultValue,
  bool Function(String promptPrefix, {required bool defaultValue})?
  confirmInput,
  String? Function(String promptPrefix, {String? defaultValue})? promptInput,
}) {
  if (confirmInput != null) {
    return confirmInput(promptPrefix, defaultValue: defaultValue);
  }
  if (promptInput != null) {
    final String? response = promptInput(
      promptPrefix,
      defaultValue: defaultValue ? 'y' : 'n',
    );
    if (response == null || response.trim().isEmpty) {
      return defaultValue;
    }
    final String normalized = response.trim().toLowerCase();
    return normalized == 'y' || normalized == 'yes' || normalized == 'true';
  }
  final String suffix = defaultValue ? ' [Y/n]: ' : ' [y/N]: ';
  stdout.write('$promptPrefix$suffix');
  final String? line = stdin.readLineSync();
  if (line == null || line.trim().isEmpty) {
    return defaultValue;
  }
  final String normalized = line.trim().toLowerCase();
  return normalized == 'y' || normalized == 'yes' || normalized == 'true';
}
