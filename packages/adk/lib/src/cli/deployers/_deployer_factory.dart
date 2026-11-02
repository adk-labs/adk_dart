/// Factory for resolving ADK [Deployer] instances by target cloud provider.
library;

import '_base_deployer.dart';
import '_cloud_run_deployer.dart';
import '_docker_deployer.dart';

/// Factory that creates a [Deployer] for a given target provider name.
class DeployerFactory {
  const DeployerFactory._();

  static final Map<String, Deployer Function()> _registry =
      <String, Deployer Function()>{
        'cloud_run': CloudRunDeployer.new,
        'docker': DockerDeployer.new,
      };

  /// Registers a custom [Deployer] builder for [cloudProvider].
  static void registerDeployer(
    String cloudProvider,
    Deployer Function() builder,
  ) {
    _registry[cloudProvider.trim().toLowerCase()] = builder;
  }

  /// Returns a [Deployer] instance for [cloudProvider] (`'cloud_run'`, `'docker'`).
  static Deployer getDeployer(String cloudProvider) {
    final String normalized = cloudProvider.trim().toLowerCase();
    final Deployer Function()? builder = _registry[normalized];
    if (builder == null) {
      throw ArgumentError.value(
        cloudProvider,
        'cloudProvider',
        'Unsupported cloud provider: $cloudProvider. '
            'Supported providers: ${_registry.keys.join(', ')}',
      );
    }
    return builder();
  }

  /// Snake-case alias for [getDeployer] matching Python `DeployerFactory.get_deployer`.
  // ignore: non_constant_identifier_names
  static Deployer get_deployer(String cloudProvider) =>
      getDeployer(cloudProvider);
}
