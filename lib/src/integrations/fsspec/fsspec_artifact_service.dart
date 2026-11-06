/// Read-only artifact service backed by an fsspec-compatible filesystem.
library;

import 'dart:convert';
import 'dart:io';

import '../../artifacts/base_artifact_service.dart';
import '../../types/content.dart';

const String _userNamespacePrefix = 'user:';
const String _displayNameMetadataKey = 'adkDisplayName';
const String _isTextMetadataKey = 'adkIsText';
const String _fileUriMetadataKey = 'adkFileUri';
const String _legacyFileUriMetadataKey = 'file_uri';
const String _fileMimeTypeMetadataKey = 'adkFileMimeType';
final RegExp _windowsDrivePrefix = RegExp(r'^[A-Za-z]:');
final RegExp _asciiDigits = RegExp(r'^[0-9]+$');

/// Structural contract for fsspec-compatible filesystem backends.
///
/// Mirrors the subset of `fsspec.AbstractFileSystem` used by
/// [FsspecArtifactService].
abstract class FilesystemProtocol {
  /// Protocol name (e.g. `'memory'`, `'file'`, `'s3'`, `'gcs'`) or list of
  /// protocol names supported by this filesystem.
  Object? get protocol;

  /// Strips any URL scheme/protocol prefix from [path] and returns the
  /// filesystem-internal path.
  String stripProtocol(String path);

  /// Invalidates cached directory listings and metadata for [path] (or the
  /// entire filesystem when [path] is omitted).
  void invalidateCache([String? path]);

  /// Recursively lists entries under [path].
  ///
  /// When [detail] is `true`, returns a `Map<String, Map<String, Object?>>`
  /// mapping each entry path to its metadata dictionary (or a `List<String>`).
  Object find(
    String path, {
    int? maxdepth,
    bool withdirs = false,
    bool detail = false,
  });

  /// Returns metadata dictionary for [path].
  ///
  /// Throws a [FileSystemException] when [path] does not exist.
  Map<String, Object?> info(String path);

  /// Reads and returns the raw bytes of the file at [path].
  ///
  /// Throws a [FileSystemException] when [path] does not exist.
  List<int> catFile(String path);
}

/// In-memory [FilesystemProtocol] implementation for `memory://` URLs and
/// unit testing.
class InMemoryFsspecFilesystem implements FilesystemProtocol {
  /// Creates an in-memory fsspec filesystem.
  InMemoryFsspecFilesystem({this.protocol = 'memory'});

  @override
  final Object? protocol;

  final Map<String, List<int>> _files = <String, List<int>>{};
  final Map<String, Map<String, Object?>> _metadata =
      <String, Map<String, Object?>>{};

  /// Writes [bytes] and optional [info] metadata at [path].
  void putFile(
    String path,
    List<int> bytes, {
    Map<String, Object?>? info,
  }) {
    final String normalized = _normalize(stripProtocol(path));
    _files[normalized] = List<int>.unmodifiable(bytes);
    _metadata[normalized] = <String, Object?>{
      'name': normalized,
      'size': bytes.length,
      'type': 'file',
      ...?info,
    };
  }

  /// Removes a file at [path], if present.
  void removeFile(String path) {
    final String normalized = _normalize(stripProtocol(path));
    _files.remove(normalized);
    _metadata.remove(normalized);
  }

  @override
  String stripProtocol(String path) {
    final int schemeSep = path.indexOf('://');
    final String stripped = schemeSep >= 0
        ? path.substring(schemeSep + 3)
        : path;
    return _normalize(stripped);
  }

  @override
  void invalidateCache([String? path]) {}

