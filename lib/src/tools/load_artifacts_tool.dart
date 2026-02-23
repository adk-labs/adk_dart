import '../models/llm_request.dart';
import '../types/content.dart';
import 'base_tool.dart';
import 'tool_context.dart';

class LoadArtifactsTool extends BaseTool {
  LoadArtifactsTool()
    : super(
        name: 'load_artifacts',
        description:
            'Loads artifacts into the current request context when requested.',
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
          'artifact contents are attached to the in-flight request when available',
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
${artifactNames.join(', ')}

When answering questions about these files, call `load_artifacts` with `artifact_names`.
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
    return value.map<String>((dynamic item) => '$item').toList(growable: false);
  }
  return const <String>[];
}

Part _asSafePart(Part artifact, String artifactName) {
  if (artifact.text != null && artifact.text!.isNotEmpty) {
    return artifact.copyWith();
  }
  if (artifact.functionCall != null || artifact.functionResponse != null) {
    return Part.text(
      '[Artifact $artifactName contains structured tool data and was loaded.]',
    );
  }
  if (artifact.codeExecutionResult != null) {
    return Part.text(
      '[Artifact $artifactName contains code execution output and was loaded.]',
    );
  }
  return Part.text('[Artifact $artifactName was loaded.]');
}
