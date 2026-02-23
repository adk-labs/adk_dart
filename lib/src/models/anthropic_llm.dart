import 'dart:convert';

import '../types/content.dart';
import 'base_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';

typedef AnthropicApiInvoker =
    Future<List<Map<String, Object?>>> Function({
      required Map<String, Object?> request,
      required bool stream,
    });
typedef AnthropicGenerateHook =
    Stream<LlmResponse> Function(LlmRequest request, bool stream);

class AnthropicLlm extends BaseLlm {
  AnthropicLlm({
    super.model = 'claude-3-5-sonnet-20241022',
    this.maxTokens = 8192,
    this.apiInvoker,
    AnthropicGenerateHook? generateHook,
  }) : _generateHook = generateHook;

  final int maxTokens;
  final AnthropicApiInvoker? apiInvoker;
  final AnthropicGenerateHook? _generateHook;

  static List<RegExp> supportedModels() {
    return <RegExp>[RegExp(r'claude-.*'), RegExp(r'anthropic\/.*')];
  }

  static String toClaudeRole(String? role) {
    if (role == 'model' || role == 'assistant') {
      return 'assistant';
    }
    return 'user';
  }

  static String toGoogleFinishReason(String? anthropicStopReason) {
    if (anthropicStopReason == 'end_turn' ||
        anthropicStopReason == 'stop_sequence' ||
        anthropicStopReason == 'tool_use') {
      return 'STOP';
    }
    if (anthropicStopReason == 'max_tokens') {
      return 'MAX_TOKENS';
    }
    return 'FINISH_REASON_UNSPECIFIED';
  }

  static bool isImagePart(Part part) {
    final InlineData? inlineData = part.inlineData;
    return inlineData != null && inlineData.mimeType.startsWith('image');
  }

  static Map<String, Object?> partToMessageBlock(Part part) {
    if (part.text != null) {
      return <String, Object?>{'type': 'text', 'text': part.text};
    }
    if (part.functionCall != null) {
      return <String, Object?>{
        'type': 'tool_use',
        'id': part.functionCall!.id ?? '',
        'name': part.functionCall!.name,
        'input': Map<String, dynamic>.from(part.functionCall!.args),
      };
    }
    if (part.functionResponse != null) {
      final Object? response = part.functionResponse!.response;
      String content = '';
      if (response is Map && response['content'] is List) {
        final List<String> lines = <String>[];
        for (final Object? item in response['content'] as List<Object?>) {
          if (item is Map && item['type'] == 'text' && item['text'] is String) {
            lines.add(item['text'] as String);
          } else if (item != null) {
            lines.add('$item');
          }
        }
        content = lines.join('\n');
      } else if (response is Map && response['result'] != null) {
        content = '${response['result']}';
      } else if (response != null) {
        content = '$response';
      }
      return <String, Object?>{
        'type': 'tool_result',
        'tool_use_id': part.functionResponse!.id ?? '',
        'is_error': false,
        'content': content,
      };
    }
    if (isImagePart(part)) {
      return <String, Object?>{
        'type': 'image',
        'source': <String, Object?>{
          'type': 'base64',
          'media_type': part.inlineData!.mimeType,
          'data': base64Encode(part.inlineData!.data),
        },
      };
    }
    if (part.executableCode != null) {
      return <String, Object?>{
        'type': 'text',
        'text': 'Code:```python\n${part.executableCode}\n```',
      };
    }
    if (part.codeExecutionResult != null) {
      return <String, Object?>{
        'type': 'text',
        'text':
            'Execution Result:```code_output\n${part.codeExecutionResult}\n```',
      };
    }
    throw UnsupportedError('Unsupported part: $part');
  }

  static Map<String, Object?> contentToMessageParam(Content content) {
    final List<Map<String, Object?>> blocks = <Map<String, Object?>>[];
    for (final Part part in content.parts) {
      if (content.role != 'user' && isImagePart(part)) {
        continue;
      }
      blocks.add(partToMessageBlock(part));
    }
    return <String, Object?>{
      'role': toClaudeRole(content.role),
      'content': blocks,
    };
  }

