/// Exposes an ADK Agent as an MCP server tool payload/runner interface.
library;

import 'dart:convert';

import '../../agents/base_agent.dart';
import '../../artifacts/in_memory_artifact_service.dart';
import '../../auth/credential_service/in_memory_credential_service.dart';
import '../../events/event.dart';
import '../../memory/in_memory_memory_service.dart';
import '../../models/llm_request.dart';
import '../../runners/runner.dart';
import '../../sessions/in_memory_session_service.dart';
import '../../types/content.dart';

const String mcpUserId = 'mcp_user';

/// Helper to wrap an ADK agent in a pre-configured in-memory Runner.
Runner buildMcpRunner(BaseAgent agent) {
  return Runner(
    appName: agent.name.isNotEmpty ? agent.name : 'adk_agent',
    agent: agent,
    artifactService: InMemoryArtifactService(),
    sessionService: InMemorySessionService(),
    memoryService: InMemoryMemoryService(),
    credentialService: InMemoryCredentialService(),
  );
}

/// Structured MCP Content Block produced from ADK content parts.
class McpContentBlock {
  /// Creates a text content block.
  McpContentBlock.text(this.text)
      : type = 'text',
        data = null,
        mimeType = null;

  /// Creates a binary data content block.
  McpContentBlock.data({
    required this.type,
    required this.data,
    required this.mimeType,
  }) : text = null;

  /// Content type (text, image, audio, resource).
  final String type;

  /// Text content.
  final String? text;

  /// Base64 encoded binary payload.
  final String? data;

  /// MIME type string.
  final String? mimeType;

  /// Serializes to JSON RPC response map.
  Map<String, dynamic> toJson() {
    if (type == 'text') {
      return <String, dynamic>{'type': 'text', 'text': text ?? ''};
    }
    return <String, dynamic>{
      'type': type,
      'data': data,
      'mimeType': mimeType,
    };
  }
}

/// Converts an ADK [Part] into an MCP [McpContentBlock].
McpContentBlock? partToMcpContentBlock(Part part) {
  if (part.text != null && part.text!.isNotEmpty) {
    return McpContentBlock.text(part.text!);
  }
  final InlineData? blob = part.inlineData;
  if (blob != null && blob.data.isNotEmpty) {
    final String data = base64Encode(blob.data);
    final String mime = blob.mimeType.isNotEmpty
        ? blob.mimeType
        : 'application/octet-stream';
    if (mime.startsWith('image/')) {
      return McpContentBlock.data(type: 'image', data: data, mimeType: mime);
    }
    if (mime.startsWith('audio/')) {
      return McpContentBlock.data(type: 'audio', data: data, mimeType: mime);
    }
    return McpContentBlock.data(type: 'resource', data: data, mimeType: mime);
  }
  return null;
}

/// Serves an ADK [agent] over MCP protocol by handling tool calls.
class AdkAgentMcpServer {
  /// Creates an MCP server wrapper around [agent].
  AdkAgentMcpServer({
    required this.agent,
    String? name,
    this.description,
    Runner? runner,
  })  : name = name ?? (agent.name.isNotEmpty ? agent.name : 'adk_agent'),
        runner = runner ?? buildMcpRunner(agent);

  /// Target agent served by this MCP server wrapper.
  final BaseAgent agent;

  /// Server tool name.
  final String name;

  /// Description exposed to MCP clients.
  final String? description;

  /// Runner used for session execution.
  final Runner runner;

  final Map<String, String> _connectionSessions = <String, String>{};

  /// Returns the MCP tool descriptor for this agent.
  Map<String, dynamic> getToolDescriptor() {
    return <String, dynamic>{
      'name': name,
      'description': description ?? agent.description,
      'inputSchema': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'request': <String, dynamic>{
            'type': 'string',
            'description': 'User message or prompt for the agent.',
          },
        },
        'required': <String>['request'],
      },
    };
  }

  /// Runs the agent for one MCP tool request and returns final content blocks.
  Future<List<McpContentBlock>> runAgent({
    required String request,
    String? connectionId,
  }) async {
    String? sessionId;
    if (connectionId != null && connectionId.isNotEmpty) {
      sessionId = _connectionSessions[connectionId];
    }

    if (sessionId == null) {
      final session = await runner.sessionService.createSession(
        appName: runner.appName,
        userId: mcpUserId,
      );
      sessionId = session.id;
      if (connectionId != null && connectionId.isNotEmpty) {
        _connectionSessions[connectionId] = sessionId;
      }
    }

    final Content newMessage = Content.userText(request);
    final List<McpContentBlock> finalContent = <McpContentBlock>[];

    await for (final Event event in runner.runAsync(
      userId: mcpUserId,
      sessionId: sessionId,
      newMessage: newMessage,
    )) {
      final Content? content = event.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }

      if (event.isFinalResponse()) {
        for (final Part part in content.parts) {
          final McpContentBlock? block = partToMcpContentBlock(part);
          if (block != null) {
            finalContent.add(block);
          }
        }
      }
    }

    return finalContent;
  }
}
