/// Pure Dart REST [FilesystemProtocol] backends for GCS, AWS S3, and Azure Blob
/// Storage.
///
/// These implementations talk directly to each cloud provider's HTTP REST API
/// using `package:http` and `package:crypto`, allowing [FsspecArtifactService]
/// to run natively in Dart without Python `fsspec`, `gcsfs`, `s3fs`, or
/// `adlfs`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../tools/_google_access_token.dart';
import 'backends.dart';
import 'fsspec_artifact_service.dart';

const String _defaultOctetStream = 'application/octet-stream';
final RegExp _cloudSchemePattern = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*)://');

String _normalizeObjectPath(String raw) {
  String result = raw.replaceAll('\\', '/').trim();
  final RegExpMatch? match = _cloudSchemePattern.firstMatch(result);
  if (match != null) {
    result = result.substring(match.end);
  }
  while (result.startsWith('/')) {
    result = result.substring(1);
  }
  while (result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

(String bucket, String key) _splitBucketAndKey(String normalizedPath) {
  final int slash = normalizedPath.indexOf('/');
  if (slash < 0) {
    return (normalizedPath, '');
  }
  return (
    normalizedPath.substring(0, slash),
    normalizedPath.substring(slash + 1),
  );
}

String _combinePrefix(String basePath, String? prefix) {
  final String cleanBase = _normalizeObjectPath(basePath);
  if (prefix == null || prefix.isEmpty) {
    return cleanBase;
  }
  final String cleanPrefix = prefix.replaceAll(RegExp(r'^/+|/+$'), '');
  if (cleanPrefix.isEmpty) {
    return cleanBase;
  }
  if (cleanBase.isEmpty) {
    return cleanPrefix;
  }
  return '$cleanBase/$cleanPrefix';
}

bool _withinMaxDepth(String root, String candidate, int? maxdepth) {
  if (maxdepth == null) {
    return true;
  }
  final String rel = root.isEmpty
      ? candidate
      : candidate.startsWith('$root/')
      ? candidate.substring(root.length + 1)
      : '';
  if (rel.isEmpty) {
    return true;
  }
  return rel.split('/').length <= maxdepth;
}

String? _readStringOption(
  Map<String, Object?>? options,
  List<String> keys, {
  List<String> envKeys = const <String>[],
}) {
  if (options != null) {
    for (final String key in keys) {
      final Object? value = options[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    final Object? clientKwargs = options['client_kwargs'];
    if (clientKwargs is Map) {
      for (final String key in keys) {
        final Object? value = clientKwargs[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
  }
  for (final String envKey in envKeys) {
    final String? envValue = Platform.environment[envKey]?.trim();
    if (envValue != null && envValue.isNotEmpty) {
      return envValue;
    }
  }
  return null;
}

bool? _readBoolOption(Map<String, Object?>? options, List<String> keys) {
  if (options == null) {
    return null;
  }
  for (final String key in keys) {
    final Object? value = options[key];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final String lower = value.trim().toLowerCase();
      if (lower == 'true' || lower == '1') {
        return true;
      }
      if (lower == 'false' || lower == '0') {
        return false;
      }
    }
  }
  return null;
}

String _stripTrailingSlash(String url) {
  String out = url.trim();
  while (out.endsWith('/')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

DateTime? _tryParseHttpOrIsoDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  final String trimmed = raw.trim();
  final DateTime? iso = DateTime.tryParse(trimmed);
  if (iso != null) {
    return iso.toUtc();
  }
  try {
    return HttpDate.parse(trimmed).toUtc();
  } on HttpException {
    return null;
  }
}

String _unescapeXml(String input) {
  if (!input.contains('&')) {
    return input;
  }
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

String? _extractXmlTag(String xml, String tagName) {
  final RegExp pattern = RegExp(
    '<$tagName(?:\\s[^>]*)?>([\\s\\S]*?)</$tagName>',
    multiLine: true,
  );
  final RegExpMatch? match = pattern.firstMatch(xml);
  if (match == null) {
    return null;
  }
  return _unescapeXml(match.group(1)!);
}

Iterable<String> _extractXmlBlocks(String xml, String tagName) sync* {
  final RegExp pattern = RegExp(
    '<$tagName(?:\\s[^>]*)?>([\\s\\S]*?)</$tagName>',
    multiLine: true,
  );
  for (final RegExpMatch match in pattern.allMatches(xml)) {
    yield match.group(1)!;
  }
}

/// RFC 3986 percent-encoding for AWS SigV4 (unreserved: A-Z a-z 0-9 - _ . ~).
String _awsUriEncode(String input, {bool encodeSlash = true}) {
  final List<int> bytes = utf8.encode(input);
  final StringBuffer buffer = StringBuffer();
  for (final int byte in bytes) {
    final bool isUnreserved =
        (byte >= 0x41 && byte <= 0x5A) || // A-Z
        (byte >= 0x61 && byte <= 0x7A) || // a-z
        (byte >= 0x30 && byte <= 0x39) || // 0-9
        byte == 0x2D || // -
        byte == 0x5F || // _
        byte == 0x2E || // .
        byte == 0x7E; // ~
    if (isUnreserved || (!encodeSlash && byte == 0x2F)) {
      buffer.writeCharCode(byte);
    } else {
      buffer.write('%');
      buffer.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return buffer.toString();
}

String _encodePathSegments(String key) {
  if (key.isEmpty) {
    return '';
  }
  return key.split('/').map(Uri.encodeComponent).join('/');
}

class _CloudWriteStream extends FsspecWriteStream {
  _CloudWriteStream(this._onCommit);

  final Future<void> Function(List<int> data) _onCommit;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  @override
  void write(List<int> bytes) {
    if (closed) {
      throw StateError('Stream is already closed.');
    }
    _buffer.add(bytes);
  }

  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    await _onCommit(_buffer.takeBytes());
  }
}

/// Pure Dart REST [FilesystemProtocol] implementation for Google Cloud Storage
/// (`gs://` / `gcs://`) using the GCS JSON API.
class GcsFsspecFilesystem extends FilesystemProtocol {
  /// Creates a [GcsFsspecFilesystem].
  ///
  /// [endpointUrl] defaults to `STORAGE_EMULATOR_HOST` (if set) or
  /// `https://storage.googleapis.com`.
  GcsFsspecFilesystem({
    String? endpointUrl,
    this.accessToken,
    this.accessTokenProvider,
    this.anonymous = false,
    http.Client? httpClient,
  }) : endpointUrl = _resolveGcsEndpoint(endpointUrl),
       _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  /// Creates a [GcsFsspecFilesystem] from fsspec-style [storageOptions].
  factory GcsFsspecFilesystem.fromStorageOptions(
    Map<String, Object?>? storageOptions, {
    http.Client? httpClient,
  }) {
    final String? endpoint = _readStringOption(
      storageOptions,
      const <String>['endpoint_url', 'endpointUrl'],
      envKeys: const <String>['STORAGE_EMULATOR_HOST'],
    );
    final Object? rawToken =
        storageOptions?['token'] ??
        storageOptions?['access_token'] ??
        storageOptions?['accessToken'];
    final bool isAnon =
        rawToken == 'anon' ||
        rawToken == 'anonymous' ||
        (_readBoolOption(storageOptions, const <String>['anon', 'anonymous']) ??
            false);
    final String? token = (!isAnon && rawToken is String && rawToken.isNotEmpty)
        ? rawToken
        : null;
    final Object? provider =
        storageOptions?['access_token_provider'] ??
        storageOptions?['accessTokenProvider'];
    return GcsFsspecFilesystem(
      endpointUrl: endpoint,
      accessToken: token,
      accessTokenProvider: provider is FutureOr<String?> Function()
          ? provider
          : null,
      anonymous: isAnon,
      httpClient: httpClient,
    );
  }

  static String _resolveGcsEndpoint(String? explicit) {
    final String? raw =
        explicit ?? Platform.environment['STORAGE_EMULATOR_HOST'];
    if (raw == null || raw.trim().isEmpty) {
      return 'https://storage.googleapis.com';
    }
    final String trimmed = _stripTrailingSlash(raw);
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'http://$trimmed';
  }

  /// Base URL of the GCS JSON API endpoint.
  final String endpointUrl;

  /// Optional static OAuth2 bearer access token.
  final String? accessToken;

  /// Optional callback returning an OAuth2 bearer access token.
  final FutureOr<String?> Function()? accessTokenProvider;

  /// When `true`, sends unauthenticated requests without an `Authorization`
  /// header.
  final bool anonymous;

  final http.Client _httpClient;
  final bool _ownsClient;

  /// Closes the underlying HTTP client if owned by this instance.
  void close() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  @override
  Object? get protocol => const <String>['gs', 'gcs'];

  @override
  String stripProtocol(String path) => _normalizeObjectPath(path);

  @override
  String unstripProtocol(String path) => 'gs://${stripProtocol(path)}';

  @override
  void invalidateCache([String? path]) {}

  @override
  (String, String, Object?)? splitPath(String path) {
    final (String bucket, String key) = _splitBucketAndKey(stripProtocol(path));
    return (bucket, key, null);
  }

  Future<Map<String, String>> _authHeaders() async {
    if (anonymous) {
      return <String, String>{};
    }
    if (accessTokenProvider != null) {
      final String? token = await accessTokenProvider!();
      if (token != null && token.isNotEmpty) {
        return <String, String>{'Authorization': 'Bearer $token'};
      }
      return <String, String>{};
    }
    if (accessToken != null && accessToken!.isNotEmpty) {
      return <String, String>{'Authorization': 'Bearer $accessToken'};
    }
    try {
      final String token = await resolveDefaultGoogleAccessToken(
        scopes: const <String>[
          'https://www.googleapis.com/auth/devstorage.read_write',
        ],
      );
      return <String, String>{'Authorization': 'Bearer $token'};
    } on StateError {
      // Allow unauthenticated requests against local emulators / custom endpoints.
      if (endpointUrl != 'https://storage.googleapis.com') {
        return <String, String>{};
      }
      rethrow;
    }
  }

  Future<void> _uploadObject(
    String path,
    List<int> data, {
    required bool exclusive,
    String? contentType,
    Map<String, String>? metadata,
  }) async {
    final String normalized = stripProtocol(path);
    final (String bucket, String key) = _splitBucketAndKey(normalized);
    if (bucket.isEmpty || key.isEmpty) {
      throw ArgumentError('GCS path must include bucket and object: $path');
    }
    final String effectiveContentType =
        (contentType != null && contentType.isNotEmpty)
        ? contentType
        : _defaultOctetStream;
    final String boundary =
        'adk_gcs_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}';
    final Map<String, Object?> metaBody = <String, Object?>{
      'name': key,
      'contentType': effectiveContentType,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
    };

    final BytesBuilder body = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'))
      ..add(utf8.encode(jsonEncode(metaBody)))
      ..add(utf8.encode('\r\n--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: $effectiveContentType\r\n\r\n'))
      ..add(data)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));

    final Map<String, String> queryParams = <String, String>{
      'uploadType': 'multipart',
      if (exclusive) 'ifGenerationMatch': '0',
    };
    final Uri uri = Uri.parse(
      '$endpointUrl/upload/storage/v1/b/${Uri.encodeComponent(bucket)}/o',
    ).replace(queryParameters: queryParams);

    final Map<String, String> headers = <String, String>{
      ...await _authHeaders(),
      'Content-Type': 'multipart/related; boundary=$boundary',
    };
    final http.Response response = await _httpClient.post(
      uri,
      headers: headers,
      body: body.takeBytes(),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    if (response.statusCode == 412) {
      throw FsspecFileExistsException(
        normalized,
        message: 'GCS precondition failed (412): ${response.body}',
      );
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized, response.body);
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized, message: response.body);
    }
    throw FileSystemException(
      'GCS upload failed (${response.statusCode}): ${response.body}',
      normalized,
    );
  }

  @override
  Future<void> pipeFile(
    String path,
    List<int> data, {
    String mode = 'overwrite',
    String? contentType,
    Map<String, String>? metadata,
  }) {
    return _uploadObject(
      path,
      data,
      exclusive: mode == 'create',
      contentType: contentType,
      metadata: metadata,
    );
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
    final Object? rawCt =
        contentSettings?['content_type'] ?? contentSettings?['contentType'];
    final String? contentType = rawCt is String && rawCt.isNotEmpty
        ? rawCt
        : null;
    final bool exclusive = mode.contains('x') || generation == 0;
    return _CloudWriteStream(
      (List<int> data) => _uploadObject(
        path,
        data,
        exclusive: exclusive,
        contentType: contentType,
        metadata: metadata,
      ),
    );
  }

  @override
  Future<List<int>> catFile(String path) async {
    final String normalized = stripProtocol(path);
    final (String bucket, String key) = _splitBucketAndKey(normalized);
    final Uri uri = Uri.parse(
      '$endpointUrl/storage/v1/b/${Uri.encodeComponent(bucket)}/o/${Uri.encodeComponent(key)}',
    ).replace(queryParameters: const <String, String>{'alt': 'media'});
    final http.Response response = await _httpClient.get(
      uri,
      headers: await _authHeaders(),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized, message: response.body);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized, response.body);
    }
    throw FileSystemException(
      'GCS download failed (${response.statusCode}): ${response.body}',
      normalized,
    );
  }

  Map<String, Object?> _objectJsonToInfo(
    String bucket,
    Map<String, Object?> json,
  ) {
    final String objName = '${json['name'] ?? ''}';
    final String fullName = '$bucket/$objName';
    final Object? rawMeta = json['metadata'];
    return <String, Object?>{
      'name': fullName,
      'type': 'file',
      'size': int.tryParse('${json['size'] ?? 0}') ?? 0,
      if (json['contentType'] is String) 'contentType': json['contentType'],
      if (json['timeCreated'] != null) 'timeCreated': '${json['timeCreated']}',
      if (json['updated'] != null) 'updated': '${json['updated']}',
      if (rawMeta is Map)
        'metadata': <String, Object?>{
          for (final MapEntry<Object?, Object?> entry in rawMeta.entries)
            if (entry.key != null) '${entry.key}': entry.value,
        },
    };
  }

  @override
  Future<Map<String, Object?>> info(String path) async {
    final String normalized = stripProtocol(path);
    final (String bucket, String key) = _splitBucketAndKey(normalized);
    if (bucket.isEmpty || key.isEmpty) {
      throw FsspecFileNotFoundException(normalized);
    }
    final Uri uri = Uri.parse(
      '$endpointUrl/storage/v1/b/${Uri.encodeComponent(bucket)}/o/${Uri.encodeComponent(key)}',
    );
    final http.Response response = await _httpClient.get(
      uri,
      headers: await _authHeaders(),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return _objectJsonToInfo(
          bucket,
          decoded.map((Object? k, Object? v) => MapEntry('$k', v)),
        );
      }
      return <String, Object?>{'name': normalized, 'type': 'file', 'size': 0};
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized, message: response.body);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized, response.body);
    }
    throw FileSystemException(
      'GCS info failed (${response.statusCode}): ${response.body}',
      normalized,
    );
  }

  @override
  Future<Object> find(
    String path, {
    int? maxdepth,
    bool withdirs = false,
    bool detail = false,
    String? prefix,
  }) async {
    final String combined = _combinePrefix(path, prefix);
    final (String bucket, String keyPrefix) = _splitBucketAndKey(combined);
    if (bucket.isEmpty) {
      return detail ? <String, Map<String, Object?>>{} : <String>[];
    }

    final Map<String, Map<String, Object?>> entries =
        <String, Map<String, Object?>>{};
    String? pageToken;
    final Map<String, String> headers = await _authHeaders();

    do {
      final Map<String, String> query = <String, String>{
        if (keyPrefix.isNotEmpty) 'prefix': keyPrefix,
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      };
      final Uri uri = Uri.parse(
        '$endpointUrl/storage/v1/b/${Uri.encodeComponent(bucket)}/o',
      ).replace(queryParameters: query.isEmpty ? null : query);
      final http.Response response = await _httpClient.get(
        uri,
        headers: headers,
      );
      if (response.statusCode == 404) {
        throw FsspecFileNotFoundException(combined, message: response.body);
      }
      if (response.statusCode == 403) {
        throw FsspecPermissionException(combined, response.body);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FileSystemException(
          'GCS list failed (${response.statusCode}): ${response.body}',
          combined,
        );
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        break;
      }
      final Object? items = decoded['items'];
      if (items is List) {
        for (final Object? item in items) {
          if (item is! Map) {
            continue;
          }
          final Map<String, Object?> infoMap = _objectJsonToInfo(
            bucket,
            item.map((Object? k, Object? v) => MapEntry('$k', v)),
          );
          final String fullName = '${infoMap['name']}';
          if (_withinMaxDepth(combined, fullName, maxdepth)) {
            entries[fullName] = infoMap;
          }
        }
      }
      final Object? nextToken = decoded['nextPageToken'];
      pageToken = nextToken is String && nextToken.isNotEmpty
          ? nextToken
          : null;
    } while (pageToken != null);

    final List<String> sortedKeys = entries.keys.toList()..sort();
    if (detail) {
      return <String, Map<String, Object?>>{
        for (final String k in sortedKeys) k: entries[k]!,
      };
    }
    return sortedKeys;
  }

  @override
  Future<void> rmFile(String path) async {
    final String normalized = stripProtocol(path);
    final (String bucket, String key) = _splitBucketAndKey(normalized);
    final Uri uri = Uri.parse(
      '$endpointUrl/storage/v1/b/${Uri.encodeComponent(bucket)}/o/${Uri.encodeComponent(key)}',
    );
    final http.Response response = await _httpClient.delete(
      uri,
      headers: await _authHeaders(),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized, message: response.body);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized, response.body);
    }
    throw FileSystemException(
      'GCS delete failed (${response.statusCode}): ${response.body}',
      normalized,
    );
  }

  @override
  Future<void> setxattrs(
    String path, {
    String? contentType,
    Map<String, String>? metadata,
  }) async {
    final String normalized = stripProtocol(path);
    final (String bucket, String key) = _splitBucketAndKey(normalized);
    final Uri uri = Uri.parse(
      '$endpointUrl/storage/v1/b/${Uri.encodeComponent(bucket)}/o/${Uri.encodeComponent(key)}',
    );
    final Map<String, Object?> payload = <String, Object?>{
      'contentType': ?contentType,
      'metadata': ?metadata,
    };
    final http.Response response = await _httpClient.patch(
      uri,
      headers: <String, String>{
        ...await _authHeaders(),
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized, message: response.body);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized, response.body);
    }
    throw FileSystemException(
      'GCS patch metadata failed (${response.statusCode}): ${response.body}',
      normalized,
    );
  }
}

