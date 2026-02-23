import '../types/content.dart';

class ParsedArtifactUri {
  const ParsedArtifactUri({
    required this.appName,
    required this.userId,
    required this.sessionId,
    required this.filename,
    required this.version,
  });

  final String appName;
  final String userId;
  final String? sessionId;
  final String filename;
  final int version;
}

final RegExp _sessionScopedArtifactUriRe = RegExp(
  r'^artifact://apps/([^/]+)/users/([^/]+)/sessions/([^/]+)/artifacts/([^/]+)/versions/(\d+)$',
);
final RegExp _userScopedArtifactUriRe = RegExp(
  r'^artifact://apps/([^/]+)/users/([^/]+)/artifacts/([^/]+)/versions/(\d+)$',
);

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

bool isArtifactRef(Part artifact) {
  final FileData? fileData = artifact.fileData;
  return fileData != null && fileData.fileUri.startsWith('artifact://');
}
