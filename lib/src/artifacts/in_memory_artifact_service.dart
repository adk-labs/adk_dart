/// In-memory artifact storage implementation.
library;

import '../errors/input_validation_error.dart';
import '../types/content.dart';
import 'artifact_util.dart';
import 'base_artifact_service.dart';

/// Artifact service backed by process-local memory maps.
///
/// ```dart
/// final artifactService = InMemoryArtifactService();
/// final version = await artifactService.saveArtifact(
///   appName: 'my_app',
///   userId: 'user_1',
///   sessionId: 'session_1',
///   filename: 'notes.txt',
///   artifact: Part.text('Meeting notes'),
/// );
/// ```
class InMemoryArtifactService extends BaseArtifactService {
  /// Creates an in-memory artifact storage service.
  InMemoryArtifactService();

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
    validatePathSegment(appName, 'app_name');
    validatePathSegment(userId, 'user_id');
    if (_fileHasUserNamespace(filename)) {
      return '$appName/$userId/user/$filename';
    }

    if (sessionId == null || sessionId.isEmpty) {
      throw ArgumentError(
        'sessionId must be provided for session-scoped artifacts.',
      );
    }
    validatePathSegment(sessionId, 'session_id');

    return '$appName/$userId/$sessionId/$filename';
  }

  /// Saves [artifact] in memory and returns the next version number.
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

    if (isArtifactRef(artifact)) {
      final ParsedArtifactUri? parsedUri = parseArtifactUri(
        artifact.fileData!.fileUri,
      );
      if (parsedUri == null) {
        throw InputValidationError(
          'Invalid artifact reference URI: ${artifact.fileData!.fileUri}',
        );
      }
      validateArtifactReferenceScope(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        parsedUri: parsedUri,
      );
    }

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
      customMetadata: customMetadata == null
          ? null
          : Map<String, Object?>.from(customMetadata),
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

  /// Loads one artifact version from memory.
  ///
  /// Returns the latest version when [version] is omitted.
  @override
  Future<Part?> loadArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    return _loadArtifactInternal(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
      version: version,
      remainingDepth: maxArtifactReferenceDepth,
    );
  }

  Future<Part?> _loadArtifactInternal({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
    required int remainingDepth,
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

    // Resolve artifact reference if needed.
    if (isArtifactRef(value)) {
      final ParsedArtifactUri parsedUri = resolveArtifactReference(
        fileUri: value.fileData!.fileUri,
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        remainingDepth: remainingDepth,
      );
      return _loadArtifactInternal(
        appName: parsedUri.appName,
        userId: parsedUri.userId,
        filename: parsedUri.filename,
        sessionId: parsedUri.sessionId,
        version: parsedUri.version,
        remainingDepth: remainingDepth - 1,
      );
    }

    if (_isEmptyPart(value)) {
      return null;
    }

    return value;
  }

  /// Lists artifact keys visible in the user or session scope.
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

  /// Deletes all stored versions for [filename] in memory.
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

  /// Lists stored version numbers for [filename].
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

  /// Lists metadata snapshots for all versions of [filename].
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

  /// Returns metadata for one stored artifact version.
  ///
  /// Returns the latest version when [version] is omitted.
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
    if (artifact.inlineData != null &&
        artifact.inlineData!.mimeType.isNotEmpty) {
      return artifact.inlineData!.mimeType;
    }
    if (artifact.fileData != null && artifact.fileData!.mimeType != null) {
      return artifact.fileData!.mimeType;
    }
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
        artifact.inlineData == null &&
        artifact.fileData == null &&
        artifact.executableCode == null &&
        artifact.codeExecutionResult == null;
  }
}

class _ArtifactEntry {
  _ArtifactEntry({required this.data, required this.artifactVersion});

  Part data;
  ArtifactVersion artifactVersion;
}