/// Pure Dart REST [FilesystemProtocol] implementation for Amazon S3 (`s3://` /
/// `s3a://`) with native AWS Signature Version 4 (SigV4) signing.
class S3FsspecFilesystem extends FilesystemProtocol {
  /// Creates an [S3FsspecFilesystem].
  S3FsspecFilesystem({
    String? accessKeyId,
    String? secretAccessKey,
    String? sessionToken,
    String? region,
    String? endpointUrl,
    bool? forcePathStyle,
    this.anonymous = false,
    http.Client? httpClient,
    DateTime Function()? nowProvider,
  }) : accessKeyId =
           accessKeyId ?? Platform.environment['AWS_ACCESS_KEY_ID']?.trim(),
       secretAccessKey =
           secretAccessKey ??
           Platform.environment['AWS_SECRET_ACCESS_KEY']?.trim(),
       sessionToken =
           sessionToken ?? Platform.environment['AWS_SESSION_TOKEN']?.trim(),
       region =
           region ??
           Platform.environment['AWS_REGION']?.trim() ??
           Platform.environment['AWS_DEFAULT_REGION']?.trim() ??
           'us-east-1',
       endpointUrl = _normalizeEndpoint(
         endpointUrl ?? Platform.environment['AWS_ENDPOINT_URL'],
       ),
       forcePathStyle =
           forcePathStyle ??
           (_normalizeEndpoint(
                 endpointUrl ?? Platform.environment['AWS_ENDPOINT_URL'],
               ) !=
               null),
       _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _nowProvider = nowProvider ?? (() => DateTime.now().toUtc());

