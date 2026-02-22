import 'dart:developer' as developer;

import '../tools/base_tool.dart';
import '../types/content.dart';

ToolDeclaration? _findToolWithFunctionDeclarations(LlmRequest request) {
  final List<ToolDeclaration>? tools = request.config.tools;
  if (tools == null) {
    return null;
  }
  for (final ToolDeclaration tool in tools) {
    if (tool.functionDeclarations.isNotEmpty) {
      return tool;
    }
  }
  return null;
}

class FunctionDeclaration {
  FunctionDeclaration({
    required this.name,
    this.description = '',
    JsonMap? parameters,
  }) : parameters = parameters ?? <String, dynamic>{};

  String name;
  String description;
  JsonMap parameters;

  FunctionDeclaration copyWith({
    String? name,
    String? description,
    JsonMap? parameters,
  }) {
    return FunctionDeclaration(
      name: name ?? this.name,
      description: description ?? this.description,
      parameters: parameters ?? Map<String, dynamic>.from(this.parameters),
    );
  }
}

class ToolDeclaration {
  ToolDeclaration({List<FunctionDeclaration>? functionDeclarations})
    : functionDeclarations = functionDeclarations ?? <FunctionDeclaration>[];

  List<FunctionDeclaration> functionDeclarations;

  ToolDeclaration copyWith({List<FunctionDeclaration>? functionDeclarations}) {
    return ToolDeclaration(
      functionDeclarations:
          functionDeclarations ??
          this.functionDeclarations
              .map((declaration) => declaration.copyWith())
              .toList(),
    );
  }
}

class GenerateContentConfig {
  GenerateContentConfig({
    this.tools,
    this.systemInstruction,
    this.responseSchema,
    this.responseMimeType,
    Map<String, String>? labels,
  }) : labels = labels ?? <String, String>{};

  List<ToolDeclaration>? tools;
  String? systemInstruction;
  Object? responseSchema;
  String? responseMimeType;
  Map<String, String> labels;

  GenerateContentConfig copyWith({
    Object? tools = _sentinel,
    Object? systemInstruction = _sentinel,
    Object? responseSchema = _sentinel,
    Object? responseMimeType = _sentinel,
    Map<String, String>? labels,
  }) {
    return GenerateContentConfig(
      tools: identical(tools, _sentinel)
          ? this.tools?.map((declaration) => declaration.copyWith()).toList()
          : tools as List<ToolDeclaration>?,
      systemInstruction: identical(systemInstruction, _sentinel)
          ? this.systemInstruction
          : systemInstruction as String?,
      responseSchema: identical(responseSchema, _sentinel)
          ? this.responseSchema
          : responseSchema,
      responseMimeType: identical(responseMimeType, _sentinel)
          ? this.responseMimeType
          : responseMimeType as String?,
      labels: labels ?? Map<String, String>.from(this.labels),
    );
  }
}

class LlmRequest {
  LlmRequest({
    this.model,
    List<Content>? contents,
    GenerateContentConfig? config,
    Map<String, BaseTool>? toolsDict,
    this.cacheConfig,
    this.cacheMetadata,
    this.cacheableContentsTokenCount,
    this.previousInteractionId,
  }) : contents = contents ?? <Content>[],
       config = config ?? GenerateContentConfig(),
       toolsDict = toolsDict ?? <String, BaseTool>{};

  String? model;
  List<Content> contents;
  GenerateContentConfig config;
  Map<String, BaseTool> toolsDict;

  Object? cacheConfig;
  Object? cacheMetadata;
  int? cacheableContentsTokenCount;
  String? previousInteractionId;

  List<Content> appendInstructions(Object instructions) {
    if (instructions is Content) {
      final List<String> textParts = <String>[];
      final List<Content> userContents = <Content>[];
      int nonTextIndex = 0;

      for (final Part part in instructions.parts) {
        if (part.text != null && part.text!.isNotEmpty) {
          textParts.add(part.text!);
          continue;
        }

        nonTextIndex += 1;
        textParts.add('[Reference to non-text content: ref_$nonTextIndex]');
        userContents.add(
          Content(
            role: 'user',
            parts: <Part>[
              Part.text('Referenced content: ref_$nonTextIndex'),
              part.copyWith(),
            ],
          ),
        );
      }

      if (textParts.isNotEmpty) {
        final String text = textParts.join('\n\n');
        if (config.systemInstruction == null ||
            config.systemInstruction!.isEmpty) {
          config.systemInstruction = text;
        } else {
          config.systemInstruction = '${config.systemInstruction}\n\n$text';
        }
      }

      if (userContents.isNotEmpty) {
        contents.addAll(userContents);
      }
      return userContents;
    }

    if (instructions is List<String>) {
      if (instructions.isEmpty) {
        return const <Content>[];
      }

      final String text = instructions.join('\n\n');
      if (config.systemInstruction == null ||
          config.systemInstruction!.isEmpty) {
        config.systemInstruction = text;
      } else {
        config.systemInstruction = '${config.systemInstruction}\n\n$text';
      }
      return const <Content>[];
    }

    throw ArgumentError.value(
      instructions,
      'instructions',
      'instructions must be List<String> or Content',
    );
  }

  void appendTools(List<BaseTool> tools) {
    if (tools.isEmpty) {
      return;
    }

    final List<FunctionDeclaration> declarations = <FunctionDeclaration>[];
    for (final BaseTool tool in tools) {
      final FunctionDeclaration? declaration = tool.getDeclaration();
      if (declaration != null) {
        declarations.add(declaration);
        toolsDict[tool.name] = tool;
      }
    }

    if (declarations.isEmpty) {
      return;
    }

    config.tools ??= <ToolDeclaration>[];
    final ToolDeclaration? toolWithDeclarations =
        _findToolWithFunctionDeclarations(this);
    if (toolWithDeclarations != null) {
      toolWithDeclarations.functionDeclarations.addAll(declarations);
      return;
    }

    config.tools!.add(ToolDeclaration(functionDeclarations: declarations));
  }

  void setOutputSchema(Object schema) {
    config.responseSchema = schema;
    config.responseMimeType = 'application/json';
  }

  LlmRequest sanitizedForModelCall() {
    final LlmRequest clone = LlmRequest(
      model: model,
      contents: contents.map((content) => content.copyWith()).toList(),
      config: config.copyWith(),
      toolsDict: Map<String, BaseTool>.from(toolsDict),
      cacheConfig: cacheConfig,
      cacheMetadata: cacheMetadata,
      cacheableContentsTokenCount: cacheableContentsTokenCount,
      previousInteractionId: previousInteractionId,
    );

    for (final Content content in clone.contents) {
      for (final Part part in content.parts) {
        final FunctionCall? call = part.functionCall;
        if (call != null && call.id != null && call.id!.startsWith('adk-')) {
          call.id = null;
        }
        final FunctionResponse? response = part.functionResponse;
        if (response != null &&
            response.id != null &&
            response.id!.startsWith('adk-')) {
          response.id = null;
        }
      }
    }

    developer.log('Sanitized request for model call.', name: 'adk_dart.models');
    return clone;
  }
}

const Object _sentinel = Object();
