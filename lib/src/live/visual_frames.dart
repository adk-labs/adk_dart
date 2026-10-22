/// Packs and unpacks live visual frame sequences as a single ZIP artifact.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../types/content.dart';

/// Archive format version written to and required in `metadata.json`.
const int _formatVersion = 1;

/// Default MIME type assumed when a frame blob does not declare one.
const String _defaultMimeType = 'image/jpeg';

/// Name of the manifest member at the root of the archive.
const String _metadataFilename = 'metadata.json';

/// Name of the archive directory holding the frame members.
const String _framesDirectory = 'frames';

/// General-purpose flag bits that make a ZIP member unreadable (encrypted or
/// compressed patched data).
const int _unreadableFlagBits = 0x1 | 0x20 | 0x40;

/// MIME type of the packed visual frames archive stored in the artifact service.
const String visualFramesZipMimeType = 'application/zip';

const Map<String, String> _mimeToExtension = <String, String>{
  'image/jpeg': 'jpeg',
  'image/jpg': 'jpeg',
  'image/jpe': 'jpeg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/bmp': 'bmp',
  'image/tiff': 'tiff',
  'image/svg+xml': 'svg',
  'image/avif': 'avif',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'image/x-icon': 'ico',
  'image/vnd.microsoft.icon': 'ico',
  'video/mp4': 'mp4',
  'video/webm': 'webm',
  'video/quicktime': 'mov',
  'video/x-msvideo': 'avi',
  'video/mpeg': 'mpeg',
  'video/ogg': 'ogv',
};

/// A single visual frame and the wall-clock time it was received.
///
/// ```dart
/// final frame = VisualFrame(
///   blob: InlineData(mimeType: 'image/jpeg', data: [0xFF, 0xD8, 0xFF]),
///   timestamp: 100.0,
/// );
/// final (archiveBytes, metadata) = packVisualFrames([frame]);
/// ```
class VisualFrame {
  /// Creates a visual frame from either a [blob] and [timestamp] (in seconds
  /// since the Unix epoch) or from [data], [mimeType], and [timestampMs].
  ///
  /// Throws an [ArgumentError] if [timestamp] is NaN or infinite.
  VisualFrame({
    InlineData? blob,
    double? timestamp,
    int? timestampMs,
    String? mimeType,
    List<int>? data,
  }) : blob =
           blob ??
           InlineData(
             mimeType: mimeType ?? _defaultMimeType,
             data: data == null ? const <int>[] : Uint8List.fromList(data),
           ),
       timestamp = _resolveTimestamp(timestamp, timestampMs);

  static double _resolveTimestamp(double? timestamp, int? timestampMs) {
    final double resolved =
        timestamp ??
        (timestampMs != null
            ? timestampMs / 1000.0
            : throw ArgumentError(
                'Either timestamp or timestampMs must be provided.',
              ));
    if (resolved.isNaN || resolved.isInfinite) {
      throw ArgumentError.value(
        resolved,
        'timestamp',
        'VisualFrame timestamp must be a finite number.',
      );
    }
    return resolved;
  }

  /// The frame payload containing its bytes and MIME type.
  final InlineData blob;

  /// Wall-clock time the frame was received, in seconds since the Unix epoch.
  final double timestamp;

  /// Wall-clock time the frame was received, rounded to whole milliseconds.
  int get timestampMs => (timestamp * 1000).round();

  /// MIME type of the frame payload.
  String get mimeType => blob.mimeType;

  /// Raw byte data of the frame payload.
  Uint8List get data => blob.data is Uint8List
      ? blob.data as Uint8List
      : Uint8List.fromList(blob.data);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! VisualFrame) {
      return false;
    }
    if (timestamp != other.timestamp || blob.mimeType != other.blob.mimeType) {
      return false;
    }
    final List<int> a = blob.data;
    final List<int> b = other.blob.data;
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(timestamp, blob.mimeType, Object.hashAll(blob.data));
}

String _extensionForMimeType(String? mimeType) {
  final String rawMime =
      (mimeType == null || mimeType.isEmpty ? _defaultMimeType : mimeType)
          .split(';')
          .first
          .trim()
          .toLowerCase();
  final String? ext = _mimeToExtension[rawMime];
  if (ext == null || ext.isEmpty || ext == 'jpg' || ext == 'jpe') {
    return 'jpeg';
  }
  return ext;
}

String _frameMemberName(int index, String? mimeType) {
  final String extension = _extensionForMimeType(mimeType);
  final String padded = index.toString().padLeft(4, '0');
  return '$_framesDirectory/frame_$padded.$extension';
}

