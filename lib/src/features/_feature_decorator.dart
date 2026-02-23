import '_feature_registry.dart';

class FeatureDecorator {
  const FeatureDecorator._({
    required this.featureName,
    required this.featureStage,
  });

  final FeatureName featureName;
  final FeatureStage featureStage;

  void checkEnabled({Map<String, String>? environment}) {
    if (!isFeatureEnabled(featureName, environment: environment)) {
      throw StateError('Feature $featureName is not enabled.');
    }
  }

  T run<T>(T Function() body, {Map<String, String>? environment}) {
    checkEnabled(environment: environment);
    return body();
  }

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

FeatureDecorator workingInProgress(FeatureName featureName) {
  return _makeFeatureDecorator(
    featureName: featureName,
    featureStage: FeatureStage.wip,
  );
}

FeatureDecorator experimental(FeatureName featureName) {
  return _makeFeatureDecorator(
    featureName: featureName,
    featureStage: FeatureStage.experimental,
  );
}

FeatureDecorator stable(FeatureName featureName) {
  return _makeFeatureDecorator(
    featureName: featureName,
    featureStage: FeatureStage.stable,
    defaultOn: true,
  );
}
