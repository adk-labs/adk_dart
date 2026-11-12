/// Artifact service backed by an fsspec-compatible filesystem.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../artifacts/base_artifact_service.dart';
import '../../errors/input_validation_error.dart';
import '../../features/_feature_decorator.dart';
import '../../features/_feature_registry.dart';
import '../../types/content.dart';

const String _userNamespacePrefix = 'user:';
const String _userNamespaceSegment = 'user';
const String _defaultMimeType = 'application/octet-stream';
const Set<String> _gcsProtocols = <String>{'gs', 'gcs'};
const Set<String> _localProtocols = <String>{'file', 'local'};
const Set<String> _rapidPreconditionErrorNames = <String>{
  'FailedPrecondition',
  'PreconditionFailed',
};
const Set<String> _rapidSetxattrsReservedKeys = <String>{
  'self',
  'path',
  'content_type',
  'content_encoding',
  'fixed_key_metadata',
  'timeout',
};
const int _maxSaveVersionAttempts = 10;
const int _maxArtifactReferenceDepth = 5;

const String _adkDisplayNameMetadataKey = 'adkDisplayName';
const String _adkIsTextMetadataKey = 'adkIsText';
const String _adkFileUriMetadataKey = 'adkFileUri';
const String _adkFileMimeTypeMetadataKey = 'adkFileMimeType';
const String _legacyFileUriMetadataKey = 'file_uri';

const Set<String> _internalMetadataKeys = <String>{
  _adkDisplayNameMetadataKey,
  _adkIsTextMetadataKey,
  _adkFileUriMetadataKey,
  _adkFileMimeTypeMetadataKey,
  _legacyFileUriMetadataKey,
};

const Set<String> _reservedPathSegments = <String>{
  'apps',
  'users',
  'sessions',
  'artifacts',
  'versions',
};

final RegExp _windowsDrivePrefix = RegExp(r'^[A-Za-z]:');
final RegExp _asciiDigits = RegExp(r'^[0-9]+$');
final RegExp _schemePattern = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*)://');

const String _reservedSegmentsLookahead =
    r'(?!/(?:apps|artifacts|sessions|users|versions)/)';
const String _pathSegmentPattern = '(?:$_reservedSegmentsLookahead.)+?';
final RegExp _sessionScopedArtifactUriRe = RegExp(
  '^artifact://apps/($_pathSegmentPattern)/users/($_pathSegmentPattern)/sessions/($_pathSegmentPattern)/artifacts/(.+)/versions/(\\d+)\$',
);
final RegExp _userScopedArtifactUriRe = RegExp(
  '^artifact://apps/($_pathSegmentPattern)/users/($_pathSegmentPattern)/artifacts/(.+)/versions/(\\d+)\$',
);

const Map<String, String> _mimeTypesByExtension = <String, String>{
  'avif': 'image/avif',
  'bmp': 'image/bmp',
  'csv': 'text/csv',
  'gif': 'image/gif',
  'gz': 'application/gzip',
  'htm': 'text/html',
  'html': 'text/html',
  'ico': 'image/vnd.microsoft.icon',
  'jpeg': 'image/jpeg',
  'jpg': 'image/jpeg',
  'js': 'text/javascript',
  'json': 'application/json',
  'md': 'text/markdown',
  'mjs': 'text/javascript',
  'mp3': 'audio/mpeg',
  'mp4': 'video/mp4',
  'ogg': 'audio/ogg',
  'pdf': 'application/pdf',
  'png': 'image/png',
  'svg': 'image/svg+xml',
  'tar': 'application/x-tar',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'tsv': 'text/tab-separated-values',
  'txt': 'text/plain',
  'wasm': 'application/wasm',
  'wav': 'audio/wav',
  'webm': 'video/webm',
  'webp': 'image/webp',
  'xml': 'application/xml',
  'yaml': 'application/yaml',
  'yml': 'application/yaml',
  'zip': 'application/zip',
};

/// Input validation exception raised by [FsspecArtifactService].
///
/// Extends [ArgumentError] and implements [InputValidationError] so callers
/// catching either type handle validation errors consistently.
class FsspecInputValidationError extends ArgumentError
    implements InputValidationError {
  /// Creates an [FsspecInputValidationError] with [message].
  FsspecInputValidationError([String super.message = 'Invalid input.']);

  @override
  String get message => '${super.message ?? 'Invalid input.'}';

  @override
  String toString() => 'InputValidationError: $message';
}

/// Exception thrown when exclusive object creation fails because the target
/// path already exists.
class FsspecFileExistsException extends FileSystemException {
  /// Creates an [FsspecFileExistsException] for [path].
  FsspecFileExistsException(
    String path, {
    String message = 'File exists',
    this.cause,
  }) : super(message, path, const OSError('File exists', 17));

  /// Optional underlying backend exception.
  final Object? cause;
}

/// Exception thrown when an fsspec backend rejects an operation due to
/// insufficient permissions.
class FsspecPermissionException extends FileSystemException {
  /// Creates an [FsspecPermissionException] for [path].
  const FsspecPermissionException(
    String path, [
    String message = 'Permission denied',
  ]) : super(message, path, const OSError('Permission denied', 13));
}

/// Stand-in for GCS generation-0 precondition failures (`FailedPrecondition` /
/// `PreconditionFailed`) on Rapid GCS buckets.
class GcsPreconditionError implements Exception {
  /// Creates a [GcsPreconditionError].
  const GcsPreconditionError([this.message = 'Precondition failed']);

  /// Human-readable error message.
  final String message;

  @override
  String toString() => 'FailedPrecondition: $message';
}

/// Writable stream handle returned by [FilesystemProtocol.openWrite].
abstract class FsspecWriteStream {
  /// Whether this stream has been closed or aborted.
  bool closed = false;

  /// Backend-specific appendable object writer handle (used by Rapid GCS
  /// streams once generation-0 creation succeeds).
  Object? get aaow => null;

  /// Writes [bytes] into the open stream.
  void write(List<int> bytes);

  /// Flushes and finalizes the stream.
  void close();
}

/// Resolver signature matching `fsspec.core.url_to_fs`.
typedef FsspecUrlToFsResolver =
    (FilesystemProtocol, String) Function(
      String url, [
      Map<String, Object?>? storageOptions,
    ]);

/// Returns the marker [Part] saved during a session rewind to mark an artifact
/// as absent.
Part newRewindTombstone() {
  return Part.fromInlineData(mimeType: _defaultMimeType, data: const <int>[]);
}

bool _isRewindTombstone(Part artifact) {
  final InlineData? inline = artifact.inlineData;
  return inline != null &&
      inline.mimeType == _defaultMimeType &&
      inline.data.isEmpty &&
      inline.displayName == null &&
      artifact.text == null &&
      artifact.fileData == null &&
      artifact.functionCall == null &&
      artifact.functionResponse == null &&
      artifact.executableCode == null &&
      artifact.codeExecutionResult == null &&
      !artifact.thought &&
      artifact.thoughtSignature == null &&
      artifact.partMetadata == null;
}

