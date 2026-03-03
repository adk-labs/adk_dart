import 'dart:io';

/// Minimal storage abstraction for GCS-like text object operations.
abstract class GcsStorageStore {
  /// Returns whether [bucketName] exists.
  Future<bool> bucketExists(String bucketName);

  /// Returns whether [blobName] exists in [bucketName].
  Future<bool> blobExists(String bucketName, String blobName);

  /// Downloads text contents for [blobName], or `null` if absent.
  Future<String?> downloadText(String bucketName, String blobName);

  /// Uploads [contents] to [blobName] in [bucketName].
  Future<void> uploadText(String bucketName, String blobName, String contents);

  /// Lists blob names in [bucketName], optionally filtered by [prefix].
  Future<List<String>> listBlobNames(String bucketName, {String? prefix});
}

/// Filesystem-backed fake implementation of [GcsStorageStore] for local use.
class FileSystemGcsStorageStore implements GcsStorageStore {
  /// Creates a fake GCS store rooted at [rootDirectory].
  FileSystemGcsStorageStore({String? rootDirectory})
    : _rootDirectory = rootDirectory ?? '.adk/fake_gcs';

  final String _rootDirectory;

  @override
  Future<bool> bucketExists(String bucketName) async {
    return Directory(_bucketDirectory(bucketName)).exists();
  }

  @override
  Future<bool> blobExists(String bucketName, String blobName) async {
    return File(_blobPath(bucketName, blobName)).exists();
  }

  @override
  Future<String?> downloadText(String bucketName, String blobName) async {
    final File file = File(_blobPath(bucketName, blobName));
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> uploadText(
    String bucketName,
    String blobName,
    String contents,
  ) async {
    final File file = File(_blobPath(bucketName, blobName));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  @override
  Future<List<String>> listBlobNames(
    String bucketName, {
    String? prefix,
  }) async {
    final Directory bucketDir = Directory(_bucketDirectory(bucketName));
    if (!await bucketDir.exists()) {
      return <String>[];
    }

    final String? effectivePrefix = prefix == null || prefix.isEmpty
        ? null
        : _normalizePath(prefix);
    final List<String> names = <String>[];
    await for (final FileSystemEntity entity in bucketDir.list(
      recursive: true,
    )) {
      if (entity is! File) {
        continue;
      }
      final String fullPath = _normalizePath(entity.path);
      final String bucketRoot = _normalizePath(bucketDir.path);
      if (!fullPath.startsWith('$bucketRoot/')) {
        continue;
      }
      final String relative = fullPath.substring(bucketRoot.length + 1);
      if (effectivePrefix != null && !relative.startsWith(effectivePrefix)) {
        continue;
      }
      names.add(relative);
    }
    names.sort();
    return names;
  }

  String _bucketDirectory(String bucketName) {
    return _canonicalPath('$_rootDirectory/$bucketName');
  }

  String _blobPath(String bucketName, String blobName) {
    _validateBlobName(blobName);
    final String bucketRoot = _bucketDirectory(bucketName);
    final String blobPath = _canonicalPath('$bucketRoot/$blobName');
    if (!_isPathWithinDirectory(path: blobPath, directory: bucketRoot)) {
      throw ArgumentError(
        'Invalid blobName `$blobName`: path must stay within bucket root.',
      );
    }
    return blobPath;
  }

  void _validateBlobName(String blobName) {
    final String normalized = _normalizePath(blobName);
    if (normalized.isEmpty) {
      throw ArgumentError('blobName must not be empty.');
    }
    if (_isAbsolutePath(normalized)) {
      throw ArgumentError(
        'Invalid blobName `$blobName`: absolute paths are not allowed.',
      );
    }
    final bool hasTraversalSegment = normalized
        .split('/')
        .any((String segment) => segment == '..');
    if (hasTraversalSegment) {
      throw ArgumentError(
        'Invalid blobName `$blobName`: path traversal is not allowed.',
      );
    }
  }
}

String _normalizePath(String path) {
  return path.replaceAll('\\', '/');
}

String _canonicalPath(String path) {
  final Uri normalized = Uri.file(
    File(path).absolute.path,
    windows: Platform.isWindows,
  ).normalizePath();
  return _normalizePath(normalized.toFilePath(windows: Platform.isWindows));
}

bool _isAbsolutePath(String path) {
  final String normalized = _normalizePath(path);
  return normalized.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:/').hasMatch(normalized);
}

bool _isPathWithinDirectory({required String path, required String directory}) {
  if (path == directory) {
    return true;
  }
  final String normalizedDirectory = directory.endsWith('/')
      ? directory
      : '$directory/';
  if (Platform.isWindows) {
    return path.toLowerCase().startsWith(normalizedDirectory.toLowerCase());
  }
  return path.startsWith(normalizedDirectory);
}