Map<String, Object?> _buildManifest(
  List<VisualFrame> frames,
  List<Uint8List> payloads,
) {
  final List<int> timestampsMs = <int>[
    for (final VisualFrame frame in frames) (frame.timestamp * 1000).round(),
  ];
  final int startMs = timestampsMs.first;
  final int endMs = timestampsMs.last;
  final int durationMs = endMs - startMs;
  final int frameCount = frames.length;
  final double estimatedFps = durationMs > 0
      ? (((frameCount - 1) * 1000 / durationMs) * 100).roundToDouble() / 100.0
      : 0.0;

  final List<Map<String, Object?>> frameEntries = <Map<String, Object?>>[];
  for (int index = 0; index < frames.length; index += 1) {
    final VisualFrame frame = frames[index];
    final Uint8List data = payloads[index];
    final int timestampMs = timestampsMs[index];
    final String rawMime = frame.blob.mimeType;
    final String mimeType = (rawMime.isEmpty ? _defaultMimeType : rawMime)
        .toLowerCase();
    frameEntries.add(<String, Object?>{
      'frameIndex': index,
      'offsetMs': timestampMs - startMs,
      'fileName': _frameMemberName(index, mimeType),
      'mimeType': mimeType,
      'sizeBytes': data.length,
    });
  }

  return <String, Object?>{
    'formatVersion': _formatVersion,
    'type': 'video_frame_sequence',
    'frameCount': frameCount,
    'startTimestampMs': startMs,
    'endTimestampMs': endMs,
    'durationMs': durationMs,
    'estimatedFps': estimatedFps,
    'frames': frameEntries,
  };
}

/// Packs [frames] and their manifest into one uncompressed (`ZIP_STORED`) ZIP
/// archive.
///
/// Returns a record of `(archiveBytes, artifactMetadata)` where
/// `artifactMetadata` is the archive's manifest without the per-frame `frames`
/// list.
///
/// Throws an [ArgumentError] if [frames] is empty, any frame carries empty
/// byte data, or frame timestamps decrease.
(Uint8List, Map<String, Object?>) packVisualFrames(List<VisualFrame> frames) {
  if (frames.isEmpty) {
    throw ArgumentError('Cannot pack an empty frame list.');
  }

  final List<Uint8List> payloads = <Uint8List>[];
  double previousTimestamp = frames.first.timestamp;
  for (int index = 0; index < frames.length; index += 1) {
    final VisualFrame frame = frames[index];
    if (frame.blob.data.isEmpty) {
      throw ArgumentError('Frame $index must contain non-empty byte data.');
    }
    if (frame.timestamp < previousTimestamp) {
      throw ArgumentError(
        'Frame timestamps must be non-decreasing '
        '(frame $index at ${frame.timestamp} < $previousTimestamp).',
      );
    }
    previousTimestamp = frame.timestamp;
    payloads.add(
      frame.blob.data is Uint8List
          ? frame.blob.data as Uint8List
          : Uint8List.fromList(frame.blob.data),
    );
  }

  final Map<String, Object?> manifest = _buildManifest(frames, payloads);
  final List<Map<String, Object?>> entries =
      manifest['frames']! as List<Map<String, Object?>>;

  final List<({String name, Uint8List data})> zipEntries =
      <({String name, Uint8List data})>[
        for (int i = 0; i < entries.length; i += 1)
          (name: entries[i]['fileName']! as String, data: payloads[i]),
        (
          name: _metadataFilename,
          data: Uint8List.fromList(
            utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
          ),
        ),
      ];

  final Uint8List archiveBytes = _writeStoredZip(zipEntries);
  final Map<String, Object?> artifactMetadata = <String, Object?>{
    for (final MapEntry<String, Object?> entry in manifest.entries)
      if (entry.key != 'frames') entry.key: entry.value,
  };
  return (archiveBytes, artifactMetadata);
}

