/// Google Cloud Storage (GCS) storage and administrative tools for ADK.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../agents/readonly_context.dart';
import '../../tools/_google_credentials.dart';
import '../../tools/base_tool.dart';
import '../../tools/base_toolset.dart';
import '../../tools/google_tool.dart';
import '../../tools/tool_context.dart';
import '../../version.dart';

/// Token cache key used for GCS credential refresh flow.
const String gcsTokenCacheKey = 'gcs_token_cache';

/// Default OAuth scopes required by GCS tools.
const List<String> gcsDefaultScope = <String>[
  'https://www.googleapis.com/auth/devstorage.full_control',
];

/// Default tool name prefix applied by [GCSToolset] and [GCSAdminToolset].
const String defaultGcsToolNamePrefix = 'gcs';

/// Default User-Agent header value sent by GCS tools.
const String gcsToolUserAgent = 'adk-gcs-tool google-adk/$adkVersion';

/// Capabilities indicating what type of operations are allowed for GCS tools.
enum GCSCapabilities {
  /// Only read operations are allowed.
  readOnly('read_only'),

  /// Both read and write operations are allowed.
  readWrite('read_write');

  /// Creates a capability with its [wireValue].
  const GCSCapabilities(this.wireValue);

  /// Wire representation of this capability.
  final String wireValue;
}

/// Settings for Google Cloud Storage tools.
///
/// ```dart
/// final settings = GCSToolSettings(
///   capabilities: [GCSCapabilities.readWrite],
///   localFileRoot: '/tmp/agent_files',
/// );
/// ```
class GCSToolSettings {
  /// Creates settings for GCS tools.
  GCSToolSettings({
    List<GCSCapabilities>? capabilities,
    this.localFileRoot,
  }) : capabilities = capabilities == null
           ? <GCSCapabilities>[GCSCapabilities.readOnly]
           : List<GCSCapabilities>.from(capabilities);

  /// Allowed capabilities for GCS tools.
  ///
  /// Defaults to `[GCSCapabilities.readOnly]`.
  final List<GCSCapabilities> capabilities;

  /// Directory that local file paths passed to GCS tools resolve under.
  ///
  /// Uploading from and downloading to the local filesystem stays disabled
  /// until this is set. Any path resolving outside this directory is rejected.
  final String? localFileRoot;
}

/// GCS Credentials Configuration for Google API tools.
///
/// ```dart
/// final credentials = GCSCredentialsConfig(
///   externalAccessTokenKey: 'user:gcs_token',
/// );
/// ```
class GCSCredentialsConfig extends BaseGoogleCredentialsConfig {
  /// Creates credential settings for Google Cloud Storage tools.
  GCSCredentialsConfig({
    super.credentials,
    super.externalAccessTokenKey,
    super.clientId,
    super.clientSecret,
    super.scopes,
  }) : super(tokenCacheKey: gcsTokenCacheKey) {
    if (scopes == null || scopes!.isEmpty) {
      scopes = List<String>.from(gcsDefaultScope);
    }
  }
}

/// Paginated list response returned by [GcsClient.listBuckets] or [GcsBucketClient.listBlobs].
class GcsPageResult<T> {
  /// Creates a paginated result with [items] and optional [nextPageToken].
  const GcsPageResult({required this.items, this.nextPageToken});

  /// Items in the current page.
  final List<T> items;

  /// Token for retrieving the next page, if more items exist.
  final String? nextPageToken;
}

/// Injectable blob handle inside a [GcsBucketClient].
abstract class GcsBlobClient {
  /// Creates a GCS blob client.
  GcsBlobClient();

  /// Object name within the bucket.
  String get name;

  /// Object generation number.
  int get generation;

  /// Raw metadata properties of the object.
  Map<String, Object?> get properties;

  /// Uploads string [data] as UTF-8 bytes into this object.
  FutureOr<void> uploadFromString(String data);

  /// Uploads local file contents at [filePath] into this object.
  FutureOr<void> uploadFromFilename(String filePath);