  @override
  Object find(
    String path, {
    int? maxdepth,
    bool withdirs = false,
    bool detail = false,
  }) {
    final String root = _normalize(stripProtocol(path));
    final String prefix = root.isEmpty ? '' : '$root/';
    final bool rootExistsAsFile = _files.containsKey(root);
    final List<String> matchedFiles = <String>[
      if (rootExistsAsFile) root,
      for (final String key in _files.keys)
        if (prefix.isEmpty || key.startsWith(prefix))
          if (_withinMaxDepth(root, key, maxdepth)) key,
    ];
    if (!rootExistsAsFile && matchedFiles.isEmpty) {
      throw FileSystemException('Path not found', path);
    }

    final Map<String, Map<String, Object?>> entries =
        <String, Map<String, Object?>>{};
    for (final String fileKey in matchedFiles) {
      entries[fileKey] = Map<String, Object?>.from(
        _metadata[fileKey] ??
            <String, Object?>{
              'name': fileKey,
              'size': _files[fileKey]?.length ?? 0,
              'type': 'file',
            },
      );
      if (withdirs) {
        final String rel = prefix.isEmpty
            ? fileKey
            : fileKey.substring(prefix.length);
        final List<String> parts = rel.split('/');
        String current = root;
        for (int i = 0; i < parts.length - 1; i++) {
          current = current.isEmpty ? parts[i] : '$current/${parts[i]}';
          if (_withinMaxDepth(root, current, maxdepth)) {
            entries.putIfAbsent(
              current,
              () => <String, Object?>{'name': current, 'type': 'directory'},
            );
          }
        }
      }
    }

    if (detail) {
      return entries;
    }
    final List<String> keys = entries.keys.toList()..sort();
    return keys;
  }

  @override
  Map<String, Object?> info(String path) {
    final String normalized = _normalize(stripProtocol(path));
    if (_files.containsKey(normalized)) {
      return Map<String, Object?>.from(
        _metadata[normalized] ??
            <String, Object?>{
              'name': normalized,
              'size': _files[normalized]!.length,
              'type': 'file',
            },
      );
    }
    final String prefix = normalized.isEmpty ? '' : '$normalized/';
    final bool hasChild = _files.keys.any(
      (String key) => prefix.isEmpty || key.startsWith(prefix),
    );
    if (hasChild) {
      return <String, Object?>{'name': normalized, 'type': 'directory'};
    }
    throw FileSystemException('File not found', path);
  }

  @override
  List<int> catFile(String path) {
    final String normalized = _normalize(stripProtocol(path));
    final List<int>? data = _files[normalized];
    if (data == null) {
      throw FileSystemException('File not found', path);
    }
    return List<int>.from(data);
  }

  bool _withinMaxDepth(String root, String candidate, int? maxdepth) {
    if (maxdepth == null) {
      return true;
    }
    final String rel = root.isEmpty
        ? candidate
        : candidate.startsWith('$root/')
        ? candidate.substring(root.length + 1)
        : '';
    if (rel.isEmpty) {
      return true;
    }
    final int depth = rel.split('/').length;
    return depth <= maxdepth;
  }

  String _normalize(String raw) {
    String result = raw.replaceAll('\\', '/').trim();
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}

/// Local disk [FilesystemProtocol] implementation for `file://` URLs and plain
/// filesystem paths.
class LocalFsspecFilesystem implements FilesystemProtocol {
  /// Creates a local disk fsspec filesystem.
  const LocalFsspecFilesystem();

  @override
  Object? get protocol => const <String>['file', 'local'];

  @override
  String stripProtocol(String path) {
    if (path.startsWith('file://')) {
      return Uri.parse(path).toFilePath();
    }
    final int schemeSep = path.indexOf('://');
    if (schemeSep >= 0) {
      return path.substring(schemeSep + 3);
    }
    return path;
  }

  @override
  void invalidateCache([String? path]) {}

