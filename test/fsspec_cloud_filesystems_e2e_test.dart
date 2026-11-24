import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adk_dart/adk_dart.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

class _StoredObject {
  _StoredObject({
    required this.bytes,
    required this.contentType,
    required this.metadata,
    required this.createdAt,
  });

  final List<int> bytes;
  final String contentType;
  final Map<String, String> metadata;
  final DateTime createdAt;
}

Future<List<int>> _readBody(HttpRequest request) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in request) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

String _xmlEscape(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// Local mock GCS JSON API server.
class _MockGcsServer {
  _MockGcsServer._(this.server);

  final HttpServer server;
  final Map<String, _StoredObject> objects = <String, _StoredObject>{};
  final List<String?> seenAuthHeaders = <String?>[];
  int pageSize = 2;

  /// If set, simulates a concurrent writer creating this object right before
  /// the next `ifGenerationMatch=0` upload.
  String? injectConflictKeyOnce;

  String get baseUrl => 'http://${server.address.host}:${server.port}';

  static Future<_MockGcsServer> start() async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final _MockGcsServer mock = _MockGcsServer._(server);
    server.listen(mock._handle);
    return mock;
  }

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    seenAuthHeaders.add(req.headers.value('authorization'));
    final List<String> segments = req.uri.pathSegments;

    // POST /upload/storage/v1/b/{bucket}/o?uploadType=multipart
    if (req.method == 'POST' &&
        segments.length == 6 &&
        segments[0] == 'upload' &&
        segments[1] == 'storage' &&
        segments[2] == 'v1' &&
        segments[3] == 'b' &&
        segments[5] == 'o') {
      final String bucket = Uri.decodeComponent(segments[4]);
      final List<int> rawBody = await _readBody(req);
      final String ctHeader = req.headers.value('content-type') ?? '';
      final RegExpMatch? boundaryMatch = RegExp(
        r'boundary=([^;\s]+)',
      ).firstMatch(ctHeader);
      if (boundaryMatch == null) {
        req.response.statusCode = 400;
        req.response.write('Missing boundary');
        await req.response.close();
        return;
      }
      final String boundary = boundaryMatch.group(1)!;
      final (Map<String, Object?> metaJson, List<int> payload) =
          _parseMultipartRelated(rawBody, boundary);
      final String objName = '${metaJson['name']}';
      final String fullKey = '$bucket/$objName';
      final bool exclusive = req.uri.queryParameters['ifGenerationMatch'] == '0';

      if (exclusive && injectConflictKeyOnce == fullKey) {
        injectConflictKeyOnce = null;
        objects[fullKey] = _StoredObject(
          bytes: utf8.encode('raced-by-other-writer'),
          contentType: 'text/plain',
          metadata: const <String, String>{},
          createdAt: DateTime.utc(2026, 11, 24, 10, 0, 0),
        );
      }

      if (exclusive && objects.containsKey(fullKey)) {
        req.response.statusCode = 412;
        req.response.write('{"error":{"code":412,"message":"Precondition Failed"}}');
        await req.response.close();
        return;
      }

      final Map<String, String> meta = <String, String>{};
      final Object? rawMeta = metaJson['metadata'];
      if (rawMeta is Map) {
        rawMeta.forEach((Object? k, Object? v) {
          if (k != null && v != null) {
            meta['$k'] = '$v';
          }
        });
      }
      final _StoredObject stored = _StoredObject(
        bytes: payload,
        contentType: '${metaJson['contentType'] ?? 'application/octet-stream'}',
        metadata: meta,
        createdAt: DateTime.utc(2026, 11, 24, 10, 0, 0),
      );
      objects[fullKey] = stored;
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(_toJson(objName, stored)));
      await req.response.close();
      return;
    }

    // /storage/v1/b/{bucket}/o
    if (segments.length == 5 &&
        segments[0] == 'storage' &&
        segments[1] == 'v1' &&
        segments[2] == 'b' &&
        segments[4] == 'o' &&
        req.method == 'GET') {
      final String bucket = Uri.decodeComponent(segments[3]);
      final String prefix = req.uri.queryParameters['prefix'] ?? '';
      final int offset =
          int.tryParse(req.uri.queryParameters['pageToken'] ?? '0') ?? 0;
      final List<MapEntry<String, _StoredObject>> matched =
          objects.entries
              .where(
                (MapEntry<String, _StoredObject> e) =>
                    e.key.startsWith('$bucket/$prefix'),
              )
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      final List<MapEntry<String, _StoredObject>> slice = matched
          .skip(offset)
          .take(pageSize)
          .toList();
      final bool hasMore = offset + slice.length < matched.length;
      final Map<String, Object?> body = <String, Object?>{
        'kind': 'storage#objects',
        'items': <Map<String, Object?>>[
          for (final MapEntry<String, _StoredObject> entry in slice)
            _toJson(entry.key.substring(bucket.length + 1), entry.value),
        ],
        if (hasMore) 'nextPageToken': '${offset + slice.length}',
      };
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(body));
      await req.response.close();
      return;
    }

    // /storage/v1/b/{bucket}/o/{object}
    if (segments.length == 6 &&
        segments[0] == 'storage' &&
        segments[1] == 'v1' &&
        segments[2] == 'b' &&
        segments[4] == 'o') {
      final String bucket = Uri.decodeComponent(segments[3]);
      final String objName = Uri.decodeComponent(segments[5]);
      final String fullKey = '$bucket/$objName';
      final _StoredObject? existing = objects[fullKey];

      if (req.method == 'GET') {
        if (existing == null) {
          req.response.statusCode = 404;
          req.response.write('Not Found');
          await req.response.close();
          return;
        }
        if (req.uri.queryParameters['alt'] == 'media') {
          req.response.statusCode = 200;
          req.response.headers.set('content-type', existing.contentType);
          req.response.add(existing.bytes);
          await req.response.close();
          return;
        }
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(_toJson(objName, existing)));
        await req.response.close();
        return;
      }

      if (req.method == 'DELETE') {
        if (existing == null) {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        objects.remove(fullKey);
        req.response.statusCode = 204;
        await req.response.close();
        return;
      }
    }

    req.response.statusCode = 404;
    await req.response.close();
  }

  Map<String, Object?> _toJson(String objName, _StoredObject obj) {
    return <String, Object?>{
      'name': objName,
      'size': '${obj.bytes.length}',
      'contentType': obj.contentType,
      'timeCreated': obj.createdAt.toIso8601String(),
      'updated': obj.createdAt.toIso8601String(),
      if (obj.metadata.isNotEmpty) 'metadata': obj.metadata,
    };
  }

  (Map<String, Object?>, List<int>) _parseMultipartRelated(
    List<int> body,
    String boundary,
  ) {
    final String latin = latin1.decode(body);
    final List<String> parts = latin.split('--$boundary');
    // parts[1] = JSON metadata part, parts[2] = media bytes part.
    final int metaSep = parts[1].indexOf('\r\n\r\n');
    final String metaJsonText = parts[1]
        .substring(metaSep + 4)
        .replaceFirst(RegExp(r'\r\n$'), '');
    final Map<String, Object?> metaJson =
        (jsonDecode(metaJsonText) as Map).map(
          (Object? k, Object? v) => MapEntry('$k', v),
        );

    final int dataSep = parts[2].indexOf('\r\n\r\n');
    final String dataLatin = parts[2]
        .substring(dataSep + 4)
        .replaceFirst(RegExp(r'\r\n$'), '');
    return (metaJson, latin1.encode(dataLatin));
  }
}