  /// Downloads this object's bytes to a local file at [filePath].
  FutureOr<void> downloadToFilename(String filePath);

  /// Downloads and returns this object's raw bytes.
  FutureOr<List<int>> downloadAsBytes();
}

/// Injectable bucket handle inside a [GcsClient].
abstract class GcsBucketClient {
  /// Creates a GCS bucket client.
  GcsBucketClient();

  /// Bucket name.
  String get name;

  /// Raw metadata properties of the bucket.
  Map<String, Object?> get properties;

  /// Whether object versioning is enabled on the bucket.
  bool get versioningEnabled;

  /// Updates whether object versioning is enabled on the bucket.
  set versioningEnabled(bool value);

  /// Whether uniform bucket-level access is enabled on the bucket.
  bool get uniformBucketLevelAccessEnabled;

  /// Updates whether uniform bucket-level access is enabled on the bucket.
  set uniformBucketLevelAccessEnabled(bool value);

  /// Patches updated properties onto the bucket in storage.
  FutureOr<void> patch();

  /// Deletes the bucket.
  ///
  /// Throws a [StateError] if the bucket is not empty.
  FutureOr<void> delete();

  /// Lists object names in the bucket with optional [prefix], [maxResults], and [pageToken].
  FutureOr<GcsPageResult<String>> listBlobs({
    String? prefix,
    int? maxResults,
    String? pageToken,
  });

  /// Returns an existing [GcsBlobClient] for [objectName] (and optional [generation]), or `null`.
  FutureOr<GcsBlobClient?> getBlob(String objectName, {int? generation});

  /// Returns a writable [GcsBlobClient] handle for [objectName].
  GcsBlobClient blob(String objectName);

  /// Deletes multiple objects named [blobs] from the bucket.
  FutureOr<void> deleteBlobs(List<String> blobs);
}

/// Injectable client interface for Google Cloud Storage operations.
///
/// ```dart
/// final client = GcsClient.inMemory();
/// await client.createBucket('my-bucket', project: 'my-project');
/// ```
abstract class GcsClient {
  /// Creates a GCS client.
  GcsClient();

  /// Creates an in-memory [GcsClient] suitable for local execution and testing.
  factory GcsClient.inMemory() = InMemoryGcsClient;

  /// Lists bucket names with optional [maxResults] and [pageToken].
  FutureOr<GcsPageResult<String>> listBuckets({
    int? maxResults,
    String? pageToken,
  });

  /// Retrieves an existing bucket by [bucketName].
  ///
  /// Throws a [StateError] if the bucket does not exist.
  FutureOr<GcsBucketClient> getBucket(String bucketName);

  /// Returns a bucket reference for [bucketName] without fetching metadata.
  GcsBucketClient bucket(String bucketName);

  /// Creates a new bucket for [bucketName] in [location].
  FutureOr<GcsBucketClient> createBucket(
    String bucketName, {
    String? project,
    String? location,
  });
}

class _InMemoryBlob implements GcsBlobClient {
  _InMemoryBlob({
    required this.bucket,
    required this.name,
    List<int>? bytes,
    int? generation,
    Map<String, Object?>? properties,
  }) : _bytes = bytes ?? <int>[],
       _generation = generation ?? 1,
       _properties = properties ?? <String, Object?>{};

  final _InMemoryBucket bucket;
  @override
  final String name;
  List<int> _bytes;
  int _generation;
  final Map<String, Object?> _properties;

  @override
  int get generation => _generation;

  @override
  Map<String, Object?> get properties => <String, Object?>{
    'name': name,
    'bucket': bucket.name,
    'size': _bytes.length,
    'generation': _generation,
    ..._properties,
  };

  @override
  void uploadFromString(String data) {
    _bytes = utf8.encode(data);
    _generation = bucket._registerBlobWrite(name, this);
  }

