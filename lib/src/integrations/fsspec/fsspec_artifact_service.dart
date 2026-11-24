/// Artifact service backed by an fsspec-compatible filesystem.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../artifacts/base_artifact_service.dart';
import '../../errors/input_validation_error.dart';
import '../../features/_feature_decorator.dart';
import '../../features/_feature_registry.dart';
import '../../types/content.dart';
import 'backends.dart';
import 'cloud_filesystems.dart';

const String _userNamespacePrefix = 'user:';
const String _userNamespaceSegment = 'user';
const String _defaultMimeType = 'application/octet-stream';
const Set<String> _localProtocols = <String>{'file', 'local'};
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

/// Exception thrown when an fsspec backend cannot find the requested path.
class FsspecFileNotFoundException extends FileSystemException {
  /// Creates an [FsspecFileNotFoundException] for [path].
  FsspecFileNotFoundException(
    String path, {
    String message = 'File not found',
    this.cause,
  }) : super(message, path, const OSError('File not found', 2));

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
  FutureOr<void> close();
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

  /// Optional backend library version string (for example the `adlfs` version
  /// on Azure filesystems).
  String? get backendVersion => null;

  /// Strips any URL scheme/protocol prefix from [path] and returns the
  /// filesystem-internal path.
  String stripProtocol(String path);

  /// Returns the parent directory path of [path], matching `fsspec._parent`.
  String parent(String path) {
    final String stripped = stripProtocol(path);
    final String trimmed = stripped.endsWith('/') && stripped.length > 1
        ? stripped.substring(0, stripped.length - 1)
        : stripped;
    final int slash = trimmed.lastIndexOf('/');
    if (slash < 0) {
      return '';
    }
    if (slash == 0) {
      return '/';
    }
    return trimmed.substring(0, slash);
  }

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
  /// Optional [prefix] restricts matches to entries under `[path]/[prefix]`.
  FutureOr<Object> find(
    String path, {
    int? maxdepth,
    bool withdirs = false,
    bool detail = false,
    String? prefix,
  });

  /// Returns metadata dictionary for [path].
  ///
  /// Throws a [FileSystemException] when [path] does not exist.
  FutureOr<Map<String, Object?>> info(String path);

  /// Returns whether [path] exists in this filesystem.
  FutureOr<bool> exists(String path) async {
    try {
      await info(path);
      return true;
    } catch (error) {
      if (_isMissingError(error)) {
        return false;
      }
      rethrow;
    }
  }

  /// Reads and returns the raw bytes of the file at [path].
  ///
  /// Throws a [FileSystemException] when [path] does not exist.
  FutureOr<List<int>> catFile(String path);

  /// Writes [data] to [path].
  ///
  /// When [mode] is `'create'`, throws [FsspecFileExistsException] (or
  /// [PathExistsException]) if [path] already exists.
  FutureOr<void> pipeFile(
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
    Map<String, String>? metadata,
    Map<String, Object?>? contentSettings,
  }) {
    throw UnsupportedError('openWrite is not supported by $runtimeType.');
  }

  /// Removes the single file at [path].
  FutureOr<void> rmFile(String path) {
    throw UnsupportedError('rmFile is not supported by $runtimeType.');
  }

  /// Removes [path], optionally recursively when [recursive] is `true`.
  FutureOr<void> rm(String path, {bool recursive = false}) async {
    if (!recursive) {
      await rmFile(path);
      return;
    }
    final Object found = await find(path);
    if (found is List) {
      for (final Object? item in found) {
        if (item is String) {
          try {
            await rmFile(item);
          } catch (error) {
            if (!_isMissingError(error)) {
              rethrow;
            }
          }
        }
      }
    }
  }

  /// Creates [path] and its parent directories if needed.
  FutureOr<void> makedirs(String path, {bool existOk = false}) {}

  /// Updates extended attributes (`contentType` and custom `metadata`) on an
  /// existing object at [path].
  FutureOr<void> setxattrs(
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

  /// Returns user metadata for [path] (used by S3 / `s3fs` backends whose
  /// `info()` and listings omit user metadata).
  FutureOr<Map<String, String>> metadata(String path) =>
      const <String, String>{};
}

