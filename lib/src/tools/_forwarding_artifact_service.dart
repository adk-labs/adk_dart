import '../artifacts/base_artifact_service.dart';
import '../types/content.dart';
import 'tool_context.dart';

class ForwardingArtifactService extends BaseArtifactService {
  ForwardingArtifactService(this.toolContext);

  final ToolContext toolContext;

  @override
  Future<int> saveArtifact({
    required String appName,
    required String userId,
    required String filename,
    required Part artifact,
    String? sessionId,
    Map<String, Object?>? customMetadata,
  }) {
    return toolContext.saveArtifact(
      filename,
      artifact,
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
  }) {
    return toolContext.loadArtifact(filename, version: version);
  }

  @override
  Future<List<String>> listArtifactKeys({
    required String appName,
    required String userId,
    String? sessionId,
  }) {
    return toolContext.listArtifacts();
  }

  @override
  Future<void> deleteArtifact({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) {
    return toolContext.deleteArtifact(filename);
  }

  @override
  Future<List<int>> listVersions({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
  }) {
    return toolContext.listArtifactVersions(filename);
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
    final List<ArtifactVersion> result = <ArtifactVersion>[];
    for (final int version in versions) {
      final ArtifactVersion? loaded = await getArtifactVersion(
        appName: appName,
        userId: userId,
        filename: filename,
        sessionId: sessionId,
        version: version,
      );
      if (loaded != null) {
        result.add(loaded);
      }
    }
    return result;
  }

  @override
  Future<ArtifactVersion?> getArtifactVersion({
    required String appName,
    required String userId,
    required String filename,
    String? sessionId,
    int? version,
  }) {
    return toolContext.getArtifactVersion(filename, version: version);
  }
}