  @override
  void uploadFromFilename(String filePath) {
    final File file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('Local source file does not exist', filePath);
    }
    _bytes = file.readAsBytesSync();
    _generation = bucket._registerBlobWrite(name, this);
  }

  @override
  void downloadToFilename(String filePath) {
    final File file = File(filePath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(_bytes);
  }

  @override
  List<int> downloadAsBytes() => List<int>.from(_bytes);
}

class _InMemoryBucket implements GcsBucketClient {
  _InMemoryBucket({
    required this.store,
    required this.name,
    this.project,
    this.location = 'US',
  });

  final Map<String, _InMemoryBucket> store;
  @override
  final String name;
  final String? project;
  final String location;

  @override
  bool versioningEnabled = false;

  @override
  bool uniformBucketLevelAccessEnabled = false;

  final Map<String, _InMemoryBlob> _blobs = <String, _InMemoryBlob>{};
  final Map<(String, int), _InMemoryBlob> _generations =
      <(String, int), _InMemoryBlob>{};
  int _nextGeneration = 1;

  int _registerBlobWrite(String blobName, _InMemoryBlob blob) {
    final int gen = _nextGeneration++;
    _blobs[blobName] = blob;
    _generations[(blobName, gen)] = _InMemoryBlob(
      bucket: this,
      name: blobName,
      bytes: List<int>.from(blob._bytes),
      generation: gen,
      properties: Map<String, Object?>.from(blob._properties),
    );
    return gen;
  }

  @override
  Map<String, Object?> get properties => <String, Object?>{
    'name': name,
    if (project != null) 'projectNumber': project,
    'location': location,
    'versioning': <String, Object?>{'enabled': versioningEnabled},
    'iamConfiguration': <String, Object?>{
      'uniformBucketLevelAccess': <String, Object?>{
        'enabled': uniformBucketLevelAccessEnabled,
      },
    },
  };

  @override
  void patch() {}

  @override
  void delete() {
    if (_blobs.isNotEmpty) {
      throw StateError('The bucket you tried to delete is not empty.');
    }
    store.remove(name);
  }

  @override
  GcsPageResult<String> listBlobs({
    String? prefix,
    int? maxResults,
    String? pageToken,
  }) {
    List<String> names = _blobs.keys.toList()..sort();
    if (prefix != null && prefix.isNotEmpty) {
      names = names.where((String n) => n.startsWith(prefix)).toList();
    }
    return _paginateStrings(
      names,
      maxResults: maxResults,
      pageToken: pageToken,
    );
  }

  @override
  GcsBlobClient? getBlob(String objectName, {int? generation}) {
    if (generation != null) {
      return _generations[(objectName, generation)];
    }
    return _blobs[objectName];
  }

  @override
  GcsBlobClient blob(String objectName) {
    return _blobs[objectName] ?? _InMemoryBlob(bucket: this, name: objectName);
  }

  @override
  void deleteBlobs(List<String> blobs) {
    for (final String b in blobs) {
      if (!_blobs.containsKey(b)) {
        throw StateError('Object $b not found in bucket $name');
      }
      _blobs.remove(b);
    }
  }
}

/// In-memory implementation of [GcsClient] shared by default across calls unless reset.
class InMemoryGcsClient extends GcsClient {
  /// Creates an in-memory GCS client.
  InMemoryGcsClient();

  final Map<String, _InMemoryBucket> _buckets = <String, _InMemoryBucket>{};

  @override
  GcsPageResult<String> listBuckets({int? maxResults, String? pageToken}) {
    final List<String> names = _buckets.keys.toList()..sort();
    return _paginateStrings(
      names,
      maxResults: maxResults,
      pageToken: pageToken,
    );
  }

  @override
  GcsBucketClient getBucket(String bucketName) {
    final _InMemoryBucket? b = _buckets[bucketName];
    if (b == null) {
      throw StateError('Bucket $bucketName not found.');
    }
    return b;
  }

  @override
  GcsBucketClient bucket(String bucketName) {
    return _buckets[bucketName] ??
        _InMemoryBucket(store: _buckets, name: bucketName);
  }

