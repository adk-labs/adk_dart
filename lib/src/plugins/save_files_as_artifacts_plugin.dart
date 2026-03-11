/// Plugin hooks and implementations for ADK runtime pipelines.
library;

import '../agents/base_agent.dart';
import '../agents/callback_context.dart';
import '../agents/invocation_context.dart';
import '../artifacts/base_artifact_service.dart';
import '../types/content.dart';
import 'base_plugin.dart';

/// URI schemes that can be forwarded to model file references.
const Set<String> _modelAccessibleUriSchemes = <String>{'gs', 'https', 'http'};
const String _pendingDeltaStateSuffix = ':pending_delta';

/// Saves user inline files as artifacts and replaces them with file references.
class SaveFilesAsArtifactsPlugin extends BasePlugin {
  /// Creates a save-files-as-artifacts plugin.
  SaveFilesAsArtifactsPlugin({super.name = 'save_files_as_artifacts_plugin'});

  /// Converts inline file parts in [userMessage] into persisted artifact refs.
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
    final Map<String, int> pendingDelta = <String, int>{};
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
        pendingDelta[fileName] = version;

        modified = true;
      } catch (_) {
        newParts.add(part);
      }
    }

    if (!modified) {
      return null;
    }
    final String stateKey = '$name$_pendingDeltaStateSuffix';
    final Map<String, int> existingPendingDelta = _castPendingDelta(
      invocationContext.session.state[stateKey],
    );
    existingPendingDelta.addAll(pendingDelta);
    invocationContext.session.state[stateKey] = existingPendingDelta;
    return Content(role: userMessage.role, parts: newParts);
  }

  /// Flushes pending artifact deltas into event actions for UI consumers.
  @override
  Future<Content?> beforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    final String stateKey = '$name$_pendingDeltaStateSuffix';
    final Map<String, int> pendingDelta = _castPendingDelta(
      callbackContext.state[stateKey],
    );
    if (pendingDelta.isEmpty) {
      return null;
    }
    callbackContext.actions.artifactDelta.addAll(pendingDelta);
    callbackContext.state[stateKey] = <String, int>{};
    return null;
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

Map<String, int> _castPendingDelta(Object? value) {
  if (value is Map<String, int>) {
    return Map<String, int>.from(value);
  }
  if (value is Map) {
    final Map<String, int> delta = <String, int>{};
    value.forEach((Object? key, Object? item) {
      if (item is num) {
        delta['$key'] = item.toInt();
      }
    });
    return delta;
  }
  return <String, int>{};
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