class _InMemoryWriteStream extends FsspecWriteStream {
  _InMemoryWriteStream({
    required this.fs,
    required this.key,
    required this.exclusive,
    this.metadata,
    this.contentSettings,
  }) {
    if (exclusive && fs._files.containsKey(key)) {
      closed = true;
      throw FsspecFileExistsException(key);
    }
  }

  final InMemoryFsspecFilesystem fs;
  final String key;
  final bool exclusive;
  final Map<String, String>? metadata;
  final Map<String, Object?>? contentSettings;
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
    final Map<String, Object?> extra = <String, Object?>{
      'mtime': DateTime.now().millisecondsSinceEpoch / 1000.0,
      if (metadata != null && metadata!.isNotEmpty)
        'metadata': Map<String, String>.from(metadata!),
      if (contentSettings != null && contentSettings!.isNotEmpty)
        'content_settings': Map<String, Object?>.from(contentSettings!),
    };
    fs.putFile(key, _buffer.takeBytes(), info: extra);
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
    this.backendVersion,
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

  @override
  final String? backendVersion;

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
    String? prefix,
  }) {
    final String baseRoot = stripProtocol(path);
    final String normalizedSubPrefix = prefix == null ? '' : _normalize(prefix);
    final String root = normalizedSubPrefix.isEmpty
        ? baseRoot
        : (baseRoot.isEmpty || baseRoot == '/'
              ? (baseRoot == '/' ? '/$normalizedSubPrefix' : normalizedSubPrefix)
              : '$baseRoot/$normalizedSubPrefix');
    final String searchPrefix = root.isEmpty || root == '/' ? root : '$root/';
    final bool rootExistsAsFile = _files.containsKey(root);
    final List<String> matchedFiles = <String>[
      if (rootExistsAsFile) root,
      for (final String key in _files.keys)
        if (key != root &&
            (searchPrefix.isEmpty ||
                (searchPrefix == '/'
                    ? key.startsWith('/')
                    : key.startsWith(searchPrefix))))
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
        final String rel = searchPrefix.isEmpty
            ? fileKey
            : searchPrefix == '/'
            ? fileKey.substring(1)
            : fileKey.substring(searchPrefix.length);
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
  Map<String, String> metadata(String path) {
    final String normalized = stripProtocol(path);
    if (!_files.containsKey(normalized)) {
      throw PathNotFoundException(path, const OSError('File not found', 2));
    }
    final Map<String, Object?>? entryInfo = _metadata[normalized];
    final Object? rawMeta = entryInfo?['metadata'];
    if (rawMeta is! Map) {
      return const <String, String>{};
    }
    final bool isS3 = _fsProtocols(
      this,
    ).any((String p) => p == 's3' || p == 's3a');
    return <String, String>{
      for (final MapEntry<Object?, Object?> entry in rawMeta.entries)
        if (entry.key != null && entry.value != null)
          (isS3
              ? '${entry.key}'.toLowerCase().replaceAll('_', '-')
              : '${entry.key}'): '${entry.value}',
    };
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
    Map<String, String>? metadata,
    Map<String, Object?>? contentSettings,
  }) {
    final String normalized = stripProtocol(path);
    return _InMemoryWriteStream(
      fs: this,
      key: normalized,
      exclusive: mode.contains('x') || generation == 0,
      metadata: metadata,
      contentSettings: contentSettings,
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
    String? prefix,
  }) {
    final String baseStripped = stripProtocol(path);
    final String stripped = (prefix != null && prefix.isNotEmpty)
        ? '$baseStripped/$prefix'
        : baseStripped;
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
    Map<String, String>? metadata,
    Map<String, Object?>? contentSettings,
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
  if (scheme == 'gs' || scheme == 'gcs') {
    final GcsFsspecFilesystem fs = GcsFsspecFilesystem.fromStorageOptions(
      storageOptions,
    );
    return (fs, fs.stripProtocol(url));
  }
  if (scheme == 's3' || scheme == 's3a') {
    final S3FsspecFilesystem fs = S3FsspecFilesystem.fromStorageOptions(
      storageOptions,
    );
    return (fs, fs.stripProtocol(url));
  }
  if (scheme == 'abfs' || scheme == 'abfss' || scheme == 'az') {
    final AzureBlobFsspecFilesystem fs =
        AzureBlobFsspecFilesystem.fromStorageOptions(storageOptions);
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
/// S3 (`s3fs`) also stores content type and custom metadata. Its
/// `custom_metadata` keys come back lowercased with `_` turned into `-`.
/// `custom_metadata` keys must be HTTP header names, and caller keys that S3
/// would read back as ADK's own keys or as each other are rejected.
///
/// Azure (`adlfs`) also stores content type and custom metadata. Its
/// `custom_metadata` keys must be C# identifiers that stay distinct and do not
/// match ADK's or `adlfs`'s own keys when case is ignored. On both stores,
/// values must be printable ASCII without spaces at either end.
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
  late final FsspecBackendAdapter _backend =
      FsspecBackendAdapter.forFilesystem(_fs, clock: _clock);
  late final String? _scheme;
  late final String _root;

  /// Underlying fsspec filesystem instance.
  FilesystemProtocol get fs => _fs;

  /// Per-backend adapter handling object creation and metadata reads.
  FsspecBackendAdapter get backend => _backend;

  /// Normalized root path within [fs].
  String get rootPath => _root;

  bool _isLocal() {
    return _fsProtocols(_fs).toSet().intersection(_localProtocols).isNotEmpty;
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

  Future<Map<String, Map<String, Object?>>> _findDetail(String path) async {
    final String strippedBase = _fs.stripProtocol(path);
    final String prefix = strippedBase == '/' ? '/' : '$strippedBase/';
    _fs.invalidateCache(path);
    Object detail;
    try {
      detail = await _backend.findDetail(prefix);
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

  @override
  Future<int> saveArtifact({
    required String appName,
    required String userId,
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    return _saveArtifact(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      filename: filename,
      artifact: artifact,
      customMetadata: customMetadata,
    );
  }

  Future<int> _saveArtifact({
    required String appName,
    required String userId,
    required String? sessionId,
    required String filename,
    required Part artifact,
    required Map<String, Object?>? customMetadata,
  }) async {
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
      if (blobMetadata.isNotEmpty && !_backend.storesCustomMetadata) {
        throw FsspecInputValidationError(
          'Saving custom_metadata requires a filesystem backend that persists'
          ' custom object metadata (such as gs://, s3:// or abfs://).',
        );
      }
      data = inline.data;
      contentType = inline.mimeType.isEmpty ? null : inline.mimeType;
      final String? displayName = inline.displayName;
      if (displayName != null && displayName.isNotEmpty) {
        blobMetadata[_adkDisplayNameMetadataKey] = displayName;
      }
    } else if (artifact.text != null) {
      if (!_backend.storesCustomMetadata) {
        throw FsspecInputValidationError(
          'Saving text artifacts requires a filesystem backend that persists'
          ' custom object metadata (such as gs://, s3:// or abfs://).',
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
      if (!_backend.storesCustomMetadata) {
        throw FsspecInputValidationError(
          'Saving file_data URI references requires a filesystem backend that'
          ' persists custom object metadata (such as gs://, s3:// or abfs://).',
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

    final List<int> versions = await _versionsUnder(artifactPath);
    int version = versions.isEmpty ? 0 : versions.last + 1;

    int attemptsLeft = _maxSaveVersionAttempts;
    while (true) {
      final String key = '$artifactPath/$version';
      try {
        await _backend.createObject(
          key,
          data,
          contentType: contentType,
          metadata: blobMetadata,
        );
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
    return _loadArtifact(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      filename: filename,
      version: version,
    );
  }

  Future<Part?> _loadArtifact({
    required String appName,
    required String userId,
    required String? sessionId,
    required String filename,
    required int? version,
    int maxDepth = _maxArtifactReferenceDepth,
  }) async {
    final String artifactPath = _artifactPath(
      appName,
      userId,
      sessionId,
      filename,
    );
    int resolvedVersion;
    if (version == null) {
      final List<int> versions = await _versionsUnder(artifactPath);
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

    final FsspecObjectMetadata? objectMetadata = await _backend.readMetadata(
      key,
    );
    if (objectMetadata == null) {
      return null;
    }

    final String? storedContentType = objectMetadata.contentType;
    final String? fileUri = objectMetadata.fileUri;
    if (fileUri != null) {
      if (fileUri.startsWith('artifact://')) {
        final _ParsedArtifactUri parsedUri = _resolveArtifactReference(
          fileUri: fileUri,
          appName: appName,
          userId: userId,
          sessionId: sessionId,
          remainingDepth: maxDepth,
        );
        return _loadArtifact(
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
        mimeType: objectMetadata.fileMimeType ?? storedContentType,
      );
    }

    List<int> data;
    try {
      data = await _fs.catFile(key);
    } catch (error) {
      if (_isMissingError(error)) {
        return null;
      }
      rethrow;
    }

    if (objectMetadata.isText) {
      return Part.text(utf8.decode(data, allowMalformed: false));
    }

    final Part loaded = Part.fromInlineData(
      data: data,
      mimeType: storedContentType ?? _guessMime(filename),
      displayName: objectMetadata.displayName,
    );
    if (_isRewindTombstone(loaded) ||
        (!_backend.storesCustomMetadata &&
            data.isEmpty &&
            storedContentType == null)) {
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
    return _listArtifactKeys(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  Future<List<String>> _listArtifactKeys({
    required String appName,
    required String userId,
    required String? sessionId,
  }) async {
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
      final Map<String, Map<String, Object?>> entries = await _findDetail(
        scope,
      );
      for (final String relPath in entries.keys) {
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
    await _deleteArtifact(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
      filename: filename,
    );
  }

  Future<void> _deleteArtifact({
    required String appName,
    required String userId,
    required String? sessionId,
    required String filename,
  }) async {
    final String artifactPath = _artifactPath(
      appName,
      userId,
      sessionId,
      filename,
    );
    for (final int version in await _versionsUnder(artifactPath)) {
      final String key = '$artifactPath/$version';
      try {
        await _fs.rmFile(key);
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

  Future<List<int>> _versionsUnder(String artifactPath) async {
    final List<int> versions = <int>[];
    final Map<String, Map<String, Object?>> entries = await _findDetail(
      artifactPath,
    );
    for (final String suffix in entries.keys) {
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
    FsspecObjectMetadata objectMetadata,
  ) {
    final String? storedContentType = objectMetadata.contentType;
    final bool hasFileUri = objectMetadata.fileUri != null;
    final String? mimeType = hasFileUri
        ? (objectMetadata.fileMimeType ?? storedContentType)
        : (storedContentType ?? _guessMime(filename));

    return ArtifactVersion(
      version: version,
      canonicalUri: _canonicalUri(key),
      createTime: objectMetadata.createTime,
      mimeType: mimeType,
      customMetadata: objectMetadata.userMetadata,
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
    final Map<String, Map<String, Object?>> versionEntries =
        <String, Map<String, Object?>>{};
    final Map<String, int> versionByKey = <String, int>{};
    final Map<String, Map<String, Object?>> entries = await _findDetail(
      artifactPath,
    );
    entries.forEach((
      String suffix,
      Map<String, Object?> info,
    ) {
      final int? version = suffix.contains('/') ? null : _parseVersion(suffix);
      if (version == null) {
        return;
      }
      final String key = '$artifactPath/$version';
      versionEntries[key] = info;
      versionByKey[key] = version;
    });
    final Map<String, FsspecObjectMetadata> metadataByKey = await _backend
        .readListingMetadata(versionEntries);
    final List<ArtifactVersion> artifactVersions = <ArtifactVersion>[];
    metadataByKey.forEach((String key, FsspecObjectMetadata objectMetadata) {
      final int? version = versionByKey[key];
      if (version != null) {
        artifactVersions.add(
          _buildArtifactVersion(version, key, filename, objectMetadata),
        );
      }
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
      final List<int> versions = await _versionsUnder(artifactPath);
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

    final FsspecObjectMetadata? objectMetadata = await _backend.readMetadata(
      key,
    );
    if (objectMetadata == null) {
      return null;
    }
    return _buildArtifactVersion(
      resolvedVersion,
      key,
      filename,
      objectMetadata,
    );
  }
}