/// Restores the frames and manifest from a packed [archiveBytes] ZIP archive.
///
/// Throws an [ArgumentError] if [archiveBytes] is not a valid ZIP archive, has
/// a compressed, encrypted, or corrupt member, or has a missing or invalid
/// `metadata.json` manifest.
(List<VisualFrame>, Map<String, Object?>) unpackVisualFrames(
  List<int> archiveBytes,
) {
  final Uint8List bytes = archiveBytes is Uint8List
      ? archiveBytes
      : Uint8List.fromList(archiveBytes);
  final Map<String, Uint8List> members = _readStoredZip(bytes);
  final Set<String> memberNames = members.keys.toSet();
  final Map<String, Object?> manifest = _readArchiveManifest(
    members,
    memberNames,
  );
  final num startTimestampMs = (manifest['startTimestampMs'] as num?) ?? 0;
  final Set<String> readMembers = <String>{};
  final List<Object?> rawEntries =
      (manifest['frames'] as List<Object?>?) ?? const <Object?>[];
  final List<VisualFrame> frames = <VisualFrame>[
    for (final Object? entry in rawEntries)
      _readFrameEntry(
        members,
        memberNames,
        entry,
        startTimestampMs.toDouble(),
        readMembers,
      ),
  ];
  return (frames, manifest);
}

Map<String, Object?> _readArchiveManifest(
  Map<String, Uint8List> members,
  Set<String> memberNames,
) {
  if (!memberNames.contains(_metadataFilename)) {
    throw ArgumentError('Visual frame archive is missing $_metadataFilename.');
  }
  final Object? decoded;
  try {
    final String jsonText = utf8.decode(
      members[_metadataFilename]!,
      allowMalformed: false,
    );
    decoded = jsonDecode(jsonText);
  } on FormatException catch (exc) {
    throw ArgumentError('$_metadataFilename is not valid JSON: $exc');
  }
  if (decoded is! Map) {
    throw ArgumentError('$_metadataFilename must contain a JSON object.');
  }
  final Map<String, Object?> manifest = <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in decoded.entries)
      '${entry.key}': entry.value,
  };
  final Object? formatVersion = manifest['formatVersion'];
  if (formatVersion is! int || formatVersion != _formatVersion) {
    throw ArgumentError(
      'Unsupported visual frame archive format version $formatVersion; '
      'this reader supports $_formatVersion.',
    );
  }
  final Object? entries = manifest.containsKey('frames')
      ? manifest['frames']
      : const <Object?>[];
  if (entries is! List) {
    throw ArgumentError('$_metadataFilename frames field must be a list.');
  }
  final Object? startTsMs = manifest.containsKey('startTimestampMs')
      ? manifest['startTimestampMs']
      : 0;
  if (startTsMs is! num || startTsMs.isNaN || startTsMs.isInfinite) {
    throw ArgumentError(
      '$_metadataFilename startTimestampMs must be a finite number.',
    );
  }
  return manifest;
}

VisualFrame _readFrameEntry(
  Map<String, Uint8List> members,
  Set<String> memberNames,
  Object? entry,
  double startTimestampMs,
  Set<String> readMembers,
) {
  if (entry is! Map) {
    throw ArgumentError('$_metadataFilename frame entries must be objects.');
  }
  final Object? memberName = entry['fileName'];
  if (memberName is! String ||
      memberName.isEmpty ||
      !memberNames.contains(memberName)) {
    throw ArgumentError(
      'Visual frame archive is missing frame member $memberName.',
    );
  }
  if (!readMembers.add(memberName)) {
    throw ArgumentError(
      '$_metadataFilename lists frame member $memberName more than once.',
    );
  }
  final Object? offsetMs = entry.containsKey('offsetMs')
      ? entry['offsetMs']
      : 0;
  if (offsetMs is! num || offsetMs.isNaN || offsetMs.isInfinite) {
    throw ArgumentError(
      '$_metadataFilename frame offsetMs must be a finite number.',
    );
  }
  final Object? rawMime = entry['mimeType'];
  final String mimeType = (rawMime is String && rawMime.isNotEmpty)
      ? rawMime
      : _defaultMimeType;
  return VisualFrame(
    blob: InlineData(
      mimeType: mimeType,
      data: Uint8List.fromList(members[memberName]!),
    ),
    timestamp: (startTimestampMs + offsetMs.toDouble()) / 1000.0,
  );
}

final Uint32List _crc32Table = () {
  final Uint32List table = Uint32List(256);
  for (int i = 0; i < 256; i += 1) {
    int c = i;
    for (int k = 0; k < 8; k += 1) {
      if ((c & 1) != 0) {
        c = 0xEDB88320 ^ (c >>> 1);
      } else {
        c = c >>> 1;
      }
    }
    table[i] = c;
  }
  return table;
}();

