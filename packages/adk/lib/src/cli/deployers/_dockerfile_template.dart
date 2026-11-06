/// Dockerfile template and rendering helpers for ADK container deployments.
library;

import 'dart:convert';

final RegExp _appNamePattern = RegExp(r'^[A-Za-z0-9_-]+$');
final RegExp _pythonVersionPattern = RegExp(
  r'^[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[A-Za-z0-9._-]+)?$',
);
final RegExp _controlCharPattern = RegExp(r'[\x00-\x1f\x7f]');

/// Validates that [appName] is safe for use in a Dockerfile and filesystem path.
String validateAppName(String appName) {
  if (appName.isEmpty || !_appNamePattern.hasMatch(appName)) {
    throw ArgumentError.value(
      appName,
      'appName',
      'Invalid app name. Only alphanumeric characters, hyphens, and underscores are allowed.',
    );
  }
  return appName;
}

/// Validates that [pythonVersion] is a safe semantic version tag.
String validatePythonVersion(String pythonVersion) {
  if (pythonVersion.isEmpty || !_pythonVersionPattern.hasMatch(pythonVersion)) {
    throw ArgumentError.value(
      pythonVersion,
      'pythonVersion',
      'Invalid Python version format.',
    );
  }
  return pythonVersion;
}

/// Validates that [value] contains no newline or control characters that could
/// inject Dockerfile instructions.
String validateDockerfileLiteral(String value, {String fieldName = 'value'}) {
  if (_controlCharPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      fieldName,
      'Control characters and newlines are not allowed in Dockerfile literals.',
    );
  }
  return value;
}

/// Renders a list of command tokens into a Dockerfile JSON `EXEC` array string.
String toExecForm(List<String> args) {
  for (final String arg in args) {
    validateDockerfileLiteral(arg, fieldName: 'args');
  }
  return jsonEncode(args);
}

/// Template string for generating an ADK container `Dockerfile`.
const String dockerfileTemplate = '''
FROM python:{python_version}-slim
WORKDIR /app

# Create a non-root user
RUN adduser --disabled-password --gecos "" myuser

# Switch to the non-root user
USER myuser

# Set up environment variables - Start
ENV PATH="/home/myuser/.local/bin:\$PATH"
{gcp_env_vars}
# Set up environment variables - End

# Install ADK - Start
RUN pip install --no-cache-dir google-adk=={adk_version}
# Install ADK - End

# Copy agent - Start
COPY --chown=myuser:myuser "agents/{app_name}/" "/app/agents/{app_name}/"
{install_agent_deps}
# Copy agent - End

{extra_packages_setup}

EXPOSE {port}

CMD {cmd_exec_form}
''';

/// Alias matching the Python constant name `DOCKERFILE_TEMPLATE`.
// ignore: constant_identifier_names
const String DOCKERFILE_TEMPLATE = dockerfileTemplate;

/// Renders the Dockerfile snippet for installing agent `requirements.txt` if
/// [hasRequirementsTxt] is `true`.
String renderInstallAgentDeps(
  String appName, {
  required bool hasRequirementsTxt,
}) {
  final String validatedApp = validateAppName(appName);
  if (!hasRequirementsTxt) {
    return '';
  }
  return 'RUN pip install --no-cache-dir -r "/app/agents/$validatedApp/requirements.txt"';
}

/// Renders a complete `Dockerfile` from the provided configuration parameters.
String renderDockerfile({
  required String appName,
  required int port,
  required List<String> cmdArgs,
  String pythonVersion = '3.11',
  String adkVersion = '1.0.0',
  String gcpEnvVars = '',
  bool hasRequirementsTxt = false,
  String extraPackagesSetup = '',
}) {
  final String safeAppName = validateAppName(appName);
  final String safePythonVersion = validatePythonVersion(pythonVersion);
  final String safeAdkVersion = validateDockerfileLiteral(
    adkVersion,
    fieldName: 'adkVersion',
  );
  if (port < 1 || port > 65535) {
    throw ArgumentError.value(port, 'port', 'Port must be between 1 and 65535.');
  }
  final String installDeps = renderInstallAgentDeps(
    safeAppName,
    hasRequirementsTxt: hasRequirementsTxt,
  );
  final String execForm = toExecForm(cmdArgs);

  return dockerfileTemplate
      .replaceAll('{python_version}', safePythonVersion)
      .replaceAll('{gcp_env_vars}', gcpEnvVars.trim())
      .replaceAll('{adk_version}', safeAdkVersion)
      .replaceAll('{app_name}', safeAppName)
      .replaceAll('{install_agent_deps}', installDeps)
      .replaceAll('{extra_packages_setup}', extraPackagesSetup.trim())
      .replaceAll('{port}', '$port')
      .replaceAll('{cmd_exec_form}', execForm);
}
