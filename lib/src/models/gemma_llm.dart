import 'dart:convert';
import 'dart:developer' as developer;

import 'base_llm.dart';
import 'llm_request.dart';
import 'llm_response.dart';
import 'google_llm.dart';
import '../types/content.dart';

class GemmaLlm extends BaseLlm {
  GemmaLlm({super.model = 'gemma-3-27b-it', GeminiGenerateHook? generateHook})
    : _delegate = Gemini(model: model, generateHook: generateHook);

  final Gemini _delegate;

  static List<RegExp> supportedModels() {
    return <RegExp>[RegExp(r'gemma-3.*')];
  }

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {
    final LlmRequest prepared = request.sanitizedForModelCall();
    prepared.model ??= model;
    assert(
      (prepared.model ?? '').startsWith('gemma-'),
      'Requesting a non-Gemma model (${prepared.model}) with GemmaLlm is not supported.',
    );

    _moveFunctionCallsIntoSystemInstruction(prepared);
    _moveSystemInstructionToInitialUserMessage(prepared);

    await for (final LlmResponse response in _delegate.generateContent(
      prepared,
      stream: stream,
    )) {
      _extractFunctionCallsFromResponse(response);
      yield response;
    }
  }
}

void _moveFunctionCallsIntoSystemInstruction(LlmRequest llmRequest) {
  final List<Content> transformed = <Content>[];
  for (final Content content in llmRequest.contents) {
    final _ConvertedGemmaContent converted = _convertContentPartsForGemma(
      content,
    );
    if (converted.hasFunctionResponsePart) {
      if (converted.parts.isNotEmpty) {
        transformed.add(Content(role: 'user', parts: converted.parts));
      }
    } else if (converted.hasFunctionCallPart) {
      if (converted.parts.isNotEmpty) {
        transformed.add(Content(role: 'model', parts: converted.parts));
      }
    } else {
      transformed.add(content.copyWith());
    }
  }
  llmRequest.contents = transformed;

  final List<ToolDeclaration>? tools = llmRequest.config.tools;
  if (tools == null || tools.isEmpty) {
    return;
  }

  final List<FunctionDeclaration> declarations = <FunctionDeclaration>[];
  for (final ToolDeclaration tool in tools) {
    if (tool.functionDeclarations.isNotEmpty) {
      declarations.addAll(tool.functionDeclarations);
    }
  }

  final String instruction = _buildGemmaFunctionSystemInstruction(declarations);
  if (instruction.isNotEmpty) {
    llmRequest.appendInstructions(<String>[instruction]);
  }
  llmRequest.config.tools = <ToolDeclaration>[];
}

void _moveSystemInstructionToInitialUserMessage(LlmRequest llmRequest) {
  final String? systemInstruction = llmRequest.config.systemInstruction;
  if (systemInstruction == null || systemInstruction.isEmpty) {
    return;
  }

  final Content instructionContent = Content(
    role: 'user',
    parts: <Part>[Part.text(systemInstruction)],
  );
  if (llmRequest.contents.isEmpty ||
      !_contentEquals(llmRequest.contents.first, instructionContent)) {
    llmRequest.contents = <Content>[instructionContent, ...llmRequest.contents];
  }
  llmRequest.config.systemInstruction = null;
}

bool _contentEquals(Content a, Content b) {
  if (a.role != b.role || a.parts.length != b.parts.length) {
    return false;
  }
  for (int i = 0; i < a.parts.length; i += 1) {
    final Part left = a.parts[i];
    final Part right = b.parts[i];
    if (left.text != right.text ||
        left.thought != right.thought ||
        left.functionCall != null ||
        right.functionCall != null ||
        left.functionResponse != null ||
        right.functionResponse != null ||
        left.inlineData != null ||
        right.inlineData != null ||
        left.fileData != null ||
        right.fileData != null ||
        left.executableCode != null ||
        right.executableCode != null ||
        left.codeExecutionResult != null ||
        right.codeExecutionResult != null) {
      return false;
    }
  }
  return true;
}

class _ConvertedGemmaContent {
  _ConvertedGemmaContent({
    required this.parts,
    required this.hasFunctionResponsePart,
    required this.hasFunctionCallPart,
  });

  final List<Part> parts;
  final bool hasFunctionResponsePart;
  final bool hasFunctionCallPart;
}

