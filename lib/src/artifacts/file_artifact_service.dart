import 'dart:convert';
import 'dart:io';

import '../errors/input_validation_error.dart';
import '../types/content.dart';
import 'base_artifact_service.dart';

const String _userNamespacePrefix = 'user:';

List<Directory> _iterArtifactDirs(Directory root) {
  if (!root.existsSync()) {
    return <Directory>[];
  }

  final List<Directory> artifactDirs = <Directory>[];
  for (final FileSystemEntity entity in root.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! Directory) {
      continue;
    }
    final Directory versions = Directory(_appendPath(entity.path, 'versions'));
    if (versions.existsSync()) {
      artifactDirs.add(entity);
    }
  }
  return artifactDirs;
}

File? _fileUriToPath(String uri) {
  final Uri? parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.scheme != 'file') {
    return null;
  }
  return File.fromUri(parsed);
}

bool _fileHasUserNamespace(String filename) {
  return filename.startsWith(_userNamespacePrefix);
}

String _stripUserNamespace(String filename) {
  if (_fileHasUserNamespace(filename)) {
    return filename.substring(_userNamespacePrefix.length);
  }
  return filename;
}

bool _isAbsolutePath(String value) {
  return value.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
}

List<String> _toPosixSegments(String value) {
  final String normalized = value.replaceAll('\\', '/');
  final List<String> raw = normalized.split('/');
  final List<String> segments = <String>[];
  for (final String segment in raw) {
    final String trimmed = segment.trim();
    if (trimmed.isEmpty || trimmed == '.') {
      continue;
    }
    if (trimmed == '..') {
      throw InputValidationError(
        "Artifact filename '$value' escapes storage directory.",
      );
    }
    segments.add(trimmed);
  }
  return segments;
}

class _ResolvedArtifactPath {
  _ResolvedArtifactPath({
    required this.artifactDir,
    required this.relativePath,
  });

  final Directory artifactDir;
  final String relativePath;
}

_ResolvedArtifactPath _resolveScopedArtifactPath(
  Directory scopeRoot,
  String filename,
) {
  final String stripped = _stripUserNamespace(filename).trim();
  if (_isAbsolutePath(stripped)) {
    throw InputValidationError(
      "Absolute artifact filename '$filename' is not permitted.",
    );
  }

  final List<String> segments = _toPosixSegments(stripped);
  final List<String> safeSegments = segments.isEmpty
      ? <String>['artifact']
      : segments;

  String currentPath = scopeRoot.path;
  for (final String segment in safeSegments) {
    currentPath = _appendPath(currentPath, segment);
  }

  final Directory candidate = Directory(currentPath).absolute;
  final String scopePath = scopeRoot.absolute.uri.path;
  final String candidatePath = candidate.uri.path;
  if (!candidatePath.startsWith(scopePath)) {
    throw InputValidationError(
      "Artifact filename '$filename' escapes storage directory ${scopeRoot.path}.",
    );
  }

  return _ResolvedArtifactPath(
    artifactDir: candidate,
    relativePath: safeSegments.join('/'),
  );
}

bool _isUserScoped(String? sessionId, String filename) {
  return sessionId == null || _fileHasUserNamespace(filename);
}

Directory _userArtifactsDir(Directory baseRoot) {
  return Directory(_appendPath(baseRoot.path, 'artifacts'));
}

Directory _sessionArtifactsDir(Directory baseRoot, String sessionId) {
  return Directory(
    _appendPath(
      _appendPath(_appendPath(baseRoot.path, 'sessions'), sessionId),
      'artifacts',
    ),
  );
}

Directory _versionsDir(Directory artifactDir) {
  return Directory(_appendPath(artifactDir.path, 'versions'));
}

File _metadataPath(Directory artifactDir, int version) {
  return File(
    _appendPath(
      _appendPath(_versionsDir(artifactDir).path, '$version'),
      'metadata.json',
    ),
  );
}

List<int> _listVersionsOnDisk(Directory artifactDir) {
  final Directory versionsDir = _versionsDir(artifactDir);
  if (!versionsDir.existsSync()) {
    return <int>[];
  }

  final List<int> versions = <int>[];
  for (final FileSystemEntity entity in versionsDir.listSync()) {
    if (entity is! Directory) {
      continue;
    }
    final int? parsed = int.tryParse(
      entity.uri.pathSegments.lastWhere(
        (String segment) => segment.isNotEmpty,
        orElse: () => '',
      ),
    );
    if (parsed != null) {
      versions.add(parsed);
    }
  }
  versions.sort();
  return versions;
}