  /// Creates an [S3FsspecFilesystem] from fsspec-style [storageOptions].
  factory S3FsspecFilesystem.fromStorageOptions(
    Map<String, Object?>? storageOptions, {
    http.Client? httpClient,
    DateTime Function()? nowProvider,
  }) {
    final String? accessKeyId = _readStringOption(
      storageOptions,
      const <String>['key', 'access_key_id', 'accessKeyId'],
      envKeys: const <String>['AWS_ACCESS_KEY_ID'],
    );
    final String? secretAccessKey = _readStringOption(
      storageOptions,
      const <String>['secret', 'secret_access_key', 'secretAccessKey'],
      envKeys: const <String>['AWS_SECRET_ACCESS_KEY'],
    );
    final String? sessionToken = _readStringOption(
      storageOptions,
      const <String>['token', 'session_token', 'sessionToken'],
      envKeys: const <String>['AWS_SESSION_TOKEN'],
    );
    final String? region = _readStringOption(
      storageOptions,
      const <String>['region', 'region_name', 'regionName'],
      envKeys: const <String>['AWS_REGION', 'AWS_DEFAULT_REGION'],
    );
    final String? endpointUrl = _readStringOption(
      storageOptions,
      const <String>['endpoint_url', 'endpointUrl'],
      envKeys: const <String>['AWS_ENDPOINT_URL'],
    );
    final bool? forcePathStyle = _readBoolOption(storageOptions, const <String>[
      'force_path_style',
      'forcePathStyle',
    ]);
    final bool anon =
        _readBoolOption(storageOptions, const <String>['anon', 'anonymous']) ??
        false;

    return S3FsspecFilesystem(
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken,
      region: region,
      endpointUrl: endpointUrl,
      forcePathStyle: forcePathStyle,
      anonymous: anon,
      httpClient: httpClient,
      nowProvider: nowProvider,
    );
  }

