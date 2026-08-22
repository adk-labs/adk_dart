import 'dart:async';
import 'dart:typed_data';

import 'package:adk_dart/adk_dart.dart' as adk;
import 'package:litertlm/litertlm.dart' as litert;

import 'active_litert_conversation.dart';

/// A [BaseLlm] implementation that uses the LiteRT-LM runtime to generate content.
class LiteRtLmModel extends adk.BaseLlm {
  /// Creates a [LiteRtLmModel] instance with a pre-created [Engine].
  LiteRtLmModel(
    this.engine, {
    this.ownsEngine = false,
    required super.model,
  });

  /// Creates a [LiteRtLmModel] instance that owns the [Engine].
  factory LiteRtLmModel.fromConfig(
    litert.EngineConfig config, {
    required String model,
  }) {
    return LiteRtLmModel(
      litert.Engine(engineConfig: config),
      ownsEngine: true,
      model: model,
    );
  }

  /// The underlying LiteRT-LM engine.
  final litert.Engine engine;

  /// Whether this model owns the engine and should dispose of it when closed.
  final bool ownsEngine;

  final ActiveLiteRtLmConversation _activeConversation =
      ActiveLiteRtLmConversation();

  @override
  Stream<adk.LlmResponse> generateContent(
    adk.LlmRequest request, {
    bool stream = false,
  }) async* {
    if (stream) {
      litert.Conversation conversation;
      litert.Message lastMessage;
      try {
        final pair = await _getOrCreateConversation(request);
        conversation = pair.$1;
        lastMessage = pair.$2;
      } catch (e) {
        yield adk.LlmResponse(errorMessage: e.toString());
        return;
      }

      final accumulatedText = StringBuffer();
      adk.LlmResponse? lastResponse;
      var isCompleted = false;

      try {
        await for (final msgChunk in conversation.sendMessageStream(
          lastMessage,
        )) {
          final response = _mapMessageToLlmResponse(msgChunk, partial: true);
          if (response.content != null) {
            for (final part in response.content!.parts) {
              if (part.text != null) {
                accumulatedText.write(part.text!);
              }
            }
          }
          lastResponse = response;
          yield response;
        }

        final finalParts = <adk.Part>[];
        if (accumulatedText.isNotEmpty) {
          finalParts.add(adk.Part.text(accumulatedText.toString()));
        }
        if (lastResponse?.content != null) {
          for (final part in lastResponse!.content!.parts) {
            if (part.functionCall != null) {
              finalParts.add(part);
            }
          }
        }

        final finalResponse = adk.LlmResponse(
          content: adk.Content(role: 'model', parts: finalParts),
          partial: false,
        );

        if (finalResponse.content != null) {
          _activeConversation.update(conversation, [
            ...request.contents,
            finalResponse.content!,
          ]);
        }

        yield finalResponse;
        isCompleted = true;
      } catch (e) {
        _activeConversation.clear();
        yield adk.LlmResponse(errorMessage: e.toString());
      } finally {
        if (!isCompleted) {
          _activeConversation.clear();
        }
      }
    } else {
      litert.Conversation conversation;
      litert.Message lastMessage;
      try {
        final pair = await _getOrCreateConversation(request);
        conversation = pair.$1;
        lastMessage = pair.$2;
      } catch (e) {
        yield adk.LlmResponse(errorMessage: e.toString());
        return;
      }

      try {
        final responseMessage = await conversation.sendMessage(lastMessage);
        final response = _mapMessageToLlmResponse(
          responseMessage,
          partial: false,
        );
        if (response.content != null) {
          _activeConversation.update(conversation, [
            ...request.contents,
            response.content!,
          ]);
        }
        yield response;
      } catch (e) {
        _activeConversation.clear();
        yield adk.LlmResponse(errorMessage: e.toString());
      }
    }
  }

  Future<(litert.Conversation, litert.Message)> _getOrCreateConversation(
    adk.LlmRequest request,
  ) async {
    if (!engine.isInitialized) {
      await engine.initialize();
    }

    if (request.contents.isEmpty) {
      throw ArgumentError('Empty request contents');
    }

    final history = request.contents.sublist(0, request.contents.length - 1);
    final lastMessage = request.contents.last;
    final liteRtLmLastMessage = _mapContentToMessage(lastMessage);

    litert.Conversation conversation;
    if (_activeConversation.matches(history)) {
      conversation = _activeConversation.conversation!;
    } else {
      _activeConversation.clear();

      final tools = <litert.Tool>[];
      final reqTools = request.config.tools;
      if (reqTools != null) {
        for (final toolDecl in reqTools) {
          for (final decl in toolDecl.functionDeclarations) {
            tools.add(ManualLiteRtLmTool(decl));
          }
        }
      }

      litert.Contents? systemInstruction;
      final systemInstStr = request.config.systemInstruction;
      if (systemInstStr != null && systemInstStr.isNotEmpty) {
        systemInstruction = litert.Contents([
          litert.Content.text(systemInstStr),
        ]);
      }

      final initialMessages = history.map(_mapContentToMessage).toList();

      final conversationConfig = litert.ConversationConfig(
        systemMessage: systemInstruction != null
            ? litert.Message.systemContents(systemInstruction)
            : null,
        initialMessages: initialMessages,
        tools: tools,
        automaticToolCalling: false,
      );

      conversation = await engine.createConversation(conversationConfig);
      _activeConversation.update(conversation, history);
    }

    return (conversation, liteRtLmLastMessage);
  }

