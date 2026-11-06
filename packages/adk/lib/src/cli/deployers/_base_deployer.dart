/// Abstract base class for ADK deployers.
library;

/// Base interface for deploying ADK applications to target runtimes.
abstract class Deployer {
  /// Creates a [Deployer].
  const Deployer();

  /// Deploys the application according to the provided options.
  Future<void> deploy({
    required String agentFolder,
    String? project,
    String? region,
    String? serviceName,
    String? appName,
    String? tempFolder,
    int port = 8000,
    bool traceToCloud = false,
    bool withUi = false,
    String? adkVersion,
    String? logLevel,
    String? sessionServiceUri,
    String? artifactServiceUri,
    String? memoryServiceUri,
    bool useLocalStorage = true,
    String? origins,
    List<String>? extraGcloudArgs,
    List<String>? extraPackages,
  });
}
