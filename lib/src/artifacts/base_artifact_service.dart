import '../types/content.dart';

class ArtifactVersion {
  ArtifactVersion({
    required this.version,
    required this.canonicalUri,
    Map<String, Object?>? customMetadata,
    double? createTime,
    this.mimeType,
  }) : customMetadata = customMetadata ?? <String, Object?>{},
       createTime = createTime ?? DateTime.now().millisecondsSinceEpoch / 1000;

  int version;
  String canonicalUri;
  Map<String, Object?> customMetadata;
  double createTime;
  String? mimeType;

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

abstract class BaseArtifactService {
  Future<int> saveArtifact({
    required String appName,
    required String userId,
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  });

  Future<Part?> loadArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  });

  Future<List<String>> listArtifactKeys({
    required String appName,
    required String userId,
    String? sessionId,
  });

  Future<void> deleteArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  });

  Future<List<int>> listVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  });

  Future<List<ArtifactVersion>> listArtifactVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  });

  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  });
}

const Object _sentinel = Object();
