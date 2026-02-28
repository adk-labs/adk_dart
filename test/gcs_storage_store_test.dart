import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('file system gcs storage store path safety', () {
    late Directory tempDir;
    late FileSystemGcsStorageStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('gcs_storage_store_');
      store = FileSystemGcsStorageStore(rootDirectory: tempDir.path);
      await Directory('${tempDir.path}/test-bucket').create(recursive: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('stores and reads a valid blob path inside bucket root', () async {
      await store.uploadText('test-bucket', 'safe/path/file.txt', 'hello');

      expect(
        await store.blobExists('test-bucket', 'safe/path/file.txt'),
        isTrue,
      );
      expect(
        await store.downloadText('test-bucket', 'safe/path/file.txt'),
        'hello',
      );

      final List<String> names = await store.listBlobNames('test-bucket');
      expect(names, contains('safe/path/file.txt'));
    });

    test('rejects blob names with traversal segments', () async {
      await expectLater(
        store.uploadText('test-bucket', '../escape.txt', 'blocked'),
        throwsArgumentError,
      );
      await expectLater(
        store.downloadText('test-bucket', 'a/../../escape.txt'),
        throwsArgumentError,
      );

      expect(File('${tempDir.path}/escape.txt').existsSync(), isFalse);
    });

    test('rejects absolute blob names', () async {
      final String absoluteBlobName = File(
        '${tempDir.path}/absolute.txt',
      ).absolute.path;

      await expectLater(
        store.uploadText('test-bucket', absoluteBlobName, 'blocked'),
        throwsArgumentError,
      );
      expect(File(absoluteBlobName).existsSync(), isFalse);
    });
  });
}