  static String? _normalizeEndpoint(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return _stripTrailingSlash(raw);
  }

  /// AWS access key ID used for SigV4 signing.
  final String? accessKeyId;

  /// AWS secret access key used for SigV4 signing.
  final String? secretAccessKey;

  /// Optional AWS STS session token.
  final String? sessionToken;

  /// AWS signing region (defaults to `us-east-1`).
  final String region;

  /// Optional custom S3-compatible endpoint URL (e.g. MinIO, LocalStack).
  final String? endpointUrl;

  /// Whether to use path-style URLs (`/{bucket}/{key}`) instead of
  /// virtual-hosted-style URLs (`{bucket}.s3.{region}.amazonaws.com/{key}`).
  final bool forcePathStyle;

  /// When `true`, skips SigV4 signing and sends unsigned requests.
  final bool anonymous;

  final http.Client _httpClient;
  final bool _ownsClient;
  final DateTime Function() _nowProvider;
  final Map<String, Map<String, String>> _metadataCache =
      <String, Map<String, String>>{};

  /// Closes the underlying HTTP client if owned by this instance.
  void close() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  @override
  Object? get protocol => const <String>['s3', 's3a'];

  @override
  String stripProtocol(String path) => _normalizeObjectPath(path);

  @override
  String unstripProtocol(String path) => 's3://${stripProtocol(path)}';

  @override
  void invalidateCache([String? path]) {
    if (path == null) {
      _metadataCache.clear();
    } else {
      _metadataCache.remove(stripProtocol(path));
    }
  }

  Uri _buildUri(
    String bucket, [
    String key = '',
    Map<String, String>? queryParams,
  ]) {
    final String encodedKey = _encodePathSegments(key);
    Uri base;
    if (endpointUrl != null) {
      final String pathPart = encodedKey.isEmpty
          ? '/${Uri.encodeComponent(bucket)}'
          : '/${Uri.encodeComponent(bucket)}/$encodedKey';
      base = Uri.parse('$endpointUrl$pathPart');
    } else if (forcePathStyle) {
      final String pathPart = encodedKey.isEmpty
          ? '/${Uri.encodeComponent(bucket)}'
          : '/${Uri.encodeComponent(bucket)}/$encodedKey';
      base = Uri.parse('https://s3.$region.amazonaws.com$pathPart');
    } else {
      final String pathPart = encodedKey.isEmpty ? '/' : '/$encodedKey';
      base = Uri.parse('https://$bucket.s3.$region.amazonaws.com$pathPart');
    }
    if (queryParams != null && queryParams.isNotEmpty) {
      return base.replace(queryParameters: queryParams);
    }
    return base;
  }

