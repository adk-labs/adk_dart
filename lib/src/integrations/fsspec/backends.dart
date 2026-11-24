/// Per-backend object creation and metadata reads for [FsspecArtifactService].
library;

import 'dart:async';
import 'dart:io';

import 'fsspec_artifact_service.dart';

const String _defaultMimeType = 'application/octet-stream';
const Set<String> _gcsProtocols = <String>{'gs', 'gcs'};
const Set<String> _localProtocols = <String>{'file', 'local'};
const Set<String> _s3Protocols = <String>{'s3', 's3a'};
const Set<String> _azureProtocols = <String>{'abfs', 'abfss', 'az'};
// Azure error codes that mean an exclusive create found an existing blob.
const Set<String> _azureConflictErrorCodes = <String>{
  'BlobAlreadyExists',
  'ConditionNotMet',
};
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

/// Custom-metadata key storing `InlineData.displayName`.
const String adkDisplayNameMetadataKey = 'adkDisplayName';

/// Custom-metadata key marking a `Part.text(...)` artifact.
const String adkIsTextMetadataKey = 'adkIsText';

/// Custom-metadata key storing `FileData.fileUri`.
const String adkFileUriMetadataKey = 'adkFileUri';

/// Custom-metadata key storing `FileData.mimeType`.
const String adkFileMimeTypeMetadataKey = 'adkFileMimeType';

/// Legacy file URI metadata key still read for backwards compatibility.
const String legacyFileUriMetadataKey = 'file_uri';

/// Object metadata keys reserved for ADK's own bookkeeping.
const Set<String> internalMetadataKeys = <String>{
  adkDisplayNameMetadataKey,
  adkIsTextMetadataKey,
  adkFileUriMetadataKey,
  adkFileMimeTypeMetadataKey,
  legacyFileUriMetadataKey,
};

/// Maps ADK's internal keys as `s3fs` returns them (lowercased, `_` as `-`)
/// back to their canonical ADK names.
final Map<String, String> _s3InternalMetadataKeys = <String, String>{
  for (final String key in internalMetadataKeys)
    key.toLowerCase().replaceAll('_', '-'): key,
};

/// Azure ignores case in metadata keys. Maps ADK's keys, lowercased, back.
final Map<String, String> _azureInternalMetadataKeys = <String, String>{
  for (final String key in internalMetadataKeys) key.toLowerCase(): key,
};

/// Metadata keys `adlfs` uses to tell files from directories.
const Set<String> _adlfsDirectoryMetadataKeys = <String>{
  'is_directory',
  'hdi_isfolder',
};

/// Lowercased keys caller metadata may not use on Azure, mapped to their owner.
final Map<String, String> _azureReservedMetadataKeys = <String, String>{
  for (final String key in _adlfsDirectoryMetadataKeys) key: key,
  ..._azureInternalMetadataKeys,
};

/// Azure metadata keys must be C# identifiers.
final RegExp _azureMetadataKeyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// S3 metadata keys are HTTP header names (RFC 9110 tokens).
final RegExp _httpTokenPattern = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");

/// Metadata values the stores keep as given: printable ASCII without spaces at
/// either end, which stores and clients trim from header values.
final RegExp _metadataValuePattern = RegExp(r'^(?:[!-~](?:[ -~]*[!-~])?)?$');

/// Exception representing an S3 HTTP 409 `ConditionalRequestConflict` error.
class S3ConditionalRequestConflictException extends FileSystemException {
  /// Creates an [S3ConditionalRequestConflictException] for [path].
  const S3ConditionalRequestConflictException(
    String path, [
    String message = 'ConditionalRequestConflict',
  ]) : super(message, path);
}

/// Exception carrying an Azure Storage error code (for example
/// `'BlobAlreadyExists'` or `'ConditionNotMet'`).
class AzureStorageException implements Exception {
  /// Creates an [AzureStorageException].
  const AzureStorageException(
    this.errorCode, [
    this.message = 'Azure storage error',
    this.cause,
  ]);

  /// Azure error code (e.g. `'BlobAlreadyExists'`, `'ConditionNotMet'`).
  final String errorCode;

