import 'dart:io';

abstract class GcsStorageStore {
  Future<bool> bucketExists(String bucketName);

  Future<bool> blobExists(String bucketName, String blobName);

  Future<String?> downloadText(String bucketName, String blobName);

  Future<void> uploadText(String bucketName, String blobName, String contents);

  Future<List<String>> listBlobNames(String bucketName, {String? prefix});
}

class FileSystemGcsStorageStore implements GcsStorageStore {
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
    return _normalizePath('$_rootDirectory/$bucketName');
  }

  String _blobPath(String bucketName, String blobName) {
    return _normalizePath('${_bucketDirectory(bucketName)}/$blobName');
  }
}

String _normalizePath(String path) {
  return path.replaceAll('\\', '/');
}
