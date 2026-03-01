import 'dart:convert';
import 'dart:io';

import '../errors/input_validation_error.dart';
import '../types/content.dart';
import '../tools/_google_access_token.dart';
import 'base_artifact_service.dart';

enum GcsArtifactMode { inMemory, live }

class GcsArtifactHttpRequest {
  GcsArtifactHttpRequest({
    required this.method,
    required this.uri,
    Map<String, String>? headers,
    List<int>? bodyBytes,
  }) : headers = headers == null
           ? <String, String>{}
           : Map<String, String>.from(headers),
       bodyBytes = bodyBytes == null
           ? const <int>[]
           : List<int>.from(bodyBytes);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> bodyBytes;
}

class GcsArtifactHttpResponse {
  GcsArtifactHttpResponse({
    required this.statusCode,
    Map<String, String>? headers,
    List<int>? bodyBytes,
  }) : headers = headers == null
           ? <String, String>{}
           : Map<String, String>.from(headers),
       bodyBytes = bodyBytes == null
           ? const <int>[]
           : List<int>.from(bodyBytes);

  final int statusCode;
  final Map<String, String> headers;
  final List<int> bodyBytes;
}

typedef GcsArtifactHttpRequestProvider =
    Future<GcsArtifactHttpResponse> Function(GcsArtifactHttpRequest request);
typedef GcsArtifactAuthHeadersProvider = Future<Map<String, String>> Function();

class GcsArtifactService extends BaseArtifactService {
  GcsArtifactService(
    String bucketName, {
    GcsArtifactMode mode = GcsArtifactMode.live,
    GcsArtifactHttpRequestProvider? httpRequestProvider,
    GcsArtifactAuthHeadersProvider? authHeadersProvider,
    Uri? apiBaseUri,
    Uri? uploadApiBaseUri,
  }) : bucketName = _normalizeBucketName(bucketName),
       _mode = mode,
       _httpRequestProvider = mode == GcsArtifactMode.live
           ? (httpRequestProvider ?? _defaultGcsArtifactHttpRequestProvider)
           : httpRequestProvider,
       _authHeadersProvider = mode == GcsArtifactMode.live
           ? (authHeadersProvider ?? _defaultGcsArtifactAuthHeadersProvider)
           : authHeadersProvider,
       _apiBaseUri = apiBaseUri ?? Uri.parse(_defaultApiBaseUri),
       _uploadApiBaseUri =
           uploadApiBaseUri ?? Uri.parse(_defaultUploadApiBaseUri);

  factory GcsArtifactService.inMemory(String bucketName) {
    return GcsArtifactService(bucketName, mode: GcsArtifactMode.inMemory);
  }

  static const String _defaultApiBaseUri = 'https://storage.googleapis.com';
  static const String _defaultUploadApiBaseUri =
      'https://storage.googleapis.com/upload/storage/v1';
  static const String _fileUriMetadataKey = 'adk_artifact_file_uri';
  static const String _fileMimeTypeMetadataKey = 'adk_artifact_mime_type';

  final String bucketName;
  final GcsArtifactMode _mode;
  final GcsArtifactHttpRequestProvider? _httpRequestProvider;
  final GcsArtifactAuthHeadersProvider? _authHeadersProvider;
  final Uri _apiBaseUri;
  final Uri _uploadApiBaseUri;
  final Map<String, _GcsBlob> _blobs = <String, _GcsBlob>{};

