/// Shared conversion helpers for ADK-specific A2A metadata and context IDs.
library;

/// The metadata key prefix reserved for ADK-specific fields.
const String adkMetadataKeyPrefix = 'adk_';

/// The fixed prefix used in encoded ADK A2A context identifiers.
const String adkContextIdPrefix = 'ADK';

/// The delimiter used to join context identifier segments.
const String adkContextIdSeparator = '/';

/// The ADK-scoped metadata key for [key].
///
/// Throws an [ArgumentError] when [key] is empty after trimming.
String getAdkMetadataKey(String key) {
  if (key.trim().isEmpty) {
    throw ArgumentError('Metadata key cannot be empty or null.');
  }
  return '$adkMetadataKeyPrefix$key';
}

/// The encoded A2A context identifier for [appName], [userId], and [sessionId].
///
/// Throws an [ArgumentError] when any identifier is empty after trimming.
String toA2aContextId(String appName, String userId, String sessionId) {
  if (appName.trim().isEmpty ||
      userId.trim().isEmpty ||
      sessionId.trim().isEmpty) {
    throw ArgumentError(
      'All parameters (appName, userId, sessionId) must be non-empty.',
    );
  }
  return <String>[
    adkContextIdPrefix,
    appName,
    userId,
    sessionId,
  ].join(adkContextIdSeparator);
}

/// The parsed `(appName, userId, sessionId)` tuple from [contextId].
///
/// Returns `(null, null, null)` when [contextId] is null, empty, or malformed.
(String?, String?, String?) fromA2aContextId(String? contextId) {
  if (contextId == null || contextId.trim().isEmpty) {
    return (null, null, null);
  }

  final List<String> parts = contextId.split(adkContextIdSeparator);
  if (parts.length != 4) {
    return (null, null, null);
  }

  final String prefix = parts[0];
  final String appName = parts[1];
  final String userId = parts[2];
  final String sessionId = parts[3];

  if (prefix != adkContextIdPrefix ||
      appName.isEmpty ||
      userId.isEmpty ||
      sessionId.isEmpty) {
    return (null, null, null);
  }

  return (appName, userId, sessionId);
}
