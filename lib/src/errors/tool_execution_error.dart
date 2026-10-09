/// Tool execution error types and exceptions used by telemetry.
library;

/// Semantic tool error types aligned with OpenTelemetry error attributes.
enum ToolErrorType {
  /// Invalid tool arguments or malformed request payload.
  badRequest('BAD_REQUEST'),

  /// Missing or invalid authentication credentials.
  unauthorized('UNAUTHORIZED'),

  /// Authenticated caller lacks permission for the operation.
  forbidden('FORBIDDEN'),

  /// Requested resource or endpoint was not found.
  notFound('NOT_FOUND'),

  /// Tool execution timed out waiting for a request.
  requestTimeout('REQUEST_TIMEOUT'),

  /// Unexpected internal failure within the tool or downstream service.
  internalServerError('INTERNAL_SERVER_ERROR'),

  /// Invalid response received from an upstream server or gateway.
  badGateway('BAD_GATEWAY'),

  /// Downstream service is temporarily unavailable or overloaded.
  serviceUnavailable('SERVICE_UNAVAILABLE'),

  /// Upstream gateway timed out waiting for a response.
  gatewayTimeout('GATEWAY_TIMEOUT');

  /// Creates a semantic tool error type with its OpenTelemetry [value].
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