  String? _normalizeMimeType(String? value) {
    final String? trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _canonicalUriForBlob(String blobName, _GcsBlob blob) {
    final String? fileUri = blob.fileUri;
    if (fileUri != null && fileUri.isNotEmpty) {
      return fileUri;
    }
    return 'gs://$bucketName/$blobName';
  }

  bool _fileHasUserNamespace(String filename) {
    return filename.startsWith('user:');
  }

  String _getBlobPrefix(
    String appName,
    String userId,
    String filename,
    String? sessionId,
  ) {
    if (_fileHasUserNamespace(filename)) {
      return '$appName/$userId/user/$filename';
    }
    if (sessionId == null || sessionId.isEmpty) {
      throw InputValidationError(
        'Session ID must be provided for session-scoped artifacts.',
      );
    }
    return '$appName/$userId/$sessionId/$filename';
  }

  String _getBlobName(
    String appName,
    String userId,
    String filename,
    int version,
    String? sessionId,
  ) {
    return '${_getBlobPrefix(appName, userId, filename, sessionId)}/$version';
  }

  @override
  Future<int> saveArtifact({
    required String appName,
    required String userId,
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    if (_mode == GcsArtifactMode.inMemory) {
      return _saveArtifactInMemory(
        appName: appName,
        userId: userId,
        filename: filename,
        artifact: artifact,
        sessionId: sessionId,
        customMetadata: customMetadata,
      );
    }
    return _saveArtifactLive(
      appName: appName,
      userId: userId,
      filename: filename,
      artifact: artifact,
      sessionId: sessionId,
      customMetadata: customMetadata,
    );
  }

  @override
  Future<Part?> loadArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    if (_mode == GcsArtifactMode.inMemory) {
      return _loadArtifactInMemory(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
        version: version,
      );
    }
    return _loadArtifactLive(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
      version: version,
    );
  }

  @override
  Future<List<String>> listArtifactKeys({
    required String appName,
    required String userId,
    String? sessionId,
  }) async {
    if (_mode == GcsArtifactMode.inMemory) {
      return _listArtifactKeysInMemory(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
    }
    return _listArtifactKeysLive(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  @override
  Future<void> deleteArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    if (_mode == GcsArtifactMode.inMemory) {
      return _deleteArtifactInMemory(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
      );
    }
    return _deleteArtifactLive(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
  }

  @override
  Future<List<int>> listVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    if (_mode == GcsArtifactMode.inMemory) {
      return _listVersionsInMemory(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
      );
    }
    return _listVersionsLive(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
  }

  @override
  Future<List<ArtifactVersion>> listArtifactVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    if (_mode == GcsArtifactMode.inMemory) {
      return _listArtifactVersionsInMemory(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
      );
    }
    return _listArtifactVersionsLive(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
  }

  @override
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    if (_mode == GcsArtifactMode.inMemory) {
      return _getArtifactVersionInMemory(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
        version: version,
      );
    }
    return _getArtifactVersionLive(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
      version: version,
    );
  }

  Future<int> _saveArtifactInMemory({
    required String appName,
    required String userId,
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    final List<int> versions = await _listVersionsInMemory(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
    final int version = versions.isEmpty ? 0 : (versions.last + 1);

    late final List<int> data;
    String? contentType;
    String? fileUri;
    if (artifact.inlineData != null) {
      data = List<int>.from(artifact.inlineData!.data);
      contentType =
          _normalizeMimeType(artifact.inlineData!.mimeType) ??
          'application/octet-stream';
    } else if (artifact.text != null) {
      data = utf8.encode(artifact.text!);
      contentType = 'text/plain';
    } else if (artifact.fileData != null) {
      final String parsedUri = artifact.fileData!.fileUri.trim();
      if (parsedUri.isEmpty) {
        throw InputValidationError(
          'Artifact file_data.file_uri must be provided.',
        );
      }
      data = const <int>[];
      contentType = _normalizeMimeType(artifact.fileData!.mimeType);
      fileUri = _normalizeCanonicalFileUri(parsedUri);
    } else {
      throw InputValidationError(
        'Artifact must have either inline_data, text, or file_data.',
      );
    }

    final String blobName = _getBlobName(
      appName,
      userId,
      filename,
      version,
      sessionId,
    );
    _blobs[blobName] = _GcsBlob(
      data: data,
      contentType: contentType,
      createTime: DateTime.now().toUtc(),
      metadata: customMetadata == null
          ? <String, Object?>{}
          : Map<String, Object?>.from(customMetadata),
      fileUri: fileUri,
    );

    return version;
  }

  Future<int> _saveArtifactLive({
    required String appName,
    required String userId,
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) async {
    final List<int> versions = await _listVersionsLive(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );
    final int version = versions.isEmpty ? 0 : (versions.last + 1);

    late final List<int> data;
    String? contentType;
    String? fileUri;
    if (artifact.inlineData != null) {
      data = List<int>.from(artifact.inlineData!.data);
      contentType =
          _normalizeMimeType(artifact.inlineData!.mimeType) ??
          'application/octet-stream';
    } else if (artifact.text != null) {
      data = utf8.encode(artifact.text!);
      contentType = 'text/plain';
    } else if (artifact.fileData != null) {
      final String parsedUri = artifact.fileData!.fileUri.trim();
      if (parsedUri.isEmpty) {
        throw InputValidationError(
          'Artifact file_data.file_uri must be provided.',
        );
      }
      data = const <int>[];
      contentType = _normalizeMimeType(artifact.fileData!.mimeType);
      fileUri = _normalizeCanonicalFileUri(parsedUri);
    } else {
      throw InputValidationError(
        'Artifact must have either inline_data, text, or file_data.',
      );
    }

    final String blobName = _getBlobName(
      appName,
      userId,
      filename,
      version,
      sessionId,
    );

    final GcsArtifactHttpResponse uploadResponse = await _sendLiveRequest(
      method: 'POST',
      uri: _buildUploadObjectUri(blobName),
      headers: <String, String>{
        'content-type': contentType ?? 'application/octet-stream',
      },
      bodyBytes: data,
    );
    if (uploadResponse.statusCode >= 400) {
      throw StateError(
        'GCS artifact upload failed (${uploadResponse.statusCode}) for '
        'gs://$bucketName/$blobName.',
      );
    }

    final Map<String, String> metadata = _toGcsMetadata(customMetadata);
    if (fileUri != null) {
      metadata[_fileUriMetadataKey] = fileUri;
    }
    if (artifact.fileData != null && contentType != null) {
      metadata[_fileMimeTypeMetadataKey] = contentType;
    }
    if (metadata.isNotEmpty) {
      final Map<String, Object?> patchBody = <String, Object?>{
        'metadata': metadata,
      };
      if (contentType != null) {
        patchBody['contentType'] = contentType;
      }
      final GcsArtifactHttpResponse patchResponse = await _sendLiveRequest(
        method: 'PATCH',
        uri: _buildObjectMetadataUri(blobName),
        headers: const <String, String>{'content-type': 'application/json'},
        bodyBytes: utf8.encode(jsonEncode(patchBody)),
      );
      if (patchResponse.statusCode >= 400) {
        throw StateError(
          'GCS artifact metadata patch failed (${patchResponse.statusCode}) '
          'for gs://$bucketName/$blobName.',
        );
      }
    }

    return version;
  }

  Future<Part?> _loadArtifactInMemory({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    int? versionToLoad = version;
    if (versionToLoad == null) {
      final List<int> versions = await _listVersionsInMemory(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
      );
      if (versions.isEmpty) {
        return null;
      }
      versionToLoad = versions.last;
    }

    final String blobName = _getBlobName(
      appName,
      userId,
      filename,
      versionToLoad,
      sessionId,
    );
    final _GcsBlob? blob = _blobs[blobName];
    if (blob == null) {
      return null;
    }
    final String? fileUri = blob.fileUri;
    if (fileUri != null && fileUri.isNotEmpty) {
      return Part.fromFileData(fileUri: fileUri, mimeType: blob.contentType);
    }
    if (blob.data.isEmpty) {
      return null;
    }

    return Part.fromInlineData(
      mimeType: blob.contentType ?? 'application/octet-stream',
      data: blob.data,
    );
  }

  Future<Part?> _loadArtifactLive({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    int? versionToLoad = version;
    if (versionToLoad == null) {
      final List<int> versions = await _listVersionsLive(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
      );
      if (versions.isEmpty) {
        return null;
      }
      versionToLoad = versions.last;
    }

    final String blobName = _getBlobName(
      appName,
      userId,
      filename,
      versionToLoad,
      sessionId,
    );
    final Map<String, Object?>? blobMetadata = await _getObjectMetadata(
      blobName,
    );
    if (blobMetadata == null) {
      return null;
    }

    final Map<String, String> metadata = _asStringMap(blobMetadata['metadata']);
    final String? fileUri = _normalizeMimeType(metadata[_fileUriMetadataKey]);
    final String? resolvedMimeType =
        _normalizeMimeType(_asNullableString(blobMetadata['contentType'])) ??
        _normalizeMimeType(metadata[_fileMimeTypeMetadataKey]);
    if (fileUri != null) {
      return Part.fromFileData(
        fileUri: _normalizeCanonicalFileUri(fileUri),
        mimeType: resolvedMimeType,
      );
    }

    final GcsArtifactHttpResponse mediaResponse = await _sendLiveRequest(
      method: 'GET',
      uri: _buildObjectMediaUri(blobName),
    );
    if (mediaResponse.statusCode == 404) {
      return null;
    }
    if (mediaResponse.statusCode >= 400) {
      throw StateError(
        'GCS artifact load failed (${mediaResponse.statusCode}) for '
        'gs://$bucketName/$blobName.',
      );
    }
    if (mediaResponse.bodyBytes.isEmpty) {
      return null;
    }

    return Part.fromInlineData(
      mimeType: resolvedMimeType ?? 'application/octet-stream',
      data: mediaResponse.bodyBytes,
    );
  }

  Future<List<String>> _listArtifactKeysInMemory({
    required String appName,
    required String userId,
    String? sessionId,
  }) async {
    final Set<String> filenames = <String>{};

    if (sessionId != null && sessionId.isNotEmpty) {
      final String sessionPrefix = '$appName/$userId/$sessionId/';
      for (final String blobName in _blobs.keys) {
        if (!blobName.startsWith(sessionPrefix)) {
          continue;
        }
        final String rest = blobName.substring(sessionPrefix.length);
        filenames.add(_removeVersionSegment(rest));
      }
    }

    final String userPrefix = '$appName/$userId/user/';
    for (final String blobName in _blobs.keys) {
      if (!blobName.startsWith(userPrefix)) {
        continue;
      }
      final String rest = blobName.substring(userPrefix.length);
      filenames.add(_removeVersionSegment(rest));
    }

    final List<String> sorted = filenames.toList()..sort();
    return sorted;
  }

  Future<List<String>> _listArtifactKeysLive({
    required String appName,
    required String userId,
    String? sessionId,
  }) async {
    final Set<String> filenames = <String>{};

    if (sessionId != null && sessionId.isNotEmpty) {
      final String sessionPrefix = '$appName/$userId/$sessionId/';
      final List<String> sessionBlobNames = await _listObjectNames(
        prefix: sessionPrefix,
      );
      for (final String blobName in sessionBlobNames) {
        if (!blobName.startsWith(sessionPrefix)) {
          continue;
        }
        final String rest = blobName.substring(sessionPrefix.length);
        filenames.add(_removeVersionSegment(rest));
      }
    }

    final String userPrefix = '$appName/$userId/user/';
    final List<String> userBlobNames = await _listObjectNames(
      prefix: userPrefix,
    );
    for (final String blobName in userBlobNames) {
      if (!blobName.startsWith(userPrefix)) {
        continue;
      }
      final String rest = blobName.substring(userPrefix.length);
      filenames.add(_removeVersionSegment(rest));
    }

    final List<String> sorted = filenames.toList()..sort();
    return sorted;
  }

  Future<void> _deleteArtifactInMemory({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final List<int> versions = await _listVersionsInMemory(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );

    for (final int version in versions) {
      final String blobName = _getBlobName(
        appName,
        userId,
        filename,
        version,
        sessionId,
      );
      _blobs.remove(blobName);
    }
  }

  Future<void> _deleteArtifactLive({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final List<int> versions = await _listVersionsLive(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );

    for (final int version in versions) {
      final String blobName = _getBlobName(
        appName,
        userId,
        filename,
        version,
        sessionId,
      );
      final GcsArtifactHttpResponse response = await _sendLiveRequest(
        method: 'DELETE',
        uri: _buildObjectMetadataUri(blobName),
      );
      if (response.statusCode == 404) {
        continue;
      }
      if (response.statusCode >= 400) {
        throw StateError(
          'GCS artifact delete failed (${response.statusCode}) for '
          'gs://$bucketName/$blobName.',
        );
      }
    }
  }

  Future<List<int>> _listVersionsInMemory({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final String prefix = _getBlobPrefix(appName, userId, filename, sessionId);

    final List<int> versions = <int>[];
    for (final String blobName in _blobs.keys) {
      if (!blobName.startsWith('$prefix/')) {
        continue;
      }
      final String tail = blobName.split('/').last;
      final int? version = int.tryParse(tail);
      if (version != null) {
        versions.add(version);
      }
    }
    versions.sort();
    return versions;
  }

  Future<List<int>> _listVersionsLive({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final String prefix = _getBlobPrefix(appName, userId, filename, sessionId);
    final List<String> blobNames = await _listObjectNames(prefix: '$prefix/');
    final List<int> versions = <int>[];
    for (final String blobName in blobNames) {
      if (!blobName.startsWith('$prefix/')) {
        continue;
      }
      final String tail = blobName.split('/').last;
      final int? version = int.tryParse(tail);
      if (version != null) {
        versions.add(version);
      }
    }
    versions.sort();
    return versions;
  }

  Future<List<ArtifactVersion>> _listArtifactVersionsInMemory({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final List<int> versions = await _listVersionsInMemory(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );

    final List<ArtifactVersion> artifactVersions = <ArtifactVersion>[];
    for (final int version in versions) {
      final String blobName = _getBlobName(
        appName,
        userId,
        filename,
        version,
        sessionId,
      );
      final _GcsBlob? blob = _blobs[blobName];
      if (blob == null) {
        continue;
      }
      artifactVersions.add(
        ArtifactVersion(
          version: version,
          canonicalUri: _canonicalUriForBlob(blobName, blob),
          createTime: blob.createTime.millisecondsSinceEpoch / 1000,
          mimeType: blob.contentType,
          customMetadata: Map<String, Object?>.from(blob.metadata),
        ),
      );
    }

    artifactVersions.sort((ArtifactVersion a, ArtifactVersion b) {
      return a.version.compareTo(b.version);
    });
    return artifactVersions;
  }

  Future<List<ArtifactVersion>> _listArtifactVersionsLive({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final List<int> versions = await _listVersionsLive(
      appName: appName,
      userId: userId,
      filename: filename,
      sessionId: sessionId,
    );

    final List<ArtifactVersion> artifactVersions = <ArtifactVersion>[];
    for (final int version in versions) {
      final ArtifactVersion? artifactVersion = await _getArtifactVersionLive(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
        version: version,
      );
      if (artifactVersion != null) {
        artifactVersions.add(artifactVersion);
      }
    }
    artifactVersions.sort((ArtifactVersion a, ArtifactVersion b) {
      return a.version.compareTo(b.version);
    });
    return artifactVersions;
  }

  Future<ArtifactVersion?> _getArtifactVersionInMemory({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    int? versionToRead = version;
    if (versionToRead == null) {
      final List<int> versions = await _listVersionsInMemory(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
      );
      if (versions.isEmpty) {
        return null;
      }
      versionToRead = versions.last;
    }

    final String blobName = _getBlobName(
      appName,
      userId,
      filename,
      versionToRead,
      sessionId,
    );
    final _GcsBlob? blob = _blobs[blobName];
    if (blob == null) {
      return null;
    }

    return ArtifactVersion(
      version: versionToRead,
      canonicalUri: _canonicalUriForBlob(blobName, blob),
      createTime: blob.createTime.millisecondsSinceEpoch / 1000,
      mimeType: blob.contentType,
      customMetadata: Map<String, Object?>.from(blob.metadata),
    );
  }

  Future<ArtifactVersion?> _getArtifactVersionLive({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    int? versionToRead = version;
    if (versionToRead == null) {
      final List<int> versions = await _listVersionsLive(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
      );
      if (versions.isEmpty) {
        return null;
      }
      versionToRead = versions.last;
    }

    final String blobName = _getBlobName(
      appName,
      userId,
      filename,
      versionToRead,
      sessionId,
    );
    final Map<String, Object?>? blobMetadata = await _getObjectMetadata(
      blobName,
    );
    if (blobMetadata == null) {
      return null;
    }

    final Map<String, String> metadata = _asStringMap(blobMetadata['metadata']);
    final String? fileUri = _normalizeMimeType(metadata[_fileUriMetadataKey]);
    final String canonicalUri = fileUri == null
        ? 'gs://$bucketName/$blobName'
        : _normalizeCanonicalFileUri(fileUri);

    return ArtifactVersion(
      version: versionToRead,
      canonicalUri: canonicalUri,
      createTime: _resolveCreateTimeSeconds(blobMetadata),
      mimeType:
          _normalizeMimeType(_asNullableString(blobMetadata['contentType'])) ??
          _normalizeMimeType(metadata[_fileMimeTypeMetadataKey]),
      customMetadata: _toArtifactCustomMetadata(metadata),
    );
  }

  Future<List<String>> _listObjectNames({required String prefix}) async {
    final GcsArtifactHttpResponse response = await _sendLiveRequest(
      method: 'GET',
      uri: _buildListObjectsUri(prefix: prefix),
    );
    if (response.statusCode == 404) {
      return const <String>[];
    }
    if (response.statusCode >= 400) {
      throw StateError(
        'GCS object list failed (${response.statusCode}) for prefix '
        '$prefix.',
      );
    }

    final Map<String, Object?> decoded = _decodeJsonObject(response.bodyBytes);
    final List<Object?> items = decoded['items'] is List
        ? List<Object?>.from(decoded['items'] as List)
        : const <Object?>[];
    final List<String> names = <String>[];
    for (final Object? item in items) {
      if (item is! Map) {
        continue;
      }
      final Map<String, Object?> map = item.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
      final String? name = _asNullableString(map['name']);
      if (name == null || name.isEmpty) {
        continue;
      }
      names.add(name);
    }
    names.sort();
    return names;
  }

  Future<Map<String, Object?>?> _getObjectMetadata(String blobName) async {
    final GcsArtifactHttpResponse response = await _sendLiveRequest(
      method: 'GET',
      uri: _buildObjectMetadataUri(blobName),
    );
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode >= 400) {
      throw StateError(
        'GCS object metadata read failed (${response.statusCode}) for '
        'gs://$bucketName/$blobName.',
      );
    }
    return _decodeJsonObject(response.bodyBytes);
  }

  Future<GcsArtifactHttpResponse> _sendLiveRequest({
    required String method,
    required Uri uri,
    Map<String, String>? headers,
    List<int>? bodyBytes,
  }) async {
    final GcsArtifactHttpRequestProvider requestProvider =
        _httpRequestProvider ??
        (GcsArtifactHttpRequest request) =>
            Future<GcsArtifactHttpResponse>.error(
              StateError('Missing GCS HTTP request provider.'),
            );
    final GcsArtifactAuthHeadersProvider authProvider =
        _authHeadersProvider ??
        () => Future<Map<String, String>>.error(
          StateError('Missing GCS auth headers provider.'),
        );
    final Map<String, String> authHeaders = await authProvider();
    if (authHeaders.isEmpty) {
      throw StateError(
        'GcsArtifactService live mode requires non-empty auth headers.',
      );
    }

    return requestProvider(
      GcsArtifactHttpRequest(
        method: method,
        uri: uri,
        headers: <String, String>{
          ...authHeaders,
          if (headers != null) ...headers,
        },
        bodyBytes: bodyBytes,
      ),
    );
  }

  Uri _buildUploadObjectUri(String blobName) {
    return _buildUri(
      baseUri: _uploadApiBaseUri,
      pathSegments: <String>['b', bucketName, 'o'],
      queryParameters: <String, String>{
        'uploadType': 'media',
        'name': blobName,
      },
    );
  }

  Uri _buildListObjectsUri({required String prefix}) {
    return _buildUri(
      baseUri: _apiBaseUri,
      pathSegments: <String>['storage', 'v1', 'b', bucketName, 'o'],
      queryParameters: <String, String>{'prefix': prefix},
    );
  }

  Uri _buildObjectMetadataUri(String blobName) {
    return _buildUri(
      baseUri: _apiBaseUri,
      pathSegments: <String>['storage', 'v1', 'b', bucketName, 'o', blobName],
    );
  }

  Uri _buildObjectMediaUri(String blobName) {
    return _buildUri(
      baseUri: _apiBaseUri,
      pathSegments: <String>['storage', 'v1', 'b', bucketName, 'o', blobName],
      queryParameters: const <String, String>{'alt': 'media'},
    );
  }

  Uri _buildUri({
    required Uri baseUri,
    required List<String> pathSegments,
    Map<String, String>? queryParameters,
  }) {
    final String base = baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    final String path = pathSegments
        .where((String segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final Uri uri = Uri.parse('$base/$path');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        ...queryParameters,
      },
    );
  }

  Map<String, String> _toGcsMetadata(Map<String, Object?>? customMetadata) {
    final Map<String, String> metadata = <String, String>{};
    if (customMetadata == null) {
      return metadata;
    }
    for (final MapEntry<String, Object?> entry in customMetadata.entries) {
      final String key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      final Object? value = entry.value;
      if (value == null) {
        continue;
      }
      metadata[key] = '$value';
    }
    return metadata;
  }

  Map<String, Object?> _toArtifactCustomMetadata(Map<String, String> metadata) {
    final Map<String, Object?> custom = <String, Object?>{};
    for (final MapEntry<String, String> entry in metadata.entries) {
      if (entry.key == _fileUriMetadataKey ||
          entry.key == _fileMimeTypeMetadataKey) {
        continue;
      }
      custom[entry.key] = entry.value;
    }
    return custom;
  }

  Map<String, String> _asStringMap(Object? value) {
    if (value is! Map) {
      return <String, String>{};
    }
    final Map<String, String> result = <String, String>{};
    value.forEach((Object? key, Object? item) {
      if (key == null || item == null) {
        return;
      }
      result['$key'] = '$item';
    });
    return result;
  }

  Map<String, Object?> _decodeJsonObject(List<int> bodyBytes) {
    if (bodyBytes.isEmpty) {
      return <String, Object?>{};
    }
    final String text = utf8.decode(bodyBytes, allowMalformed: true).trim();
    if (text.isEmpty) {
      return <String, Object?>{};
    }
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is! Map) {
        return <String, Object?>{};
      }
      return decoded.map(
        (Object? key, Object? value) => MapEntry('$key', value),
      );
    } on FormatException {
      return <String, Object?>{};
    }
  }

  String? _asNullableString(Object? value) {
    if (value == null) {
      return null;
    }
    final String asString = '$value';
    if (asString.isEmpty) {
      return null;
    }
    return asString;
  }

  double _resolveCreateTimeSeconds(Map<String, Object?> metadata) {
    final String? timeCreated = _asNullableString(metadata['timeCreated']);
    if (timeCreated == null) {
      return DateTime.now().millisecondsSinceEpoch / 1000;
    }
    final DateTime? parsed = DateTime.tryParse(timeCreated);
    if (parsed == null) {
      return DateTime.now().millisecondsSinceEpoch / 1000;
    }
    return parsed.toUtc().millisecondsSinceEpoch / 1000;
  }

  String _removeVersionSegment(String blobPathSuffix) {
    final List<String> parts = blobPathSuffix.split('/');
    if (parts.length <= 1) {
      return blobPathSuffix;
    }
    return parts.sublist(0, parts.length - 1).join('/');
  }

  static String _normalizeBucketName(String value) {
    String bucketName = value.trim();
    if (bucketName.startsWith('gs://')) {
      bucketName = bucketName.substring('gs://'.length);
    }
    bucketName = bucketName.replaceFirst(RegExp(r'^/+'), '');
    bucketName = bucketName.replaceFirst(RegExp(r'/+$'), '');
    final int slashIndex = bucketName.indexOf('/');
    if (slashIndex >= 0) {
      bucketName = bucketName.substring(0, slashIndex);
    }
    if (bucketName.isEmpty) {
      throw ArgumentError('bucketName must not be empty.');
    }
    return bucketName;
  }

  static String _normalizeCanonicalFileUri(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    final Uri? parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.scheme.toLowerCase() != 'gs') {
      return trimmed;
    }
    final String host = parsed.host.trim();
    if (host.isEmpty) {
      return trimmed;
    }
    final List<String> normalizedSegments = parsed.pathSegments
        .where((String segment) => segment.isNotEmpty)
        .toList(growable: false);
    return Uri(
      scheme: 'gs',
      host: host,
      pathSegments: normalizedSegments,
    ).toString();
  }
}

class _GcsBlob {
  _GcsBlob({
    required this.data,
    required this.contentType,
    required this.createTime,
    required this.metadata,
    this.fileUri,
  });

  final List<int> data;
  final String? contentType;
  final DateTime createTime;
  final Map<String, Object?> metadata;
  final String? fileUri;
}

Future<GcsArtifactHttpResponse> _defaultGcsArtifactHttpRequestProvider(
  GcsArtifactHttpRequest request,
) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest rawRequest = await client.openUrl(
      request.method,
      request.uri,
    );
    request.headers.forEach(rawRequest.headers.set);
    if (request.bodyBytes.isNotEmpty) {
      rawRequest.add(request.bodyBytes);
    }

    final HttpClientResponse response = await rawRequest.close();
    final List<int> bodyBytes = await response.fold<List<int>>(<int>[], (
      List<int> previous,
      List<int> element,
    ) {
      previous.addAll(element);
      return previous;
    });
    final Map<String, String> headers = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      if (values.isNotEmpty) {
        headers[name] = values.join(',');
      }
    });

    return GcsArtifactHttpResponse(
      statusCode: response.statusCode,
      headers: headers,
      bodyBytes: bodyBytes,
    );
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, String>> _defaultGcsArtifactAuthHeadersProvider() async {
  final String token = await resolveDefaultGoogleAccessToken(
    scopes: const <String>[
      'https://www.googleapis.com/auth/devstorage.read_write',
    ],
  );
  return <String, String>{
    HttpHeaders.authorizationHeader: 'Bearer $token',
    HttpHeaders.acceptHeader: ContentType.json.mimeType,
    HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
  };
}