class _ParsedArtifactUri {
  const _ParsedArtifactUri({
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

bool _isDriveQualified(String value) {
  return _windowsDrivePrefix.hasMatch(value);
}

bool _isArtifactRef(Part part) {
  final String? uri = part.fileData?.fileUri;
  return uri != null && uri.isNotEmpty && uri.startsWith('artifact://');
}

_ParsedArtifactUri? _parseArtifactUri(String uri) {
  if (uri.isEmpty || !uri.startsWith('artifact://')) {
    return null;
  }
  final RegExpMatch? sessionMatch = _sessionScopedArtifactUriRe.firstMatch(uri);
  if (sessionMatch != null) {
    final int? version = int.tryParse(sessionMatch.group(5)!);
    if (version == null) {
      return null;
    }
    return _ParsedArtifactUri(
      appName: sessionMatch.group(1)!,
      userId: sessionMatch.group(2)!,
      sessionId: sessionMatch.group(3)!,
      filename: sessionMatch.group(4)!,
      version: version,
    );
  }
  final RegExpMatch? userMatch = _userScopedArtifactUriRe.firstMatch(uri);
  if (userMatch != null) {
    final int? version = int.tryParse(userMatch.group(4)!);
    if (version == null) {
      return null;
    }
    return _ParsedArtifactUri(
      appName: userMatch.group(1)!,
      userId: userMatch.group(2)!,
      sessionId: null,
      filename: userMatch.group(3)!,
      version: version,
    );
  }
  return null;
}

void _validateArtifactReferenceScope({
  required String appName,
  required String userId,
  required String? sessionId,
  required _ParsedArtifactUri parsedUri,
}) {
  if (parsedUri.appName != appName || parsedUri.userId != userId) {
    throw FsspecInputValidationError(
      'Artifact references must stay within the same app and user scope.',
    );
  }
  if (parsedUri.sessionId != null && parsedUri.sessionId != sessionId) {
    throw FsspecInputValidationError(
      'Session-scoped artifact references must stay within the same'
      ' session scope.',
    );
  }
}

_ParsedArtifactUri _resolveArtifactReference({
  required String fileUri,
  required String appName,
  required String userId,
  required String? sessionId,
  required int remainingDepth,
}) {
  if (remainingDepth <= 0) {
    throw FsspecInputValidationError(
      'Exceeded maximum recursion depth resolving artifact reference:'
      ' $fileUri',
    );
  }
  final _ParsedArtifactUri? parsedUri = _parseArtifactUri(fileUri);
  if (parsedUri == null) {
    throw FsspecInputValidationError(
      'Invalid artifact reference URI: $fileUri',
    );
  }
  _validateArtifactReferenceScope(
    appName: appName,
    userId: userId,
    sessionId: sessionId,
    parsedUri: parsedUri,
  );
  return parsedUri;
}

void _validatePathSegment(String value, String fieldName) {
  if (value.isEmpty || value.trim().isEmpty) {
    throw FsspecInputValidationError('$fieldName must not be empty.');
  }
  if (value.contains('\x00')) {
    throw FsspecInputValidationError(
      '$fieldName must not contain null bytes.',
    );
  }
  if (value.startsWith('/') || value.startsWith(r'\')) {
    throw FsspecInputValidationError(
      '$fieldName "$value" must not be an absolute path or start with a'
      ' slash.',
    );
  }
  if (_isDriveQualified(value)) {
    throw FsspecInputValidationError(
      '$fieldName "$value" must not be drive-qualified.',
    );
  }
  final List<String> splitSegments = value.replaceAll(r'\', '/').split('/');
  if (value == '.' || value == '..' || splitSegments.contains('..')) {
    throw FsspecInputValidationError(
      '$fieldName "$value" must not contain traversal segments.',
    );
  }
  if (value.contains('/') || value.contains(r'\')) {
    final Set<String> segments = splitSegments
        .map((String s) => s.toLowerCase())
        .toSet();
    if (segments.intersection(_reservedPathSegments).isNotEmpty) {
      throw FsspecInputValidationError(
        '$fieldName "$value" must not contain reserved path segments.',
      );
    }
  }
}

void _validateSessionIdForFlatStorage(String sessionId) {
  _validatePathSegment(sessionId, 'session_id');
  if (sessionId.replaceAll(r'\', '/').split('/').first ==
      _userNamespaceSegment) {
    throw FsspecInputValidationError(
      "session_id must not be or start with the reserved value 'user'.",
    );
  }
}

bool _fileHasUserNamespace(String filename) {
  return filename.startsWith(_userNamespacePrefix);
}

Map<String, Object?> _userMetadata(Map<String, Object?>? rawMetadata) {
  if (rawMetadata == null || rawMetadata.isEmpty) {
    return <String, Object?>{};
  }
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in rawMetadata.entries)
      if (!_internalMetadataKeys.contains(entry.key)) entry.key: entry.value,
  };
}

void _validateFilename(String filename) {
  final String name = _fileHasUserNamespace(filename)
      ? filename.substring(_userNamespacePrefix.length)
      : filename;
  if (name.isEmpty) {
    throw FsspecInputValidationError('filename must not be empty.');
  }
  if (name.contains('\x00')) {
    throw FsspecInputValidationError('filename must not contain null bytes.');
  }
  if (name.startsWith('/') ||
      name.startsWith(r'\') ||
      _isDriveQualified(name)) {
    throw FsspecInputValidationError(
      'filename "$filename" must be a relative path.',
    );
  }
  final List<String> segments = name.replaceAll(r'\', '/').split('/');
  if (segments.any(
    (String segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    throw FsspecInputValidationError(
      'filename "$filename" must not contain empty or traversal segments.',
    );
  }
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

String _guessMime(String filename) {
  final String stripped = _fileHasUserNamespace(filename)
      ? filename.substring(_userNamespacePrefix.length)
      : filename;
  final int slashIdx = stripped.lastIndexOf('/');
  final String basename = slashIdx >= 0
      ? stripped.substring(slashIdx + 1)
      : stripped;
  final int dotIdx = basename.lastIndexOf('.');
  if (dotIdx <= 0 || dotIdx == basename.length - 1) {
    return _defaultMimeType;
  }
  final String ext = basename.substring(dotIdx + 1).toLowerCase();
  return _mimeTypesByExtension[ext] ?? _defaultMimeType;
}

List<String> _fsProtocols(FilesystemProtocol fs) {
  final Object? proto = fs.protocol;
  if (proto is String) {
    return <String>[proto];
  }
  if (proto is Iterable) {
    return proto.map((Object? e) => '$e').toList(growable: false);
  }
  return const <String>[];
}

(String?, String) _splitProtocol(String url) {
  final RegExpMatch? match = _schemePattern.firstMatch(url);
  if (match == null) {
    return (null, url);
  }
  final String scheme = match.group(1)!.toLowerCase();
  final String rest = url.substring(match.end);
  return (scheme, rest);
}

double _parseTimestamp(
  Map<String, Object?> info, {
  double Function()? clock,
}) {
  for (final String field in const <String>[
    'timeCreated',
    'created',
    'mtime',
    'LastModified',
    'updated',
  ]) {
    final Object? raw = info[field];
    if (raw is num) {
      return raw.toDouble();
    }
    if (raw is DateTime) {
      return raw.toUtc().microsecondsSinceEpoch / 1000000.0;
    }
    if (raw is String && raw.isNotEmpty) {
      final bool hasExplicitZone =
          raw.endsWith('Z') ||
          raw.endsWith('z') ||
          RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw) ||
          RegExp(r'[+-]\d{4}$').hasMatch(raw);
      final String normalizedIso = hasExplicitZone ? raw : '${raw}Z';
      final DateTime? parsed = DateTime.tryParse(normalizedIso);
      if (parsed != null) {
        return parsed.toUtc().microsecondsSinceEpoch / 1000000.0;
      }
    }
  }
  return clock != null
      ? clock()
      : DateTime.now().millisecondsSinceEpoch / 1000.0;
}

bool _isFileExistsError(Object error) {
  if (error is PathExistsException || error is FsspecFileExistsException) {
    return true;
  }
  if (error is FileSystemException && error.osError?.errorCode == 17) {
    return true;
  }
  return false;
}

bool _isMissingError(Object error) {
  if (_isFileExistsError(error) || error is FsspecPermissionException) {
    return false;
  }
  if (error is PathNotFoundException) {
    return true;
  }
  if (error is FileSystemException) {
    final int? code = error.osError?.errorCode;
    if (code != null) {
      // POSIX ENOENT (2), ENOTDIR (20); Windows ERROR_FILE_NOT_FOUND (2),
      // ERROR_PATH_NOT_FOUND (3), ERROR_DIRECTORY (267).
      return code == 2 || code == 3 || code == 20 || code == 267;
    }
    final String lower = error.message.toLowerCase();
    return lower.contains('not found') ||
        lower.contains('no such file') ||
        lower.contains('not a directory');
  }
  return false;
}

/// Structural contract for fsspec-compatible filesystem backends.
///
/// Mirrors the subset of `fsspec.AbstractFileSystem` used by
/// [FsspecArtifactService].
abstract class FilesystemProtocol {
  /// Creates a [FilesystemProtocol].
  const FilesystemProtocol();

  /// Protocol name (e.g. `'memory'`, `'file'`, `'s3'`, `'gs'`) or list of
  /// protocol names supported by this filesystem.
  Object? get protocol;

  /// Whether this backend implements an async-capable fsspec filesystem.
  bool get asyncImpl => false;

  /// Whether this filesystem instance was created with `asynchronous=True`.
  bool get asynchronous => false;

  /// Whether write operations automatically create parent directories.
  bool get autoMkdir => true;

  /// Strips any URL scheme/protocol prefix from [path] and returns the
  /// filesystem-internal path.
  String stripProtocol(String path);

  /// Prepends the canonical protocol scheme of this filesystem to [path].
  String unstripProtocol(String path) {
    final List<String> protocols = _fsProtocols(this);
    final String scheme = protocols.isEmpty ? 'file' : protocols.first;
    final String stripped = stripProtocol(path);
    return '$scheme://$stripped';
  }

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

  /// Writes [data] to [path].
  ///
  /// When [mode] is `'create'`, throws [FsspecFileExistsException] (or
  /// [PathExistsException]) if [path] already exists.
  void pipeFile(
    String path,
    List<int> data, {
    String mode = 'overwrite',
    String? contentType,
    Map<String, String>? metadata,
  }) {
    throw UnsupportedError('pipeFile is not supported by $runtimeType.');
  }

  /// Opens [path] for writing with [mode] (e.g. `'xb'` or `'wb'`).
  FsspecWriteStream openWrite(
    String path, {
    String mode = 'wb',
    int? generation,
    bool finalizeOnClose = false,
  }) {
    throw UnsupportedError('openWrite is not supported by $runtimeType.');
  }

  /// Removes the single file at [path].
  void rmFile(String path) {
    throw UnsupportedError('rmFile is not supported by $runtimeType.');
  }

  /// Creates [path] and its parent directories if needed.
  void makedirs(String path, {bool existOk = false}) {}

  /// Updates extended attributes (`contentType` and custom `metadata`) on an
  /// existing object at [path].
  void setxattrs(
    String path, {
    String? contentType,
    Map<String, String>? metadata,
  }) {
    throw UnsupportedError('setxattrs is not supported by $runtimeType.');
  }

  /// Optional gcsfs helper splitting [path] into `(bucket, key, generation)`.
  (String, String, Object?)? splitPath(String path) => null;

  /// Optional gcsfs helper returning the bucket type for [bucket] (e.g.
  /// `'ZONAL_HIERARCHICAL'` on Rapid GCS buckets).
  String? syncLookupBucketType(String bucket) => null;
}

class _InMemoryWriteStream extends FsspecWriteStream {
  _InMemoryWriteStream({
    required this.fs,
    required this.key,
    required this.exclusive,
  }) {
    if (exclusive && fs._files.containsKey(key)) {
      closed = true;
      throw FsspecFileExistsException(key);
    }
  }

  final InMemoryFsspecFilesystem fs;
  final String key;
  final bool exclusive;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  @override
  void write(List<int> bytes) {
    if (closed) {
      throw StateError('Stream is already closed.');
    }
    _buffer.add(bytes);
  }

  @override
  void close() {
    if (closed) {
      return;
    }
    closed = true;
    if (exclusive && fs._files.containsKey(key)) {
      throw FsspecFileExistsException(key);
    }
    fs.putFile(key, _buffer.takeBytes());
  }
}

/// In-memory [FilesystemProtocol] implementation for `memory://` URLs and
/// unit testing of object-store and POSIX-like fsspec backends.
class InMemoryFsspecFilesystem extends FilesystemProtocol {
  /// Creates an in-memory fsspec filesystem.
  InMemoryFsspecFilesystem({
    this.protocol = 'memory',
    this.rootMarker = '',
    this.asyncImpl = false,
    this.asynchronous = false,
    this.autoMkdir = true,
  });

  @override
  final Object? protocol;

  /// Root prefix marker (`''` for object/memory stores, `'/'` for POSIX stores).
  final String rootMarker;

  @override
  final bool asyncImpl;

  @override
  final bool asynchronous;

  @override
  final bool autoMkdir;

  /// Paths passed to [invalidateCache], recorded in call order for diagnostics
  /// and unit tests.
  final List<String?> invalidated = <String?>[];

  final Map<String, List<int>> _files = <String, List<int>>{};
  final Map<String, Map<String, Object?>> _metadata =
      <String, Map<String, Object?>>{};

  /// Read-only view of stored keys mapped to `(bytes, info)` records.
  Map<String, (List<int>, Map<String, Object?>)> get objects =>
      <String, (List<int>, Map<String, Object?>)>{
        for (final String key in _files.keys)
          key: (_files[key]!, _metadata[key] ?? <String, Object?>{}),
      };

  /// Writes [bytes] and optional [info] metadata at [path].
  void putFile(
    String path,
    List<int> bytes, {
    Map<String, Object?>? info,
  }) {
    final String normalized = stripProtocol(path);
    final List<int> copied = List<int>.unmodifiable(bytes);
    _files[normalized] = copied;
    _metadata[normalized] = <String, Object?>{
      'name': normalized,
      'size': copied.length,
      'type': 'file',
      ...?info,
    };
  }

  /// Removes a file at [path], if present.
  void removeFile(String path) {
    final String normalized = stripProtocol(path);
    _files.remove(normalized);
    _metadata.remove(normalized);
  }

  /// Updates stored info fields on [path] in place for test setup.
  void updateInfo(String path, Map<String, Object?> fields) {
    final String normalized = stripProtocol(path);
    final Map<String, Object?>? existing = _metadata[normalized];
    if (existing == null) {
      throw PathNotFoundException(path, const OSError('File not found', 2));
    }
    existing.addAll(fields);
  }

  @override
  String stripProtocol(String path) {
    final RegExpMatch? match = _schemePattern.firstMatch(path);
    final String stripped = match != null ? path.substring(match.end) : path;
    return _normalize(stripped);
  }

  @override
  String unstripProtocol(String path) {
    final List<String> protocols = _fsProtocols(this);
    final String scheme = protocols.isEmpty ? 'memory' : protocols.first;
    final String normalized = stripProtocol(path);
    return '$scheme://$normalized';
  }

  @override
  void invalidateCache([String? path]) {
    invalidated.add(path);
  }

  @override
  Object find(
    String path, {
    int? maxdepth,
    bool withdirs = false,
    bool detail = false,
  }) {
    final String root = stripProtocol(path);
    final String prefix = root.isEmpty || root == '/' ? root : '$root/';
    final bool rootExistsAsFile = _files.containsKey(root);
    final List<String> matchedFiles = <String>[
      if (rootExistsAsFile) root,
      for (final String key in _files.keys)
        if (key != root &&
            (prefix.isEmpty ||
                (prefix == '/' ? key.startsWith('/') : key.startsWith(prefix))))
          if (_withinMaxDepth(root, key, maxdepth)) key,
    ];

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
            : prefix == '/'
            ? fileKey.substring(1)
            : fileKey.substring(prefix.length);
        final List<String> parts = rel.split('/');
        String current = root == '/' ? '' : root;
        for (int i = 0; i < parts.length - 1; i++) {
          current = current.isEmpty
              ? (rootMarker == '/' ? '/${parts[i]}' : parts[i])
              : '$current/${parts[i]}';
          if (_withinMaxDepth(root, current, maxdepth)) {
            entries.putIfAbsent(
              current,
              () => <String, Object?>{'name': current, 'type': 'directory'},
            );
          }
        }
      }
    }

    final List<String> sortedKeys = entries.keys.toList()..sort();
    if (detail) {
      return <String, Map<String, Object?>>{
        for (final String k in sortedKeys) k: entries[k]!,
      };
    }
    return sortedKeys;
  }

  @override
  Map<String, Object?> info(String path) {
    final String normalized = stripProtocol(path);
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
    final String prefix = normalized.isEmpty || normalized == '/'
        ? normalized
        : '$normalized/';
    final bool hasChild = _files.keys.any(
      (String key) =>
          prefix.isEmpty ||
          (prefix == '/' ? key.startsWith('/') : key.startsWith(prefix)),
    );
    if (hasChild) {
      return <String, Object?>{'name': normalized, 'type': 'directory'};
    }
    throw PathNotFoundException(path, const OSError('File not found', 2));
  }

  @override
  List<int> catFile(String path) {
    final String normalized = stripProtocol(path);
    final List<int>? data = _files[normalized];
    if (data == null) {
      throw PathNotFoundException(path, const OSError('File not found', 2));
    }
    return List<int>.from(data);
  }

  @override
  void pipeFile(
    String path,
    List<int> data, {
    String mode = 'overwrite',
    String? contentType,
    Map<String, String>? metadata,
  }) {
    final String normalized = stripProtocol(path);
    if (mode == 'create' && _files.containsKey(normalized)) {
      throw FsspecFileExistsException(normalized);
    }
    final Map<String, Object?> extra = <String, Object?>{
      'mtime': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'contentType': ?contentType,
      if (metadata != null && metadata.isNotEmpty)
        'metadata': Map<String, String>.from(metadata),
    };
    putFile(normalized, data, info: extra);
  }

  @override
  FsspecWriteStream openWrite(
    String path, {
    String mode = 'wb',
    int? generation,
    bool finalizeOnClose = false,
  }) {
    final String normalized = stripProtocol(path);
    return _InMemoryWriteStream(
      fs: this,
      key: normalized,
      exclusive: mode.contains('x') || generation == 0,
    );
  }

  @override
  void rmFile(String path) {
    final String normalized = stripProtocol(path);
    if (!_files.containsKey(normalized)) {
      throw PathNotFoundException(path, const OSError('File not found', 2));
    }
    _files.remove(normalized);
    _metadata.remove(normalized);
  }

  @override
  void setxattrs(
    String path, {
    String? contentType,
    Map<String, String>? metadata,
  }) {
    final String normalized = stripProtocol(path);
    final Map<String, Object?>? entry = _metadata[normalized];
    if (entry == null) {
      throw PathNotFoundException(path, const OSError('File not found', 2));
    }
    if (contentType != null) {
      entry['contentType'] = contentType;
    }
    if (metadata != null && metadata.isNotEmpty) {
      final Map<String, String> merged = <String, String>{};
      final Object? existing = entry['metadata'];
      if (existing is Map) {
        existing.forEach((Object? k, Object? v) {
          if (k != null && v != null) {
            merged['$k'] = '$v';
          }
        });
      }
      merged.addAll(metadata);
      entry['metadata'] = merged;
    }
  }

  bool _withinMaxDepth(String root, String candidate, int? maxdepth) {
    if (maxdepth == null) {
      return true;
    }
    final String rel = root.isEmpty
        ? candidate
        : root == '/'
        ? (candidate.startsWith('/') ? candidate.substring(1) : candidate)
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
    if (rootMarker == '/') {
      if (result.isEmpty || result == '/') {
        return '/';
      }
      while (result.startsWith('//')) {
        result = result.substring(1);
      }
      if (!result.startsWith('/')) {
        result = '/$result';
      }
      while (result.length > 1 && result.endsWith('/')) {
        result = result.substring(0, result.length - 1);
      }
      return result;
    }
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}

class _LocalWriteStream extends FsspecWriteStream {
  _LocalWriteStream(String path, {required bool exclusive}) {
    final File file = File(path);
    if (exclusive) {
      file.createSync(exclusive: true);
    }
    _raf = file.openSync(mode: FileMode.writeOnly);
  }

  late final RandomAccessFile _raf;

  @override
  void write(List<int> bytes) {
    if (closed) {
      throw StateError('Stream is already closed.');
    }
    _raf.writeFromSync(bytes);
  }

  @override
  void close() {
    if (closed) {
      return;
    }
    closed = true;
    _raf.closeSync();
  }
}

/// Local disk [FilesystemProtocol] implementation for `file://` URLs and plain
/// filesystem paths.
class LocalFsspecFilesystem extends FilesystemProtocol {
  /// Creates a local disk fsspec filesystem.
  const LocalFsspecFilesystem();

  @override
  Object? get protocol => const <String>['file', 'local'];

  @override
  bool get autoMkdir => false;

  @override
  String stripProtocol(String path) {
    if (path.startsWith('file://')) {
      final String afterScheme = path.substring('file://'.length);
      if (afterScheme.length >= 3 &&
          afterScheme.startsWith('/') &&
          _isDriveQualified(afterScheme.substring(1))) {
        return afterScheme.substring(1).replaceAll(r'\', '/');
      }
      return Uri.parse(path).toFilePath();
    }
    final RegExpMatch? match = _schemePattern.firstMatch(path);
    if (match != null) {
      return path.substring(match.end);
    }
    return path;
  }

  @override
  String unstripProtocol(String path) {
    final String normalized = stripProtocol(path).replaceAll(r'\', '/');
    return 'file://$normalized';
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
    final FileSystemEntityType entityType = FileSystemEntity.typeSync(
      stripped,
      followLinks: true,
    );
    if (entityType == FileSystemEntityType.notFound) {
      throw PathNotFoundException(
        stripped,
        const OSError('Directory not found', 2),
      );
    }
    if (entityType == FileSystemEntityType.file) {
      final File file = File(stripped);
      final FileStat stat = file.statSync();
      final String normalized = stripped.replaceAll('\\', '/');
      final Map<String, Object?> meta = <String, Object?>{
        'name': normalized,
        'size': stat.size,
        'type': 'file',
        'mtime': stat.modified.toUtc().microsecondsSinceEpoch / 1000000.0,
      };
      return detail
          ? <String, Map<String, Object?>>{normalized: meta}
          : <String>[normalized];
    }

    final Directory dir = Directory(stripped);
    final String rootPath = dir.path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+$'), '');
    final Map<String, Map<String, Object?>> results =
        <String, Map<String, Object?>>{};
    for (final FileSystemEntity entity in dir.listSync(
      recursive: true,
      followLinks: false,
    )) {
      final String entityPath = entity.path.replaceAll('\\', '/');
      final String rel = entityPath.startsWith('$rootPath/')
          ? entityPath.substring(rootPath.length + 1)
          : entityPath;
      final int depth = rel.isEmpty ? 0 : rel.split('/').length;
      if (maxdepth != null && depth > maxdepth) {
        continue;
      }
      if (entity is File) {
        final FileStat stat = entity.statSync();
        results[entityPath] = <String, Object?>{
          'name': entityPath,
          'size': stat.size,
          'type': 'file',
          'mtime': stat.modified.toUtc().microsecondsSinceEpoch / 1000000.0,
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
    final FileSystemEntityType entityType = FileSystemEntity.typeSync(
      stripped,
      followLinks: true,
    );
    if (entityType == FileSystemEntityType.file) {
      final File file = File(stripped);
      final FileStat stat = file.statSync();
      return <String, Object?>{
        'name': stripped.replaceAll('\\', '/'),
        'size': stat.size,
        'type': 'file',
        'mtime': stat.modified.toUtc().microsecondsSinceEpoch / 1000000.0,
      };
    }
    if (entityType == FileSystemEntityType.directory) {
      return <String, Object?>{
        'name': stripped.replaceAll('\\', '/'),
        'type': 'directory',
      };
    }
    throw PathNotFoundException(stripped, const OSError('Path not found', 2));
  }

  @override
  List<int> catFile(String path) {
    final String stripped = stripProtocol(path);
    final FileSystemEntityType entityType = FileSystemEntity.typeSync(
      stripped,
      followLinks: true,
    );
    if (entityType != FileSystemEntityType.file) {
      throw PathNotFoundException(stripped, const OSError('File not found', 2));
    }
    return File(stripped).readAsBytesSync();
  }

  @override
  FsspecWriteStream openWrite(
    String path, {
    String mode = 'wb',
    int? generation,
    bool finalizeOnClose = false,
  }) {
    final String stripped = stripProtocol(path);
    return _LocalWriteStream(stripped, exclusive: mode.contains('x'));
  }

  @override
  void pipeFile(
    String path,
    List<int> data, {
    String mode = 'overwrite',
    String? contentType,
    Map<String, String>? metadata,
  }) {
    final FsspecWriteStream stream = openWrite(
      path,
      mode: mode == 'create' ? 'xb' : 'wb',
    );
    try {
      if (data.isNotEmpty) {
        stream.write(data);
      }
      stream.close();
    } catch (_) {
      stream.close();
      rethrow;
    }
  }

  @override
  void rmFile(String path) {
    final String stripped = stripProtocol(path);
    final FileSystemEntityType entityType = FileSystemEntity.typeSync(
      stripped,
      followLinks: false,
    );
    if (entityType == FileSystemEntityType.notFound) {
      throw PathNotFoundException(stripped, const OSError('File not found', 2));
    }
    File(stripped).deleteSync();
  }

  @override
  void makedirs(String path, {bool existOk = false}) {
    final String stripped = stripProtocol(path);
    final Directory dir = Directory(stripped);
    if (!existOk && dir.existsSync()) {
      throw PathExistsException(stripped, const OSError('File exists', 17));
    }
    final FileSystemEntityType existingType = FileSystemEntity.typeSync(
      stripped,
      followLinks: true,
    );
    if (existingType == FileSystemEntityType.file) {
      throw FileSystemException(
        'Not a directory',
        stripped,
        const OSError('Not a directory', 20),
      );
    }
    dir.createSync(recursive: true);
  }
}

final Map<String, InMemoryFsspecFilesystem> _sharedMemoryFilesystems =
    <String, InMemoryFsspecFilesystem>{};

/// Resolves [url] into a `(FilesystemProtocol, String rootPath)` pair.
(FilesystemProtocol, String) urlToFs(
  String url, [
  Map<String, Object?>? storageOptions,
]) {
  final (String? rawScheme, _) = _splitProtocol(url);
  final String scheme = rawScheme ?? 'file';
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

/// Artifact service backed by any `fsspec`-compatible filesystem.
///
/// Uses the same object layout and custom metadata keys as
/// `GcsArtifactService`:
/// - Session-scoped: `{root}/{app_name}/{user_id}/{session_id}/{filename}/{version}`
/// - User-scoped (`user:`): `{root}/{app_name}/{user_id}/user/{filename}/{version}`
///
/// Gated behind [FeatureName.fsspecArtifactService] (`@experimental`).
class FsspecArtifactService extends BaseArtifactService {
  /// Creates an [FsspecArtifactService] rooted at [baseUrl].
  ///
  /// Throws [StateError] when [FeatureName.fsspecArtifactService] is not
  /// enabled, and [ArgumentError] when [baseUrl] is empty, [fs] is combined
  /// with non-empty [storageOptions], [fs] does not handle [baseUrl]'s scheme,
  /// or [fs] was created with `asynchronous=True`.
  FsspecArtifactService(
    this.baseUrl, {
    FilesystemProtocol? fs,
    Map<String, Object?>? storageOptions,
    FsspecUrlToFsResolver? urlToFsResolver,
    double Function()? clock,
  }) : _clock = clock {
    experimental(FeatureName.fsspecArtifactService).checkEnabled();

    if (baseUrl.isEmpty) {
      throw ArgumentError('base_url must be a non-empty string.');
    }

    final (String? protocol, _) = _splitProtocol(baseUrl);
    FilesystemProtocol resolvedFs;
    String root;
    if (fs == null) {
      final Map<String, Object?> effectiveOptions = <String, Object?>{
        'use_listings_cache': false,
        ...?storageOptions,
      };
      final (FilesystemProtocol createdFs, String resolvedRoot) =
          (urlToFsResolver ?? urlToFs)(baseUrl, effectiveOptions);
      resolvedFs = createdFs;
      root = resolvedRoot;
    } else {
      if (storageOptions != null && storageOptions.isNotEmpty) {
        throw ArgumentError('storage_options cannot be combined with fs.');
      }
      final List<String> handledProtocols = _fsProtocols(fs);
      if (protocol != null && !handledProtocols.contains(protocol)) {
        throw ArgumentError(
          "base_url protocol '$protocol' is not handled by the provided fs"
          ' (protocols: (${handledProtocols.join(', ')})).',
        );
      }
      resolvedFs = fs;
      root = fs.stripProtocol(baseUrl);
    }

    if (resolvedFs.asyncImpl && resolvedFs.asynchronous) {
      throw ArgumentError(
        'fs must be synchronous; create it without asynchronous=True.',
      );
    }

    _fs = resolvedFs;
    _scheme = protocol;
    _root = root.replaceAll(RegExp(r'/+$'), '');
  }

  /// Root URL or path passed at construction time.
  final String baseUrl;

  /// Alias for [baseUrl].
  String get url => baseUrl;

  final double Function()? _clock;
  late final FilesystemProtocol _fs;
  late final String? _scheme;
  late final String _root;

  /// Underlying fsspec filesystem instance.
  FilesystemProtocol get fs => _fs;

  /// Normalized root path within [fs].
  String get rootPath => _root;

  bool _isGcs() {
    return _fsProtocols(_fs).toSet().intersection(_gcsProtocols).isNotEmpty;
  }

  bool _isLocal() {
    return _fsProtocols(_fs).toSet().intersection(_localProtocols).isNotEmpty;
  }

  bool _isRapidGcsBucket(String key) {
    final (String, String, Object?)? parts = _fs.splitPath(key);
    if (parts == null) {
      return false;
    }
    final String? bucketType = _fs.syncLookupBucketType(parts.$1);
    return bucketType != null && bucketType.endsWith('ZONAL_HIERARCHICAL');
  }

  String _canonicalUri(String key) {
    final String uri = _fs.unstripProtocol(key);
    final int sep = uri.indexOf('://');
    final String scheme = sep >= 0 ? uri.substring(0, sep) : '';
    String rest = sep >= 0 ? uri.substring(sep + 3) : uri;
    final String effectiveScheme = _scheme ?? scheme;
    if (effectiveScheme == 'file' && _isDriveQualified(rest)) {
      rest = '/$rest';
    }
    return '$effectiveScheme://$rest';
  }

  String _path(List<String> parts) {
    if (_root.isEmpty && !_isPosixRooted()) {
      return parts.join('/');
    }
    return <String>[_root, ...parts].join('/');
  }

  bool _isPosixRooted() {
    if (_isLocal()) {
      return !_isDriveQualified(_root);
    }
    final FilesystemProtocol backend = _fs;
    if (backend is InMemoryFsspecFilesystem) {
      return backend.rootMarker == '/';
    }
    return _fs.stripProtocol('/').startsWith('/');
  }

  String _scopePath(
    String appName,
    String userId,
    String? sessionId,
    String filename,
  ) {
    if (_fileHasUserNamespace(filename)) {
      return _path(<String>[appName, userId, _userNamespaceSegment]);
    }
    if (sessionId == null) {
      throw FsspecInputValidationError(
        'Session ID must be provided for session-scoped artifacts.',
      );
    }
    _validatePathSegment(sessionId, 'session_id');
    return _path(<String>[appName, userId, sessionId]);
  }

  String _artifactPath(
    String appName,
    String userId,
    String? sessionId,
    String filename,
  ) {
    _validatePathSegment(appName, 'app_name');
    _validatePathSegment(userId, 'user_id');
    _validateFilename(filename);
    final String scope = _scopePath(appName, userId, sessionId, filename);
    return '$scope/$filename';
  }

  Map<String, Map<String, Object?>> _findDetail(String path) {
    final String strippedBase = _fs.stripProtocol(path);
    final String prefix = strippedBase == '/' ? '/' : '$strippedBase/';
    _fs.invalidateCache(path);
    Object detail;
    try {
      detail = _fs.find(prefix, detail: true);
    } catch (error) {
      if (_isMissingError(error)) {
        return <String, Map<String, Object?>>{};
      }
      rethrow;
    }

    if (detail is! Map) {
      return <String, Map<String, Object?>>{};
    }
    final Map<String, Map<String, Object?>> matched =
        <String, Map<String, Object?>>{};
    detail.forEach((Object? rawName, Object? rawInfo) {
      if (rawInfo is! Map) {
        return;
      }
      final Map<String, Object?> info = <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in rawInfo.entries)
          '${entry.key}': entry.value,
      };
      if ((info['type'] ?? 'file') != 'file') {
        return;
      }
      final String stripped = _fs.stripProtocol('$rawName');
      if (stripped.startsWith(prefix)) {
        matched[stripped.substring(prefix.length)] = info;
      }
    });
    return matched;
  }

  void _removeFailedVersion(String key) {
    try {
      _fs.rmFile(key);
    } catch (_) {
      // Best-effort cleanup; preserve original write error for the caller.
    }
    _fs.invalidateCache(key);
  }

  void _writeVersion(
    String key,
    List<int> data,
    String? contentType,
    Map<String, String> blobMetadata,
  ) {
    if (!_isGcs()) {
      if (_isLocal()) {
        final FsspecWriteStream stream = _fs.openWrite(key, mode: 'xb');
        try {
          if (data.isNotEmpty) {
            stream.write(data);
          }
          stream.close();
        } catch (_) {
          stream.close();
          rethrow;
        }
      } else {
        _fs.pipeFile(key, data, mode: 'create');
      }
      return;
    }

    if (_isRapidGcsBucket(key)) {
      final List<String> reserved =
          blobMetadata.keys
              .where(_rapidSetxattrsReservedKeys.contains)
              .toList()
            ..sort();
      if (reserved.isNotEmpty) {
        throw FsspecInputValidationError(
          'custom_metadata keys are not supported on Rapid GCS buckets:'
          ' ${reserved.join(', ')}.',
        );
      }
      final FsspecWriteStream stream = _fs.openWrite(
        key,
        mode: 'wb',
        generation: 0,
        finalizeOnClose: true,
      );
      try {
        if (data.isNotEmpty) {
          stream.write(data);
        }
        stream.close();
      } catch (exc) {
        stream.closed = true;
        final String excName = exc.runtimeType.toString();
        if (exc is GcsPreconditionError ||
            _rapidPreconditionErrorNames.contains(excName)) {
          throw FsspecFileExistsException(key, cause: exc);
        }
        if (stream.aaow != null) {
          _removeFailedVersion(key);
        }
        rethrow;
      }
      try {
        _fs.setxattrs(
          key,
          contentType: contentType ?? _defaultMimeType,
          metadata: blobMetadata,
        );
      } catch (_) {
        _removeFailedVersion(key);
        rethrow;
      }
      return;
    }

    _fs.pipeFile(
      key,
      data,
      mode: 'create',
      contentType: contentType,
      metadata: blobMetadata.isEmpty ? null : blobMetadata,
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
  }) async {
    return _saveArtifactSync(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      filename: filename,
      artifact: artifact,
      customMetadata: customMetadata,
    );
  }

  int _saveArtifactSync({
    required String appName,
    required String userId,
    required String? sessionId,
    required String filename,
    required Part artifact,
    required Map<String, Object?>? customMetadata,
  }) {
    final String artifactPath = _artifactPath(
      appName,
      userId,
      sessionId,
      filename,
    );
    if (sessionId != null && !_fileHasUserNamespace(filename)) {
      _validateSessionIdForFlatStorage(sessionId);
    }

    final Map<String, String> blobMetadata = <String, String>{
      for (final MapEntry<String, Object?> entry
          in _userMetadata(customMetadata).entries)
        entry.key: '${entry.value}',
    };

    late final List<int> data;
    late final String? contentType;
    if (artifact.inlineData != null) {
      final InlineData inline = artifact.inlineData!;
      if (blobMetadata.isNotEmpty && !_isGcs()) {
        throw FsspecInputValidationError(
          'Saving custom_metadata requires a filesystem backend that'
          ' persists custom object metadata (such as gs://).',
        );
      }
      data = inline.data;
      contentType = inline.mimeType.isEmpty ? null : inline.mimeType;
      final String? displayName = inline.displayName;
      if (displayName != null && displayName.isNotEmpty) {
        blobMetadata[_adkDisplayNameMetadataKey] = displayName;
      }
    } else if (artifact.text != null) {
      if (!_isGcs()) {
        throw FsspecInputValidationError(
          'Saving text artifacts requires a filesystem backend that'
          ' persists custom object metadata (such as gs://).',
        );
      }
      data = utf8.encode(artifact.text!);
      contentType = 'text/plain';
      blobMetadata[_adkIsTextMetadataKey] = 'true';
    } else if (artifact.fileData != null) {
      final FileData fileData = artifact.fileData!;
      final String fileUri = fileData.fileUri;
      if (fileUri.isEmpty) {
        throw FsspecInputValidationError(
          'Artifact file_data must have a file_uri.',
        );
      }
      if (!_isGcs()) {
        throw FsspecInputValidationError(
          'Saving file_data URI references requires a filesystem backend'
          ' that persists custom object metadata (such as gs://).',
        );
      }
      if (_isArtifactRef(artifact)) {
        final _ParsedArtifactUri? parsedUri = _parseArtifactUri(fileUri);
        if (parsedUri == null) {
          throw FsspecInputValidationError(
            'Invalid artifact reference URI: $fileUri',
          );
        }
        _validateArtifactReferenceScope(
          appName: appName,
          userId: userId,
          sessionId: sessionId,
          parsedUri: parsedUri,
        );
      }
      blobMetadata[_adkFileUriMetadataKey] = fileUri;
      final String? fileMimeType = fileData.mimeType;
      if (fileMimeType != null && fileMimeType.isNotEmpty) {
        blobMetadata[_adkFileMimeTypeMetadataKey] = fileMimeType;
      }
      data = const <int>[];
      contentType = (fileMimeType != null && fileMimeType.isNotEmpty)
          ? fileMimeType
          : null;
    } else {
      throw FsspecInputValidationError(
        'Artifact must have either inline_data, text, or file_data.',
      );
    }

    if (!_isGcs() && !_fs.autoMkdir) {
      _fs.makedirs(artifactPath, existOk: true);
    }

    final List<int> versions = _versionsUnder(artifactPath);
    int version = versions.isEmpty ? 0 : versions.last + 1;

    int attemptsLeft = _maxSaveVersionAttempts;
    while (true) {
      final String key = '$artifactPath/$version';
      try {
        _writeVersion(key, data, contentType, blobMetadata);
      } catch (error) {
        if (!_isFileExistsError(error)) {
          rethrow;
        }
        attemptsLeft -= 1;
        if (attemptsLeft == 0) {
          rethrow;
        }
        version += 1;
        continue;
      }
      _fs.invalidateCache(artifactPath);
      _fs.invalidateCache(key);
      return version;
    }
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
      sessionId: sessionId,
      filename: filename,
      version: version,
    );
  }

  Part? _loadArtifactSync({
    required String appName,
    required String userId,
    required String? sessionId,
    required String filename,
    required int? version,
    int maxDepth = _maxArtifactReferenceDepth,
  }) {
    final String artifactPath = _artifactPath(
      appName,
      userId,
      sessionId,
      filename,
    );
    int resolvedVersion;
    if (version == null) {
      final List<int> versions = _versionsUnder(artifactPath);
      if (versions.isEmpty) {
        return null;
      }
      resolvedVersion = versions.last;
    } else if (version < 0) {
      return null;
    } else {
      resolvedVersion = version;
    }
    final String key = '$artifactPath/$resolvedVersion';

    _fs.invalidateCache(key);
    Map<String, Object?> info;
    try {
      info = _fs.info(key);
    } catch (error) {
      if (_isMissingError(error)) {
        return null;
      }
      rethrow;
    }
    if ((info['type'] ?? 'file') != 'file') {
      return null;
    }

    final String? storedContentType = _nonEmptyString(
      info['contentType'] ?? info['ContentType'],
    );
    final Map<String, Object?> metadata = _metadataMap(info['metadata']);

    final String? fileUri =
        _nonEmptyString(metadata[_adkFileUriMetadataKey]) ??
        _nonEmptyString(metadata[_legacyFileUriMetadataKey]);
    if (fileUri != null) {
      if (fileUri.startsWith('artifact://')) {
        final _ParsedArtifactUri parsedUri = _resolveArtifactReference(
          fileUri: fileUri,
          appName: appName,
          userId: userId,
          sessionId: sessionId,
          remainingDepth: maxDepth,
        );
        return _loadArtifactSync(
          appName: parsedUri.appName,
          userId: parsedUri.userId,
          sessionId: parsedUri.sessionId,
          filename: parsedUri.filename,
          version: parsedUri.version,
          maxDepth: maxDepth - 1,
        );
      }
      return Part.fromFileData(
        fileUri: fileUri,
        mimeType:
            _nonEmptyString(metadata[_adkFileMimeTypeMetadataKey]) ??
            storedContentType,
      );
    }

    List<int> data;
    try {
      data = _fs.catFile(key);
    } catch (error) {
      if (_isMissingError(error)) {
        return null;
      }
      rethrow;
    }

    if (metadata[_adkIsTextMetadataKey] == 'true') {
      return Part.text(utf8.decode(data, allowMalformed: false));
    }

    final Part loaded = Part.fromInlineData(
      data: data,
      mimeType: storedContentType ?? _guessMime(filename),
      displayName: _nonEmptyString(metadata[_adkDisplayNameMetadataKey]),
    );
    if (_isRewindTombstone(loaded) ||
        (!_isGcs() && data.isEmpty && storedContentType == null)) {
      return null;
    }
    return loaded;
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

  List<String> _listArtifactKeysSync({
    required String appName,
    required String userId,
    required String? sessionId,
  }) {
    _validatePathSegment(appName, 'app_name');
    _validatePathSegment(userId, 'user_id');
    final List<String> scopes = <String>[
      _path(<String>[appName, userId, _userNamespaceSegment]),
    ];
    if (sessionId != null) {
      _validatePathSegment(sessionId, 'session_id');
      scopes.add(_path(<String>[appName, userId, sessionId]));
    }

    final Set<String> filenames = <String>{};
    for (final String scope in scopes) {
      for (final String relPath in _findDetail(scope).keys) {
        final int slashIdx = relPath.lastIndexOf('/');
        if (slashIdx <= 0) {
          continue;
        }
        final String filename = relPath.substring(0, slashIdx);
        final String suffix = relPath.substring(slashIdx + 1);
        if (_parseVersion(suffix) != null) {
          filenames.add(filename);
        }
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
    _deleteArtifactSync(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      filename: filename,
    );
  }

  void _deleteArtifactSync({
    required String appName,
    required String userId,
    required String? sessionId,
    required String filename,
  }) {
    final String artifactPath = _artifactPath(
      appName,
      userId,
      sessionId,
      filename,
    );
    for (final int version in _versionsUnder(artifactPath)) {
      final String key = '$artifactPath/$version';
      try {
        _fs.rmFile(key);
      } catch (error) {
        if (!_isMissingError(error)) {
          rethrow;
        }
      }
      _fs.invalidateCache(key);
    }
    _fs.invalidateCache(artifactPath);
  }

  @override
  Future<List<int>> listVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    return _versionsUnder(
      _artifactPath(appName, userId, sessionId, filename),
    );
  }

  List<int> _versionsUnder(String artifactPath) {
    final List<int> versions = <int>[];
    for (final String suffix in _findDetail(artifactPath).keys) {
      final int? version = suffix.contains('/') ? null : _parseVersion(suffix);
      if (version == null) {
        continue;
      }
      versions.add(version);
    }
    versions.sort();
    return versions;
  }

  ArtifactVersion _buildArtifactVersion(
    int version,
    String key,
    String filename,
    Map<String, Object?> info,
  ) {
    final String? storedContentType = _nonEmptyString(
      info['contentType'] ?? info['ContentType'],
    );
    final Map<String, Object?> metadata = _metadataMap(info['metadata']);
    final bool hasFileUri =
        _nonEmptyString(metadata[_adkFileUriMetadataKey]) != null ||
        _nonEmptyString(metadata[_legacyFileUriMetadataKey]) != null;
    final String? mimeType = hasFileUri
        ? (_nonEmptyString(metadata[_adkFileMimeTypeMetadataKey]) ??
              storedContentType)
        : (storedContentType ?? _guessMime(filename));

    return ArtifactVersion(
      version: version,
      canonicalUri: _canonicalUri(key),
      createTime: _parseTimestamp(info, clock: _clock),
      mimeType: mimeType,
      customMetadata: _userMetadata(metadata),
    );
  }

  @override
  Future<List<ArtifactVersion>> listArtifactVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final String artifactPath = _artifactPath(
      appName,
      userId,
      sessionId,
      filename,
    );
    final List<ArtifactVersion> artifactVersions = <ArtifactVersion>[];
    _findDetail(artifactPath).forEach((
      String suffix,
      Map<String, Object?> info,
    ) {
      final int? version = suffix.contains('/') ? null : _parseVersion(suffix);
      if (version == null) {
        return;
      }
      final String key = '$artifactPath/$version';
      artifactVersions.add(
        _buildArtifactVersion(version, key, filename, info),
      );
    });
    artifactVersions.sort(
      (ArtifactVersion a, ArtifactVersion b) => a.version.compareTo(b.version),
    );
    return artifactVersions;
  }

  @override
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    final String artifactPath = _artifactPath(
      appName,
      userId,
      sessionId,
      filename,
    );
    int resolvedVersion;
    if (version == null) {
      final List<int> versions = _versionsUnder(artifactPath);
      if (versions.isEmpty) {
        return null;
      }
      resolvedVersion = versions.last;
    } else if (version < 0) {
      return null;
    } else {
      resolvedVersion = version;
    }
    final String key = '$artifactPath/$resolvedVersion';

    _fs.invalidateCache(key);
    Map<String, Object?> info;
    try {
      info = _fs.info(key);
    } catch (error) {
      if (_isMissingError(error)) {
        return null;
      }
      rethrow;
    }
    if ((info['type'] ?? 'file') != 'file') {
      return null;
    }
    return _buildArtifactVersion(resolvedVersion, key, filename, info);
  }

  static String? _nonEmptyString(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  static Map<String, Object?> _metadataMap(Object? raw) {
    if (raw is! Map) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        if (entry.key != null) '${entry.key}': entry.value,
    };
  }
}
