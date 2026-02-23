import 'env_utils.dart';

typedef FeatureWarningHandler = void Function(String message);

class FeatureDecorator {
  const FeatureDecorator({
    required this.label,
    required this.defaultMessage,
    this.blockUsage = false,
    this.bypassEnvVar,
  });

  final String label;
  final String defaultMessage;
  final bool blockUsage;
  final String? bypassEnvVar;

  void check(
    String objectName, {
    String? message,
    Map<String, String>? environment,
    FeatureWarningHandler? onWarning,
  }) {
    final bool bypassed =
        bypassEnvVar != null &&
        isEnvEnabled(bypassEnvVar!, environment: environment);
    if (bypassed) {
      return;
    }

    final String rendered =
        '[${label.toUpperCase()}] $objectName: ${message ?? defaultMessage}';
    if (blockUsage) {
      throw StateError(rendered);
    }
    if (onWarning != null) {
      onWarning(rendered);
    }
  }
}

const FeatureDecorator workingInProgress = FeatureDecorator(
  label: 'WIP',
  defaultMessage:
      'This feature is a work in progress and is not working completely. ADK users are not supposed to use it.',
  blockUsage: true,
  bypassEnvVar: 'ADK_ALLOW_WIP_FEATURES',
);

const FeatureDecorator experimental = FeatureDecorator(
  label: 'EXPERIMENTAL',
  defaultMessage:
      'This feature is experimental and may change or be removed in future versions without notice. It may introduce breaking changes at any time.',
  bypassEnvVar: 'ADK_SUPPRESS_EXPERIMENTAL_FEATURE_WARNINGS',
);