  @override
  GcsBucketClient createBucket(
    String bucketName, {
    String? project,
    String? location,
  }) {
    if (_buckets.containsKey(bucketName)) {
      throw StateError('Bucket $bucketName already exists.');
    }
    final _InMemoryBucket created = _InMemoryBucket(
      store: _buckets,
      name: bucketName,
      project: project,
      location: location ?? 'US',
    );
    _buckets[bucketName] = created;
    return created;
  }
}

GcsPageResult<String> _paginateStrings(
  List<String> items, {
  int? maxResults,
  String? pageToken,
}) {
  final int start = pageToken == null ? 0 : (int.tryParse(pageToken) ?? 0);
  if (start >= items.length) {
    return const GcsPageResult<String>(items: <String>[]);
  }
  if (maxResults == null) {
    return GcsPageResult<String>(items: items.sublist(start));
  }
  final int end = (start + maxResults < items.length)
      ? start + maxResults
      : items.length;
  final String? nextToken = end < items.length ? '$end' : null;
  return GcsPageResult<String>(
    items: items.sublist(start, end),
    nextPageToken: nextToken,
  );
}

/// Factory function signature for resolving a [GcsClient].
typedef GcsClientFactory =
    GcsClient Function({Object? credentials, String? project});

final InMemoryGcsClient _defaultSharedGcsClient = InMemoryGcsClient();
GcsClientFactory _gcsClientFactory = _defaultGcsClientFactory;

GcsClient _defaultGcsClientFactory({Object? credentials, String? project}) {
  return _defaultSharedGcsClient;
}

/// Overrides the [GcsClient] factory used by GCS tools.
void setGcsClientFactory(GcsClientFactory factory) {
  _gcsClientFactory = factory;
}

/// Restores the default [GcsClient] factory.
void resetGcsClientFactory() {
  _gcsClientFactory = _defaultGcsClientFactory;
}

/// Returns a [GcsClient] for [credentials] and optional [project].
GcsClient getGcsClient({Object? credentials, String? project}) {
  return _gcsClientFactory(credentials: credentials, project: project);
}

/// Resolves a model-supplied local file [path] under `settings.localFileRoot`.
///
/// Throws an [ArgumentError] if no root is configured, if [path] names the root
/// itself, or if [path] escapes the root after resolving `..` and symlinks.
String resolveGcsLocalPath(String path, GCSToolSettings? settings) {
  final String? root = settings?.localFileRoot;
  if (root == null || root.trim().isEmpty) {
    throw ArgumentError(
      "Local file access is disabled. Set 'local_file_root' in the GCS tool "
      'settings to let these tools read from or write to the local filesystem.',
    );
  }

  final String resolvedRoot = _canonicalizePath(Directory(root).absolute.path);
  final File candidateFile = File(path).isAbsolute
      ? File(path)
      : File('$resolvedRoot${Platform.pathSeparator}$path');
  final String resolvedCandidate = _canonicalizePath(
    candidateFile.absolute.path,
  );

  if (resolvedCandidate == resolvedRoot) {
    throw ArgumentError(
      'Local file path must name a file under the configured root: $path',
    );
  }
  final String rootWithSep = resolvedRoot.endsWith(Platform.pathSeparator)
      ? resolvedRoot
      : '$resolvedRoot${Platform.pathSeparator}';
  if (!resolvedCandidate.startsWith(rootWithSep)) {
    throw ArgumentError(
      'Local file path escapes the configured root: $path',
    );
  }
  return resolvedCandidate;
}