  Map<String, String> _signHeaders({
    required String method,
    required Uri uri,
    required List<int> bodyBytes,
    Map<String, String> extraHeaders = const <String, String>{},
  }) {
    final Map<String, String> headers = <String, String>{...extraHeaders};
    if (anonymous ||
        accessKeyId == null ||
        accessKeyId!.isEmpty ||
        secretAccessKey == null ||
        secretAccessKey!.isEmpty) {
      return headers;
    }

    final DateTime now = _nowProvider().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final String dateStamp =
        '${now.year.toString().padLeft(4, '0')}${two(now.month)}${two(now.day)}';
    final String amzDate =
        '${dateStamp}T${two(now.hour)}${two(now.minute)}${two(now.second)}Z';

    final String payloadHash = sha256.convert(bodyBytes).toString();
    final bool isDefaultPort =
        !uri.hasPort ||
        (uri.scheme == 'http' && uri.port == 80) ||
        (uri.scheme == 'https' && uri.port == 443);
    final String hostHeader = isDefaultPort
        ? uri.host
        : '${uri.host}:${uri.port}';

    headers['x-amz-date'] = amzDate;
    headers['x-amz-content-sha256'] = payloadHash;
    if (sessionToken != null && sessionToken!.isNotEmpty) {
      headers['x-amz-security-token'] = sessionToken!;
    }

    // Build canonical headers map (lowercased, trimmed).
    final Map<String, String> lowerHeaders = <String, String>{
      'host': hostHeader,
    };
    headers.forEach((String k, String v) {
      lowerHeaders[k.toLowerCase().trim()] = v.trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
    });
    final List<String> sortedHeaderNames = lowerHeaders.keys.toList()..sort();
    final String canonicalHeaders = sortedHeaderNames
        .map((String k) => '$k:${lowerHeaders[k]}\n')
        .join();
    final String signedHeaders = sortedHeaderNames.join(';');

    // Canonical URI (path segments RFC 3986 encoded).
    final String rawPath = uri.path.isEmpty ? '/' : uri.path;
    final String canonicalUri = _awsUriEncode(
      Uri.decodeFull(rawPath),
      encodeSlash: false,
    );

    // Canonical query string (sorted by encoded key, then encoded value).
    final List<(String, String)> queryPairs = <(String, String)>[];
    uri.queryParametersAll.forEach((String k, List<String> values) {
      final String ek = _awsUriEncode(k);
      if (values.isEmpty) {
        queryPairs.add((ek, ''));
      } else {
        for (final String v in values) {
          queryPairs.add((ek, _awsUriEncode(v)));
        }
      }
    });
    queryPairs.sort(((String, String) a, (String, String) b) {
      final int cmp = a.$1.compareTo(b.$1);
      return cmp != 0 ? cmp : a.$2.compareTo(b.$2);
    });
    final String canonicalQueryString = queryPairs
        .map(((String, String) p) => '${p.$1}=${p.$2}')
        .join('&');

    final String canonicalRequest = <String>[
      method.toUpperCase(),
      canonicalUri,
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final String credentialScope = '$dateStamp/$region/s3/aws4_request';
    final String stringToSign = <String>[
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    List<int> hmacSha256(List<int> key, String message) {
      return Hmac(sha256, key).convert(utf8.encode(message)).bytes;
    }

    final List<int> kDate = hmacSha256(
      utf8.encode('AWS4$secretAccessKey'),
      dateStamp,
    );
    final List<int> kRegion = hmacSha256(kDate, region);
    final List<int> kService = hmacSha256(kRegion, 's3');
    final List<int> kSigning = hmacSha256(kService, 'aws4_request');
    final String signature = Hmac(
      sha256,
      kSigning,
    ).convert(utf8.encode(stringToSign)).toString();

    headers['Authorization'] =
        'AWS4-HMAC-SHA256 Credential=$accessKeyId/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';
    return headers;
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    List<int> bodyBytes = const <int>[],
    Map<String, String> headers = const <String, String>{},
  }) async {
    final Map<String, String> signedHeaders = _signHeaders(
      method: method,
      uri: uri,
      bodyBytes: bodyBytes,
      extraHeaders: headers,
    );
    final http.Request request = http.Request(method, uri);
    request.headers.addAll(signedHeaders);
    if (bodyBytes.isNotEmpty) {
      request.bodyBytes = bodyBytes;
    }
    final http.StreamedResponse streamed = await _httpClient.send(request);
    return http.Response.fromStream(streamed);
  }

  Future<void> _putObject(
    String path,
    List<int> data, {
    required bool exclusive,
    String? contentType,
    Map<String, String>? metadata,
  }) async {
    final String normalized = stripProtocol(path);
    final (String bucket, String key) = _splitBucketAndKey(normalized);
    if (bucket.isEmpty || key.isEmpty) {
      throw ArgumentError('S3 path must include bucket and key: $path');
    }
    final Map<String, String> headers = <String, String>{
      'content-type': (contentType != null && contentType.isNotEmpty)
          ? contentType
          : _defaultOctetStream,
      if (exclusive) 'if-none-match': '*',
    };
    if (metadata != null) {
      metadata.forEach((String k, String v) {
        final String s3Key = k.toLowerCase().replaceAll('_', '-');
        headers['x-amz-meta-$s3Key'] = v;
      });
    }
    final Uri uri = _buildUri(bucket, key);
    final http.Response response = await _send(
      'PUT',
      uri,
      bodyBytes: data,
      headers: headers,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      _metadataCache.remove(normalized);
      return;
    }
    if (response.statusCode == 412) {
      throw FsspecFileExistsException(
        normalized,
        message: 'S3 PreconditionFailed (412): ${response.body}',
      );
    }
    if (response.statusCode == 409) {
      if (response.body.contains('ConditionalRequestConflict')) {
        throw S3ConditionalRequestConflictException(normalized, response.body);
      }
      throw FsspecFileExistsException(normalized, message: response.body);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized, response.body);
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized, message: response.body);
    }
    throw FileSystemException(
      'S3 PUT failed (${response.statusCode}): ${response.body}',
      normalized,
    );
  }

  @override
  Future<void> pipeFile(
    String path,
    List<int> data, {
    String mode = 'overwrite',
    String? contentType,
    Map<String, String>? metadata,
  }) {
    return _putObject(
      path,
      data,
      exclusive: mode == 'create',
      contentType: contentType,
      metadata: metadata,
    );
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
    final Object? rawCt =
        contentSettings?['content_type'] ?? contentSettings?['contentType'];
    final String? contentType = rawCt is String && rawCt.isNotEmpty
        ? rawCt
        : null;
    final bool exclusive = mode.contains('x') || generation == 0;
    return _CloudWriteStream(
      (List<int> data) => _putObject(
        path,
        data,
        exclusive: exclusive,
        contentType: contentType,
        metadata: metadata,
      ),
    );
  }

  @override
  Future<List<int>> catFile(String path) async {
    final String normalized = stripProtocol(path);
    final (String bucket, String key) = _splitBucketAndKey(normalized);
    final Uri uri = _buildUri(bucket, key);
    final http.Response response = await _send('GET', uri);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized, message: response.body);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized, response.body);
    }
    throw FileSystemException(
      'S3 GET failed (${response.statusCode}): ${response.body}',
      normalized,
    );
  }

  @override
  Future<Map<String, Object?>> info(String path) async {
    final String normalized = stripProtocol(path);
    final (String bucket, String key) = _splitBucketAndKey(normalized);
    if (bucket.isEmpty || key.isEmpty) {
      throw FsspecFileNotFoundException(normalized);
    }
    final Uri uri = _buildUri(bucket, key);
    final http.Response response = await _send('HEAD', uri);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final Map<String, String> userMeta = <String, String>{};
      response.headers.forEach((String k, String v) {
        final String lower = k.toLowerCase();
        if (lower.startsWith('x-amz-meta-')) {
          userMeta[lower.substring('x-amz-meta-'.length)] = v;
        }
      });
      _metadataCache[normalized] = Map<String, String>.unmodifiable(userMeta);

      final int size =
          int.tryParse(response.headers['content-length'] ?? '0') ?? 0;
      final String? contentType = response.headers['content-type'];
      final DateTime? lastModified = _tryParseHttpOrIsoDate(
        response.headers['last-modified'],
      );
      return <String, Object?>{
        'name': normalized,
        'type': 'file',
        'size': size,
        'ContentLength': size,
        if (contentType != null && contentType.isNotEmpty)
          'ContentType': contentType,
        'LastModified': ?lastModified,
        'Metadata': Map<String, String>.from(userMeta),
      };
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized);
    }
    throw FileSystemException(
      'S3 HEAD failed (${response.statusCode})',
      normalized,
    );
  }

  @override
  Future<Map<String, String>> metadata(String path) async {
    final String normalized = stripProtocol(path);
    final Map<String, String>? cached = _metadataCache[normalized];
    if (cached != null) {
      return Map<String, String>.from(cached);
    }
    final Map<String, Object?> infoMap = await info(normalized);
    final Object? rawMeta = infoMap['Metadata'];
    if (rawMeta is Map) {
      return <String, String>{
        for (final MapEntry<Object?, Object?> entry in rawMeta.entries)
          if (entry.key != null && entry.value != null)
            '${entry.key}': '${entry.value}',
      };
    }
    return const <String, String>{};
  }

  @override
  Future<Object> find(
    String path, {
    int? maxdepth,
    bool withdirs = false,
    bool detail = false,
    String? prefix,
  }) async {
    final String combined = _combinePrefix(path, prefix);
    final (String bucket, String keyPrefix) = _splitBucketAndKey(combined);
    if (bucket.isEmpty) {
      return detail ? <String, Map<String, Object?>>{} : <String>[];
    }

    final Map<String, Map<String, Object?>> entries =
        <String, Map<String, Object?>>{};
    String? continuationToken;

    do {
      final Map<String, String> query = <String, String>{
        'list-type': '2',
        if (keyPrefix.isNotEmpty) 'prefix': keyPrefix,
        if (continuationToken != null && continuationToken.isNotEmpty)
          'continuation-token': continuationToken,
      };
      final Uri uri = _buildUri(bucket, '', query);
      final http.Response response = await _send('GET', uri);
      if (response.statusCode == 404) {
        throw FsspecFileNotFoundException(combined, message: response.body);
      }
      if (response.statusCode == 403) {
        throw FsspecPermissionException(combined, response.body);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FileSystemException(
          'S3 ListObjectsV2 failed (${response.statusCode}): ${response.body}',
          combined,
        );
      }

      final String xml = response.body;
      for (final String block in _extractXmlBlocks(xml, 'Contents')) {
        final String? objKey = _extractXmlTag(block, 'Key');
        if (objKey == null || objKey.isEmpty) {
          continue;
        }
        final String fullName = '$bucket/$objKey';
        if (!_withinMaxDepth(combined, fullName, maxdepth)) {
          continue;
        }
        final int size =
            int.tryParse(_extractXmlTag(block, 'Size') ?? '0') ?? 0;
        final DateTime? lastModified = _tryParseHttpOrIsoDate(
          _extractXmlTag(block, 'LastModified'),
        );
        entries[fullName] = <String, Object?>{
          'name': fullName,
          'type': 'file',
          'size': size,
          'ContentLength': size,
          'LastModified': ?lastModified,
        };
      }

      final bool isTruncated =
          (_extractXmlTag(xml, 'IsTruncated') ?? '').toLowerCase() == 'true';
      continuationToken = isTruncated
          ? _extractXmlTag(xml, 'NextContinuationToken')
          : null;
    } while (continuationToken != null && continuationToken.isNotEmpty);

    final List<String> sortedKeys = entries.keys.toList()..sort();
    if (detail) {
      return <String, Map<String, Object?>>{
        for (final String k in sortedKeys) k: entries[k]!,
      };
    }
    return sortedKeys;
  }

  @override
  Future<void> rmFile(String path) async {
    final String normalized = stripProtocol(path);
    final (String bucket, String key) = _splitBucketAndKey(normalized);
    final Uri uri = _buildUri(bucket, key);
    final http.Response response = await _send('DELETE', uri);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      _metadataCache.remove(normalized);
      return;
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized, message: response.body);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized, response.body);
    }
    throw FileSystemException(
      'S3 DELETE failed (${response.statusCode}): ${response.body}',
      normalized,
    );
  }
}