/// Local mock S3 REST API server that verifies AWS SigV4 Authorization headers.
class _MockS3Server {
  _MockS3Server._(this.server, {required this.expectedAccessKey});

  final HttpServer server;
  final String expectedAccessKey;
  final Map<String, _StoredObject> objects = <String, _StoredObject>{};
  final List<String?> seenAuthHeaders = <String?>[];
  final List<String?> seenSessionTokens = <String?>[];
  int pageSize = 2;
  String? injectConflictKeyOnce;

  String get baseUrl => 'http://${server.address.host}:${server.port}';

  static Future<_MockS3Server> start({
    String expectedAccessKey = 'AKIAIOSFODNN7EXAMPLE',
  }) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final _MockS3Server mock = _MockS3Server._(
      server,
      expectedAccessKey: expectedAccessKey,
    );
    server.listen(mock._handle);
    return mock;
  }

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final String? auth = req.headers.value('authorization');
    seenAuthHeaders.add(auth);
    seenSessionTokens.add(req.headers.value('x-amz-security-token'));

    final List<String> segments = req.uri.pathSegments
        .where((String s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      req.response.statusCode = 400;
      await req.response.close();
      return;
    }
    final String bucket = segments.first;
    final String key = segments.length > 1 ? segments.sublist(1).join('/') : '';

    // ListObjectsV2: GET /{bucket}?list-type=2
    if (req.method == 'GET' &&
        key.isEmpty &&
        req.uri.queryParameters['list-type'] == '2') {
      final String prefix = req.uri.queryParameters['prefix'] ?? '';
      final int offset =
          int.tryParse(req.uri.queryParameters['continuation-token'] ?? '0') ??
          0;
      final List<MapEntry<String, _StoredObject>> matched =
          objects.entries
              .where(
                (MapEntry<String, _StoredObject> e) =>
                    e.key.startsWith('$bucket/$prefix'),
              )
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      final List<MapEntry<String, _StoredObject>> slice = matched
          .skip(offset)
          .take(pageSize)
          .toList();
      final bool truncated = offset + slice.length < matched.length;
      final StringBuffer xml = StringBuffer()
        ..write('<?xml version="1.0" encoding="UTF-8"?>')
        ..write('<ListBucketResult>')
        ..write('<Name>${_xmlEscape(bucket)}</Name>')
        ..write('<IsTruncated>$truncated</IsTruncated>');
      if (truncated) {
        xml.write(
          '<NextContinuationToken>${offset + slice.length}</NextContinuationToken>',
        );
      }
      for (final MapEntry<String, _StoredObject> entry in slice) {
        final String objKey = entry.key.substring(bucket.length + 1);
        xml
          ..write('<Contents>')
          ..write('<Key>${_xmlEscape(objKey)}</Key>')
          ..write('<Size>${entry.value.bytes.length}</Size>')
          ..write(
            '<LastModified>${entry.value.createdAt.toIso8601String()}</LastModified>',
          )
          ..write('</Contents>');
      }
      xml.write('</ListBucketResult>');
      req.response.statusCode = 200;
      req.response.headers.set('content-type', 'application/xml');
      req.response.write(xml.toString());
      await req.response.close();
      return;
    }

    final String fullKey = '$bucket/$key';
    if (req.method == 'PUT') {
      final List<int> body = await _readBody(req);
      final bool exclusive = req.headers.value('if-none-match') == '*';
      if (exclusive && injectConflictKeyOnce == fullKey) {
        injectConflictKeyOnce = null;
        objects[fullKey] = _StoredObject(
          bytes: utf8.encode('raced-s3'),
          contentType: 'text/plain',
          metadata: const <String, String>{},
          createdAt: DateTime.utc(2026, 11, 24, 10, 0, 0),
        );
      }
      if (exclusive && objects.containsKey(fullKey)) {
        req.response.statusCode = 412;
        req.response.write('<Error><Code>PreconditionFailed</Code></Error>');
        await req.response.close();
        return;
      }
      final Map<String, String> meta = <String, String>{};
      req.headers.forEach((String name, List<String> values) {
        final String lower = name.toLowerCase();
        if (lower.startsWith('x-amz-meta-') && values.isNotEmpty) {
          meta[lower.substring('x-amz-meta-'.length)] = values.first;
        }
      });
      objects[fullKey] = _StoredObject(
        bytes: body,
        contentType:
            req.headers.value('content-type') ?? 'application/octet-stream',
        metadata: meta,
        createdAt: DateTime.utc(2026, 11, 24, 10, 0, 0),
      );
      req.response.statusCode = 200;
      await req.response.close();
      return;
    }

    final _StoredObject? existing = objects[fullKey];
    if (req.method == 'HEAD') {
      if (existing == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      req.response.statusCode = 200;
      req.response.headers.set('content-type', existing.contentType);
      req.response.headers.set('content-length', '${existing.bytes.length}');
      req.response.headers.set(
        'last-modified',
        HttpDate.format(existing.createdAt),
      );
      existing.metadata.forEach((String k, String v) {
        req.response.headers.set('x-amz-meta-$k', v);
      });
      await req.response.close();
      return;
    }

    if (req.method == 'GET') {
      if (existing == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      req.response.statusCode = 200;
      req.response.headers.set('content-type', existing.contentType);
      req.response.add(existing.bytes);
      await req.response.close();
      return;
    }

    if (req.method == 'DELETE') {
      if (existing == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      objects.remove(fullKey);
      req.response.statusCode = 204;
      await req.response.close();
      return;
    }

    req.response.statusCode = 404;
    await req.response.close();
  }
}

/// Local mock Azure Blob Storage REST API server.
class _MockAzureBlobServer {
  _MockAzureBlobServer._(this.server);

  final HttpServer server;
  final Map<String, _StoredObject> objects = <String, _StoredObject>{};
  final List<String?> seenAuthHeaders = <String?>[];
  final List<Map<String, String>> seenQueryParams = <Map<String, String>>[];
  final List<String?> seenBlobTypes = <String?>[];
  int pageSize = 2;
  String? injectConflictKeyOnce;

  String get baseUrl => 'http://${server.address.host}:${server.port}';

  static Future<_MockAzureBlobServer> start() async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final _MockAzureBlobServer mock = _MockAzureBlobServer._(server);
    server.listen(mock._handle);
    return mock;
  }

  Future<void> close() => server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    seenAuthHeaders.add(req.headers.value('authorization'));
    seenQueryParams.add(Map<String, String>.from(req.uri.queryParameters));

    final List<String> segments = req.uri.pathSegments
        .where((String s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      req.response.statusCode = 400;
      await req.response.close();
      return;
    }
    final String container = segments.first;
    final String blob = segments.length > 1
        ? segments.sublist(1).join('/')
        : '';

    // ListBlobs: GET /{container}?restype=container&comp=list
    if (req.method == 'GET' &&
        blob.isEmpty &&
        req.uri.queryParameters['restype'] == 'container' &&
        req.uri.queryParameters['comp'] == 'list') {
      final String prefix = req.uri.queryParameters['prefix'] ?? '';
      final int offset =
          int.tryParse(req.uri.queryParameters['marker'] ?? '0') ?? 0;
      final List<MapEntry<String, _StoredObject>> matched =
          objects.entries
              .where(
                (MapEntry<String, _StoredObject> e) =>
                    e.key.startsWith('$container/$prefix'),
              )
              .toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      final List<MapEntry<String, _StoredObject>> slice = matched
          .skip(offset)
          .take(pageSize)
          .toList();
      final bool hasMore = offset + slice.length < matched.length;
      final StringBuffer xml = StringBuffer()
        ..write('<?xml version="1.0" encoding="utf-8"?>')
        ..write('<EnumerationResults><Blobs>');
      for (final MapEntry<String, _StoredObject> entry in slice) {
        final String blobName = entry.key.substring(container.length + 1);
        xml
          ..write('<Blob>')
          ..write('<Name>${_xmlEscape(blobName)}</Name>')
          ..write('<Properties>')
          ..write(
            '<Creation-Time>${HttpDate.format(entry.value.createdAt)}</Creation-Time>',
          )
          ..write(
            '<Last-Modified>${HttpDate.format(entry.value.createdAt)}</Last-Modified>',
          )
          ..write('<Content-Length>${entry.value.bytes.length}</Content-Length>')
          ..write(
            '<Content-Type>${_xmlEscape(entry.value.contentType)}</Content-Type>',
          )
          ..write('</Properties>')
          ..write('<Metadata>');
        entry.value.metadata.forEach((String k, String v) {
          xml.write('<$k>${_xmlEscape(v)}</$k>');
        });
        xml.write('</Metadata></Blob>');
      }
      xml.write('</Blobs>');
      if (hasMore) {
        xml.write('<NextMarker>${offset + slice.length}</NextMarker>');
      } else {
        xml.write('<NextMarker />');
      }
      xml.write('</EnumerationResults>');
      req.response.statusCode = 200;
      req.response.headers.set('content-type', 'application/xml');
      req.response.write(xml.toString());
      await req.response.close();
      return;
    }

    final String fullKey = '$container/$blob';
    if (req.method == 'PUT') {
      seenBlobTypes.add(req.headers.value('x-ms-blob-type'));
      final List<int> body = await _readBody(req);
      final bool exclusive = req.headers.value('if-none-match') == '*';
      if (exclusive && injectConflictKeyOnce == fullKey) {
        injectConflictKeyOnce = null;
        objects[fullKey] = _StoredObject(
          bytes: utf8.encode('raced-azure'),
          contentType: 'text/plain',
          metadata: const <String, String>{},
          createdAt: DateTime.utc(2026, 11, 24, 10, 0, 0),
        );
      }
      if (exclusive && objects.containsKey(fullKey)) {
        req.response.statusCode = 409;
        req.response.headers.set('x-ms-error-code', 'BlobAlreadyExists');
        req.response.write('<Error><Code>BlobAlreadyExists</Code></Error>');
        await req.response.close();
        return;
      }
      final Map<String, String> meta = <String, String>{};
      req.headers.forEach((String name, List<String> values) {
        final String lower = name.toLowerCase();
        if (lower.startsWith('x-ms-meta-') && values.isNotEmpty) {
          meta[lower.substring('x-ms-meta-'.length)] = values.first;
        }
      });
      objects[fullKey] = _StoredObject(
        bytes: body,
        contentType:
            req.headers.value('content-type') ?? 'application/octet-stream',
        metadata: meta,
        createdAt: DateTime.utc(2026, 11, 24, 10, 0, 0),
      );
      req.response.statusCode = 201;
      await req.response.close();
      return;
    }

    final _StoredObject? existing = objects[fullKey];
    if (req.method == 'HEAD') {
      if (existing == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      req.response.statusCode = 200;
      req.response.headers.set('content-type', existing.contentType);
      req.response.headers.set('content-length', '${existing.bytes.length}');
      req.response.headers.set(
        'x-ms-creation-time',
        HttpDate.format(existing.createdAt),
      );
      existing.metadata.forEach((String k, String v) {
        req.response.headers.set('x-ms-meta-$k', v);
      });
      await req.response.close();
      return;
    }

    if (req.method == 'GET') {
      if (existing == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      req.response.statusCode = 200;
      req.response.headers.set('content-type', existing.contentType);
      req.response.add(existing.bytes);
      await req.response.close();
      return;
    }

    if (req.method == 'DELETE') {
      if (existing == null) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      objects.remove(fullKey);
      req.response.statusCode = 202;
      await req.response.close();
      return;
    }

    req.response.statusCode = 404;
    await req.response.close();
  }
}

void main() {
  setUp(() {
    overrideFeatureEnabled(FeatureName.fsspecArtifactService, true);
  });

  tearDown(() {
    resetFeatureRegistryForTest();
  });

  group('GcsFsspecFilesystem E2E over HTTP', () {
    late _MockGcsServer server;

    setUp(() async {
      server = await _MockGcsServer.start();
    });

    tearDown(() async {
      await server.close();
    });

    test(
      'full FsspecArtifactService CRUD, metadata, pagination, auth, and 412 retry',
      () async {
        final FsspecArtifactService service = FsspecArtifactService(
          'gs://my-gcs-bucket/root',
          storageOptions: <String, Object?>{
            'endpoint_url': server.baseUrl,
            'access_token_provider': () async => 'test-gcs-oauth-token',
          },
        );
        expect(service.fs, isA<GcsFsspecFilesystem>());
        expect(service.backend, isA<GcsBackendAdapter>());

        // Save v0 with customMetadata and mimeType.
        final int v0 = await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'report.pdf',
          artifact: Part.fromInlineData(
            mimeType: 'application/pdf',
            data: utf8.encode('PDF-BYTES-V0'),
            displayName: 'Quarterly Report',
          ),
          customMetadata: <String, Object?>{
            'author': 'alice',
            'quarter': 'Q4',
          },
        );
        expect(v0, 0);

        // Save v1 (triggers pagination once we add a third object).
        final int v1 = await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'report.pdf',
          artifact: Part.fromInlineData(
            mimeType: 'application/pdf',
            data: utf8.encode('PDF-BYTES-V1'),
          ),
          customMetadata: <String, Object?>{'author': 'bob'},
        );
        expect(v1, 1);

        // Save a text artifact in a second filename to test listArtifactKeys + pagination.
        final int noteV0 = await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'notes.txt',
          artifact: Part.text('hello gcs world'),
        );
        expect(noteV0, 0);

        // Verify Bearer auth header was sent on every request.
        expect(server.seenAuthHeaders, isNotEmpty);
        expect(
          server.seenAuthHeaders.every(
            (String? h) => h == 'Bearer test-gcs-oauth-token',
          ),
          isTrue,
        );

        // loadArtifact (latest & explicit version).
        final Part? latest = await service.loadArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'report.pdf',
        );
        expect(utf8.decode(latest!.inlineData!.data), 'PDF-BYTES-V1');
        expect(latest.inlineData!.mimeType, 'application/pdf');

        final Part? loadedV0 = await service.loadArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'report.pdf',
          version: 0,
        );
        expect(utf8.decode(loadedV0!.inlineData!.data), 'PDF-BYTES-V0');
        expect(loadedV0.inlineData!.displayName, 'Quarterly Report');

        final Part? loadedNote = await service.loadArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'notes.txt',
        );
        expect(loadedNote?.text, 'hello gcs world');

        // listVersions & getArtifactVersion.
        expect(
          await service.listVersions(
            appName: 'app',
            userId: 'u1',
            sessionId: 's1',
            filename: 'report.pdf',
          ),
          <int>[0, 1],
        );
        final ArtifactVersion? metaV0 = await service.getArtifactVersion(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'report.pdf',
          version: 0,
        );
        expect(metaV0, isNotNull);
        expect(metaV0!.mimeType, 'application/pdf');
        expect(metaV0.customMetadata, <String, Object?>{
          'author': 'alice',
          'quarter': 'Q4',
        });
        expect(
          metaV0.canonicalUri,
          'gs://my-gcs-bucket/root/app/u1/s1/report.pdf/0',
        );

        // listArtifactKeys (across > pageSize=2 objects -> verifies nextPageToken).
        expect(
          await service.listArtifactKeys(
            appName: 'app',
            userId: 'u1',
            sessionId: 's1',
          ),
          <String>['notes.txt', 'report.pdf'],
        );

        // Concurrent create retry: inject 412 conflict on version 0 of raced.bin.
        server.injectConflictKeyOnce =
            'my-gcs-bucket/root/app/u1/s1/raced.bin/0';
        final int racedVersion = await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'raced.bin',
          artifact: Part.fromInlineData(
            mimeType: 'application/octet-stream',
            data: <int>[1, 2, 3],
          ),
        );
        expect(racedVersion, 1);

        // exists + deleteArtifact.
        final GcsFsspecFilesystem gcsFs = service.fs as GcsFsspecFilesystem;
        expect(
          await gcsFs.exists('my-gcs-bucket/root/app/u1/s1/report.pdf/0'),
          isTrue,
        );
        await service.deleteArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'report.pdf',
        );
        expect(
          await gcsFs.exists('my-gcs-bucket/root/app/u1/s1/report.pdf/0'),
          isFalse,
        );
        expect(
          await service.listVersions(
            appName: 'app',
            userId: 'u1',
            sessionId: 's1',
            filename: 'report.pdf',
          ),
          isEmpty,
        );
        gcsFs.close();
      },
    );
  });

  group('S3FsspecFilesystem E2E over HTTP', () {
    late _MockS3Server server;

    setUp(() async {
      server = await _MockS3Server.start();
    });

    tearDown(() async {
      await server.close();
    });

    test(
      'full FsspecArtifactService CRUD, SigV4 Authorization verification, metadata, pagination, and 412 retry',
      () async {
        final FsspecArtifactService service = FsspecArtifactService(
          's3://my-s3-bucket/root',
          storageOptions: <String, Object?>{
            'endpoint_url': server.baseUrl,
            'access_key_id': 'AKIAIOSFODNN7EXAMPLE',
            'secret_access_key': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
            'session_token': 'FwoGZXIvYXdzEBYaDTestSessionToken',
            'region': 'us-west-2',
          },
        );
        expect(service.fs, isA<S3FsspecFilesystem>());
        expect(service.backend, isA<S3BackendAdapter>());

        // Save v0 with customMetadata & mimeType.
        final int v0 = await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'chart.png',
          artifact: Part.fromInlineData(
            mimeType: 'image/png',
            data: <int>[137, 80, 78, 71],
            displayName: 'Sales Chart',
          ),
          customMetadata: <String, Object?>{'env': 'prod', 'owner': 'ml-team'},
        );
        expect(v0, 0);

        // Save v1 & another key to exercise pagination (pageSize=2).
        final int v1 = await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'chart.png',
          artifact: Part.fromInlineData(
            mimeType: 'image/png',
            data: <int>[137, 80, 78, 71, 0],
          ),
        );
        expect(v1, 1);

        await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'summary.txt',
          artifact: Part.text('s3 summary text'),
        );

        // Verify AWS SigV4 Authorization header format and session token.
        expect(server.seenAuthHeaders, isNotEmpty);
        final RegExp sigV4Pattern = RegExp(
          r'^AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/\d{8}/us-west-2/s3/aws4_request, '
          r'SignedHeaders=[a-z0-9;-]+, Signature=[0-9a-f]{64}$',
        );
        for (final String? auth in server.seenAuthHeaders) {
          expect(auth, isNotNull);
          expect(sigV4Pattern.hasMatch(auth!), isTrue, reason: 'Bad SigV4: $auth');
        }
        expect(
          server.seenSessionTokens.every(
            (String? t) => t == 'FwoGZXIvYXdzEBYaDTestSessionToken',
          ),
          isTrue,
        );

        // loadArtifact & metadata round-trip.
        final Part? loadedV0 = await service.loadArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'chart.png',
          version: 0,
        );
        expect(loadedV0!.inlineData!.data, <int>[137, 80, 78, 71]);
        expect(loadedV0.inlineData!.mimeType, 'image/png');
        expect(loadedV0.inlineData!.displayName, 'Sales Chart');

        final Part? loadedText = await service.loadArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'summary.txt',
        );
        expect(loadedText?.text, 's3 summary text');

        // listVersions, getArtifactVersion, listArtifactKeys.
        expect(
          await service.listVersions(
            appName: 'app',
            userId: 'u1',
            sessionId: 's1',
            filename: 'chart.png',
          ),
          <int>[0, 1],
        );
        final ArtifactVersion? versionInfo = await service.getArtifactVersion(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'chart.png',
          version: 0,
        );
        expect(versionInfo!.mimeType, 'image/png');
        expect(versionInfo.customMetadata, <String, Object?>{
          'env': 'prod',
          'owner': 'ml-team',
        });
        expect(
          versionInfo.canonicalUri,
          's3://my-s3-bucket/root/app/u1/s1/chart.png/0',
        );
        expect(
          await service.listArtifactKeys(
            appName: 'app',
            userId: 'u1',
            sessionId: 's1',
          ),
          <String>['chart.png', 'summary.txt'],
        );

        // Concurrent create retry (If-None-Match: * -> 412 -> retries v1).
        server.injectConflictKeyOnce =
            'my-s3-bucket/root/app/u1/s1/raced.dat/0';
        final int raced = await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'raced.dat',
          artifact: Part.fromInlineData(
            mimeType: 'application/octet-stream',
            data: <int>[9, 8, 7],
          ),
        );
        expect(raced, 1);

        // deleteArtifact & exists.
        final S3FsspecFilesystem s3Fs = service.fs as S3FsspecFilesystem;
        await service.deleteArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'chart.png',
        );
        expect(
          await s3Fs.exists('my-s3-bucket/root/app/u1/s1/chart.png/0'),
          isFalse,
        );
        expect(
          await service.listVersions(
            appName: 'app',
            userId: 'u1',
            sessionId: 's1',
            filename: 'chart.png',
          ),
          isEmpty,
        );
        s3Fs.close();
      },
    );

    test('supports anonymous/unsigned mode for local emulators', () async {
      final S3FsspecFilesystem anonFs = S3FsspecFilesystem(
        endpointUrl: server.baseUrl,
        anonymous: true,
      );
      await anonFs.pipeFile(
        'emulated-bucket/hello.txt',
        utf8.encode('unsigned-ok'),
        mode: 'create',
        contentType: 'text/plain',
      );
      expect(
        utf8.decode(await anonFs.catFile('emulated-bucket/hello.txt')),
        'unsigned-ok',
      );
      expect(server.seenAuthHeaders.every((String? h) => h == null), isTrue);
      anonFs.close();
    });
  });

  group('AzureBlobFsspecFilesystem E2E over HTTP', () {
    late _MockAzureBlobServer server;
    // Valid 32-byte base64 key for SharedKey HMAC-SHA256 signing.
    final String fakeAccountKey = base64.encode(
      sha256.convert(utf8.encode('test-azure-secret-key')).bytes,
    );

    setUp(() async {
      server = await _MockAzureBlobServer.start();
    });

    tearDown(() async {
      await server.close();
    });

    test(
      'full FsspecArtifactService CRUD, SharedKey HMAC-SHA256 auth, metadata, pagination, and 409/412 retry',
      () async {
        final FsspecArtifactService service = FsspecArtifactService(
          'abfs://my-container/root',
          storageOptions: <String, Object?>{
            'account_name': 'mytestacct',
            'account_key': fakeAccountKey,
            'endpoint_url': server.baseUrl,
          },
        );
        expect(service.fs, isA<AzureBlobFsspecFilesystem>());
        expect(service.fs.backendVersion, '2026.8.0');
        expect(service.backend, isA<AzureBackendAdapter>());

        // Save v0 with customMetadata & mimeType.
        final int v0 = await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'data.json',
          artifact: Part.fromInlineData(
            mimeType: 'application/json',
            data: utf8.encode('{"ok":true}'),
            displayName: 'Payload JSON',
          ),
          customMetadata: <String, Object?>{'source_env': 'staging'},
        );
        expect(v0, 0);

        // Save v1 + another artifact to trigger XML NextMarker pagination.
        final int v1 = await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'data.json',
          artifact: Part.fromInlineData(
            mimeType: 'application/json',
            data: utf8.encode('{"ok":true,"v":1}'),
          ),
        );
        expect(v1, 1);

        await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'readme.md',
          artifact: Part.text('# Azure Blob E2E'),
        );

        // Verify SharedKey Authorization header & x-ms-blob-type: BlockBlob.
        expect(server.seenAuthHeaders, isNotEmpty);
        final RegExp sharedKeyPattern = RegExp(
          r'^SharedKey mytestacct:[A-Za-z0-9+/]+=*$',
        );
        for (final String? auth in server.seenAuthHeaders) {
          expect(auth, isNotNull);
          expect(
            sharedKeyPattern.hasMatch(auth!),
            isTrue,
            reason: 'Bad SharedKey: $auth',
          );
        }
        expect(
          server.seenBlobTypes.every((String? t) => t == 'BlockBlob'),
          isTrue,
        );

        // loadArtifact & metadata round-trip.
        final Part? loadedV0 = await service.loadArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'data.json',
          version: 0,
        );
        expect(utf8.decode(loadedV0!.inlineData!.data), '{"ok":true}');
        expect(loadedV0.inlineData!.mimeType, 'application/json');
        expect(loadedV0.inlineData!.displayName, 'Payload JSON');

        final Part? loadedMd = await service.loadArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'readme.md',
        );
        expect(loadedMd?.text, '# Azure Blob E2E');

        // listVersions, getArtifactVersion, listArtifactKeys.
        expect(
          await service.listVersions(
            appName: 'app',
            userId: 'u1',
            sessionId: 's1',
            filename: 'data.json',
          ),
          <int>[0, 1],
        );
        final ArtifactVersion? versionInfo = await service.getArtifactVersion(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'data.json',
          version: 0,
        );
        expect(versionInfo!.mimeType, 'application/json');
        expect(versionInfo.customMetadata, <String, Object?>{
          'source_env': 'staging',
        });
        expect(
          versionInfo.canonicalUri,
          'abfs://my-container/root/app/u1/s1/data.json/0',
        );
        expect(
          await service.listArtifactKeys(
            appName: 'app',
            userId: 'u1',
            sessionId: 's1',
          ),
          <String>['data.json', 'readme.md'],
        );

        // Concurrent create retry (If-None-Match: * -> 409 BlobAlreadyExists -> retries v1).
        server.injectConflictKeyOnce =
            'my-container/root/app/u1/s1/raced.bin/0';
        final int raced = await service.saveArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'raced.bin',
          artifact: Part.fromInlineData(
            mimeType: 'application/octet-stream',
            data: <int>[4, 5, 6],
          ),
        );
        expect(raced, 1);

        // deleteArtifact & exists.
        final AzureBlobFsspecFilesystem azFs =
            service.fs as AzureBlobFsspecFilesystem;
        await service.deleteArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'data.json',
        );
        expect(
          await azFs.exists('my-container/root/app/u1/s1/data.json/0'),
          isFalse,
        );
        expect(
          await service.listVersions(
            appName: 'app',
            userId: 'u1',
            sessionId: 's1',
            filename: 'data.json',
          ),
          isEmpty,
        );
        azFs.close();
      },
    );

    test('supports SAS token authentication with abfss:// and az://', () async {
      final FsspecArtifactService service = FsspecArtifactService(
        'abfss://sas-container/prefix',
        storageOptions: <String, Object?>{
          'endpoint_url': server.baseUrl,
          'sas_token': '?sv=2023-11-03&ss=b&srt=o&sp=rwdlac&sig=FakeSasSig',
        },
      );
      expect(service.fs, isA<AzureBlobFsspecFilesystem>());

      final int version = await service.saveArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'hello.txt',
        artifact: Part.text('sas-authenticated'),
      );
      expect(version, 0);

      final Part? loaded = await service.loadArtifact(
        appName: 'app',
        userId: 'u1',
        sessionId: 's1',
        filename: 'hello.txt',
      );
      expect(loaded?.text, 'sas-authenticated');

      // Verify SAS query params were attached to every request.
      expect(server.seenQueryParams, isNotEmpty);
      for (final Map<String, String> qp in server.seenQueryParams) {
        expect(qp['sv'], '2023-11-03');
        expect(qp['sig'], 'FakeSasSig');
      }

      // Also verify az:// scheme resolves to AzureBlobFsspecFilesystem.
      final FsspecArtifactService azService = FsspecArtifactService(
        'az://sas-container/prefix',
        storageOptions: <String, Object?>{
          'endpoint_url': server.baseUrl,
          'sas_token': 'sv=2023-11-03&sig=FakeSasSig',
        },
      );
      expect(azService.fs, isA<AzureBlobFsspecFilesystem>());
      expect(
        (await azService.loadArtifact(
          appName: 'app',
          userId: 'u1',
          sessionId: 's1',
          filename: 'hello.txt',
        ))?.text,
        'sas-authenticated',
      );

      (service.fs as AzureBlobFsspecFilesystem).close();
      (azService.fs as AzureBlobFsspecFilesystem).close();
    });
  });
}