  /// Human-readable error message.
  final String message;

  /// Optional underlying cause.
  final Object? cause;

  @override
  String toString() => 'AzureStorageException($errorCode): $message';
}

/// Exception wrapping an underlying Azure error (mirroring Python's
/// `RuntimeError(...) from cause` raised by `adlfs`).
class AzureRuntimeException implements Exception {
  /// Creates an [AzureRuntimeException].
  const AzureRuntimeException(this.message, {this.cause});

  /// Human-readable error message.
  final String message;

  /// Optional underlying cause (such as an [AzureStorageException]).
  final Object? cause;

  @override
  String toString() => 'AzureRuntimeException: $message';
}

/// Exception thrown when an fsspec backend library version is too old or
/// missing required support (mirrors Python's `ImportError`).
class FsspecImportError extends UnsupportedError {
  /// Creates an [FsspecImportError] with [message].
  FsspecImportError(super.message);

  @override
  String toString() => 'ImportError: $message';
}

/// Returns only caller-supplied metadata keys, hiding ADK internal markers.
Map<String, Object?> filterUserMetadata(Map<String, Object?>? rawMetadata) {
  if (rawMetadata == null || rawMetadata.isEmpty) {
    return <String, Object?>{};
  }
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in rawMetadata.entries)
      if (!internalMetadataKeys.contains(entry.key)) entry.key: entry.value,
  };
}

