/// Tool execution error types and exceptions used by telemetry.
library;

/// Semantic tool error types aligned with OpenTelemetry error attributes.
enum ToolErrorType {
  badRequest('BAD_REQUEST'),
  unauthorized('UNAUTHORIZED'),
  forbidden('FORBIDDEN'),
  notFound('NOT_FOUND'),
  requestTimeout('REQUEST_TIMEOUT'),
  internalServerError('INTERNAL_SERVER_ERROR'),
  badGateway('BAD_GATEWAY'),
  serviceUnavailable('SERVICE_UNAVAILABLE'),
  gatewayTimeout('GATEWAY_TIMEOUT');

  const ToolErrorType(this.value);

  /// Serialized OpenTelemetry-compatible error type value.
  final String value;
}

/// Exception raised when a tool fails with a semantic error classification.
class ToolExecutionError implements Exception {
  /// Creates a tool execution error.
  ToolExecutionError(this.message, {ToolErrorType? type, String? errorType})
    : errorType = errorType ?? type?.value;

  /// Human-readable error message.
  final String message;

  /// Optional OpenTelemetry-compatible error type.
  final String? errorType;

  @override
  String toString() => message;
}
