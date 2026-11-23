import 'dart:io';
import 'dart:typed_data';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

final DateTime _fixedDatetime = DateTime.utc(2025, 1, 1, 12, 0, 0);

bool _isAscii(String value) {
  for (int i = 0; i < value.length; i += 1) {
    if (value.codeUnitAt(i) > 0x7F) {
      return false;
    }
  }
  return true;
}

class _FakeAzureWriter extends FsspecWriteStream {
  _FakeAzureWriter(this._commit, {this.onWrite});

  final void Function(List<int> data) _commit;
  final void Function(List<int> bytes)? onWrite;
  final BytesBuilder _chunks = BytesBuilder(copy: false);

  @override
  void write(List<int> bytes) {
    if (onWrite != null) {
      onWrite!(bytes);
      return;
    }
    _chunks.add(bytes);
  }

  @override
  void close() {
    if (!closed) {
      closed = true;
      _commit(_chunks.takeBytes());
    }
  }

  /// Simulates Python's `AbstractBufferedFile.__del__`, which commits an
  /// unclosed writer on GC.
  void finalize() {
    if (!closed) {
      close();
    }
  }
}

/// In-memory fsspec filesystem matching `adlfs` behavior from upstream
/// `FakeAzureObjectStore`.
class _FakeAzureObjectStore extends InMemoryFsspecFilesystem {
  _FakeAzureObjectStore({super.backendVersion})
    : super(protocol: const <String>['abfs', 'az', 'abfss']);

  final Map<String, List<Map<String, Object?>>> dircache =
      <String, List<Map<String, Object?>>>{};

  FsspecWriteStream Function(
    String path,
    String mode,
    Map<String, String>? metadata,
    Map<String, Object?>? contentSettings,
  )?
  openHook;

  Object Function(String path, String? prefix, bool detail)? findHook;

  @override
  void invalidateCache([String? path]) {
    super.invalidateCache(path);
    if (path == null) {
      dircache.clear();
    } else {
      dircache.remove(stripProtocol(path));
    }
  }

  @override
  Map<String, Object?> info(String path) {
    final String key = stripProtocol(path);
    final List<Map<String, Object?>>? listing = dircache[parent(key)];
    if (listing != null &&
        listing.every((Map<String, Object?> entry) => entry['name'] != key)) {
      throw PathNotFoundException(path, const OSError('File not found', 2));
    }
    return super.info(path);
  }

  void _store(
    String key,
    List<int> value,
    Map<String, String> metadata,
    Map<String, Object?>? contentSettings, {
    required bool exclusive,
  }) {
    final Object? rawContentType = contentSettings?['content_type'];
    final String contentType =
        (rawContentType is String && rawContentType.isNotEmpty)
        ? rawContentType
        : 'application/octet-stream';
    if (exclusive && objects.containsKey(key)) {
      if (value.isEmpty) {
        throw AzureStorageException('BlobAlreadyExists', key);
      }
      throw FsspecFileExistsException(key);
    }
    putFile(
      key,
      value,
      info: <String, Object?>{
        'creation_time': _fixedDatetime,
        'metadata': Map<String, String>.from(metadata),
        'content_settings': <String, Object?>{'content_type': contentType},
      },
    );
  }

  void put(
    String path,
    List<int> value, {
    Map<String, String>? metadata,
    String? contentType,
  }) {
    _store(
      stripProtocol(path),
      value,
      metadata ?? const <String, String>{},
      contentType != null
          ? <String, Object?>{'content_type': contentType}
          : null,
      exclusive: false,
    );
  }

  @override
  void pipeFile(
    String path,
    List<int> data, {
    String mode = 'overwrite',
    String? contentType,
    Map<String, String>? metadata,
  }) {
    _store(
      stripProtocol(path),
      data,
      const <String, String>{'is_directory': 'false'},
      contentType != null
          ? <String, Object?>{'content_type': contentType}
          : null,
      exclusive: mode == 'create',
    );
  }