  @override
  Object find(
    String path, {
    int? maxdepth,
    bool withdirs = false,
    bool detail = false,
  }) {
    final String stripped = stripProtocol(path);
    final File file = File(stripped);
    if (file.existsSync()) {
      final String normalized = stripped.replaceAll('\\', '/');
      final Map<String, Object?> meta = <String, Object?>{
        'name': normalized,
        'size': file.lengthSync(),
        'type': 'file',
      };
      return detail
          ? <String, Map<String, Object?>>{normalized: meta}
          : <String>[normalized];
    }

    final Directory dir = Directory(stripped);
    if (!dir.existsSync()) {
      throw FileSystemException('Directory not found', path);
    }

    final String rootPath = dir.path.replaceAll('\\', '/').replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final Map<String, Map<String, Object?>> results =
        <String, Map<String, Object?>>{};
    for (final FileSystemEntity entity
        in dir.listSync(recursive: true, followLinks: false)) {
      final String entityPath = entity.path.replaceAll('\\', '/');
      final String rel = entityPath.startsWith('$rootPath/')
          ? entityPath.substring(rootPath.length + 1)
          : entityPath;
      final int depth = rel.isEmpty ? 0 : rel.split('/').length;
      if (maxdepth != null && depth > maxdepth) {
        continue;
      }
      if (entity is File) {
        results[entityPath] = <String, Object?>{
          'name': entityPath,
          'size': entity.lengthSync(),
          'type': 'file',
        };
      } else if (withdirs && entity is Directory) {
        results[entityPath] = <String, Object?>{
          'name': entityPath,
          'type': 'directory',
        };
      }
    }
    if (detail) {
      return results;
    }
    final List<String> keys = results.keys.toList()..sort();
    return keys;
  }

  @override
  Map<String, Object?> info(String path) {
    final String stripped = stripProtocol(path);
    final File file = File(stripped);
    if (file.existsSync()) {
      return <String, Object?>{
        'name': stripped.replaceAll('\\', '/'),
        'size': file.lengthSync(),
        'type': 'file',
      };
    }
    final Directory dir = Directory(stripped);
    if (dir.existsSync()) {
      return <String, Object?>{
        'name': stripped.replaceAll('\\', '/'),
        'type': 'directory',
      };
    }
    throw FileSystemException('Path not found', path);
  }

  @override
  List<int> catFile(String path) {
    final String stripped = stripProtocol(path);
    final File file = File(stripped);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', path);
    }
    return file.readAsBytesSync();
  }
}

final Map<String, InMemoryFsspecFilesystem> _sharedMemoryFilesystems =
    <String, InMemoryFsspecFilesystem>{};

/// Resolves [url] into a `(FilesystemProtocol, String rootPath)` pair.
(FilesystemProtocol, String) urlToFs(
  String url, [
  Map<String, Object?>? storageOptions,
]) {
  final int schemeIdx = url.indexOf('://');
  final String scheme = schemeIdx >= 0
      ? url.substring(0, schemeIdx).toLowerCase()
      : 'file';
  if (scheme == 'file' || scheme == 'local') {
    const LocalFsspecFilesystem fs = LocalFsspecFilesystem();
    return (fs, fs.stripProtocol(url));
  }
  if (scheme == 'memory') {
    final InMemoryFsspecFilesystem fs = _sharedMemoryFilesystems.putIfAbsent(
      scheme,
      () => InMemoryFsspecFilesystem(protocol: scheme),
    );
    return (fs, fs.stripProtocol(url));
  }
  final InMemoryFsspecFilesystem fs = InMemoryFsspecFilesystem(
    protocol: scheme,
  );
  return (fs, fs.stripProtocol(url));
}

bool _fileHasUserNamespace(String filename) {
  return filename.startsWith(_userNamespacePrefix);
}