/// Pure Dart REST [FilesystemProtocol] implementation for Azure Blob Storage
/// (`abfs://`, `abfss://`, `az://`) with native SharedKey HMAC-SHA256 signing,
/// SAS token, and Bearer token authentication.
class AzureBlobFsspecFilesystem extends FilesystemProtocol {
  /// Creates an [AzureBlobFsspecFilesystem].
  AzureBlobFsspecFilesystem({
    String? accountName,
    String? accountKey,
    String? sasToken,
    String? bearerToken,
    String? endpointUrl,
    this.apiVersion = '2023-11-03',
    http.Client? httpClient,
    DateTime Function()? nowProvider,
  }) : accountName =
           accountName ??
           Platform.environment['AZURE_STORAGE_ACCOUNT_NAME']?.trim(),
       accountKey =
           accountKey ??
           Platform.environment['AZURE_STORAGE_ACCOUNT_KEY']?.trim(),
       sasToken = _normalizeSasToken(
         sasToken ?? Platform.environment['AZURE_STORAGE_SAS_TOKEN'],
       ),
       bearerToken = bearerToken?.trim(),
       endpointUrl = _normalizeAzureEndpoint(
         endpointUrl ?? Platform.environment['AZURE_STORAGE_BLOB_ENDPOINT'],
       ),
       _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _nowProvider = nowProvider ?? (() => DateTime.now().toUtc());

  /// Creates an [AzureBlobFsspecFilesystem] from fsspec-style [storageOptions].
  factory AzureBlobFsspecFilesystem.fromStorageOptions(
    Map<String, Object?>? storageOptions, {
    http.Client? httpClient,
    DateTime Function()? nowProvider,
  }) {
    final String? accountName = _readStringOption(
      storageOptions,
      const <String>['account_name', 'accountName'],
      envKeys: const <String>['AZURE_STORAGE_ACCOUNT_NAME'],
    );
    final String? accountKey = _readStringOption(
      storageOptions,
      const <String>['account_key', 'accountKey'],
      envKeys: const <String>['AZURE_STORAGE_ACCOUNT_KEY'],
    );
    final String? sasToken = _readStringOption(
      storageOptions,
      const <String>['sas_token', 'sasToken'],
      envKeys: const <String>['AZURE_STORAGE_SAS_TOKEN'],
    );
    final String? bearerToken = _readStringOption(
      storageOptions,
      const <String>['bearer_token', 'bearerToken', 'token'],
    );
    final String? endpointUrl = _readStringOption(
      storageOptions,
      const <String>['endpoint_url', 'endpointUrl', 'blob_endpoint'],
      envKeys: const <String>['AZURE_STORAGE_BLOB_ENDPOINT'],
    );
    return AzureBlobFsspecFilesystem(
      accountName: accountName,
      accountKey: accountKey,
      sasToken: sasToken,
      bearerToken: bearerToken,
      endpointUrl: endpointUrl,
      httpClient: httpClient,
      nowProvider: nowProvider,
    );
  }

  static String? _normalizeSasToken(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final String trimmed = raw.trim();
    return trimmed.startsWith('?') ? trimmed.substring(1) : trimmed;
  }

  static String? _normalizeAzureEndpoint(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return _stripTrailingSlash(raw);
  }

  /// Azure Storage account name.
  final String? accountName;

  /// Base64-encoded Azure Storage account key for SharedKey signing.
  final String? accountKey;

  /// Optional SAS query string (without leading `?`).
  final String? sasToken;

  /// Optional Entra ID / OAuth2 bearer token.
  final String? bearerToken;

  /// Optional custom Blob Storage endpoint URL (e.g. Azurite or test server).
  final String? endpointUrl;

  /// Azure Storage REST API version sent in `x-ms-version`.
  final String apiVersion;

  final http.Client _httpClient;
  final bool _ownsClient;
  final DateTime Function() _nowProvider;

  /// Closes the underlying HTTP client if owned by this instance.
  void close() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  @override
  Object? get protocol => const <String>['abfs', 'abfss', 'az'];

