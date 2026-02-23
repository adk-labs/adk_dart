import '../types/content.dart';
import 'llm_request.dart';
import 'llm_response.dart';

Map<String, Object?>? convertPartToInteractionContent(Part part) {
  if (part.text != null) {
    return <String, Object?>{'type': 'text', 'text': part.text};
  }
  if (part.functionCall != null) {
    return <String, Object?>{
      'type': 'function_call',
      'id': part.functionCall!.id ?? '',
      'name': part.functionCall!.name,
      'arguments': Map<String, dynamic>.from(part.functionCall!.args),
    };
  }
  if (part.functionResponse != null) {
    final Object response = part.functionResponse!.response;
    return <String, Object?>{
      'type': 'function_result',
      'name': part.functionResponse!.name,
      'call_id': part.functionResponse!.id ?? '',
      'result': response,
    };
  }
  if (part.inlineData != null) {
    return <String, Object?>{
      'type': 'inline_data',
      'mime_type': part.inlineData!.mimeType,
      'data': List<int>.from(part.inlineData!.data),
      'display_name': part.inlineData!.displayName,
    };
  }
  if (part.fileData != null) {
    return <String, Object?>{
      'type': 'file_data',
      'uri': part.fileData!.fileUri,
      'mime_type': part.fileData!.mimeType,
      'display_name': part.fileData!.displayName,
    };
  }
  if (part.codeExecutionResult != null) {
    return <String, Object?>{
      'type': 'code_execution_result',
      'result': part.codeExecutionResult,
    };
  }
  if (part.executableCode != null) {
    return <String, Object?>{
      'type': 'code_execution_call',
      'arguments': <String, Object?>{'code': '${part.executableCode}'},
    };
  }
  return null;
}

Map<String, Object?> convertContentToTurn(Content content) {
  final List<Map<String, Object?>> converted = content.parts
      .map(convertPartToInteractionContent)
      .whereType<Map<String, Object?>>()
      .toList(growable: false);
  return <String, Object?>{
    'role': content.role ?? 'user',
    'content': converted,
  };
}

List<Map<String, Object?>> convertContentsToTurns(List<Content> contents) {
  return contents
      .map(convertContentToTurn)
      .where((Map<String, Object?> turn) {
        final Object? content = turn['content'];
        return content is List && content.isNotEmpty;
      })
      .toList(growable: false);
}

List<Map<String, Object?>> convertToolsConfigToInteractionsFormat(
  GenerateContentConfig config,
) {
  final List<ToolDeclaration>? tools = config.tools;
  if (tools == null || tools.isEmpty) {
    return const <Map<String, Object?>>[];
  }

  final List<Map<String, Object?>> output = <Map<String, Object?>>[];
  for (final ToolDeclaration tool in tools) {
    for (final FunctionDeclaration function in tool.functionDeclarations) {
      output.add(<String, Object?>{
        'type': 'function',
        'name': function.name,
        if (function.description.isNotEmpty)
          'description': function.description,
        if (function.parameters.isNotEmpty) 'parameters': function.parameters,
      });
    }
  }
  return output;
}

Stream<LlmResponse> generateContentViaInteractions({
  required LlmRequest llmRequest,
  required Stream<LlmResponse> Function(LlmRequest request, {bool stream})
  invoker,
  bool stream = false,
}) {
  return invoker(llmRequest, stream: stream);
}