String _appendPath(String base, String segment) {
  if (base.endsWith(Platform.pathSeparator)) {
    return '$base$segment';
  }
  return '$base${Platform.pathSeparator}$segment';
}

String? _relativePosixPath(Directory root, Directory child) {
  final String rootPath = root.absolute.uri.path;
  final String childPath = child.absolute.uri.path;
  if (!childPath.startsWith(rootPath)) {
    return null;
  }

  String relative = childPath.substring(rootPath.length);
  if (relative.startsWith('/')) {
    relative = relative.substring(1);
  }
  if (relative.endsWith('/')) {
    relative = relative.substring(0, relative.length - 1);
  }
  return relative;
}

class _FileArtifactMetadata {
  _FileArtifactMetadata({
    required this.fileName,
    required this.version,
    required this.canonicalUri,
    required this.customMetadata,
    this.mimeType,
  });

  final String fileName;
  final int version;
  final String canonicalUri;
  final String? mimeType;
  final Map<String, Object?> customMetadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'file_name': fileName,
      'version': version,
      'canonical_uri': canonicalUri,
      'mime_type': mimeType,
      'custom_metadata': customMetadata,
    };
  }

  static _FileArtifactMetadata? fromJsonString(String jsonString) {
    try {
      final Object? decoded = jsonDecode(jsonString);
      if (decoded is! Map) {
        return null;
      }
      return _FileArtifactMetadata(
        fileName: '${decoded['file_name'] ?? ''}',
        version: decoded['version'] is num
            ? (decoded['version'] as num).toInt()
            : int.tryParse('${decoded['version']}') ?? 0,
        canonicalUri: '${decoded['canonical_uri'] ?? ''}',
        mimeType: decoded['mime_type'] as String?,
        customMetadata: decoded['custom_metadata'] is Map
            ? (decoded['custom_metadata'] as Map).map(
                (Object? key, Object? value) => MapEntry('$key', value),
              )
            : <String, Object?>{},
      );
    } catch (_) {
      return null;
    }
  }
}

void _writeMetadata(
  File path, {
  required String filename,
  required String? mimeType,
  required int version,
  required String canonicalUri,
  required Map<String, Object?> customMetadata,
}) {
  final _FileArtifactMetadata metadata = _FileArtifactMetadata(
    fileName: filename,
    mimeType: mimeType,
    version: version,
    canonicalUri: canonicalUri,
    customMetadata: customMetadata,
  );
  path.writeAsStringSync(jsonEncode(metadata.toJson()));
}

_FileArtifactMetadata? _readMetadata(File path) {
  if (!path.existsSync()) {
    return null;
  }
  return _FileArtifactMetadata.fromJsonString(path.readAsStringSync());
}

class FileArtifactService extends BaseArtifactService {
  FileArtifactService(Object rootDir)
    : rootDir = Directory('$rootDir').absolute {
    this.rootDir.createSync(recursive: true);
  }

  final Directory rootDir;

  Directory _baseRoot(String userId) {
    return Directory(_appendPath(_appendPath(rootDir.path, 'users'), userId));
  }

  Directory _scopeRoot(String userId, String? sessionId, String filename) {
    final Directory base = _baseRoot(userId);
    if (_isUserScoped(sessionId, filename)) {
      return _userArtifactsDir(base);
    }
    if (sessionId == null || sessionId.isEmpty) {
      throw InputValidationError(
        'Session ID must be provided for session-scoped artifacts.',
      );
    }
    return _sessionArtifactsDir(base, sessionId);
  }

  _ResolvedArtifactPath _artifactPath(
    String userId,
    String? sessionId,
    String filename,
  ) {
    final Directory scopeRoot = _scopeRoot(userId, sessionId, filename);
    return _resolveScopedArtifactPath(scopeRoot, filename);
  }

  String _canonicalUri(
    String userId,
    String? sessionId,
    String filename,
    int version,
  ) {
    final _ResolvedArtifactPath artifactPath = _artifactPath(
      userId,
      sessionId,
      filename,
    );
    final String storedFilename = artifactPath.artifactDir.uri.pathSegments
        .where((String segment) => segment.isNotEmpty)
        .last;
    final File payload = File(
      _appendPath(
        _appendPath(_versionsDir(artifactPath.artifactDir).path, '$version'),
        storedFilename,
      ),
    );
    return payload.absolute.uri.toString();
  }

