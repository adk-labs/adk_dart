import 'dart:convert';

import '../errors/input_validation_error.dart';
import '../types/content.dart';
import 'base_artifact_service.dart';

class GcsArtifactService extends BaseArtifactService {
  GcsArtifactService(this.bucketName);

  final String bucketName;
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
    final List<int> versions = await listVersions(
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
      fileUri = parsedUri;
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

  @override
  Future<Part?> loadArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    int? versionToLoad = version;
    if (versionToLoad == null) {
      final List<int> versions = await listVersions(
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

  @override
  Future<List<String>> listArtifactKeys({
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

  @override
  Future<void> deleteArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final List<int> versions = await listVersions(
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

  @override
  Future<List<int>> listVersions({
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

  @override
  Future<List<ArtifactVersion>> listArtifactVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) async {
    final List<int> versions = await listVersions(
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

  @override
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) async {
    int? versionToRead = version;
    if (versionToRead == null) {
      final List<int> versions = await listVersions(
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

  String _removeVersionSegment(String blobPathSuffix) {
    final List<String> parts = blobPathSuffix.split('/');
    if (parts.length <= 1) {
      return blobPathSuffix;
    }
    return parts.sublist(0, parts.length - 1).join('/');
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