  @override
  Object find(
    String path, {
    int? maxdepth,
    bool withdirs = false,
    bool detail = false,
    String? prefix,
  }) {
    if (findHook != null) {
      return findHook!(path, prefix, detail);
    }
    final String fullPath = stripProtocol(path);
    if (objects.containsKey(fullPath)) {
      // Mirrors adlfs find(path) returning [path] when path is itself a blob.
      return <String>[fullPath];
    }
    final String cleanPrefix = (prefix ?? '').replaceAll(
      RegExp(r'^/+|/+$'),
      '',
    );
    final String target = cleanPrefix.isEmpty
        ? '$fullPath/'
        : '$fullPath/$cleanPrefix';
    final Map<String, Map<String, Object?>> result =
        <String, Map<String, Object?>>{};
    final List<String> keys = objects.keys.toList()..sort();
    for (final String key in keys) {
      if (key.startsWith(target)) {
        final Map<String, Object?> info = objects[key]!.$2;
        final Object? rawMeta = info['metadata'];
        result[key] = <String, Object?>{
          ...info,
          'metadata': rawMeta is Map
              ? Map<String, Object?>.from(rawMeta)
              : <String, Object?>{},
        };
      }
    }
    return result;
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
    if (openHook != null) {
      return openHook!(path, mode, metadata, contentSettings);
    }
    if (mode != 'wb' && mode != 'xb') {
      throw ArgumentError('Unexpected mode: $mode');
    }
    return _FakeAzureWriter(
      (List<int> data) => _store(
        stripProtocol(path),
        data,
        metadata ?? const <String, String>{'is_directory': 'false'},
        contentSettings,
        exclusive: mode == 'xb',
      ),
    );
  }
}

/// In-memory fsspec filesystem matching `s3fs` behavior from upstream
/// `FakeS3ObjectStore`.
class _FakeS3ObjectStore extends InMemoryFsspecFilesystem {
  _FakeS3ObjectStore() : super(protocol: const <String>['s3', 's3a']);

  final Map<String, Map<String, String>> headMetadata =
      <String, Map<String, String>>{};

  @override
  void pipeFile(
    String path,
    List<int> data, {
    String mode = 'overwrite',
    String? contentType,
    Map<String, String>? metadata,
  }) {
    final String normalized = stripProtocol(path);
    if (mode == 'create' && objects.containsKey(normalized)) {
      throw FsspecFileExistsException(normalized);
    }
    final Map<String, String> normalizedMeta = <String, String>{
      if (metadata != null)
        for (final MapEntry<String, String> e in metadata.entries)
          e.key.toLowerCase().replaceAll('_', '-'): e.value,
    };
    headMetadata[normalized] = normalizedMeta;
    putFile(
      normalized,
      data,
      info: <String, Object?>{
        'LastModified': _fixedDatetime,
        // S3 defaults untyped objects to binary/octet-stream unless set.
        'ContentType': contentType ?? 'binary/octet-stream',
      },
    );
  }

  @override
  Map<String, String> metadata(String path) {
    final String normalized = stripProtocol(path);
    if (!objects.containsKey(normalized)) {
      throw PathNotFoundException(path, const OSError('File not found', 2));
    }
    return Map<String, String>.from(
      headMetadata[normalized] ?? const <String, String>{},
    );
  }

  @override
  void rmFile(String path) {
    final String normalized = stripProtocol(path);
    super.rmFile(path);
    headMetadata.remove(normalized);
  }
}

class _FailingCloseWriter extends FsspecWriteStream {
  _FailingCloseWriter(this.error);

  final Object error;

  @override
  void write(List<int> bytes) {}

  @override
  void close() {
    throw error;
  }
}

