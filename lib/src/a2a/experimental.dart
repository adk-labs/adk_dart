const String a2aExperimentalDefaultMessage =
    'ADK implementation for A2A support (A2aAgentExecutor, RemoteA2aAgent '
    'and supporting components) is experimental and may change in '
    'backward-incompatible ways.';

T a2aExperimental<T>(T value, {String? message}) {
  return value;
}