  _FileArtifactMetadata? _latestMetadata(Directory artifactDir) {
    final List<int> versions = _listVersionsOnDisk(artifactDir);
    if (versions.isEmpty) {
      return null;
    }
    return _readMetadata(_metadataPath(artifactDir, versions.last));
  }

  bool _isUnderRootDir(File file) {
    final String rootPath = rootDir.absolute.uri.path.endsWith('/')
        ? rootDir.absolute.uri.path
        : '${rootDir.absolute.uri.path}/';
    final String candidatePath = file.absolute.uri.path;
    return candidatePath.startsWith(rootPath);
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
    final _ResolvedArtifactPath artifactPath = _artifactPath(
      userId,
      sessionId,
      filename,
    );
    final Directory artifactDir = artifactPath.artifactDir;
    artifactDir.createSync(recursive: true);

    final List<int> versions = _listVersionsOnDisk(artifactDir);
    final int nextVersion = versions.isEmpty ? 0 : (versions.last + 1);

    final Directory versionDir = Directory(
      _appendPath(_versionsDir(artifactDir).path, '$nextVersion'),
    );
    versionDir.createSync(recursive: true);

    final String storedFilename = artifactDir.uri.pathSegments
        .where((String segment) => segment.isNotEmpty)
        .last;
    final File contentPath = File(_appendPath(versionDir.path, storedFilename));

    String? mimeType;
    if (artifact.inlineData != null) {
      contentPath.writeAsBytesSync(artifact.inlineData!.data);
      mimeType = artifact.inlineData!.mimeType.isEmpty
          ? 'application/octet-stream'
          : artifact.inlineData!.mimeType;
    } else if (artifact.text != null) {
      contentPath.writeAsStringSync(artifact.text!, encoding: utf8);
    } else {
      throw InputValidationError(
        'Artifact must have either inline_data or text content.',
      );
    }

    final String canonicalUri = _canonicalUri(
      userId,
      sessionId,
      filename,
      nextVersion,
    );
    _writeMetadata(
      _metadataPath(artifactDir, nextVersion),
      filename: filename,
      mimeType: mimeType,
      version: nextVersion,
      canonicalUri: canonicalUri,
      customMetadata: customMetadata ?? <String, Object?>{},
    );

    return nextVersion;
  }

  @override
  Future<Part?> loadArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    final _ResolvedArtifactPath artifactPath = _artifactPath(
      userId,
      sessionId,
      filename,
    );
    final Directory artifactDir = artifactPath.artifactDir;
    if (!artifactDir.existsSync()) {
      return null;
    }

    final List<int> versions = _listVersionsOnDisk(artifactDir);
    if (versions.isEmpty) {
      return null;
    }

    final int versionToLoad;
    if (version == null) {
      versionToLoad = versions.last;
    } else {
      if (!versions.contains(version)) {
        return null;
      }
      versionToLoad = version;
    }

    final Directory versionDir = Directory(
      _appendPath(_versionsDir(artifactDir).path, '$versionToLoad'),
    );
    final _FileArtifactMetadata? metadata = _readMetadata(
      _metadataPath(artifactDir, versionToLoad),
    );
    final String? mimeType = metadata?.mimeType;

    final String storedFilename = artifactDir.uri.pathSegments
        .where((String segment) => segment.isNotEmpty)
        .last;
    File contentPath = File(_appendPath(versionDir.path, storedFilename));

    if (!contentPath.existsSync() && metadata != null) {
      final File? fromUri = _fileUriToPath(metadata.canonicalUri);
      if (fromUri != null && fromUri.existsSync()) {
        if (!_isUnderRootDir(fromUri)) {
          throw InputValidationError(
            "Artifact canonical_uri '${metadata.canonicalUri}' points outside rootDir ${rootDir.path}.",
          );
        }
        contentPath = fromUri;
      }
    }

    if (!contentPath.existsSync()) {
      return null;
    }

    if (mimeType != null && mimeType.isNotEmpty) {
      return Part.fromInlineData(
        mimeType: mimeType,
        data: contentPath.readAsBytesSync(),
      );
    }

