import 'dart:convert';

import '../models/llm_request.dart';
import '../types/content.dart';
import 'base_tool.dart';
import 'tool_context.dart';

const List<String> _geminiSupportedInlineMimePrefixes = <String>[
  'image/',
  'audio/',
  'video/',
];
const Set<String> _geminiSupportedInlineMimeTypes = <String>{'application/pdf'};
const Set<String> _textLikeMimeTypes = <String>{
  'application/csv',
  'application/json',
  'application/xml',
};

class LoadArtifactsTool extends BaseTool {
  LoadArtifactsTool()
    : super(
        name: 'load_artifacts',
        description: '''Loads artifacts into the session for this request.

NOTE: Call when you need access to artifacts (for example, uploads saved by the
web UI).''',
      );

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'artifact_names': <String, dynamic>{
            'type': 'array',
            'items': <String, dynamic>{'type': 'string'},
          },
        },
      },
    );
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) async {
    final List<String> artifactNames = _coerceArtifactNames(
      args['artifact_names'],
    );
    return <String, Object?>{
      'artifact_names': artifactNames,
      'status':
          'artifact contents temporarily inserted and removed. to access these artifacts, call load_artifacts tool again.',
    };
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    await super.processLlmRequest(
      toolContext: toolContext,
      llmRequest: llmRequest,
    );

    final List<String> artifactNames = await toolContext.listArtifacts();
    if (artifactNames.isNotEmpty) {
      llmRequest.appendInstructions(<String>[
        '''
You have a list of artifacts:
${jsonEncode(artifactNames)}

When the user asks questions about any of the artifacts, you should call the
`load_artifacts` function to load the artifact. Always call load_artifacts
before answering questions related to the artifacts, regardless of whether the
artifacts have been loaded before. Do not depend on prior answers about the
artifacts.
''',
      ]);
    }

    if (llmRequest.contents.isEmpty) {
      return;
    }
    final Content tail = llmRequest.contents.last;
    if (tail.parts.isEmpty) {
      return;
    }
    final FunctionResponse? response = tail.parts.first.functionResponse;
    if (response == null || response.name != name) {
      return;
    }

    final Object? payloadNames = response.response['artifact_names'];
    final List<String> requestedNames = _coerceArtifactNames(payloadNames);
    for (final String artifactName in requestedNames) {
      Part? artifact = await toolContext.loadArtifact(artifactName);
      if (artifact == null && !artifactName.startsWith('user:')) {
        artifact = await toolContext.loadArtifact('user:$artifactName');
      }
      if (artifact == null) {
        continue;
      }

      llmRequest.contents.add(
        Content(
          role: 'user',
          parts: <Part>[
            Part.text('Artifact $artifactName is:'),
            _asSafePart(artifact, artifactName),
          ],
        ),
      );
    }
  }
}

List<String> _coerceArtifactNames(Object? value) {
  if (value is List) {
    final List<String> artifactNames = <String>[];
    for (final dynamic item in value) {
      final String name = '$item'.trim();
      if (name.isEmpty || name == 'null') {
        continue;
      }
      artifactNames.add(name);
    }
    return artifactNames;
  }
  return const <String>[];
}

Part _asSafePart(Part artifact, String artifactName) {
  if (artifact.inlineData != null) {
    return _asSafeInlineDataPart(artifact, artifactName);
  }
  if (artifact.text != null && artifact.text!.isNotEmpty) {
    return artifact.copyWith();
  }
  if (artifact.fileData != null) {
    return artifact.copyWith();
  }
  if (artifact.functionCall != null || artifact.functionResponse != null) {
    return Part.text(
      '[Artifact $artifactName contains structured tool data and was loaded.]',
    );
  }
  if (artifact.codeExecutionResult != null || artifact.executableCode != null) {
    return Part.text(
      '[Artifact $artifactName contains code execution output and was loaded.]',
    );
  }
  return Part.text('[Artifact $artifactName was loaded.]');
}

Part _asSafeInlineDataPart(Part artifact, String artifactName) {
  final InlineData inlineData = artifact.inlineData!;
  if (_isInlineMimeTypeSupported(inlineData.mimeType)) {
    return artifact.copyWith();
  }

  final String mimeType =
      _normalizeMimeType(inlineData.mimeType) ?? 'application/octet-stream';
  final List<int> data = inlineData.data;
  if (data.isEmpty) {
    return Part.text(
      '[Artifact: $artifactName, type: $mimeType. No inline data was provided.]',
    );
  }

  if (mimeType.startsWith('text/') || _textLikeMimeTypes.contains(mimeType)) {
    return Part.text(utf8.decode(data, allowMalformed: true));
  }

  final double sizeKb = data.length / 1024;
  return Part.text(
    '[Binary artifact: $artifactName, type: $mimeType, size: ${sizeKb.toStringAsFixed(1)} KB. Content cannot be displayed inline.]',
  );
}

String? _normalizeMimeType(String? mimeType) {
  if (mimeType == null) {
    return null;
  }
  final String trimmed = mimeType.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final int delimiterIndex = trimmed.indexOf(';');
  final String normalized = delimiterIndex == -1
      ? trimmed
      : trimmed.substring(0, delimiterIndex);
  return normalized.trim().toLowerCase();
}

bool _isInlineMimeTypeSupported(String? mimeType) {
  final String? normalized = _normalizeMimeType(mimeType);
  if (normalized == null) {
    return false;
  }
  if (_geminiSupportedInlineMimeTypes.contains(normalized)) {
    return true;
  }
  for (final String prefix in _geminiSupportedInlineMimePrefixes) {
    if (normalized.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}
