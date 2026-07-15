/// Artifact URI parsing and conversion helpers.
library;

import '../errors/input_validation_error.dart';
import '../types/content.dart';

/// Parsed components of an `artifact://` URI.
class ParsedArtifactUri {
  /// Creates parsed artifact URI fields.
  const ParsedArtifactUri({
    required this.appName,
    required this.userId,
    required this.sessionId,
    required this.filename,
    required this.version,
  });

  /// Application scope in the artifact URI.
  final String appName;

  /// User scope in the artifact URI.
  final String userId;

  /// Optional session scope in the artifact URI.
  final String? sessionId;

  /// Artifact filename segment.
  final String filename;

  /// Artifact version number.
  final int version;
}

final RegExp _sessionScopedArtifactUriRe = RegExp(
  r'^artifact://apps/([^/]+)/users/([^/]+)/sessions/([^/]+)/artifacts/([^/]+)/versions/(\d+)$',
);
final RegExp _userScopedArtifactUriRe = RegExp(
  r'^artifact://apps/([^/]+)/users/([^/]+)/artifacts/([^/]+)/versions/(\d+)$',
);

/// Parses [uri] into a [ParsedArtifactUri] when it matches known formats.
ParsedArtifactUri? parseArtifactUri(String uri) {
  if (uri.isEmpty || !uri.startsWith('artifact://')) {
    return null;
  }

  final RegExpMatch? sessionMatch = _sessionScopedArtifactUriRe.firstMatch(uri);
  if (sessionMatch != null) {
    return ParsedArtifactUri(
      appName: sessionMatch.group(1)!,
      userId: sessionMatch.group(2)!,
      sessionId: sessionMatch.group(3)!,
      filename: sessionMatch.group(4)!,
      version: int.parse(sessionMatch.group(5)!),
    );
  }

  final RegExpMatch? userMatch = _userScopedArtifactUriRe.firstMatch(uri);
  if (userMatch != null) {
    return ParsedArtifactUri(
      appName: userMatch.group(1)!,
      userId: userMatch.group(2)!,
      sessionId: null,
      filename: userMatch.group(3)!,
      version: int.parse(userMatch.group(4)!),
    );
  }

  return null;
}

/// Builds an artifact URI from the provided scope and version fields.
String getArtifactUri(
  String appName,
  String userId,
  String filename,
  int version, {
  String? sessionId,
}) {
  if (sessionId != null && sessionId.isNotEmpty) {
    return 'artifact://apps/$appName/users/$userId/sessions/$sessionId/artifacts/$filename/versions/$version';
  }
  return 'artifact://apps/$appName/users/$userId/artifacts/$filename/versions/$version';
}

/// Whether [artifact] references an `artifact://` file URI.
bool isArtifactRef(Part artifact) {
  final FileData? fileData = artifact.fileData;
  return fileData != null && fileData.fileUri.startsWith('artifact://');
}

/// Ensures artifact references cannot escape the caller's scope.
///
/// Throws [InputValidationError] when [parsedUri] points at a different app or
/// user, or when a session-scoped reference targets a different session than
/// [sessionId].
void validateArtifactReferenceScope({
  required String appName,
  required String userId,
  required String? sessionId,
  required ParsedArtifactUri parsedUri,
}) {
  if (parsedUri.appName != appName || parsedUri.userId != userId) {
    throw InputValidationError(
      'Artifact references must stay within the same app and user scope.',
    );
  }
  if (parsedUri.sessionId != null && parsedUri.sessionId != sessionId) {
    throw InputValidationError(
      'Session-scoped artifact references must stay within the same session'
      ' scope.',
    );
  }
}

/// Rejects values that could alter the constructed path.
///
/// Throws [InputValidationError] if [value] contains traversal segments, null
/// bytes, is empty, or starts with a slash or backslash.
void validatePathSegment(String value, String fieldName) {
  if (value.isEmpty) {
    throw InputValidationError('$fieldName must not be empty.');
  }
  if (value.contains('\x00')) {
    throw InputValidationError('$fieldName must not contain null bytes.');
  }
  if (value.startsWith('/') || value.startsWith('\\')) {
    throw InputValidationError(
      '$fieldName "$value" must not be an absolute path or start with a slash.',
    );
  }
  if (value == '.' ||
      value == '..' ||
      value.split('/').contains('..') ||
      value.split('\\').contains('..')) {
    throw InputValidationError(
      '$fieldName "$value" must not contain traversal segments.',
    );
  }
}