  @override
  String? get backendVersion => '2026.8.0';

  @override
  String stripProtocol(String path) => _normalizeObjectPath(path);

  @override
  String unstripProtocol(String path) => 'abfs://${stripProtocol(path)}';

  @override
  void invalidateCache([String? path]) {}

  String get _resolvedBaseUrl {
    if (endpointUrl != null && endpointUrl!.isNotEmpty) {
      return endpointUrl!;
    }
    if (accountName != null && accountName!.isNotEmpty) {
      return 'https://$accountName.blob.core.windows.net';
    }
    throw StateError(
      'AzureBlobFsspecFilesystem requires either accountName '
      '(AZURE_STORAGE_ACCOUNT_NAME) or endpointUrl '
      '(AZURE_STORAGE_BLOB_ENDPOINT).',
    );
  }

  Uri _buildUri(
    String container, [
    String blob = '',
    Map<String, String>? queryParams,
  ]) {
    final String encodedBlob = _encodePathSegments(blob);
    final String pathPart = encodedBlob.isEmpty
        ? '/${Uri.encodeComponent(container)}'
        : '/${Uri.encodeComponent(container)}/$encodedBlob';
    final Uri base = Uri.parse('$_resolvedBaseUrl$pathPart');

    final Map<String, String> mergedQuery = <String, String>{};
    if (queryParams != null) {
      mergedQuery.addAll(queryParams);
    }
    if (sasToken != null && sasToken!.isNotEmpty) {
      final Map<String, String> sasParams = Uri.splitQueryString(sasToken!);
      mergedQuery.addAll(sasParams);
    }
    if (mergedQuery.isEmpty) {
      return base;
    }
    return base.replace(queryParameters: mergedQuery);
  }