List<String> _adapterFsProtocols(FilesystemProtocol fs) {
  final Object? proto = fs.protocol;
  if (proto is String) {
    return <String>[proto];
  }
  if (proto is Iterable) {
    return proto
        .whereType<String>()
        .where((String p) => p.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

double _parseAdapterTimestamp(
  Map<String, Object?> info, {
  double Function()? clock,
}) {
  const List<String> fields = <String>[
    'timeCreated',
    'created',
    'creation_time',
    'mtime',
    'LastModified',
    'updated',
  ];
  for (final String field in fields) {
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
      : DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0;
}

bool _isAdapterMissingError(Object error) {
  if (error is PathNotFoundException) {
    return true;
  }
  if (error is FileSystemException) {
    final int? code = error.osError?.errorCode;
    if (code == 2 || code == 20) {
      return true;
    }
    final String msg = error.message.toLowerCase();
    if (msg.contains('not found') ||
        msg.contains('no such file') ||
        msg.contains('not a directory')) {
      return true;
    }
  }
  return false;
}

/// Percent-encodes [value] for ASCII-only metadata stores (S3, Azure), leaving
/// printable ASCII (`0x21..0x7E`) except `%` untouched. Spaces (`0x20`) are
/// percent-encoded because stores trim them from header values.
String _encodeAsciiMetadataValue(String value) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in value.runes) {
    if (rune >= 0x21 && rune <= 0x7E && rune != 0x25) {
      buffer.writeCharCode(rune);
    } else {
      final String encoded = Uri.encodeComponent(String.fromCharCode(rune));
      buffer.write(encoded);
    }
  }
  return buffer.toString();
}

/// Returns [metadata] encoded and validated for stores that only keep ASCII
/// metadata (S3, Azure).
///
/// ADK's own values, such as display names and file URIs, are percent-encoded
/// so they round-trip. Caller metadata that the store would reject or change is
/// rejected with [FsspecInputValidationError].
Map<String, String> _encodeAsciiMetadata(
  Map<String, String> metadata, {
  required String store,
  required String keyRule,
  required bool Function(String key) isValidKey,
  required String Function(String key) storeKey,
  required Map<String, String> reserved,
}) {
  final Map<String, String> encoded = <String, String>{};
  // Store-form keys of caller metadata seen so far, mapped to the caller key.
  final Map<String, String> seen = <String, String>{};
  for (final MapEntry<String, String> entry in metadata.entries) {
    final String key = entry.key;
    final String value = entry.value;
    if (internalMetadataKeys.contains(key)) {
      encoded[key] = _encodeAsciiMetadataValue(value);
      continue;
    }
    if (!isValidKey(key) || !_metadataValuePattern.hasMatch(value)) {
      throw FsspecInputValidationError(
        'custom_metadata on $store needs $keyRule keys and printable ASCII '
        "values without spaces at either end, got '$key': '$value'.",
      );
    }
    final String storedAs = storeKey(key);
    final String? owner = reserved[storedAs] ?? seen[storedAs];
    if (owner != null) {
      throw FsspecInputValidationError(
        "custom_metadata key '$key' is stored on $store as the same key as "
        "'$owner'.",
      );
    }
    seen[storedAs] = key;
    encoded[key] = value;
  }
  return encoded;
}

bool _isAdlfsVersionOlderThan2026_8_0(String? version) {
  if (version == null || version.isEmpty) {
    return false;
  }
  final RegExpMatch? match = RegExp(
    r'^(\d+)\.(\d+)(?:\.(\d+))?(?:[a-zA-Z0-9.+_-]*)?$',
  ).firstMatch(version.trim());
  if (match == null) {
    return false;
  }
  final int major = int.parse(match.group(1)!);
  final int minor = int.parse(match.group(2)!);
  final int patch = match.group(3) != null ? int.parse(match.group(3)!) : 0;
  if (major != 2026) {
    return major < 2026;
  }
  if (minor != 8) {
    return minor < 8;
  }
  return patch < 0;
}

/// Normalized storage metadata for a single stored artifact version.
class FsspecObjectMetadata {
  /// Creates normalized object metadata.
  FsspecObjectMetadata({
    required Map<String, Object?> rawMetadata,
    required this.contentType,
    required this.createTime,
  }) : rawMetadata = Map<String, Object?>.unmodifiable(rawMetadata);

  /// Raw key/value metadata attached to the object, including ADK bookkeeping keys.
  final Map<String, Object?> rawMetadata;

  /// The object's declared MIME type, if the backend reports one.
  final String? contentType;

  /// Unix timestamp (seconds) when the object was created.
  final double createTime;

  String? _getReserved(String key) {
    final Object? value = rawMetadata[key];
    return value != null ? '$value' : null;
  }

  /// External or artifact reference URI stored on the object.
  String? get fileUri {
    final String? primary = _getReserved(adkFileUriMetadataKey);
    if (primary != null && primary.isNotEmpty) {
      return primary;
    }
    final String? legacy = _getReserved(legacyFileUriMetadataKey);
    return (legacy != null && legacy.isNotEmpty) ? legacy : null;
  }

  /// Returns `true` if the object was saved from a `Part.text(...)`.
  bool get isText => _getReserved(adkIsTextMetadataKey) == 'true';

  /// Returns the `InlineData.displayName` recorded on the object, if any.
  String? get displayName {
    final String? value = _getReserved(adkDisplayNameMetadataKey);
    return (value != null && value.isNotEmpty) ? value : null;
  }

  /// Returns the `FileData.mimeType` recorded on the object, if any.
  String? get fileMimeType {
    final String? value = _getReserved(adkFileMimeTypeMetadataKey);
    return (value != null && value.isNotEmpty) ? value : null;
  }

  /// Returns caller-supplied metadata with ADK bookkeeping keys removed.
  Map<String, Object?> get userMetadata => filterUserMetadata(rawMetadata);
}

/// Creates version objects and reads their metadata for one fsspec backend.
abstract class FsspecBackendAdapter {
  /// Creates a backend adapter for [fs].
  FsspecBackendAdapter(this.fs, {double Function()? clock}) : _clock = clock;

  /// Underlying fsspec filesystem.
  final FilesystemProtocol fs;

  final double Function()? _clock;

  /// Whether [createObject] persists content type and custom object metadata.
  bool get storesCustomMetadata => false;

  /// Returns the backend adapter matching [fs]'s protocol.
  static FsspecBackendAdapter forFilesystem(
    FilesystemProtocol fs, {
    double Function()? clock,
  }) {
    final Set<String> protocols = _adapterFsProtocols(fs).toSet();
    if (protocols.intersection(_gcsProtocols).isNotEmpty) {
      return GcsBackendAdapter(fs, clock: clock);
    }
    if (protocols.intersection(_s3Protocols).isNotEmpty) {
      return S3BackendAdapter(fs, clock: clock);
    }
    if (protocols.intersection(_azureProtocols).isNotEmpty) {
      return AzureBackendAdapter(fs, clock: clock);
    }
    return GenericBackendAdapter(fs, clock: clock);
  }

  /// Reads and normalizes metadata for a single file object at [key].
  Future<FsspecObjectMetadata?> readMetadata(String key) async {
    fs.invalidateCache(key);
    try {
      final Map<String, Object?> info = await fs.info(key);
      if ((info['type'] ?? 'file') != 'file') {
        return null;
      }
      return await fromInfoAsync(key, info);
    } catch (error) {
      if (_isAdapterMissingError(error)) {
        return null;
      }
      rethrow;
    }
  }

  /// Normalizes an `info()` / `find(detail: true)` map for [key].
  FsspecObjectMetadata fromInfo(String key, Map<String, Object?> info) {
    final Object? rawMeta = info['metadata'];
    final Map<String, Object?> metadataMap = rawMeta is Map
        ? <String, Object?>{
            for (final MapEntry<Object?, Object?> entry in rawMeta.entries)
              if (entry.key != null) '${entry.key}': entry.value,
          }
        : <String, Object?>{};
    final Object? rawContentType = info['contentType'] ?? info['ContentType'];
    final String? contentType =
        (rawContentType is String && rawContentType.isNotEmpty)
        ? rawContentType
        : null;
    return FsspecObjectMetadata(
      rawMetadata: metadataMap,
      contentType: contentType,
      createTime: _parseAdapterTimestamp(info, clock: _clock),
    );
  }

  /// Asynchronously normalizes an `info()` / `find(detail: true)` map for
  /// [key]. Defaults to [fromInfo].
  Future<FsspecObjectMetadata> fromInfoAsync(
    String key,
    Map<String, Object?> info,
  ) async {
    return fromInfo(key, info);
  }

  /// Returns `find(detail: true)` entries for objects under [prefix].
  Future<Object> findDetail(String prefix) async {
    return await fs.find(prefix, detail: true);
  }

  /// Normalizes `find(detail: true)` entries, keyed by object path.
  Future<Map<String, FsspecObjectMetadata>> readListingMetadata(
    Map<String, Map<String, Object?>> entries,
  ) async {
    final Map<String, FsspecObjectMetadata> result =
        <String, FsspecObjectMetadata>{};
    for (final MapEntry<String, Map<String, Object?>> entry
        in entries.entries) {
      result[entry.key] = await fromInfoAsync(entry.key, entry.value);
    }
    return result;
  }

  /// Creates the version object [key], failing with [FsspecFileExistsException]
  /// if it already exists.
  Future<void> createObject(
    String key,
    List<int> data, {
    String? contentType,
    Map<String, String> metadata = const <String, String>{},
  });
}

/// Reads and writes object metadata on Google Cloud Storage (`gcsfs`).
class GcsBackendAdapter extends FsspecBackendAdapter {
  /// Creates a GCS backend adapter.
  GcsBackendAdapter(super.fs, {super.clock});

  @override
  bool get storesCustomMetadata => true;

  bool _isRapidBucket(String key) {
    final (String, String, Object?)? parts = fs.splitPath(key);
    if (parts == null) {
      return false;
    }
    final String? bucketType = fs.syncLookupBucketType(parts.$1);
    return bucketType != null && bucketType.endsWith('ZONAL_HIERARCHICAL');
  }

  Future<void> _removeFailedVersion(String key) async {
    try {
      await fs.rmFile(key);
    } catch (_) {
      // Best-effort cleanup; preserve original write error for the caller.
    }
    fs.invalidateCache(key);
  }

  Future<void> _writeRapid(
    String key,
    List<int> data,
    String? contentType,
    Map<String, String> metadata,
  ) async {
    final List<String> reserved =
        metadata.keys.where(_rapidSetxattrsReservedKeys.contains).toList()
          ..sort();
    if (reserved.isNotEmpty) {
      throw FsspecInputValidationError(
        'custom_metadata keys are not supported on Rapid GCS buckets: '
        '${reserved.join(', ')}.',
      );
    }
    final FsspecWriteStream stream = fs.openWrite(
      key,
      mode: 'wb',
      generation: 0,
      finalizeOnClose: true,
    );
    try {
      if (data.isNotEmpty) {
        stream.write(data);
      }
      await stream.close();
    } catch (exc) {
      stream.closed = true;
      final String excName = exc.runtimeType.toString();
      if (exc is GcsPreconditionError ||
          _rapidPreconditionErrorNames.contains(excName)) {
        throw FsspecFileExistsException(key, cause: exc);
      }
      if (stream.aaow != null) {
        await _removeFailedVersion(key);
      }
      rethrow;
    }
    try {
      await fs.setxattrs(
        key,
        contentType: contentType ?? _defaultMimeType,
        metadata: metadata,
      );
    } catch (_) {
      await _removeFailedVersion(key);
      rethrow;
    }
  }

  @override
  Future<void> createObject(
    String key,
    List<int> data, {
    String? contentType,
    Map<String, String> metadata = const <String, String>{},
  }) async {
    if (_isRapidBucket(key)) {
      await _writeRapid(key, data, contentType, metadata);
      return;
    }
    await fs.pipeFile(
      key,
      data,
      mode: 'create',
      contentType: contentType,
      metadata: metadata.isEmpty ? null : Map<String, String>.from(metadata),
    );
  }
}

/// Reads and writes object metadata on Amazon S3 (`s3fs`).
///
/// S3 metadata keys are lowercased with `_` converted to `-`, and values must
/// be printable ASCII without spaces at either end. ADK's own metadata keys
/// are mapped back on read and their values are percent-encoded so they
/// round-trip. Caller keys must be HTTP header names (RFC 9110 tokens), and
/// caller keys that would read back as ADK's own keys or as each other are
/// rejected.
class S3BackendAdapter extends FsspecBackendAdapter {
  /// Creates an S3 backend adapter.
  S3BackendAdapter(super.fs, {super.clock});

  @override
  bool get storesCustomMetadata => true;

  FsspecObjectMetadata _buildMetadata(
    Map<String, String> s3Metadata,
    Map<String, Object?> info,
  ) {
    final Map<String, Object?> rawMetadata = <String, Object?>{};
    s3Metadata.forEach((String s3Key, String value) {
      final String name = _s3InternalMetadataKeys[s3Key] ?? s3Key;
      final String decoded = internalMetadataKeys.contains(name)
          ? Uri.decodeComponent(value)
          : value;
      rawMetadata[name] = decoded;
    });
    final Object? rawContentType = info['ContentType'] ?? info['contentType'];
    final String? contentType =
        (rawContentType is String && rawContentType.isNotEmpty)
        ? rawContentType
        : null;
    return FsspecObjectMetadata(
      rawMetadata: rawMetadata,
      contentType: contentType,
      createTime: _parseAdapterTimestamp(info, clock: _clock),
    );
  }

  @override
  FsspecObjectMetadata fromInfo(String key, Map<String, Object?> info) {
    final FutureOr<Map<String, String>> rawS3Metadata = fs.metadata(key);
    if (rawS3Metadata is Future<Map<String, String>>) {
      throw StateError(
        'S3BackendAdapter.fromInfo called synchronously on an async '
        'FilesystemProtocol; use fromInfoAsync instead.',
      );
    }
    return _buildMetadata(rawS3Metadata, info);
  }

  @override
  Future<FsspecObjectMetadata> fromInfoAsync(
    String key,
    Map<String, Object?> info,
  ) async {
    final Map<String, String> s3Metadata = await fs.metadata(key);
    return _buildMetadata(s3Metadata, info);
  }

  @override
  Future<Map<String, FsspecObjectMetadata>> readListingMetadata(
    Map<String, Map<String, Object?>> entries,
  ) async {
    final Map<String, FsspecObjectMetadata> result =
        <String, FsspecObjectMetadata>{};
    for (final String key in entries.keys) {
      final FsspecObjectMetadata? meta = await readMetadata(key);
      if (meta != null) {
        result[key] = meta;
      }
    }
    return result;
  }

  @override
  Future<void> createObject(
    String key,
    List<int> data, {
    String? contentType,
    Map<String, String> metadata = const <String, String>{},
  }) async {
    final Map<String, String>? encoded = metadata.isEmpty
        ? null
        : _encodeAsciiMetadata(
            metadata,
            store: 'S3',
            keyRule: 'HTTP header name',
            isValidKey: _httpTokenPattern.hasMatch,
            storeKey: (String k) => k.toLowerCase().replaceAll('_', '-'),
            reserved: _s3InternalMetadataKeys,
          );
    // S3 would default to binary/octet-stream. Match GCS and Azure.
    final String effectiveContentType =
        (contentType != null && contentType.isNotEmpty)
        ? contentType
        : _defaultMimeType;
    try {
      await fs.pipeFile(
        key,
        data,
        mode: 'create',
        contentType: effectiveContentType,
        metadata: encoded,
      );
    } on S3ConditionalRequestConflictException catch (exc) {
      throw FsspecFileExistsException(key, cause: exc);
    } on FileSystemException catch (exc) {
      if (exc.message.contains('ConditionalRequestConflict')) {
        throw FsspecFileExistsException(key, cause: exc);
      }
      rethrow;
    }
  }
}

/// Reads and writes object metadata on Azure Blob Storage (`adlfs`).
///
/// `adlfs` returns `metadata`, `content_settings`, and `creation_time` in both
/// `info()` and listings. Its `pipe_file` cannot take metadata, so objects are
/// created with `openWrite(key, mode: 'xb', metadata: ..., contentSettings: ...)`
/// which commits with `If-None-Match: *`. This needs `adlfs` 2026.8.0 or newer;
/// older versions drop `content_settings`, so saving with them is rejected.
/// `adlfs` treats a blob with a size as a file, so its `is_directory` marker is
/// not written and is hidden on read.
///
/// Azure metadata must be ASCII, and keys must be C# identifiers compared
/// without case. ADK's own values (such as display names and file URIs) are
/// percent-encoded so they round-trip. Caller metadata is rejected if a key is
/// not a C# identifier, a value is not printable ASCII or has spaces at either
/// end, or a key matches ADK's or `adlfs`'s own keys or another caller key
/// ignoring case.
class AzureBackendAdapter extends FsspecBackendAdapter {
  /// Creates an Azure backend adapter.
  AzureBackendAdapter(super.fs, {super.clock, String? adlfsVersion})
    : _dropsContentType = _isAdlfsVersionOlderThan2026_8_0(
        adlfsVersion ?? fs.backendVersion,
      );

  final bool _dropsContentType;

  @override
  bool get storesCustomMetadata => true;

  @override
  Future<FsspecObjectMetadata?> readMetadata(String key) async {
    // adlfs invalidateCache(key) keeps a cached parent listing, which info()
    // would trust and report key as missing.
    fs.invalidateCache(fs.parent(key));
    return super.readMetadata(key);
  }

  @override
  Future<Object> findDetail(String prefix) async {
    // adlfs find(path) returns [path] when path is itself a blob, which a flat
    // namespace allows next to blobs below it (a/0 and a/0/0). Listing from
    // the container with prefix= skips that check.
    final int slash = prefix.indexOf('/');
    final String container = slash >= 0 ? prefix.substring(0, slash) : prefix;
    final String path = slash >= 0 ? prefix.substring(slash + 1) : '';
    return await fs.find(container, prefix: path, detail: true);
  }

  @override
  FsspecObjectMetadata fromInfo(String key, Map<String, Object?> info) {
    final Map<String, Object?> rawMetadata = <String, Object?>{};
    final Object? rawMeta = info['metadata'];
    if (rawMeta is Map) {
      rawMeta.forEach((Object? rawName, Object? rawValue) {
        if (rawName == null) {
          return;
        }
        final String origName = '$rawName';
        final String lower = origName.toLowerCase();
        if (_adlfsDirectoryMetadataKeys.contains(lower)) {
          return;
        }
        final String name = _azureInternalMetadataKeys[lower] ?? origName;
        Object? value = rawValue;
        if (internalMetadataKeys.contains(name) && value != null) {
          value = Uri.decodeComponent('$value');
        }
        rawMetadata[name] = value;
      });
    }
    String? contentType;
    final Object? contentSettings = info['content_settings'];
    if (contentSettings is Map) {
      final Object? ct = contentSettings['content_type'];
      if (ct is String && ct.isNotEmpty) {
        contentType = ct;
      }
    }
    return FsspecObjectMetadata(
      rawMetadata: rawMetadata,
      contentType: contentType,
      createTime: _parseAdapterTimestamp(info, clock: _clock),
    );
  }

  static bool _isAzureConflict(Object error) {
    if (error is AzureStorageException) {
      return _azureConflictErrorCodes.contains(error.errorCode);
    }
    return false;
  }

  static Object? _errorCause(Object error) {
    if (error is AzureRuntimeException) {
      return error.cause;
    }
    if (error is AzureStorageException) {
      return error.cause;
    }
    if (error is FsspecFileExistsException) {
      return error.cause;
    }
    return null;
  }

  @override
  Future<void> createObject(
    String key,
    List<int> data, {
    String? contentType,
    Map<String, String> metadata = const <String, String>{},
  }) async {
    if (_dropsContentType) {
      throw FsspecImportError(
        'Saving artifacts on Azure needs adlfs 2026.8.0 or newer. Upgrade it '
        'with `pip install -U adlfs`.',
      );
    }
    final Map<String, String> encoded = _encodeAsciiMetadata(
      metadata,
      store: 'Azure',
      keyRule: 'C# identifier',
      isValidKey: _azureMetadataKeyPattern.hasMatch,
      storeKey: (String k) => k.toLowerCase(),
      reserved: _azureReservedMetadataKeys,
    );
    final Map<String, Object?>? contentSettings = contentType != null
        ? <String, Object?>{'content_type': contentType}
        : null;
    final FsspecWriteStream stream = fs.openWrite(
      key,
      mode: 'xb',
      metadata: encoded,
      contentSettings: contentSettings,
    );
    try {
      stream.write(data);
      await stream.close();
    } catch (exc) {
      // Keep finalizers from calling close() and committing a failed write.
      stream.closed = true;
      // adlfs maps a conflicting commit to FileExistsError. Azure errors still
      // come through raw from its fallback upload of empty payloads, or wrapped
      // in RuntimeError, such as a 412.
      final Object? cause = _errorCause(exc);
      if (_isAzureConflict(exc) || (cause != null && _isAzureConflict(cause))) {
        throw FsspecFileExistsException(key, cause: exc);
      }
      rethrow;
    }
  }
}

/// Fallback adapter for backends without custom object metadata.
class GenericBackendAdapter extends FsspecBackendAdapter {
  /// Creates a generic backend adapter.
  GenericBackendAdapter(super.fs, {super.clock});

  @override
  Future<void> createObject(
    String key,
    List<int> data, {
    String? contentType,
    Map<String, String> metadata = const <String, String>{},
  }) async {
    if (!fs.autoMkdir) {
      final int slash = key.lastIndexOf('/');
      if (slash > 0) {
        await fs.makedirs(key.substring(0, slash), existOk: true);
      }
    }
    final Set<String> protocols = _adapterFsProtocols(fs).toSet();
    if (protocols.intersection(_localProtocols).isNotEmpty) {
      final FsspecWriteStream stream = fs.openWrite(key, mode: 'xb');
      try {
        if (data.isNotEmpty) {
          stream.write(data);
        }
        await stream.close();
      } catch (_) {
        await stream.close();
        rethrow;
      }
    } else {
      await fs.pipeFile(key, data, mode: 'create');
    }
  }
}
