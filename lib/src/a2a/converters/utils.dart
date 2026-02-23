const String adkMetadataKeyPrefix = 'adk_';
const String adkContextIdPrefix = 'ADK';
const String adkContextIdSeparator = '/';

String getAdkMetadataKey(String key) {
  if (key.trim().isEmpty) {
    throw ArgumentError('Metadata key cannot be empty or null.');
  }
  return '$adkMetadataKeyPrefix$key';
}

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
