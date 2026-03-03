/// Experimental feature guards for A2A integration APIs.
library;

/// The default warning message for A2A experimental APIs.
const String a2aExperimentalDefaultMessage =
    'ADK implementation for A2A support (A2aAgentExecutor, RemoteA2aAgent '
    'and supporting components) is experimental and may change in '
    'backward-incompatible ways.';

/// The passthrough [value] marked as experimental.
///
/// Use this wrapper to make experimental API surfaces explicit at call sites.
T a2aExperimental<T>(T value, {String? message}) {
  return value;
}
