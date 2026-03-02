/// Artifact service contracts and shared metadata models.
library;

import '../types/content.dart';

/// Metadata describing one persisted artifact version.
class ArtifactVersion {
  /// Creates an artifact version descriptor.
  ArtifactVersion({
    required this.version,
    required this.canonicalUri,
    Map<String, Object?>? customMetadata,
    double? createTime,
    this.mimeType,
  }) : customMetadata = customMetadata ?? <String, Object?>{},
       createTime = createTime ?? DateTime.now().millisecondsSinceEpoch / 1000;

  /// Artifact version number.
  int version;

  /// Canonical URI for this artifact version.
  String canonicalUri;

  /// Provider-specific custom metadata.
  Map<String, Object?> customMetadata;

  /// Creation time in seconds since epoch.
  double createTime;

  /// Optional MIME type for artifact payload.
  String? mimeType;

  /// Returns a copied version descriptor with optional overrides.
  ArtifactVersion copyWith({
    int? version,
    String? canonicalUri,
    Map<String, Object?>? customMetadata,
    double? createTime,
    Object? mimeType = _sentinel,
  }) {
    return ArtifactVersion(
      version: version ?? this.version,
      canonicalUri: canonicalUri ?? this.canonicalUri,
      customMetadata:
          customMetadata ?? Map<String, Object?>.from(this.customMetadata),
      createTime: createTime ?? this.createTime,
      mimeType: identical(mimeType, _sentinel)
          ? this.mimeType
          : mimeType as String?,
    );
  }
}

/// Base contract for artifact persistence services.
abstract class BaseArtifactService {
  /// Creates an artifact persistence service.
  BaseArtifactService();

  /// Saves [artifact] and returns the assigned version number.
  Future<int> saveArtifact({
    required String appName,
    required String userId,
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  });

  /// Loads an artifact by name and optional [version].
  Future<Part?> loadArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  });

  /// Lists artifact keys available in the scoped namespace.
  Future<List<String>> listArtifactKeys({
    required String appName,
    required String userId,
    String? sessionId,
  });

  /// Deletes all versions of one artifact.
  Future<void> deleteArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  });

  /// Lists numeric versions for one artifact key.
  Future<List<int>> listVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  });

  /// Lists full version metadata for one artifact key.
  Future<List<ArtifactVersion>> listArtifactVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  });

  /// Returns metadata for one artifact version.
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  });
}

const Object _sentinel = Object();
