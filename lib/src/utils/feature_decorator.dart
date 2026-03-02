import 'env_utils.dart';

/// Callback for handling emitted feature warnings.
typedef FeatureWarningHandler = void Function(String message);

/// Runtime feature gate that can warn or block usage.
class FeatureDecorator {
  /// Creates a feature decorator.
  const FeatureDecorator({
    required this.label,
    required this.defaultMessage,
    this.blockUsage = false,
    this.bypassEnvVar,
  });

  /// Feature label shown in warnings/errors.
  final String label;

  /// Default warning/error message.
  final String defaultMessage;

  /// Whether usage should throw instead of warning.
  final bool blockUsage;

  /// Optional environment variable that bypasses checks.
  final String? bypassEnvVar;

  /// Validates feature usage for [objectName].
  ///
  /// Throws a [StateError] when [blockUsage] is true and the feature is not
  /// bypassed.
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

/// Decorator for work-in-progress features.
const FeatureDecorator workingInProgress = FeatureDecorator(
  label: 'WIP',
  defaultMessage:
      'This feature is a work in progress and is not working completely. ADK users are not supposed to use it.',
  blockUsage: true,
  bypassEnvVar: 'ADK_ALLOW_WIP_FEATURES',
);

/// Decorator for experimental features.
const FeatureDecorator experimental = FeatureDecorator(
  label: 'EXPERIMENTAL',
  defaultMessage:
      'This feature is experimental and may change or be removed in future versions without notice. It may introduce breaking changes at any time.',
  bypassEnvVar: 'ADK_SUPPRESS_EXPERIMENTAL_FEATURE_WARNINGS',
);