_ConvertedGemmaContent _convertContentPartsForGemma(Content content) {
  final List<Part> newParts = <Part>[];
  bool hasFunctionResponsePart = false;
  bool hasFunctionCallPart = false;

  for (final Part part in content.parts) {
    if (part.functionResponse != null) {
      hasFunctionResponsePart = true;
      final FunctionResponse functionResponse = part.functionResponse!;
      newParts.add(
        Part.text(
          'Invoking tool `${functionResponse.name}` produced: `${jsonEncode(functionResponse.response)}`.',
        ),
      );
      continue;
    }
    if (part.functionCall != null) {
      hasFunctionCallPart = true;
      final FunctionCall functionCall = part.functionCall!;
      final Map<String, Object?> payload = <String, Object?>{
        'name': functionCall.name,
        'args': functionCall.args,
      };
      if (functionCall.id != null) {
        payload['id'] = functionCall.id;
      }
      if (functionCall.partialArgs != null) {
        payload['partial_args'] = functionCall.partialArgs;
      }
      if (functionCall.willContinue != null) {
        payload['will_continue'] = functionCall.willContinue;
      }
      newParts.add(Part.text(jsonEncode(payload)));
      continue;
    }
    newParts.add(part.copyWith());
  }

  return _ConvertedGemmaContent(
    parts: newParts,
    hasFunctionResponsePart: hasFunctionResponsePart,
    hasFunctionCallPart: hasFunctionCallPart,
  );
}

String _buildGemmaFunctionSystemInstruction(
  List<FunctionDeclaration> declarations,
) {
  if (declarations.isEmpty) {
    return '';
  }

  final List<String> encodedDeclarations = declarations
      .map((FunctionDeclaration declaration) {
        final Map<String, Object?> value = <String, Object?>{
          'name': declaration.name,
          'description': declaration.description,
          'parameters': declaration.parameters,
        };
        return jsonEncode(value);
      })
      .toList(growable: false);

  return 'You have access to the following functions:\n['
      '${encodedDeclarations.join(',\n')}\n'
      ']\n'
      'When you call a function, you MUST respond in the format of: '
      '{"name": function name, "parameters": dictionary of argument name and its value}\n'
      'When you call a function, you MUST NOT include any other text in the response.\n';
}

void _extractFunctionCallsFromResponse(LlmResponse llmResponse) {
  if (llmResponse.partial == true) {
    return;
  }

  final Content? content = llmResponse.content;
  if (content == null || content.parts.length != 1) {
    return;
  }
  final String? responseText = content.parts.first.text;
  if (responseText == null || responseText.isEmpty) {
    return;
  }

  try {
    String? jsonCandidate;
    final RegExp markdownBlockPattern = RegExp(
      r'```(?:(json|tool_code))?\s*(.*?)\s*```',
      dotAll: true,
    );
    final RegExpMatch? blockMatch = markdownBlockPattern.firstMatch(
      responseText,
    );
    if (blockMatch != null) {
      jsonCandidate = (blockMatch.group(2) ?? '').trim();
    } else {
      jsonCandidate = _getLastValidJsonSubstring(responseText);
    }

    if (jsonCandidate == null || jsonCandidate.isEmpty) {
      return;
    }

    final Object? decoded = jsonDecode(jsonCandidate);
    if (decoded is! Map) {
      return;
    }

    final String? name = _asNullableString(
      decoded['name'] ?? decoded['function'],
    );
    final Map<String, dynamic>? parameters = _asStringDynamicMap(
      decoded['parameters'] ?? decoded['args'],
    );
    if (name == null || parameters == null) {
      return;
    }

    content.parts = <Part>[Part.fromFunctionCall(name: name, args: parameters)];
  } catch (error, stackTrace) {
    developer.log(
      'Error processing Gemma function call response.',
      name: 'adk_dart.models.gemma_llm',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

String? _getLastValidJsonSubstring(String text) {
  String? lastJson;
  int startPos = 0;
  while (startPos < text.length) {
    final int braceIndex = text.indexOf('{', startPos);
    if (braceIndex < 0) {
      break;
    }
    final int? endIndex = _findJsonObjectEndIndex(text, braceIndex);
    if (endIndex == null) {
      startPos = braceIndex + 1;
      continue;
    }
    final String candidate = text.substring(braceIndex, endIndex + 1);
    try {
      final Object? decoded = jsonDecode(candidate);
      if (decoded is Map) {
        lastJson = candidate;
      }
      startPos = endIndex + 1;
    } catch (_) {
      startPos = braceIndex + 1;
    }
  }
  return lastJson;
}

int? _findJsonObjectEndIndex(String text, int startIndex) {
  int depth = 0;
  bool inString = false;
  bool escape = false;

  for (int i = startIndex; i < text.length; i += 1) {
    final int charCode = text.codeUnitAt(i);
    if (escape) {
      escape = false;
      continue;
    }

    if (charCode == 0x5c) {
      // \
      if (inString) {
        escape = true;
      }
      continue;
    }

    if (charCode == 0x22) {
      // "
      inString = !inString;
      continue;
    }

    if (inString) {
      continue;
    }

    if (charCode == 0x7b) {
      // {
      depth += 1;
      continue;
    }
    if (charCode == 0x7d) {
      // }
      depth -= 1;
      if (depth == 0) {
        return i;
      }
      if (depth < 0) {
        return null;
      }
    }
  }
  return null;
}

String? _asNullableString(Object? value) {
  if (value is String) {
    final String trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

Map<String, dynamic>? _asStringDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((Object? key, Object? value) => MapEntry('$key', value));
  }
  return null;
}