  /// Releases resources used by the model and its engine.
  Future<void> close() async {
    _activeConversation.clear();
    if (ownsEngine) {
      await engine.dispose();
    }
  }

  /// Releases resources (alias for [close] compatibility).
  Future<void> dispose() => close();
}

/// Adapter converting a manual ADK function declaration to a LiteRT-LM tool specification.
class ManualLiteRtLmTool implements litert.Tool {
  /// Creates a manual tool adapter.
  ManualLiteRtLmTool(this.declaration);

  /// The ADK function declaration.
  final adk.FunctionDeclaration declaration;

  @override
  Map<String, Object?> getToolDescription() {
    return {
      'type': 'function',
      'function': {
        'name': declaration.name,
        'description': declaration.description,
        'parameters': declaration.parameters,
      }
    };
  }

  @override
  FutureOr<Object?> execute(Map<String, Object?> arguments) {
    throw UnsupportedError('Manual tool execution not supported');
  }
}

// --- Mapping Helpers ---

litert.Message _mapContentToMessage(adk.Content adkContent) {
  final isToolResponse = adkContent.parts.any(
    (part) => part.functionResponse != null,
  );
  final role = isToolResponse
      ? litert.Role.tool
      : switch (adkContent.role) {
          'user' => litert.Role.user,
          'model' => litert.Role.model,
          'system' => litert.Role.system,
          'tool' => litert.Role.tool,
          _ => litert.Role.user,
        };

  final parts = adkContent.parts
      .map(_mapPartToContent)
      .whereType<litert.Content>()
      .toList();
  final contents = litert.Contents(parts);

  return switch (role) {
    litert.Role.user => litert.Message.userContents(contents),
    litert.Role.system => litert.Message.systemContents(contents),
    litert.Role.tool => litert.Message.tool(contents),
    litert.Role.model => litert.Message.model(
        contents: contents,
        toolCalls: adkContent.parts
            .map((part) {
              final fc = part.functionCall;
              if (fc != null) {
                return litert.ToolCall(name: fc.name, arguments: fc.args);
              }
              return null;
            })
            .whereType<litert.ToolCall>()
            .toList(),
      ),
  };
}

litert.Content? _mapPartToContent(adk.Part part) {
  final text = part.text;
  final inlineData = part.inlineData;
  final fileData = part.fileData;
  final functionResponse = part.functionResponse;

  if (text != null) {
    return litert.Content.text(text);
  }
  if (inlineData != null) {
    final mimeType = inlineData.mimeType.toLowerCase();
    final data = Uint8List.fromList(inlineData.data);
    if (mimeType.startsWith('image/')) {
      return litert.Content.imageBytes(data);
    } else if (mimeType.startsWith('audio/')) {
      return litert.Content.audioBytes(data);
    }
  }
  if (fileData != null) {
    final mimeType = fileData.mimeType?.toLowerCase() ?? '';
    final path = fileData.fileUri;
    if (mimeType.startsWith('image/')) {
      return litert.Content.imageFile(path);
    } else if (mimeType.startsWith('audio/')) {
      return litert.Content.audioFile(path);
    }
  }
  if (functionResponse != null) {
    return litert.Content.toolResponse(
      name: functionResponse.name,
      response: functionResponse.response,
    );
  }
  return null;
}

adk.LlmResponse _mapMessageToLlmResponse(
  litert.Message message, {
  bool partial = false,
}) {
  final adkParts = <adk.Part>[];
  for (final content in message.contents.values) {
    if (content is litert.TextContent) {
      adkParts.add(adk.Part.text(content.text));
    } else if (content is litert.ImageBytesContent) {
      adkParts.add(adk.Part.text('[Image Bytes]'));
    } else if (content is litert.ImageFileContent) {
      adkParts.add(adk.Part.text('[Image File: ${content.path}]'));
    } else if (content is litert.AudioBytesContent) {
      adkParts.add(adk.Part.text('[Audio Bytes]'));
    } else if (content is litert.AudioFileContent) {
      adkParts.add(adk.Part.text('[Audio File: ${content.path}]'));
    } else if (content is litert.ToolResponseContent) {
      adkParts.add(adk.Part.text('[Tool Response: ${content.name}]'));
    }
  }

  for (final toolCall in message.toolCalls) {
    adkParts.add(
      adk.Part(
        functionCall: adk.FunctionCall(
          name: toolCall.name,
          args: toolCall.arguments,
        ),
      ),
    );
  }

  return adk.LlmResponse(
    content: adk.Content(role: 'model', parts: adkParts),
    partial: partial,
  );
}