String _canonicalizePath(String rawPath) {
  final Uri normalizedUri = Uri.file(rawPath).normalizePath();
  String normalized = normalizedUri.toFilePath();
  if (normalized.length > 1 &&
      normalized.endsWith(Platform.pathSeparator)) {
    normalized = normalized.substring(0, normalized.length - 1);
  }

  // Resolve any existing ancestor symlink components so symlinks cannot escape root.
  final File f = File(normalized);
  if (f.existsSync()) {
    return f.resolveSymbolicLinksSync();
  }
  final Directory d = Directory(normalized);
  if (d.existsSync()) {
    return d.resolveSymbolicLinksSync();
  }

  final List<String> tail = <String>[];
  Directory current = f.parent;
  while (!current.existsSync()) {
    final String parentPath = current.parent.path;
    if (parentPath == current.path) {
      break;
    }
    tail.insert(
      0,
      current.uri.pathSegments.where((String s) => s.isNotEmpty).last,
    );
    current = current.parent;
  }
  final String baseResolved = current.existsSync()
      ? current.resolveSymbolicLinksSync()
      : current.path;
  final String fileName = f.uri.pathSegments
      .where((String s) => s.isNotEmpty)
      .last;
  return <String>[baseResolved, ...tail, fileName].join(Platform.pathSeparator);
}

