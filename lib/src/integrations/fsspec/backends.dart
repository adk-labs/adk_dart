/// Per-backend object creation and metadata reads for [FsspecArtifactService].
library;

import 'dart:io';

import 'fsspec_artifact_service.dart';

const String _defaultMimeType = 'application/octet-stream';
const Set<String> _gcsProtocols = <String>{'gs', 'gcs'};
const Set<String> _localProtocols = <String>{'file', 'local'};
const Set<String> _s3Protocols = <String>{'s3', 's3a'};
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

/// Exception representing an S3 HTTP 409 `ConditionalRequestConflict` error.
class S3ConditionalRequestConflictException extends FileSystemException {
  /// Creates an [S3ConditionalRequestConflictException] for [path].
  const S3ConditionalRequestConflictException(
    String path, [
    String message = 'ConditionalRequestConflict',
  ]) : super(message, path);
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

bool _isAscii(String value) {
  for (int i = 0; i < value.length; i += 1) {
    if (value.codeUnitAt(i) > 0x7F) {
      return false;
    }
  }
  return true;
}

/// Percent-encodes [value] for S3 metadata, leaving printable ASCII (`0x20..0x7E`)
/// except `%` untouched, matching Python's `urllib.parse.quote(value, safe=...)`.
String _s3EncodeMetadataValue(String value) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in value.runes) {
    if (rune >= 0x20 && rune <= 0x7E && rune != 0x25) {
      buffer.writeCharCode(rune);
    } else {
      final String encoded = Uri.encodeComponent(String.fromCharCode(rune));
      buffer.write(encoded);
    }
  }
  return buffer.toString();
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
    return GenericBackendAdapter(fs, clock: clock);
  }

  /// Reads and normalizes metadata for a single file object at [key].
  FsspecObjectMetadata? readMetadata(String key) {
    fs.invalidateCache(key);
    try {
      final Map<String, Object?> info = fs.info(key);
      if ((info['type'] ?? 'file') != 'file') {
        return null;
      }
      return fromInfo(key, info);
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

  /// Normalizes `find(detail: true)` entries, keyed by object path.
  Map<String, FsspecObjectMetadata> readListingMetadata(
    Map<String, Map<String, Object?>> entries,
  ) {
    return <String, FsspecObjectMetadata>{
      for (final MapEntry<String, Map<String, Object?>> entry
          in entries.entries)
        entry.key: fromInfo(entry.key, entry.value),
    };
  }

  /// Creates the version object [key], failing with [FsspecFileExistsException]
  /// if it already exists.
  void createObject(
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

  void _removeFailedVersion(String key) {
    try {
      fs.rmFile(key);
    } catch (_) {
      // Best-effort cleanup; preserve original write error for the caller.
    }
    fs.invalidateCache(key);
  }

  void _writeRapid(
    String key,
    List<int> data,
    String? contentType,
    Map<String, String> metadata,
  ) {
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
      fs.setxattrs(
        key,
        contentType: contentType ?? _defaultMimeType,
        metadata: metadata,
      );
    } catch (_) {
      _removeFailedVersion(key);
      rethrow;
    }
  }

  @override
  void createObject(
    String key,
    List<int> data, {
    String? contentType,
    Map<String, String> metadata = const <String, String>{},
  }) {
    if (_isRapidBucket(key)) {
      _writeRapid(key, data, contentType, metadata);
      return;
    }
    fs.pipeFile(
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
/// be ASCII. ADK's own metadata keys are mapped back on read and their values
/// are percent-encoded so they round-trip.
class S3BackendAdapter extends FsspecBackendAdapter {
  /// Creates an S3 backend adapter.
  S3BackendAdapter(super.fs, {super.clock});

  @override
  bool get storesCustomMetadata => true;

  @override
  FsspecObjectMetadata fromInfo(String key, Map<String, Object?> info) {
    final Map<String, Object?> rawMetadata = <String, Object?>{};
    final Map<String, String> s3Metadata = fs.metadata(key);
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
  Map<String, FsspecObjectMetadata> readListingMetadata(
    Map<String, Map<String, Object?>> entries,
  ) {
    final Map<String, FsspecObjectMetadata> result =
        <String, FsspecObjectMetadata>{};
    for (final String key in entries.keys) {
      final FsspecObjectMetadata? meta = readMetadata(key);
      if (meta != null) {
        result[key] = meta;
      }
    }
    return result;
  }

  @override
  void createObject(
    String key,
    List<int> data, {
    String? contentType,
    Map<String, String> metadata = const <String, String>{},
  }) {
    final Map<String, String> encoded = <String, String>{
      for (final MapEntry<String, String> entry in metadata.entries)
        entry.key: internalMetadataKeys.contains(entry.key)
            ? _s3EncodeMetadataValue(entry.value)
            : entry.value,
    };
    _validateMetadata(encoded);
    try {
      fs.pipeFile(
        key,
        data,
        mode: 'create',
        contentType: contentType,
        metadata: encoded.isEmpty ? null : encoded,
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

  static void _validateMetadata(Map<String, String> metadata) {
    for (final MapEntry<String, String> entry in metadata.entries) {
      if (!_isAscii(entry.key) || !_isAscii(entry.value)) {
        throw FsspecInputValidationError(
          "custom_metadata keys and values must be ASCII on S3, got "
          "'${entry.key}': '${entry.value}'.",
        );
      }
    }
    final Map<String, String> s3Keys = <String, String>{
      for (final String key in metadata.keys)
        key: key.toLowerCase().replaceAll('_', '-'),
    };
    final List<String> reserved =
        s3Keys.entries
            .where(
              (MapEntry<String, String> e) =>
                  !internalMetadataKeys.contains(e.key) &&
                  _s3InternalMetadataKeys.containsKey(e.value),
            )
            .map((MapEntry<String, String> e) => e.key)
            .toList()
          ..sort();
    if (reserved.isNotEmpty) {
      throw FsspecInputValidationError(
        'custom_metadata keys would read back as ADK keys on S3: '
        '${reserved.join(', ')}.',
      );
    }
    final Map<String, int> counts = <String, int>{};
    for (final String s3Key in s3Keys.values) {
      counts[s3Key] = (counts[s3Key] ?? 0) + 1;
    }
    final List<String> merged =
        s3Keys.entries
            .where((MapEntry<String, String> e) => (counts[e.value] ?? 0) > 1)
            .map((MapEntry<String, String> e) => e.key)
            .toList()
          ..sort();
    if (merged.isNotEmpty) {
      throw FsspecInputValidationError(
        'custom_metadata keys would read back as the same key on S3: '
        '${merged.join(', ')}.',
      );
    }
  }
}

/// Fallback adapter for backends without custom object metadata.
class GenericBackendAdapter extends FsspecBackendAdapter {
  /// Creates a generic backend adapter.
  GenericBackendAdapter(super.fs, {super.clock});

  @override
  void createObject(
    String key,
    List<int> data, {
    String? contentType,
    Map<String, String> metadata = const <String, String>{},
  }) {
    if (!fs.autoMkdir) {
      final int slash = key.lastIndexOf('/');
      if (slash > 0) {
        fs.makedirs(key.substring(0, slash), existOk: true);
      }
    }
    final Set<String> protocols = _adapterFsProtocols(fs).toSet();
    if (protocols.intersection(_localProtocols).isNotEmpty) {
      final FsspecWriteStream stream = fs.openWrite(key, mode: 'xb');
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
      fs.pipeFile(key, data, mode: 'create');
    }
  }
}