void main() {
  setUp(() {
    overrideFeatureEnabled(FeatureName.fsspecArtifactService, true);
  });

  tearDown(() {
    resetFeatureRegistryForTest();
  });

  group('Adapter selection & timestamp parsing', () {
    test('selects AzureBackendAdapter for abfs, abfss, and az protocols', () {
      for (final String proto in const <String>['abfs', 'abfss', 'az']) {
        final FsspecBackendAdapter adapter = FsspecBackendAdapter.forFilesystem(
          InMemoryFsspecFilesystem(protocol: proto),
        );
        expect(adapter, isA<AzureBackendAdapter>());
        expect(adapter.storesCustomMetadata, isTrue);
      }
    });

    test('parses creation_time timestamp in fromInfo', () {
      final _FakeAzureObjectStore azure = _FakeAzureObjectStore();
      final AzureBackendAdapter adapter = AzureBackendAdapter(azure);
      final FsspecObjectMetadata meta = adapter.fromInfo(
        'b/app/u/s/doc/0',
        <String, Object?>{'creation_time': _fixedDatetime},
      );
      expect(
        meta.createTime,
        _fixedDatetime.microsecondsSinceEpoch / 1000000.0,
      );
    });

    test('generic backend error messages mention gs://, s3:// or abfs://', () async {
      final FsspecArtifactService svc = FsspecArtifactService(
        'memory://bucket',
        fs: InMemoryFsspecFilesystem(protocol: 'memory'),
      );
      for (final (Part part, Map<String, Object?>? meta) in <(
        Part,
        Map<String, Object?>?,
      )>[
        (
          Part.fromInlineData(mimeType: 'text/plain', data: <int>[1]),
          const <String, Object?>{'k': 'v'},
        ),
        (Part.text('hi'), null),
        (Part.fromFileData(fileUri: 'gs://other/x'), null),
      ]) {
        await expectLater(
          () => svc.saveArtifact(
            appName: 'app',
            userId: 'u',
            sessionId: 's',
            filename: 'doc',
            artifact: part,
            customMetadata: meta,
          ),
          throwsA(
            isA<FsspecInputValidationError>().having(
              (FsspecInputValidationError e) => e.message,
              'message',
              contains('gs://, s3:// or abfs://'),
            ),
          ),
        );
      }
    });
  });

  group('Tightened S3 metadata checks (4d9e2c75f)', () {
    final List<(String, Map<String, Object?>, String)> invalidS3Cases =
        <(String, Map<String, Object?>, String)>[
          (
            'lowercased-adk-key',
            const <String, Object?>{'adkistext': 'true'},
            "same key as 'adkIsText'",
          ),
          (
            'legacy-key-with-underscore',
            const <String, Object?>{'FILE_URI': 's3://x/y'},
            "same key as 'file_uri'",
          ),
          (
            'non-ascii-value',
            const <String, Object?>{'note': '\u4f60\u597d'},
            'ASCII values',
          ),
          (
            'keys-differing-in-case',
            const <String, Object?>{'userId': '1', 'userid': '2'},
            "same key as 'userId'",
          ),
          (
            'underscore-and-dash',
            const <String, Object?>{'a_b': '1', 'a-b': '2'},
            "same key as 'a_b'",
          ),
          (
            'key-with-space',
            const <String, Object?>{'bad key': 'v'},
            'HTTP header name keys',
          ),
          (
            'empty-key',
            const <String, Object?>{'': 'v'},
            'HTTP header name keys',
          ),
          (
            'control-character',
            const <String, Object?>{'note': 'a\nb'},
            'printable ASCII values',
          ),
          (
            'leading-space',
            const <String, Object?>{'note': ' x'},
            'without spaces at either end',
          ),
          (
            'trailing-space',
            const <String, Object?>{'note': 'x '},
            'without spaces at either end',
          ),
        ];

    for (final (String id, Map<String, Object?> meta, String match)
        in invalidS3Cases) {
      test('rejects invalid S3 metadata: $id', () async {
        final _FakeS3ObjectStore s3 = _FakeS3ObjectStore();
        final FsspecArtifactService svc = FsspecArtifactService(
          's3://b',
          fs: s3,
        );

        await expectLater(
          () => svc.saveArtifact(
            appName: 'app',
            userId: 'u',
            sessionId: 's',
            filename: 'doc',
            artifact: Part.fromInlineData(
              mimeType: 'text/plain',
              data: <int>[120],
            ),
            customMetadata: meta,
          ),
          throwsA(
            isA<FsspecInputValidationError>().having(
              (FsspecInputValidationError e) => e.message,
              'message',
              contains(match),
            ),
          ),
        );
        expect(s3.objects, isEmpty);
      });
    }

    test('keeps valid S3 caller metadata as given', () async {
      final _FakeS3ObjectStore s3 = _FakeS3ObjectStore();
      final FsspecArtifactService svc = FsspecArtifactService('s3://b', fs: s3);

      await svc.saveArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'doc',
        artifact: Part.text('hi'),
        customMetadata: const <String, Object?>{'a.b': '50% off, now'},
      );

      final ArtifactVersion? versionMeta = await svc.getArtifactVersion(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'doc',
      );
      expect(versionMeta, isNotNull);
      expect(versionMeta!.customMetadata, <String, Object?>{
        'a.b': '50% off, now',
      });
      expect(s3.headMetadata['b/app/u/s/doc/0']?['a.b'], '50% off, now');
    });

    test(
      'S3 round-trips edge-spaced non-ASCII display_name and file_uri without edge spaces stored',
      () async {
        final List<Part> artifacts = <Part>[
          Part.fromInlineData(
            data: <int>[120],
            mimeType: 'image/png',
            displayName: ' \u56fe 100%.png ',
          ),
          Part.fromFileData(
            fileUri: 's3://other/\u56fe%20x.pdf',
            mimeType: 'application/pdf',
          ),
        ];

        for (final Part artifact in artifacts) {
          final _FakeS3ObjectStore s3 = _FakeS3ObjectStore();
          final FsspecArtifactService svc = FsspecArtifactService(
            's3://b',
            fs: s3,
          );
          await svc.saveArtifact(
            appName: 'app',
            userId: 'u',
            sessionId: 's',
            filename: 'doc',
            artifact: artifact,
          );

          final Part? loaded = await svc.loadArtifact(
            appName: 'app',
            userId: 'u',
            sessionId: 's',
            filename: 'doc',
          );
          expect(loaded?.inlineData?.displayName, artifact.inlineData?.displayName);
          expect(loaded?.fileData?.fileUri, artifact.fileData?.fileUri);
          expect(loaded?.fileData?.mimeType, artifact.fileData?.mimeType);

          final Map<String, String> stored = s3.headMetadata['b/app/u/s/doc/0']!;
          for (final String value in stored.values) {
            expect(_isAscii(value), isTrue);
            expect(value, value.trim());
          }
        }
      },
    );

    test('S3 untyped content gets application/octet-stream', () async {
      final _FakeS3ObjectStore s3 = _FakeS3ObjectStore();
      final FsspecArtifactService svc = FsspecArtifactService('s3://b', fs: s3);

      await svc.saveArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'ref',
        artifact: Part.fromFileData(fileUri: 's3://other/x'),
      );

      final ArtifactVersion? versionMeta = await svc.getArtifactVersion(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'ref',
      );
      expect(s3.info('b/app/u/s/ref/0')['ContentType'], 'application/octet-stream');
      expect(versionMeta, isNotNull);
      expect(versionMeta!.mimeType, 'application/octet-stream');
    });
  });

  group('Azure metadata & backend support (481e1b2f1)', () {
    test('Azure metadata round-trips and preserves caller key case', () async {
      final _FakeAzureObjectStore azure = _FakeAzureObjectStore();
      final FsspecArtifactService svc = FsspecArtifactService(
        'abfs://b',
        fs: azure,
      );
      final Map<String, Part> parts = <String, Part>{
        'notes': Part.text('hi'),
        'chart': Part.fromInlineData(
          data: <int>[120],
          mimeType: 'image/png',
          displayName: ' \u56fe 100%.png ',
        ),
        'ref': Part.fromFileData(
          fileUri: 's3://other/\u56fe%20x.pdf',
          mimeType: 'application/pdf',
        ),
        'empty': Part.fromInlineData(data: const <int>[], mimeType: 'text/plain'),
      };

      for (final MapEntry<String, Part> entry in parts.entries) {
        await svc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: entry.key,
          artifact: entry.value,
          customMetadata: const <String, Object?>{
            'userId': '42',
            'trace_id': 'abc',
          },
        );
      }

      final Part? notes = await svc.loadArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'notes',
      );
      expect(notes?.text, 'hi');

      final Part? chart = await svc.loadArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'chart',
      );
      expect(chart?.inlineData?.data, <int>[120]);
      expect(chart?.inlineData?.mimeType, 'image/png');
      expect(chart?.inlineData?.displayName, ' \u56fe 100%.png ');

      final Part? ref = await svc.loadArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'ref',
      );
      expect(ref?.fileData?.fileUri, 's3://other/\u56fe%20x.pdf');
      expect(ref?.fileData?.mimeType, 'application/pdf');

      final Part? empty = await svc.loadArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'empty',
      );
      expect(empty?.inlineData?.data, isEmpty);
      expect(empty?.inlineData?.mimeType, 'text/plain');

      final ArtifactVersion? versionMeta = await svc.getArtifactVersion(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'notes',
      );
      expect(versionMeta, isNotNull);
      // Unlike S3, Azure keeps key case.
      expect(versionMeta!.customMetadata, <String, Object?>{
        'userId': '42',
        'trace_id': 'abc',
      });

      for (final (_, Map<String, Object?> entry) in azure.objects.values) {
        final Map<Object?, Object?> storedMeta =
            entry['metadata']! as Map<Object?, Object?>;
        expect(storedMeta.containsKey('is_directory'), isFalse);
        for (final Object? rawVal in storedMeta.values) {
          final String value = '$rawVal';
          expect(_isAscii(value), isTrue);
          expect(value, value.trim());
        }
      }
    });

    final List<(String, Map<String, Object?>, String)> invalidAzureCases =
        <(String, Map<String, Object?>, String)>[
          (
            'dash-in-key',
            const <String, Object?>{'x-trace': '1'},
            'C# identifier keys',
          ),
          (
            'leading-digit-key',
            const <String, Object?>{'1key': '1'},
            'C# identifier keys',
          ),
          (
            'non-ascii-value',
            const <String, Object?>{'note': '\u4f60\u597d'},
            'ASCII values',
          ),
          (
            'tab-in-value',
            const <String, Object?>{'note': 'x\t'},
            'without spaces at either end',
          ),
          (
            'leading-space-value',
            const <String, Object?>{'note': ' x'},
            'without spaces at either end',
          ),
          (
            'lowercased-adk-key',
            const <String, Object?>{'adkistext': 'true'},
            "same key as 'adkIsText'",
          ),
          (
            'adlfs-is-directory',
            const <String, Object?>{'is_directory': 'true'},
            "same key as 'is_directory'",
          ),
          (
            'adlfs-is-directory-mixed-case',
            const <String, Object?>{'Is_Directory': 'true'},
            "same key as 'is_directory'",
          ),
          (
            'adlfs-hdi-isfolder',
            const <String, Object?>{'hdi_isfolder': 'true'},
            "same key as 'hdi_isfolder'",
          ),
          (
            'case-collision',
            const <String, Object?>{'userId': '1', 'userid': '2'},
            "same key as 'userId'",
          ),
        ];

    for (final (String id, Map<String, Object?> meta, String match)
        in invalidAzureCases) {
      test('rejects invalid Azure metadata: $id', () async {
        final _FakeAzureObjectStore azure = _FakeAzureObjectStore();
        final FsspecArtifactService svc = FsspecArtifactService(
          'abfs://b',
          fs: azure,
        );

        await expectLater(
          () => svc.saveArtifact(
            appName: 'app',
            userId: 'u',
            sessionId: 's',
            filename: 'doc',
            artifact: Part.fromInlineData(
              mimeType: 'text/plain',
              data: <int>[120],
            ),
            customMetadata: meta,
          ),
          throwsA(
            isA<FsspecInputValidationError>().having(
              (FsspecInputValidationError e) => e.message,
              'message',
              contains(match),
            ),
          ),
        );
        expect(azure.objects, isEmpty);
      });
    }

    for (final (String errorCode, bool retried) in <(String, bool)>[
      ('BlobAlreadyExists', true),
      ('ConditionNotMet', true),
      ('ContainerBeingDeleted', false),
    ]) {
      test(
        'wrapped Azure conflict ($errorCode) retried=$retried',
        () async {
          final _FakeAzureObjectStore azure = _FakeAzureObjectStore();
          final FsspecArtifactService svc = FsspecArtifactService(
            'abfs://b',
            fs: azure,
          );
          final AzureStorageException azureError = AzureStorageException(
            errorCode,
            errorCode,
          );

          azure.openHook = (
            String path,
            String mode,
            Map<String, String>? metadata,
            Map<String, Object?>? contentSettings,
          ) {
            if (path.endsWith('/0')) {
              return _FailingCloseWriter(
                AzureRuntimeException(
                  'Failed to upload block!',
                  cause: azureError,
                ),
              );
            }
            azure.openHook = null;
            return azure.openWrite(
              path,
              mode: mode,
              metadata: metadata,
              contentSettings: contentSettings,
            );
          };

          if (retried) {
            final int version = await svc.saveArtifact(
              appName: 'app',
              userId: 'u',
              sessionId: 's',
              filename: 'doc',
              artifact: Part.text('hi'),
            );
            expect(version, 1);
          } else {
            await expectLater(
              () => svc.saveArtifact(
                appName: 'app',
                userId: 'u',
                sessionId: 's',
                filename: 'doc',
                artifact: Part.text('hi'),
              ),
              throwsA(
                isA<AzureRuntimeException>().having(
                  (AzureRuntimeException e) => e.message,
                  'message',
                  contains('Failed to upload block'),
                ),
              ),
            );
          }
        },
      );
    }

    test('artifact nested under a version (a/0) is visible on Azure', () async {
      final FsspecArtifactService svc = FsspecArtifactService(
        'abfs://b',
        fs: _FakeAzureObjectStore(),
      );
      await svc.saveArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'a',
        artifact: Part.text('a'),
      );
      await svc.saveArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'a/0',
        artifact: Part.text('child'),
      );

      expect(
        await svc.listVersions(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'a/0',
        ),
        <int>[0],
      );
      final Part? child = await svc.loadArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'a/0',
      );
      expect(child?.text, 'child');

      await svc.deleteArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'a/0',
      );
      expect(
        await svc.listVersions(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'a/0',
        ),
        isEmpty,
      );
      expect(
        await svc.listVersions(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'a',
        ),
        <int>[0],
      );
    });

    test(
      'Azure reads ADK keys in any case, hides adlfs keys, and drops stale parent dircache',
      () async {
        final _FakeAzureObjectStore azure = _FakeAzureObjectStore();
        // A listing of the parent cached before another client saved version 0.
        azure.dircache['b/app/u/s/doc'] = <Map<String, Object?>>[];
        azure.put(
          'b/app/u/s/doc/0',
          'hi'.codeUnits,
          metadata: const <String, String>{
            'ADKISTEXT': 'true',
            'is_directory': 'false',
            'Hdi_isfolder': 'false',
            'userKey': 'v',
          },
        );
        final FsspecArtifactService svc = FsspecArtifactService(
          'abfs://b',
          fs: azure,
        );

        final ArtifactVersion? versionMeta = await svc.getArtifactVersion(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'doc',
          version: 0,
        );
        final Part? loaded = await svc.loadArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'doc',
        );

        expect(loaded?.text, 'hi');
        expect(versionMeta, isNotNull);
        expect(versionMeta!.customMetadata, <String, Object?>{'userKey': 'v'});
      },
    );

    for (final (String adlfsVersion, bool rejected) in <(String, bool)>[
      ('2024.12.0', true),
      ('2026.5.0', true),
      ('2026.8.0', false),
      ('UNKNOWN', false),
    ]) {
      test(
        'Azure save checks adlfs version $adlfsVersion (rejected=$rejected)',
        () async {
          final FsspecArtifactService svc = FsspecArtifactService(
            'abfs://b',
            fs: _FakeAzureObjectStore(backendVersion: adlfsVersion),
          );

          // Listing does not require saving and always succeeds.
          expect(
            await svc.listArtifactKeys(
              appName: 'app',
              userId: 'u',
              sessionId: 's',
            ),
            isEmpty,
          );

          Future<int> save() => svc.saveArtifact(
            appName: 'app',
            userId: 'u',
            sessionId: 's',
            filename: 'doc',
            artifact: Part.text('hi'),
          );

          if (rejected) {
            await expectLater(
              save,
              throwsA(
                isA<FsspecImportError>().having(
                  (FsspecImportError e) => e.message,
                  'message',
                  contains('adlfs 2026.8.0'),
                ),
              ),
            );
          } else {
            expect(await save(), 0);
          }
        },
      );
    }

    test('Azure failed write is not committed later on finalize', () async {
      final _FakeAzureObjectStore azure = _FakeAzureObjectStore();
      final FsspecArtifactService svc = FsspecArtifactService(
        'abfs://b',
        fs: azure,
      );
      final List<_FakeAzureWriter> writers = <_FakeAzureWriter>[];

      azure.openHook = (
        String path,
        String mode,
        Map<String, String>? metadata,
        Map<String, Object?>? contentSettings,
      ) {
        final _FakeAzureWriter writer = _FakeAzureWriter(
          (List<int> data) => azure.put(path, data, metadata: metadata),
          onWrite: (List<int> _) {
            throw const FileSystemException('network');
          },
        );
        writers.add(writer);
        return writer;
      };

      await expectLater(
        () => svc.saveArtifact(
          appName: 'app',
          userId: 'u',
          sessionId: 's',
          filename: 'doc',
          artifact: Part.text('hi'),
        ),
        throwsA(
          isA<FileSystemException>().having(
            (FileSystemException e) => e.message,
            'message',
            contains('network'),
          ),
        ),
      );

      // Simulate GC finalizer; must NOT commit the failed write.
      writers.removeLast().finalize();
      expect(azure.objects, isEmpty);
    });

    test('Azure empty payload conflict retries next version', () async {
      final _FakeAzureObjectStore azure = _FakeAzureObjectStore();
      azure.put('b/app/u/s/doc/0', const <int>[]);
      azure.findHook = (String path, String? prefix, bool detail) =>
          <String, Map<String, Object?>>{};
      final FsspecArtifactService svc = FsspecArtifactService(
        'abfs://b',
        fs: azure,
      );

      final int version = await svc.saveArtifact(
        appName: 'app',
        userId: 'u',
        sessionId: 's',
        filename: 'doc',
        artifact: Part.fromInlineData(
          data: const <int>[],
          mimeType: 'text/plain',
        ),
      );
      expect(version, 1);
    });
  });

  group('FSSPEC_AZURE artifact service contract tests', () {
    test('session-scoped and user-scoped canonical URIs, versions, refs, and rewind', () async {
      final _FakeAzureObjectStore azure = _FakeAzureObjectStore();
      final FsspecArtifactService svc = FsspecArtifactService(
        'abfs://test_bucket',
        fs: azure,
      );

      final int v0 = await svc.saveArtifact(
        appName: 'app0',
        userId: 'user0',
        sessionId: 'sess0',
        filename: 'doc.txt',
        artifact: Part.text('hello v0'),
        customMetadata: const <String, Object?>{'tag': 'alpha'},
      );
      final int v1 = await svc.saveArtifact(
        appName: 'app0',
        userId: 'user0',
        sessionId: 'sess0',
        filename: 'doc.txt',
        artifact: Part.text('hello v1'),
      );
      expect(v0, 0);
      expect(v1, 1);

      final List<ArtifactVersion> versions = await svc.listArtifactVersions(
        appName: 'app0',
        userId: 'user0',
        sessionId: 'sess0',
        filename: 'doc.txt',
      );
      expect(versions.map((ArtifactVersion v) => v.version).toList(), <int>[0, 1]);
      expect(
        versions[0].canonicalUri,
        'abfs://test_bucket/app0/user0/sess0/doc.txt/0',
      );
      expect(versions[0].customMetadata, <String, Object?>{'tag': 'alpha'});
      expect(
        versions[1].canonicalUri,
        'abfs://test_bucket/app0/user0/sess0/doc.txt/1',
      );

      // User-scoped artifact
      await svc.saveArtifact(
        appName: 'app0',
        userId: 'user0',
        filename: 'user:shared.txt',
        artifact: Part.text('user scoped'),
      );
      final ArtifactVersion? userVer = await svc.getArtifactVersion(
        appName: 'app0',
        userId: 'user0',
        filename: 'user:shared.txt',
      );
      expect(
        userVer?.canonicalUri,
        'abfs://test_bucket/app0/user0/user/user:shared.txt/0',
      );

      // Artifact reference resolution
      await svc.saveArtifact(
        appName: 'app0',
        userId: 'user0',
        sessionId: 'sess0',
        filename: 'ref.txt',
        artifact: Part.fromFileData(
          fileUri:
              'artifact://apps/app0/users/user0/sessions/sess0/artifacts/doc.txt/versions/0',
        ),
      );
      final Part? resolved = await svc.loadArtifact(
        appName: 'app0',
        userId: 'user0',
        sessionId: 'sess0',
        filename: 'ref.txt',
      );
      expect(resolved?.text, 'hello v0');

      // Rewind tombstone loads as null
      await svc.saveArtifact(
        appName: 'app0',
        userId: 'user0',
        sessionId: 'sess0',
        filename: 'doc.txt',
        artifact: newRewindTombstone(),
      );
      expect(
        await svc.loadArtifact(
          appName: 'app0',
          userId: 'user0',
          sessionId: 'sess0',
          filename: 'doc.txt',
        ),
        isNull,
      );
    });
  });
}
