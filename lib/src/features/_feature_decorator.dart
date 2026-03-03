/// Decorators that gate execution behind runtime feature flags.
library;

import '_feature_registry.dart';

/// Callable feature gate bound to a single [FeatureName].
class FeatureDecorator {
  /// Creates a decorator for [featureName] at [featureStage].
  const FeatureDecorator._({
    required this.featureName,
    required this.featureStage,
  });

  /// The feature this decorator validates.
  final FeatureName featureName;

  /// The stage used to classify this decorator's feature.
  final FeatureStage featureStage;

  /// Throws a [StateError] when [featureName] is not enabled.
  void checkEnabled({Map<String, String>? environment}) {
    if (!isFeatureEnabled(featureName, environment: environment)) {
      throw StateError('Feature $featureName is not enabled.');
    }
  }

  /// Runs [body] only when [featureName] is enabled.
  T run<T>(T Function() body, {Map<String, String>? environment}) {
    checkEnabled(environment: environment);
    return body();
  }

  /// Runs async [body] only when [featureName] is enabled.
  Future<T> runAsync<T>(
    Future<T> Function() body, {
    Map<String, String>? environment,
  }) async {
    checkEnabled(environment: environment);
    return body();
  }
}

FeatureDecorator _makeFeatureDecorator({
  required FeatureName featureName,
  required FeatureStage featureStage,
  bool defaultOn = false,
}) {
  final FeatureConfig? config = getFeatureConfig(featureName);
  if (config == null) {
    registerFeature(
      featureName,
      FeatureConfig(featureStage, defaultOn: defaultOn),
    );
  } else if (config.stage != featureStage) {
    throw ArgumentError(
      "Feature '$featureName' is being defined with stage '$featureStage', "
      "but it was previously registered with stage '${config.stage}'. "
      'Please ensure the feature is consistently defined.',
    );
  }

  return FeatureDecorator._(
    featureName: featureName,
    featureStage: featureStage,
  );
}

/// Returns a decorator for a work-in-progress [featureName].
FeatureDecorator workingInProgress(FeatureName featureName) {
  return _makeFeatureDecorator(
    featureName: featureName,
    featureStage: FeatureStage.wip,
  );
}

/// Returns a decorator for an experimental [featureName].
FeatureDecorator experimental(FeatureName featureName) {
  return _makeFeatureDecorator(
    featureName: featureName,
    featureStage: FeatureStage.experimental,
  );
}

/// Returns a decorator for a stable [featureName].
FeatureDecorator stable(FeatureName featureName) {
  return _makeFeatureDecorator(
    featureName: featureName,
    featureStage: FeatureStage.stable,
    defaultOn: true,
  );
}