/// Lists GCS bucket names in a Google Cloud project.
Future<Map<String, Object?>> listBuckets({
  required String projectId,
  Object? credentials,
  int? pageSize,
  String? pageToken,
}) async {
  try {
    final GcsClient gcsClient = getGcsClient(
      project: projectId,
      credentials: credentials,
    );
    final GcsPageResult<String> page = await gcsClient.listBuckets(
      maxResults: pageSize,
      pageToken: pageToken,
    );
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': page.items,
      if (pageSize != null &&
          page.nextPageToken != null &&
          page.nextPageToken!.isNotEmpty)
        'next_page_token': page.nextPageToken,
    };
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Gets metadata information about a GCS bucket.
Future<Map<String, Object?>> getBucket({
  required String bucketName,
  Object? credentials,
}) async {
  try {
    final GcsClient gcsClient = getGcsClient(credentials: credentials);
    final GcsBucketClient bucket = await gcsClient.getBucket(bucketName);
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': Map<String, Object?>.from(bucket.properties),
    };
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Creates a new GCS bucket in [projectId].
Future<Map<String, Object?>> createBucket({
  required String projectId,
  required String bucketName,
  Object? credentials,
  String? location,
}) async {
  try {
    final GcsClient gcsClient = getGcsClient(
      project: projectId,
      credentials: credentials,
    );
    final GcsBucketClient newBucket = await gcsClient.createBucket(
      bucketName,
      project: projectId,
      location: location,
    );
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': 'Bucket ${newBucket.name} created successfully.',
    };
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Updates properties of a GCS bucket.
Future<Map<String, Object?>> updateBucket({
  required String bucketName,
  Object? credentials,
  bool? versioningEnabled,
  bool? uniformBucketLevelAccessEnabled,
}) async {
  try {
    final GcsClient gcsClient = getGcsClient(credentials: credentials);
    final GcsBucketClient bucket = await gcsClient.getBucket(bucketName);
    if (versioningEnabled != null) {
      bucket.versioningEnabled = versioningEnabled;
    }
    if (uniformBucketLevelAccessEnabled != null) {
      bucket.uniformBucketLevelAccessEnabled = uniformBucketLevelAccessEnabled;
    }
    if (versioningEnabled != null || uniformBucketLevelAccessEnabled != null) {
      await bucket.patch();
    }
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': 'Bucket ${bucket.name} updated successfully.',
    };
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Deletes a GCS bucket.
Future<Map<String, Object?>> deleteBucket({
  required String bucketName,
  Object? credentials,
}) async {
  try {
    final GcsClient gcsClient = getGcsClient(credentials: credentials);
    final GcsBucketClient bucket = await gcsClient.getBucket(bucketName);
    await bucket.delete();
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': 'Bucket $bucketName deleted successfully.',
    };
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Lists object names in a GCS bucket.
Future<Map<String, Object?>> listObjects({
  required String bucketName,
  Object? credentials,
  String? prefix,
  int? pageSize,
  String? pageToken,
}) async {
  try {
    final GcsClient gcsClient = getGcsClient(credentials: credentials);
    final GcsBucketClient bucket = await gcsClient.getBucket(bucketName);
    final GcsPageResult<String> blobs = await bucket.listBlobs(
      prefix: prefix,
      maxResults: pageSize,
      pageToken: pageToken,
    );
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': blobs.items,
      if (pageSize != null &&
          blobs.nextPageToken != null &&
          blobs.nextPageToken!.isNotEmpty)
        'next_page_token': blobs.nextPageToken,
    };
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Gets metadata information about a GCS object (blob).
Future<Map<String, Object?>> getObjectMetadata({
  required String bucketName,
  required String objectName,
  Object? credentials,
  int? generation,
}) async {
  try {
    final GcsClient gcsClient = getGcsClient(credentials: credentials);
    final GcsBucketClient bucket = await gcsClient.getBucket(bucketName);
    final GcsBlobClient? blob = await bucket.getBlob(
      objectName,
      generation: generation,
    );
    if (blob == null) {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details': 'Object $objectName not found in bucket $bucketName',
      };
    }
    return <String, Object?>{
      'status': 'SUCCESS',
      'results': Map<String, Object?>.from(blob.properties),
    };
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Creates a new object (blob) in a GCS bucket from provided [data] or [sourceFilePath].
Future<Map<String, Object?>> createObject({
  required String bucketName,
  required String objectName,
  Object? credentials,
  String? data,
  String? sourceFilePath,
  GCSToolSettings? settings,
}) async {
  try {
    final GcsClient gcsClient = getGcsClient(credentials: credentials);
    final GcsBucketClient bucket = await gcsClient.getBucket(bucketName);
    final GcsBlobClient blob = bucket.blob(objectName);
    if (sourceFilePath != null) {
      final String resolved = resolveGcsLocalPath(sourceFilePath, settings);
      await blob.uploadFromFilename(resolved);
    } else if (data != null) {
      await blob.uploadFromString(data);
    } else {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details': "Either 'data' or 'source_file_path' must be provided.",
      };
    }

    return <String, Object?>{
      'status': 'SUCCESS',
      'results':
          'Object $objectName created successfully in bucket $bucketName.',
    };
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Gets the content/data of a GCS object (blob).
Future<Map<String, Object?>> getObjectData({
  required String bucketName,
  required String objectName,
  Object? credentials,
  int? generation,
  String? destinationFilePath,
  GCSToolSettings? settings,
}) async {
  try {
    final GcsClient gcsClient = getGcsClient(credentials: credentials);
    final GcsBucketClient bucket = await gcsClient.getBucket(bucketName);
    final GcsBlobClient? blob = await bucket.getBlob(
      objectName,
      generation: generation,
    );
    if (blob == null) {
      return <String, Object?>{
        'status': 'ERROR',
        'error_details': 'Object $objectName not found in bucket $bucketName',
      };
    }

    if (destinationFilePath != null) {
      final String resolved = resolveGcsLocalPath(
        destinationFilePath,
        settings,
      );
      File(resolved).parent.createSync(recursive: true);
      await blob.downloadToFilename(resolved);
      return <String, Object?>{
        'status': 'SUCCESS',
        'results':
            'Object $objectName downloaded successfully to $destinationFilePath.',
      };
    }

    final List<int> rawBytes = await blob.downloadAsBytes();
    try {
      final String content = utf8.decode(rawBytes);
      return <String, Object?>{
        'status': 'SUCCESS',
        'results': content,
        'encoding': 'text',
      };
    } on FormatException {
      return <String, Object?>{
        'status': 'SUCCESS',
        'results': base64Encode(rawBytes),
        'encoding': 'base64',
      };
    }
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Deletes multiple objects (blobs) from a GCS bucket.
Future<Map<String, Object?>> deleteObjects({
  required String bucketName,
  required List<String> objectNames,
  Object? credentials,
}) async {
  try {
    final GcsClient gcsClient = getGcsClient(credentials: credentials);
    final GcsBucketClient bucket = await gcsClient.getBucket(bucketName);
    await bucket.deleteBlobs(objectNames);
    return <String, Object?>{
      'status': 'SUCCESS',
      'results':
          'Objects $objectNames deleted successfully from bucket $bucketName.',
    };
  } catch (ex) {
    return <String, Object?>{'status': 'ERROR', 'error_details': '$ex'};
  }
}

/// Google-credential-aware tool for GCS object storage operations.
class GCSStorageTool extends GoogleTool {
  /// Creates a GCS storage tool.
  GCSStorageTool({
    required super.func,
    required String super.name,
    super.description,
    GCSCredentialsConfig? credentialsConfig,
    GCSToolSettings? gcsToolSettings,
  }) : super(
         credentialsConfig: credentialsConfig,
         toolSettings: gcsToolSettings,
       );

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) {
    return super.run(
      args: _normalizeGcsToolArgs(args),
      toolContext: toolContext,
    );
  }
}

/// Google-credential-aware tool for GCS bucket administration operations.
class GCSAdminTool extends GoogleTool {
  /// Creates a GCS admin tool.
  GCSAdminTool({
    required super.func,
    required String super.name,
    super.description,
    GCSCredentialsConfig? credentialsConfig,
    GCSToolSettings? gcsToolSettings,
  }) : super(
         credentialsConfig: credentialsConfig,
         toolSettings: gcsToolSettings,
       );

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) {
    return super.run(
      args: _normalizeGcsToolArgs(args),
      toolContext: toolContext,
    );
  }
}

Map<String, dynamic> _normalizeGcsToolArgs(Map<String, dynamic> args) {
  final Map<String, dynamic> out = <String, dynamic>{};
  args.forEach((String k, dynamic v) {
    final String camel = k.replaceAllMapped(
      RegExp(r'_([a-z])'),
      (Match m) => m.group(1)!.toUpperCase(),
    );
    out[camel] = v;
  });
  return out;
}

/// GCS Toolset containing tools for interacting with GCS object storage.
///
/// The exposed tool names are:
/// - `create_object`
/// - `get_object_data`
/// - `get_object_metadata`
/// - `list_objects`
/// - `delete_objects`
///
/// ```dart
/// final toolset = GCSToolset(
///   gcsToolSettings: GCSToolSettings(
///     capabilities: [GCSCapabilities.readWrite],
///   ),
/// );
/// final tools = await toolset.getTools();
/// ```
class GCSToolset extends BaseToolset {
  /// Creates a GCS storage toolset.
  GCSToolset({
    super.toolFilter,
    GCSCredentialsConfig? credentialsConfig,
    GCSToolSettings? gcsToolSettings,
  }) : _credentialsConfig = credentialsConfig,
       _toolSettings = gcsToolSettings ?? GCSToolSettings(),
       super(toolNamePrefix: defaultGcsToolNamePrefix);

  final GCSCredentialsConfig? _credentialsConfig;
  final GCSToolSettings _toolSettings;

  /// Configured credentials config, if any.
  GCSCredentialsConfig? get credentialsConfig => _credentialsConfig;

  /// Configured GCS tool settings.
  GCSToolSettings get gcsToolSettings => _toolSettings;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final List<BaseTool> allTools = <BaseTool>[];

    if (_toolSettings.capabilities.contains(GCSCapabilities.readOnly) ||
        _toolSettings.capabilities.contains(GCSCapabilities.readWrite)) {
      allTools.addAll(<BaseTool>[
        GCSStorageTool(
          func: getObjectData,
          name: 'get_object_data',
          description: 'Get the content/data of a GCS object (blob).',
          credentialsConfig: _credentialsConfig,
          gcsToolSettings: _toolSettings,
        ),
        GCSStorageTool(
          func: getObjectMetadata,
          name: 'get_object_metadata',
          description: 'Get metadata information about a GCS object (blob).',
          credentialsConfig: _credentialsConfig,
          gcsToolSettings: _toolSettings,
        ),
        GCSStorageTool(
          func: listObjects,
          name: 'list_objects',
          description: 'List object names in a GCS bucket.',
          credentialsConfig: _credentialsConfig,
          gcsToolSettings: _toolSettings,
        ),
      ]);
    }

    if (_toolSettings.capabilities.contains(GCSCapabilities.readWrite)) {
      allTools.addAll(<BaseTool>[
        GCSStorageTool(
          func: createObject,
          name: 'create_object',
          description:
              'Create a new object (blob) in a GCS bucket from provided data or a local file.',
          credentialsConfig: _credentialsConfig,
          gcsToolSettings: _toolSettings,
        ),
        GCSStorageTool(
          func: deleteObjects,
          name: 'delete_objects',
          description: 'Delete multiple objects (blobs) from a GCS bucket.',
          credentialsConfig: _credentialsConfig,
          gcsToolSettings: _toolSettings,
        ),
      ]);
    }

    return allTools
        .where((BaseTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }
}

/// GCS Admin Toolset containing tools for interacting with GCS buckets.
///
/// The exposed tool names are:
/// - `get_bucket`
/// - `create_bucket`
/// - `update_bucket`
/// - `delete_bucket`
/// - `list_buckets`
///
/// ```dart
/// final adminToolset = GCSAdminToolset(
///   gcsToolSettings: GCSToolSettings(
///     capabilities: [GCSCapabilities.readWrite],
///   ),
/// );
/// final tools = await adminToolset.getTools();
/// ```
class GCSAdminToolset extends BaseToolset {
  /// Creates a GCS admin toolset.
  GCSAdminToolset({
    super.toolFilter,
    GCSCredentialsConfig? credentialsConfig,
    GCSToolSettings? gcsToolSettings,
  }) : _credentialsConfig = credentialsConfig,
       _toolSettings = gcsToolSettings ?? GCSToolSettings(),
       super(toolNamePrefix: defaultGcsToolNamePrefix);

  final GCSCredentialsConfig? _credentialsConfig;
  final GCSToolSettings _toolSettings;

  /// Configured credentials config, if any.
  GCSCredentialsConfig? get credentialsConfig => _credentialsConfig;

  /// Configured GCS tool settings.
  GCSToolSettings get gcsToolSettings => _toolSettings;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final List<BaseTool> allTools = <BaseTool>[];

    if (_toolSettings.capabilities.contains(GCSCapabilities.readOnly) ||
        _toolSettings.capabilities.contains(GCSCapabilities.readWrite)) {
      allTools.addAll(<BaseTool>[
        GCSAdminTool(
          func: getBucket,
          name: 'get_bucket',
          description: 'Get metadata information about a GCS bucket.',
          credentialsConfig: _credentialsConfig,
          gcsToolSettings: _toolSettings,
        ),
        GCSAdminTool(
          func: listBuckets,
          name: 'list_buckets',
          description: 'List GCS bucket names in a Google Cloud project.',
          credentialsConfig: _credentialsConfig,
          gcsToolSettings: _toolSettings,
        ),
      ]);
    }

    if (_toolSettings.capabilities.contains(GCSCapabilities.readWrite)) {
      allTools.addAll(<BaseTool>[
        GCSAdminTool(
          func: createBucket,
          name: 'create_bucket',
          description: 'Create a new GCS bucket.',
          credentialsConfig: _credentialsConfig,
          gcsToolSettings: _toolSettings,
        ),
        GCSAdminTool(
          func: updateBucket,
          name: 'update_bucket',
          description: 'Update properties of a GCS bucket.',
          credentialsConfig: _credentialsConfig,
          gcsToolSettings: _toolSettings,
        ),
        GCSAdminTool(
          func: deleteBucket,
          name: 'delete_bucket',
          description: 'Delete a GCS bucket.',
          credentialsConfig: _credentialsConfig,
          gcsToolSettings: _toolSettings,
        ),
      ]);
    }

    return allTools
        .where((BaseTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }
}
