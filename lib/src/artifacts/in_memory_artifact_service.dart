import '../types/content.dart';
import 'base_artifact_service.dart';

class InMemoryArtifactService extends BaseArtifactService {
  final Map<String, List<_ArtifactEntry>> _artifacts =
      <String, List<_ArtifactEntry>>{};

  bool _fileHasUserNamespace(String filename) {
    return filename.startsWith('user:');
  }

  String _artifactPath({
    required String appName,
    required String userId,
    required String filename,
    required String? sessionId,
  }) {
    if (_fileHasUserNamespace(filename)) {
      return '$appName/$userId/user/$filename';
    }

    if (sessionId == null || sessionId.isEmpty) {
      throw ArgumentError(
        'sessionId must be provided for session-scoped artifacts.',
      );
    }

    return '$appName/$userId/$sessionId/$filename';
  }

  @override
  Future<int> saveArtifact({
    required String appName,
    required String userId,
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    final String path = _artifactPath(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );

    final List<_ArtifactEntry> versions = _artifacts.putIfAbsent(
      path,
      () => <_ArtifactEntry>[],
    );

    final int version = versions.length;
    final String canonicalUri = _fileHasUserNamespace(filename)
        ? 'memory://apps/$appName/users/$userId/artifacts/$filename/versions/$version'
        : 'memory://apps/$appName/users/$userId/sessions/$sessionId/artifacts/$filename/versions/$version';

    final ArtifactVersion artifactVersion = ArtifactVersion(
      version: version,
      canonicalUri: canonicalUri,
      customMetadata: customMetadata,
      mimeType: _detectMimeType(artifact),
    );

    versions.add(
      _ArtifactEntry(
        data: artifact.copyWith(),
        artifactVersion: artifactVersion,
      ),
    );
    return version;
  }

  @override
  Future<Part?> loadArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    final String path = _artifactPath(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
    final List<_ArtifactEntry>? entries = _artifacts[path];
    if (entries == null || entries.isEmpty) {
      return null;
    }

    final int index = version ?? (entries.length - 1);
    if (index < 0 || index >= entries.length) {
      return null;
    }

    final Part value = entries[index].data.copyWith();
    if (_isEmptyPart(value)) {
      return null;
    }

    return value;
  }

  @override
  Future<List<String>> listArtifactKeys({
    required String appName,
    required String userId,
    String? sessionId,
  }) async {
    final String userPrefix = '$appName/$userId/user/';
    final String? sessionPrefix = sessionId == null
        ? null
        : '$appName/$userId/$sessionId/';

    final Set<String> filenames = <String>{};
    for (final String path in _artifacts.keys) {
      if (sessionPrefix != null && path.startsWith(sessionPrefix)) {
        filenames.add(path.substring(sessionPrefix.length));
      } else if (path.startsWith(userPrefix)) {
        filenames.add(path.substring(userPrefix.length));
      }
    }

    final List<String> sorted = filenames.toList()..sort();
    return sorted;
  }

  @override
  Future<void> deleteArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final String path = _artifactPath(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
    _artifacts.remove(path);
  }

  @override
  Future<List<int>> listVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final String path = _artifactPath(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );

    final int count = _artifacts[path]?.length ?? 0;
    return List<int>.generate(count, (int index) => index);
  }

  @override
  Future<List<ArtifactVersion>> listArtifactVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final String path = _artifactPath(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
    final List<_ArtifactEntry>? entries = _artifacts[path];
    if (entries == null || entries.isEmpty) {
      return const <ArtifactVersion>[];
    }

    return entries
        .map((entry) => entry.artifactVersion.copyWith())
        .toList(growable: false);
  }

  @override
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    final String path = _artifactPath(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
    final List<_ArtifactEntry>? entries = _artifacts[path];
    if (entries == null || entries.isEmpty) {
      return null;
    }

    final int index = version ?? (entries.length - 1);
    if (index < 0 || index >= entries.length) {
      return null;
    }
    return entries[index].artifactVersion.copyWith();
  }

  String? _detectMimeType(Part artifact) {
    if (artifact.text != null) {
      return 'text/plain';
    }
    return null;
  }

  bool _isEmptyPart(Part artifact) {
    final bool noText = artifact.text == null || artifact.text!.isEmpty;
    return noText &&
        artifact.functionCall == null &&
        artifact.functionResponse == null &&
        artifact.codeExecutionResult == null;
  }
}

class _ArtifactEntry {
  _ArtifactEntry({required this.data, required this.artifactVersion});

  Part data;
  ArtifactVersion artifactVersion;
}