int _crc32(Uint8List bytes) {
  int crc = 0xFFFFFFFF;
  for (int i = 0; i < bytes.length; i += 1) {
    crc = _crc32Table[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List _writeStoredZip(List<({String name, Uint8List data})> entries) {
  final BytesBuilder localBuilder = BytesBuilder(copy: false);
  final BytesBuilder centralBuilder = BytesBuilder(copy: false);
  int localOffset = 0;

  for (final ({String name, Uint8List data}) entry in entries) {
    final Uint8List nameBytes = Uint8List.fromList(utf8.encode(entry.name));
    final Uint8List data = entry.data;
    final int crc = _crc32(data);
    final int size = data.length;

    // Local file header (30 bytes + filename)
    final ByteData localHeader = ByteData(30);
    localHeader.setUint32(0, 0x04034b50, Endian.little);
    localHeader.setUint16(4, 20, Endian.little); // version needed (2.0)
    localHeader.setUint16(6, 0, Endian.little); // flags
    localHeader.setUint16(8, 0, Endian.little); // compression = ZIP_STORED (0)
    localHeader.setUint16(10, 0, Endian.little); // mod time
    localHeader.setUint16(12, 0x0021, Endian.little); // mod date (1980-01-01)
    localHeader.setUint32(14, crc, Endian.little);
    localHeader.setUint32(18, size, Endian.little);
    localHeader.setUint32(22, size, Endian.little);
    localHeader.setUint16(26, nameBytes.length, Endian.little);
    localHeader.setUint16(28, 0, Endian.little); // extra length

    localBuilder.add(localHeader.buffer.asUint8List());
    localBuilder.add(nameBytes);
    localBuilder.add(data);

    // Central directory file header (46 bytes + filename)
    final ByteData centralHeader = ByteData(46);
    centralHeader.setUint32(0, 0x02014b50, Endian.little);
    centralHeader.setUint16(4, 20, Endian.little); // version made by
    centralHeader.setUint16(6, 20, Endian.little); // version needed (46-40=6)
    centralHeader.setUint16(8, 0, Endian.little); // flags (46-38=8)
    centralHeader.setUint16(10, 0, Endian.little); // compression = 0
    centralHeader.setUint16(12, 0, Endian.little); // mod time
    centralHeader.setUint16(14, 0x0021, Endian.little); // mod date
    centralHeader.setUint32(16, crc, Endian.little);
    centralHeader.setUint32(20, size, Endian.little);
    centralHeader.setUint32(24, size, Endian.little);
    centralHeader.setUint16(28, nameBytes.length, Endian.little);
    centralHeader.setUint16(30, 0, Endian.little); // extra length
    centralHeader.setUint16(32, 0, Endian.little); // comment length
    centralHeader.setUint16(34, 0, Endian.little); // disk number
    centralHeader.setUint16(36, 0, Endian.little); // internal attrs
    centralHeader.setUint32(38, 0, Endian.little); // external attrs
    centralHeader.setUint32(42, localOffset, Endian.little);

    centralBuilder.add(centralHeader.buffer.asUint8List());
    centralBuilder.add(nameBytes);

    localOffset += 30 + nameBytes.length + size;
  }

  final Uint8List centralBytes = centralBuilder.toBytes();
  final ByteData eocd = ByteData(22);
  eocd.setUint32(0, 0x06054b50, Endian.little);
  eocd.setUint16(4, 0, Endian.little); // disk number
  eocd.setUint16(6, 0, Endian.little); // start disk
  eocd.setUint16(8, entries.length, Endian.little);
  eocd.setUint16(10, entries.length, Endian.little);
  eocd.setUint32(12, centralBytes.length, Endian.little);
  eocd.setUint32(16, localOffset, Endian.little);
  eocd.setUint16(20, 0, Endian.little); // comment length

  localBuilder.add(centralBytes);
  localBuilder.add(eocd.buffer.asUint8List());
  return localBuilder.toBytes();
}

Map<String, Uint8List> _readStoredZip(Uint8List bytes) {
  if (bytes.length < 22) {
    throw ArgumentError('Visual frame archive is not a valid ZIP.');
  }
  final ByteData view = ByteData.sublistView(bytes);

  // Locate End of Central Directory (EOCD) record from the end of the buffer.
  int eocdOffset = -1;
  final int minEocdOffset = bytes.length - 22 - 0xFFFF;
  final int stopOffset = minEocdOffset < 0 ? 0 : minEocdOffset;
  for (int i = bytes.length - 22; i >= stopOffset; i -= 1) {
    if (view.getUint32(i, Endian.little) == 0x06054b50) {
      final int commentLen = view.getUint16(i + 20, Endian.little);
      if (i + 22 + commentLen == bytes.length) {
        eocdOffset = i;
        break;
      }
    }
  }
  if (eocdOffset < 0) {
    throw ArgumentError('Visual frame archive is not a valid ZIP.');
  }

  final int entryCount = view.getUint16(eocdOffset + 10, Endian.little);
  final int centralDirSize = view.getUint32(eocdOffset + 12, Endian.little);
  final int centralDirOffset = view.getUint32(eocdOffset + 16, Endian.little);
  if (centralDirOffset + centralDirSize > eocdOffset) {
    throw ArgumentError('Visual frame archive is not a valid ZIP.');
  }

  final List<
    ({
      String name,
      int versionNeeded,
      int flags,
      int compressionMethod,
      int crc32,
      int compressedSize,
      int uncompressedSize,
      int localHeaderOffset,
    })
  >
  centralEntries =
      <
        ({
          String name,
          int versionNeeded,
          int flags,
          int compressionMethod,
          int crc32,
          int compressedSize,
          int uncompressedSize,
          int localHeaderOffset,
        })
      >[];

  int cursor = centralDirOffset;
  for (int i = 0; i < entryCount; i += 1) {
    if (cursor + 46 > eocdOffset ||
        view.getUint32(cursor, Endian.little) != 0x02014b50) {
      throw ArgumentError('Visual frame archive is not a valid ZIP.');
    }
    final int versionNeeded = view.getUint16(cursor + 6, Endian.little) & 0xFF;
    if (versionNeeded > 63) {
      throw ArgumentError('Visual frame archive is not a valid ZIP.');
    }
    final int flags = view.getUint16(cursor + 8, Endian.little);
    final int compressionMethod = view.getUint16(cursor + 10, Endian.little);
    final int crc32 = view.getUint32(cursor + 16, Endian.little);
    final int compressedSize = view.getUint32(cursor + 20, Endian.little);
    final int uncompressedSize = view.getUint32(cursor + 24, Endian.little);
    final int nameLen = view.getUint16(cursor + 28, Endian.little);
    final int extraLen = view.getUint16(cursor + 30, Endian.little);
    final int commentLen = view.getUint16(cursor + 32, Endian.little);
    final int localHeaderOffset = view.getUint32(cursor + 42, Endian.little);

    final int nameStart = cursor + 46;
    final int nextCursor = nameStart + nameLen + extraLen + commentLen;
    if (nextCursor > eocdOffset) {
      throw ArgumentError('Visual frame archive is not a valid ZIP.');
    }
    final String name;
    try {
      name = utf8.decode(
        Uint8List.sublistView(bytes, nameStart, nameStart + nameLen),
      );
    } on FormatException {
      throw ArgumentError('Visual frame archive is not a valid ZIP.');
    }
    centralEntries.add((
      name: name,
      versionNeeded: versionNeeded,
      flags: flags,
      compressionMethod: compressionMethod,
      crc32: crc32,
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize,
      localHeaderOffset: localHeaderOffset,
    ));
    cursor = nextCursor;
  }

  for (final entry in centralEntries) {
    if (entry.compressionMethod != 0 ||
        (entry.flags & _unreadableFlagBits) != 0) {
      throw ArgumentError(
        "Visual frame archive member '${entry.name}' must be stored "
        'uncompressed and unencrypted.',
      );
    }
  }

  final Map<String, Uint8List> members = <String, Uint8List>{};
  for (final entry in centralEntries) {
    final int localOffset = entry.localHeaderOffset;
    if (localOffset + 30 > centralDirOffset ||
        view.getUint32(localOffset, Endian.little) != 0x04034b50) {
      throw ArgumentError('Visual frame archive is not a valid ZIP.');
    }
    final int localNameLen = view.getUint16(localOffset + 26, Endian.little);
    final int localExtraLen = view.getUint16(localOffset + 28, Endian.little);
    final int dataStart = localOffset + 30 + localNameLen + localExtraLen;
    final int dataEnd = dataStart + entry.compressedSize;
    if (entry.compressedSize != entry.uncompressedSize ||
        dataEnd > centralDirOffset) {
      throw ArgumentError('Visual frame archive is not a valid ZIP.');
    }
    final Uint8List data = Uint8List.sublistView(bytes, dataStart, dataEnd);
    if (_crc32(data) != entry.crc32) {
      throw ArgumentError('Visual frame archive is not a valid ZIP.');
    }
    members[entry.name] = Uint8List.fromList(data);
  }
  return members;
}
