/// Reporting errors to untrusted callers without leaking their detail.
library;

import 'dart:developer' as developer;
import 'dart:math';

import 'env_utils.dart';

/// Environment variable that puts exception text back into responses that leave
/// the process.
///
/// Off by default, and meant for local debugging only.
const String envDebugErrors = 'ADK_DEBUG_ERRORS';

const int _errorIdLength = 12;
final Random _random = Random.secure();

/// Returns a short opaque id correlating a response with a log entry.
String newErrorId() {
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < _errorIdLength; i++) {
    buffer.write(_random.nextInt(16).toRadixString(16));
  }
  return buffer.toString();
}

/// Builds the error text that is safe to hand to an untrusted caller.
///
/// Returns [summary] and the correlation [errorId], plus — only when
/// [envDebugErrors] is enabled — the exception type and message.
String redactError(
  Object exc, {
  required String summary,
  required String errorId,
  Map<String, String>? environment,
}) {
  final String detail = '$summary (error_id: $errorId)';
  if (isEnvEnabled(envDebugErrors, environment: environment)) {
    return '$detail: ${exc.runtimeType}: $exc';
  }
  return detail;
}

/// Logs an exception in full and returns text safe to return to the caller.
String reportError(
  Object exc, {
  required String summary,
  String? logMessage,
  StackTrace? stackTrace,
  void Function(String message, Object error, StackTrace? stackTrace)?
      onLogError,
  Map<String, String>? environment,
}) {
  final String errorId = newErrorId();
  final String message = '${logMessage ?? summary} [error_id=$errorId]';
  if (onLogError != null) {
    onLogError(message, exc, stackTrace);
  } else {
    developer.log(
      message,
      name: 'google_adk.error_reporting',
      level: 1000,
      error: exc,
      stackTrace: stackTrace,
    );
  }
  return redactError(
    exc,
    summary: summary,
    errorId: errorId,
    environment: environment,
  );
}