  Map<String, String> _signHeaders({
    required String method,
    required Uri uri,
    required int contentLength,
    Map<String, String> extraHeaders = const <String, String>{},
  }) {
    final Map<String, String> headers = <String, String>{
      'x-ms-date': HttpDate.format(_nowProvider().toUtc()),
      'x-ms-version': apiVersion,
      ...extraHeaders,
    };

    if (accountKey != null &&
        accountKey!.isNotEmpty &&
        accountName != null &&
        accountName!.isNotEmpty) {
      final Map<String, String> lower = <String, String>{
        for (final MapEntry<String, String> entry in headers.entries)
          entry.key.toLowerCase().trim(): entry.value.trim(),
      };
      final List<String> xmsKeys =
          lower.keys.where((String k) => k.startsWith('x-ms-')).toList()
            ..sort();
      final String canonicalizedHeaders = xmsKeys
          .map((String k) => '$k:${lower[k]}\n')
          .join();

      final String resourcePath = uri.path.startsWith('/$accountName/')
          ? uri.path
          : '/$accountName${uri.path}';
      final StringBuffer canonicalizedResource = StringBuffer(resourcePath);
      if (uri.queryParametersAll.isNotEmpty) {
        final Map<String, List<String>> lowerParams = <String, List<String>>{};
        uri.queryParametersAll.forEach((String k, List<String> vals) {
          lowerParams
              .putIfAbsent(k.toLowerCase(), () => <String>[])
              .addAll(vals);
        });
        final List<String> sortedParamKeys = lowerParams.keys.toList()..sort();
        for (final String k in sortedParamKeys) {
          final List<String> sortedVals = List<String>.from(lowerParams[k]!)
            ..sort();
          canonicalizedResource.write('\n$k:${sortedVals.join(',')}');
        }
      }

      final String contentLengthStr = contentLength > 0 ? '$contentLength' : '';
      final String stringToSign = <String>[
        method.toUpperCase(),
        lower['content-encoding'] ?? '',
        lower['content-language'] ?? '',
        contentLengthStr,
        lower['content-md5'] ?? '',
        lower['content-type'] ?? '',
        '', // Date (empty when x-ms-date is used)
        lower['if-modified-since'] ?? '',
        lower['if-match'] ?? '',
        lower['if-none-match'] ?? '',
        lower['if-unmodified-since'] ?? '',
        lower['range'] ?? '',
        '$canonicalizedHeaders${canonicalizedResource.toString()}',
      ].join('\n');

      final List<int> keyBytes = base64.decode(accountKey!);
      final Digest digest = Hmac(
        sha256,
        keyBytes,
      ).convert(utf8.encode(stringToSign));
      final String signature = base64.encode(digest.bytes);
      headers['Authorization'] = 'SharedKey $accountName:$signature';
    } else if (bearerToken != null && bearerToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearerToken';
    }

    return headers;
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    List<int> bodyBytes = const <int>[],
    Map<String, String> headers = const <String, String>{},
  }) async {
    final Map<String, String> signedHeaders = _signHeaders(
      method: method,
      uri: uri,
      contentLength: bodyBytes.length,
      extraHeaders: headers,
    );
    final http.Request request = http.Request(method, uri);
    request.headers.addAll(signedHeaders);
    if (bodyBytes.isNotEmpty) {
      request.bodyBytes = bodyBytes;
    }
    final http.StreamedResponse streamed = await _httpClient.send(request);
    return http.Response.fromStream(streamed);
  }

  String _extractAzureErrorCode(http.Response response) {
    final String? fromHeader = response.headers['x-ms-error-code']?.trim();
    if (fromHeader != null && fromHeader.isNotEmpty) {
      return fromHeader;
    }
    final String? fromXml = _extractXmlTag(response.body, 'Code')?.trim();
    if (fromXml != null && fromXml.isNotEmpty) {
      return fromXml;
    }
    return response.statusCode == 409 ? 'BlobAlreadyExists' : 'ConditionNotMet';
  }

  Future<void> _putBlob(
    String path,
    List<int> data, {
    required bool exclusive,
    String? contentType,
    Map<String, String>? metadata,
  }) async {
    final String normalized = stripProtocol(path);
    final (String container, String blob) = _splitBucketAndKey(normalized);
    if (container.isEmpty || blob.isEmpty) {
      throw ArgumentError(
        'Azure Blob path must include container and blob: $path',
      );
    }
    final Map<String, String> headers = <String, String>{
      'x-ms-blob-type': 'BlockBlob',
      'content-type': (contentType != null && contentType.isNotEmpty)
          ? contentType
          : _defaultOctetStream,
      if (exclusive) 'if-none-match': '*',
    };
    if (metadata != null) {
      metadata.forEach((String k, String v) {
        headers['x-ms-meta-$k'] = v;
      });
    }
    final Uri uri = _buildUri(container, blob);
    final http.Response response = await _send(
      'PUT',
      uri,
      bodyBytes: data,
      headers: headers,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    if (response.statusCode == 409 || response.statusCode == 412) {
      final String errorCode = _extractAzureErrorCode(response);
      throw AzureStorageException(errorCode, response.body);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized, response.body);
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized, message: response.body);
    }
    throw FileSystemException(
      'Azure PUT blob failed (${response.statusCode}): ${response.body}',
      normalized,
    );
  }

  @override
  Future<void> pipeFile(
    String path,
    List<int> data, {
    String mode = 'overwrite',
    String? contentType,
    Map<String, String>? metadata,
  }) {
    return _putBlob(
      path,
      data,
      exclusive: mode == 'create',
      contentType: contentType,
      metadata: metadata,
    );
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
    final Object? rawCt =
        contentSettings?['content_type'] ?? contentSettings?['contentType'];
    final String? contentType = rawCt is String && rawCt.isNotEmpty
        ? rawCt
        : null;
    final bool exclusive = mode.contains('x') || generation == 0;
    return _CloudWriteStream(
      (List<int> data) => _putBlob(
        path,
        data,
        exclusive: exclusive,
        contentType: contentType,
        metadata: metadata,
      ),
    );
  }

  @override
  Future<List<int>> catFile(String path) async {
    final String normalized = stripProtocol(path);
    final (String container, String blob) = _splitBucketAndKey(normalized);
    final Uri uri = _buildUri(container, blob);
    final http.Response response = await _send('GET', uri);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized, message: response.body);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized, response.body);
    }
    throw FileSystemException(
      'Azure GET blob failed (${response.statusCode}): ${response.body}',
      normalized,
    );
  }

  @override
  Future<Map<String, Object?>> info(String path) async {
    final String normalized = stripProtocol(path);
    final (String container, String blob) = _splitBucketAndKey(normalized);
    if (container.isEmpty || blob.isEmpty) {
      throw FsspecFileNotFoundException(normalized);
    }
    final Uri uri = _buildUri(container, blob);
    final http.Response response = await _send('HEAD', uri);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final Map<String, String> userMeta = <String, String>{};
      response.headers.forEach((String k, String v) {
        final String lower = k.toLowerCase();
        if (lower.startsWith('x-ms-meta-')) {
          userMeta[lower.substring('x-ms-meta-'.length)] = v;
        }
      });
      final int size =
          int.tryParse(response.headers['content-length'] ?? '0') ?? 0;
      final String? contentType = response.headers['content-type'];
      final DateTime? creationTime = _tryParseHttpOrIsoDate(
        response.headers['x-ms-creation-time'] ??
            response.headers['last-modified'],
      );
      return <String, Object?>{
        'name': normalized,
        'type': 'file',
        'size': size,
        'metadata': userMeta,
        'content_settings': <String, Object?>{
          if (contentType != null && contentType.isNotEmpty)
            'content_type': contentType,
        },
        'creation_time': ?creationTime,
      };
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized);
    }
    throw FileSystemException(
      'Azure HEAD blob failed (${response.statusCode})',
      normalized,
    );
  }

  Map<String, String> _parseAzureMetadataXml(String blobBlock) {
    final String? metadataBlock = _extractXmlTag(blobBlock, 'Metadata');
    if (metadataBlock == null || metadataBlock.isEmpty) {
      return <String, String>{};
    }
    final Map<String, String> result = <String, String>{};
    final RegExp entryPattern = RegExp(
      r'<([A-Za-z_][A-Za-z0-9_.-]*)>([\s\S]*?)</\1>',
      multiLine: true,
    );
    for (final RegExpMatch match in entryPattern.allMatches(metadataBlock)) {
      result[match.group(1)!] = _unescapeXml(match.group(2)!);
    }
    return result;
  }

  @override
  Future<Object> find(
    String path, {
    int? maxdepth,
    bool withdirs = false,
    bool detail = false,
    String? prefix,
  }) async {
    final String combined = _combinePrefix(path, prefix);
    final (String container, String blobPrefix) = _splitBucketAndKey(combined);
    if (container.isEmpty) {
      return detail ? <String, Map<String, Object?>>{} : <String>[];
    }

    final Map<String, Map<String, Object?>> entries =
        <String, Map<String, Object?>>{};
    String? nextMarker;

    do {
      final Map<String, String> query = <String, String>{
        'restype': 'container',
        'comp': 'list',
        'include': 'metadata',
        if (blobPrefix.isNotEmpty) 'prefix': blobPrefix,
        if (nextMarker != null && nextMarker.isNotEmpty) 'marker': nextMarker,
      };
      final Uri uri = _buildUri(container, '', query);
      final http.Response response = await _send('GET', uri);
      if (response.statusCode == 404) {
        throw FsspecFileNotFoundException(combined, message: response.body);
      }
      if (response.statusCode == 403) {
        throw FsspecPermissionException(combined, response.body);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FileSystemException(
          'Azure ListBlobs failed (${response.statusCode}): ${response.body}',
          combined,
        );
      }

      final String xml = response.body;
      for (final String block in _extractXmlBlocks(xml, 'Blob')) {
        final String? blobName = _extractXmlTag(block, 'Name');
        if (blobName == null || blobName.isEmpty) {
          continue;
        }
        final String fullName = '$container/$blobName';
        if (!_withinMaxDepth(combined, fullName, maxdepth)) {
          continue;
        }
        final String props = _extractXmlTag(block, 'Properties') ?? '';
        final int size =
            int.tryParse(_extractXmlTag(props, 'Content-Length') ?? '0') ?? 0;
        final String? contentType = _extractXmlTag(props, 'Content-Type');
        final DateTime? creationTime = _tryParseHttpOrIsoDate(
          _extractXmlTag(props, 'Creation-Time') ??
              _extractXmlTag(props, 'Last-Modified'),
        );
        final Map<String, String> userMeta = _parseAzureMetadataXml(block);
        entries[fullName] = <String, Object?>{
          'name': fullName,
          'type': 'file',
          'size': size,
          'metadata': userMeta,
          'content_settings': <String, Object?>{
            if (contentType != null && contentType.isNotEmpty)
              'content_type': contentType,
          },
          'creation_time': ?creationTime,
        };
      }

      final String? marker = _extractXmlTag(xml, 'NextMarker')?.trim();
      nextMarker = (marker != null && marker.isNotEmpty) ? marker : null;
    } while (nextMarker != null);

    final List<String> sortedKeys = entries.keys.toList()..sort();
    if (detail) {
      return <String, Map<String, Object?>>{
        for (final String k in sortedKeys) k: entries[k]!,
      };
    }
    return sortedKeys;
  }

  @override
  Future<void> rmFile(String path) async {
    final String normalized = stripProtocol(path);
    final (String container, String blob) = _splitBucketAndKey(normalized);
    final Uri uri = _buildUri(container, blob);
    final http.Response response = await _send('DELETE', uri);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    if (response.statusCode == 404) {
      throw FsspecFileNotFoundException(normalized, message: response.body);
    }
    if (response.statusCode == 403) {
      throw FsspecPermissionException(normalized, response.body);
    }
    throw FileSystemException(
      'Azure DELETE blob failed (${response.statusCode}): ${response.body}',
      normalized,
    );
  }
}