    return Part.text(contentPath.readAsStringSync(encoding: utf8));
  }

  @override
  Future<List<String>> listArtifactKeys({
    required String appName,
    required String userId,
    String? sessionId,
  }) async {
    final Set<String> filenames = <String>{};
    final Directory baseRoot = _baseRoot(userId);

    if (sessionId != null && sessionId.isNotEmpty) {
      final Directory sessionRoot = _sessionArtifactsDir(baseRoot, sessionId);
      for (final Directory artifactDir in _iterArtifactDirs(sessionRoot)) {
        final _FileArtifactMetadata? metadata = _latestMetadata(artifactDir);
        if (metadata != null && metadata.fileName.isNotEmpty) {
          filenames.add(metadata.fileName);
          continue;
        }
        final String? relative = _relativePosixPath(sessionRoot, artifactDir);
        if (relative != null && relative.isNotEmpty) {
          filenames.add(relative);
        }
      }
    }

    final Directory userRoot = _userArtifactsDir(baseRoot);
    for (final Directory artifactDir in _iterArtifactDirs(userRoot)) {
      final _FileArtifactMetadata? metadata = _latestMetadata(artifactDir);
      if (metadata != null && metadata.fileName.isNotEmpty) {
        filenames.add(metadata.fileName);
        continue;
      }
      final String? relative = _relativePosixPath(userRoot, artifactDir);
      if (relative != null && relative.isNotEmpty) {
        filenames.add('user:$relative');
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
    final Directory artifactDir = _artifactPath(
      userId,
      sessionId,
      filename,
    ).artifactDir;
    if (artifactDir.existsSync()) {
      artifactDir.deleteSync(recursive: true);
    }
  }

  @override
  Future<List<int>> listVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final Directory artifactDir = _artifactPath(
      userId,
      sessionId,
      filename,
    ).artifactDir;
    return _listVersionsOnDisk(artifactDir);
  }

  @override
  Future<List<ArtifactVersion>> listArtifactVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final Directory artifactDir = _artifactPath(
      userId,
      sessionId,
      filename,
    ).artifactDir;
    final List<int> versions = _listVersionsOnDisk(artifactDir);

    final List<ArtifactVersion> result = <ArtifactVersion>[];
    for (final int version in versions) {
      final _FileArtifactMetadata? metadata = _readMetadata(
        _metadataPath(artifactDir, version),
      );
      result.add(
        _buildArtifactVersion(
          userId: userId,
          sessionId: sessionId,
          filename: filename,
          version: version,
          metadata: metadata,
        ),
      );
    }
    return result;
  }

  @override
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    final Directory artifactDir = _artifactPath(
      userId,
      sessionId,
      filename,
    ).artifactDir;
    final List<int> versions = _listVersionsOnDisk(artifactDir);
    if (versions.isEmpty) {
      return null;
    }

    final int versionToRead;
    if (version == null) {
      versionToRead = versions.last;
    } else {
      if (!versions.contains(version)) {
        return null;
      }
      versionToRead = version;
    }

    final _FileArtifactMetadata? metadata = _readMetadata(
      _metadataPath(artifactDir, versionToRead),
    );
    return _buildArtifactVersion(
      userId: userId,
      sessionId: sessionId,
      filename: filename,
      version: versionToRead,
      metadata: metadata,
    );
  }

  ArtifactVersion _buildArtifactVersion({
    required String userId,
    required String? sessionId,
    required String filename,
    required int version,
    required _FileArtifactMetadata? metadata,
  }) {
    final String canonicalUri = metadata?.canonicalUri.isNotEmpty == true
        ? metadata!.canonicalUri
        : _canonicalUri(userId, sessionId, filename, version);
    final Map<String, Object?> customMetadata =
        metadata?.customMetadata ?? <String, Object?>{};
    final String? mimeType = metadata?.mimeType;

    final Directory artifactDir = _artifactPath(
      userId,
      sessionId,
      filename,
    ).artifactDir;
    final String storedFilename = artifactDir.uri.pathSegments
        .where((String segment) => segment.isNotEmpty)
        .last;
    final File payload = File(
      _appendPath(
        _appendPath(_versionsDir(artifactDir).path, '$version'),
        storedFilename,
      ),
    );
    final double createTime = payload.existsSync()
        ? payload.statSync().changed.millisecondsSinceEpoch / 1000
        : DateTime.now().millisecondsSinceEpoch / 1000;

    return ArtifactVersion(
      version: version,
      canonicalUri: canonicalUri,
      customMetadata: customMetadata,
      createTime: createTime,
      mimeType: mimeType,
    );
  }
}
