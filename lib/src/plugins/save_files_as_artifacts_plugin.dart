import '../agents/invocation_context.dart';
import '../artifacts/base_artifact_service.dart';
import '../types/content.dart';
import 'base_plugin.dart';

const Set<String> _modelAccessibleUriSchemes = <String>{'gs', 'https', 'http'};

class SaveFilesAsArtifactsPlugin extends BasePlugin {
  SaveFilesAsArtifactsPlugin({super.name = 'save_files_as_artifacts_plugin'});

  @override
  Future<Content?> onUserMessageCallback({
    required InvocationContext invocationContext,
    required Content userMessage,
  }) async {
    final artifactService = invocationContext.artifactService;
    if (artifactService == null) {
      return userMessage;
    }

    if (userMessage.parts.isEmpty) {
      return null;
    }

    final List<Part> newParts = <Part>[];
    bool modified = false;

    for (int i = 0; i < userMessage.parts.length; i += 1) {
      final Part part = userMessage.parts[i];
      final InlineData? inlineData = part.inlineData;
      if (inlineData == null) {
        newParts.add(part);
        continue;
      }

      try {
        String fileName = inlineData.displayName ?? '';
        if (fileName.isEmpty) {
          fileName = 'artifact_${invocationContext.invocationId}_$i';
        }
        final String displayName = fileName;

        final int version = await artifactService.saveArtifact(
          appName: invocationContext.appName,
          userId: invocationContext.userId,
          sessionId: invocationContext.session.id,
          filename: fileName,
          artifact: part.copyWith(),
        );

        newParts.add(Part.text('[Uploaded Artifact: "$displayName"]'));

        final Part? filePart = await _buildFileReferencePart(
          invocationContext: invocationContext,
          filename: fileName,
          version: version,
          mimeType: inlineData.mimeType,
          displayName: displayName,
        );
        if (filePart != null) {
          newParts.add(filePart);
        }

        modified = true;
      } catch (_) {
        newParts.add(part);
      }
    }

    if (!modified) {
      return null;
    }
    return Content(role: userMessage.role, parts: newParts);
  }

  Future<Part?> _buildFileReferencePart({
    required InvocationContext invocationContext,
    required String filename,
    required int version,
    required String? mimeType,
    required String displayName,
  }) async {
    final BaseArtifactService? artifactService =
        invocationContext.artifactService;
    if (artifactService == null) {
      return null;
    }

    ArtifactVersion? artifactVersion;
    try {
      artifactVersion = await artifactService.getArtifactVersion(
        appName: invocationContext.appName,
        userId: invocationContext.userId,
        sessionId: invocationContext.session.id,
        filename: filename,
        version: version,
      );
    } catch (_) {
      return null;
    }

    if (artifactVersion == null ||
        artifactVersion.canonicalUri.isEmpty ||
        !_isModelAccessibleUri(artifactVersion.canonicalUri)) {
      return null;
    }

    return Part.fromFileData(
      fileUri: artifactVersion.canonicalUri,
      mimeType: mimeType ?? artifactVersion.mimeType,
      displayName: displayName,
    );
  }
}

bool _isModelAccessibleUri(String uri) {
  Uri parsed;
  try {
    parsed = Uri.parse(uri);
  } on FormatException {
    return false;
  }
  if (parsed.scheme.isEmpty) {
    return false;
  }
  return _modelAccessibleUriSchemes.contains(parsed.scheme.toLowerCase());
}