  static Part contentBlockToPart(Map<String, Object?> block) {
    final String type = '${block['type'] ?? ''}';
    if (type == 'text') {
      return Part.text('${block['text'] ?? ''}');
    }
    if (type == 'tool_use') {
      final Object? input = block['input'];
      return Part.fromFunctionCall(
        name: '${block['name'] ?? ''}',
        args: input is Map
            ? input.cast<String, dynamic>()
            : <String, dynamic>{},
        id: block['id'] as String?,
      );
    }
    throw UnsupportedError('Unsupported content block type: $type');
  }

  static Map<String, Object?> functionDeclarationToToolParam(
    FunctionDeclaration declaration,
  ) {
    return <String, Object?>{
      'name': declaration.name,
      'description': declaration.description,
      'input_schema': declaration.parameters.isEmpty
          ? <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{},
            }
          : declaration.parameters,
    };
  }

  static LlmResponse messageToLlmResponse(Map<String, Object?> message) {
    final List<Object?> contentBlocks =
        (message['content'] as List<Object?>?) ?? <Object?>[];
    final List<Part> parts = <Part>[];
    for (final Object? block in contentBlocks) {
      if (block is Map) {
        parts.add(contentBlockToPart(block.cast<String, Object?>()));
      }
    }

    final Map<String, Object?> usage =
        (message['usage'] as Map?)?.cast<String, Object?>() ??
        <String, Object?>{};
    final int inputTokens = (usage['input_tokens'] as num?)?.toInt() ?? 0;
    final int outputTokens = (usage['output_tokens'] as num?)?.toInt() ?? 0;

    return LlmResponse(
      content: Content(role: 'model', parts: parts),
      usageMetadata: <String, Object?>{
        'prompt_token_count': inputTokens,
        'candidates_token_count': outputTokens,
        'total_token_count': inputTokens + outputTokens,
      },
      finishReason: toGoogleFinishReason(message['stop_reason'] as String?),
    );
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model ??= model;
    maybeAppendUserContent(prepared);

    if (apiInvoker != null) {
      final List<Map<String, Object?>> messages = await apiInvoker!(
        request: _buildAnthropicRequest(prepared, stream: stream),
        stream: stream,
      );
      for (final Map<String, Object?> message in messages) {
        yield messageToLlmResponse(message);
      }
      return;
    }

    if (_generateHook != null) {
      yield* _generateHook(prepared, stream);
      return;
    }

    final String text = _extractUserText(prepared);
    yield LlmResponse(
      modelVersion: prepared.model,
      content: Content.modelText('Anthropic response: $text'),
      turnComplete: true,
    );
  }

  Map<String, Object?> _buildAnthropicRequest(
    LlmRequest request, {
    required bool stream,
  }) {
    final List<Map<String, Object?>> messages = request.contents
        .map(contentToMessageParam)
        .toList();
    final List<Map<String, Object?>> tools = <Map<String, Object?>>[];
    final List<ToolDeclaration>? declarations = request.config.tools;
    if (declarations != null) {
      for (final ToolDeclaration tool in declarations) {
        for (final FunctionDeclaration declaration
            in tool.functionDeclarations) {
          tools.add(functionDeclarationToToolParam(declaration));
        }
      }
    }
    return <String, Object?>{
      'model': request.model,
      'max_tokens': maxTokens,
      'stream': stream,
      if ((request.config.systemInstruction ?? '').isNotEmpty)
        'system': request.config.systemInstruction,
      'messages': messages,
      if (tools.isNotEmpty) 'tools': tools,
    };
  }

  String _extractUserText(LlmRequest request) {
    for (int i = request.contents.length - 1; i >= 0; i -= 1) {
      final Content content = request.contents[i];
      if (content.role != 'user') {
        continue;
      }
      for (int j = content.parts.length - 1; j >= 0; j -= 1) {
        final String? text = content.parts[j].text;
        if (text != null && text.isNotEmpty) {
          return text;
        }
      }
    }
    return '';
  }
}

typedef Claude = AnthropicLlm;