void _validateFilename(String filename) {
  if (filename.isEmpty) {
    throw ArgumentError.value(
      filename,
      'filename',
      'Artifact filename cannot be empty.',
    );
  }
  if (filename.contains('\x00')) {
    throw ArgumentError.value(
      filename,
      'filename',
      'Artifact filename cannot contain null bytes: $filename',
    );
  }
  if (filename.startsWith('/') ||
      filename.startsWith(r'\') ||
      _windowsDrivePrefix.hasMatch(filename)) {
    throw ArgumentError.value(
      filename,
      'filename',
      'Artifact filename must be relative: $filename',
    );
  }
  final List<String> segments = filename.replaceAll(r'\', '/').split('/');
  if (segments.any(
    (String segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    throw ArgumentError.value(
      filename,
      'filename',
      'Artifact filename cannot contain empty, ".", or ".." path segments: '
          '$filename',
    );
  }
}

String _normalizePath(String path) {
  String result = path.replaceAll(r'\', '/');
  while (result.endsWith('/') && result != '/') {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

String _joinPath(List<String> parts) {
  final List<String> cleaned = <String>[];
  for (int i = 0; i < parts.length; i++) {
    final String part = parts[i];
    if (part.isEmpty) {
      continue;
    }
    String normalized = part.replaceAll(r'\', '/');
    if (i == 0 && normalized.startsWith('/')) {
      normalized = normalized.replaceFirst(RegExp(r'^/+'), '');
      while (normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      cleaned.add('/$normalized');
    } else {
      normalized = normalized
          .replaceFirst(RegExp(r'^/+'), '')
          .replaceFirst(RegExp(r'/+$'), '');
      if (normalized.isNotEmpty) {
        cleaned.add(normalized);
      }
    }
  }
  if (cleaned.isEmpty) {
    return '';
  }
  if (cleaned.length == 1 && cleaned.first == '/') {
    return '/';
  }
  if (cleaned.first == '/') {
    return '/${cleaned.sublist(1).join('/')}';
  }
  return cleaned.join('/');
}

int? _parseVersion(String suffix) {
  if (!_asciiDigits.hasMatch(suffix)) {
    return null;
  }
  if (suffix.length > 1 && suffix.startsWith('0')) {
    return null;
  }
  return int.tryParse(suffix);
}

List<Map<String, Object?>> _metadataContainers(Map<String, Object?> info) {
  final List<Map<String, Object?>> containers = <Map<String, Object?>>[];
  final Object? nested = info['metadata'] ?? info['Metadata'];
  if (nested is Map) {
    containers.add(<String, Object?>{
      for (final MapEntry<Object?, Object?> entry in nested.entries)
        '${entry.key}': entry.value,
    });
  }
  containers.add(info);
  return containers;
}

String? _extractMetadataValue(Map<String, Object?> info, String key) {
  final String loweredKey = key.toLowerCase();
  for (final Map<String, Object?> container in _metadataContainers(info)) {
    for (final MapEntry<String, Object?> entry in container.entries) {
      if (entry.key.toLowerCase() == loweredKey && entry.value != null) {
        return '${entry.value}';
      }
    }
  }
  return null;
}

String? _extractContentType(Map<String, Object?> info) {
  for (final Map<String, Object?> container in _metadataContainers(info)) {
    for (final String key in const <String>[
      'ContentType',
      'content_type',
      'content-type',
      'mimetype',
      'mime_type',
    ]) {
      final Object? value = container[key];
      if (value is String && value.isNotEmpty) {
        return value.split(';').first.trim();
      }
    }
  }
  return null;
}

bool _shouldDecodeText(Map<String, Object?> info, String? contentType) {
  final String? isTextValue = _extractMetadataValue(info, _isTextMetadataKey);
  if (isTextValue != null) {
    return isTextValue.toLowerCase() == 'true';
  }
  return contentType?.toLowerCase() == 'text/plain';
}

/// Read-only artifact service backed by an fsspec-compatible filesystem.
///
/// Stores and reads artifacts using the same object layout and custom metadata
/// keys as `GcsArtifactService`:
/// - Session-scoped: `{root}/{app_name}/{user_id}/{session_id}/{filename}/{version}`
/// - User-scoped (`user:`): `{root}/{app_name}/{user_id}/user/{filename}/{version}`
class FsspecArtifactService extends BaseArtifactService {
  /// Creates an [FsspecArtifactService] rooted at [url].
  ///
  /// When [fs] is provided, [url] is stripped via [FilesystemProtocol.stripProtocol]
  /// and [storageOptions] must be omitted or empty.
  FsspecArtifactService(
    this.url, {
    FilesystemProtocol? fs,
    Map<String, Object?>? storageOptions,
  }) {
    if (fs != null && storageOptions != null && storageOptions.isNotEmpty) {
      throw ArgumentError(
        'Cannot specify both an explicit filesystem `fs` and `storageOptions`.',
      );
    }
    if (fs != null) {
      _fs = fs;
      _rootPath = _normalizePath(fs.stripProtocol(url));
    } else {
      final (FilesystemProtocol resolvedFs, String root) = urlToFs(
        url,
        storageOptions,
      );
      _fs = resolvedFs;
      _rootPath = _normalizePath(root);
    }
  }

  /// Root URL or path passed at construction time.
  final String url;

  late final FilesystemProtocol _fs;
  late final String _rootPath;

  /// Underlying fsspec filesystem instance.
  FilesystemProtocol get fs => _fs;

  /// Normalized root path within [fs].
  String get rootPath => _rootPath;

  String _scopePrefix({
    required String appName,
    required String userId,
    String? sessionId,
    required bool userScoped,
  }) {
    if (userScoped) {
      return _joinPath(<String>[_rootPath, appName, userId, 'user']);
    }
    if (sessionId == null || sessionId.isEmpty) {
      throw ArgumentError(
        'Session ID must be provided for session-scoped artifacts.',
      );
    }
    return _joinPath(<String>[_rootPath, appName, userId, sessionId]);
  }

  String _artifactPrefix({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) {
    _validateFilename(filename);
    final bool userScoped = _fileHasUserNamespace(filename);
    final String scope = _scopePrefix(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      userScoped: userScoped,
    );
    return _joinPath(<String>[scope, filename]);
  }

  String _versionPath({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    required int version,
  }) {
    final String prefix = _artifactPrefix(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
    return _joinPath(<String>[prefix, '$version']);
  }

  void _invalidateCache([String? path]) {
    try {
      if (path != null) {
        _fs.invalidateCache(path);
      } else {
        _fs.invalidateCache();
      }
    } catch (_) {
      try {
        _fs.invalidateCache();
      } catch (_) {}
    }
  }

  List<String> _findFiles(String prefix, {int? maxdepth}) {
    _invalidateCache(prefix);
    Object raw;
    try {
      raw = _fs.find(
        prefix,
        maxdepth: maxdepth,
        withdirs: false,
        detail: true,
      );
    } on FileSystemException {
      return const <String>[];
    }

    if (raw is Map) {
      final List<String> files = <String>[];
      raw.forEach((Object? key, Object? value) {
        if (value is Map) {
          final Object? type = value['type'] ?? value['StorageClass'];
          if (type == 'directory') {
            return;
          }
        }
        files.add(_normalizePath(_fs.stripProtocol('$key')));
      });
      return files;
    }
    if (raw is Iterable) {
      return raw
          .map((Object? item) => _normalizePath(_fs.stripProtocol('$item')))
          .toList(growable: false);
    }
    return const <String>[];
  }

  List<int> _listVersionsSync({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) {
    final String prefix = _artifactPrefix(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
    final List<String> files = _findFiles(prefix, maxdepth: 1);
    final String expectedPrefix = prefix.isEmpty ? '' : '$prefix/';
    final List<int> versions = <int>[];
    for (final String file in files) {
      if (!file.startsWith(expectedPrefix)) {
        continue;
      }
      final String suffix = file.substring(expectedPrefix.length);
      if (suffix.contains('/')) {
        continue;
      }
      final int? parsed = _parseVersion(suffix);
      if (parsed != null) {
        versions.add(parsed);
      }
    }
    versions.sort();
    return versions;
  }

  Part? _loadArtifactSync({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) {
    int? resolvedVersion = version;
    if (resolvedVersion == null) {
      final List<int> versions = _listVersionsSync(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
      );
      if (versions.isEmpty) {
        return null;
      }
      resolvedVersion = versions.last;
    } else {
      _validateFilename(filename);
    }

    final String versionPath = _versionPath(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
      version: resolvedVersion,
    );
    _invalidateCache(versionPath);

    Map<String, Object?> info;
    try {
      info = _fs.info(versionPath);
    } on FileSystemException {
      return null;
    }
    if (info['type'] == 'directory') {
      return null;
    }

    final String? displayName = _extractMetadataValue(
      info,
      _displayNameMetadataKey,
    );
    final String? contentType = _extractContentType(info);
    final String? fileUri =
        _extractMetadataValue(info, _fileUriMetadataKey) ??
        _extractMetadataValue(info, _legacyFileUriMetadataKey);
    if (fileUri != null && fileUri.isNotEmpty) {
      final String? fileMimeType =
          _extractMetadataValue(info, _fileMimeTypeMetadataKey) ?? contentType;
      return Part.fromFileData(
        fileUri: fileUri,
        mimeType: fileMimeType,
        displayName: displayName,
      );
    }

    List<int> rawBytes;
    try {
      rawBytes = _fs.catFile(versionPath);
    } on FileSystemException {
      return null;
    }

    if (_shouldDecodeText(info, contentType) && displayName == null) {
      try {
        final String decoded = utf8.decode(rawBytes, allowMalformed: false);
        return Part.text(decoded);
      } on FormatException {
        // Fall back to inlineData when bytes are not valid UTF-8.
      }
    }

    return Part.fromInlineData(
      mimeType: contentType ?? 'application/octet-stream',
      data: rawBytes,
      displayName: displayName,
    );
  }

  List<String> _listArtifactKeysSync({
    required String appName,
    required String userId,
    String? sessionId,
  }) {
    final Set<String> keys = <String>{};

    void collectFromScope(String scopePrefix, {required bool requireUserNs}) {
      final List<String> files = _findFiles(scopePrefix);
      final String expectedPrefix = scopePrefix.isEmpty ? '' : '$scopePrefix/';
      for (final String file in files) {
        if (!file.startsWith(expectedPrefix)) {
          continue;
        }
        final String relative = file.substring(expectedPrefix.length);
        final int lastSlash = relative.lastIndexOf('/');
        if (lastSlash <= 0) {
          continue;
        }
        final String filename = relative.substring(0, lastSlash);
        final String versionSegment = relative.substring(lastSlash + 1);
        if (_parseVersion(versionSegment) == null) {
          continue;
        }
        if (requireUserNs && !_fileHasUserNamespace(filename)) {
          continue;
        }
        keys.add(filename);
      }
    }

    if (sessionId != null && sessionId.isNotEmpty) {
      final String sessionScope = _scopePrefix(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        userScoped: false,
      );
      collectFromScope(sessionScope, requireUserNs: false);
    }

    final String userScope = _scopePrefix(
      appName: appName,
      userId: userId,
      userScoped: true,
    );
    collectFromScope(userScope, requireUserNs: true);

    final List<String> sorted = keys.toList()..sort();
    return sorted;
  }

  @override
  Future<Part?> loadArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    return _loadArtifactSync(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
      version: version,
    );
  }

  @override
  Future<List<String>> listArtifactKeys({
    required String appName,
    required String userId,
    String? sessionId,
  }) async {
    return _listArtifactKeysSync(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  @override
  Future<List<int>> listVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    return _listVersionsSync(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
  }

  @override
  Future<int> saveArtifact({
    required String appName,
    required String userId,
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) {
    throw UnimplementedError(
      'FsspecArtifactService is currently read-only; '
      'saveArtifact is not implemented yet.',
    );
  }

  @override
  Future<void> deleteArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) {
    throw UnimplementedError(
      'FsspecArtifactService is currently read-only; '
      'deleteArtifact is not implemented yet.',
    );
  }

  @override
  Future<List<ArtifactVersion>> listArtifactVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) {
    throw UnimplementedError(
      'FsspecArtifactService is currently read-only; '
      'listArtifactVersions is not implemented yet.',
    );
  }

  @override
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) {
    throw UnimplementedError(
      'FsspecArtifactService is currently read-only; '
      'getArtifactVersion is not implemented yet.',
    );
  }
}
