/// Exposes an ADK Agent as an MCP server tool payload/runner interface.
library;

import 'dart:async';
import 'dart:convert';

import '../../agents/base_agent.dart';
import '../../artifacts/in_memory_artifact_service.dart';
import '../../auth/credential_service/in_memory_credential_service.dart';
import '../../events/event.dart';
import '../../memory/in_memory_memory_service.dart';
import '../../runners/runner.dart';
import '../../sessions/in_memory_session_service.dart';
import '../../types/content.dart';

/// Default user identifier assigned to MCP-originated agent invocations.
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
  McpContentBlock.text(this.text) : type = 'text', data = null, mimeType = null;

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
    return <String, dynamic>{'type': type, 'data': data, 'mimeType': mimeType};
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
  }) : name = name ?? (agent.name.isNotEmpty ? agent.name : 'adk_agent'),
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
  final Map<String, Future<String>> _pendingSessions =
      <String, Future<String>>{};

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

  Future<String> _getOrCreateSession(String? connectionId) async {
    if (connectionId != null && connectionId.isNotEmpty) {
      final String? existing = _connectionSessions[connectionId];
      if (existing != null) {
        return existing;
      }
      final Future<String>? pending = _pendingSessions[connectionId];
      if (pending != null) {
        return pending;
      }
      final Completer<String> completer = Completer<String>();
      _pendingSessions[connectionId] = completer.future;
      try {
        final session = await runner.sessionService.createSession(
          appName: runner.appName,
          userId: mcpUserId,
        );
        _connectionSessions[connectionId] = session.id;
        completer.complete(session.id);
        return session.id;
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
        rethrow;
      } finally {
        _pendingSessions.remove(connectionId);
      }
    }

    final session = await runner.sessionService.createSession(
      appName: runner.appName,
      userId: mcpUserId,
    );
    return session.id;
  }

  /// Closes and reaps the session associated with [sessionId] (or connection ID).
  Future<void> closeSession(String sessionId) async {
    String? targetSessionId = _connectionSessions.remove(sessionId);
    if (targetSessionId == null) {
      final Future<String>? pending = _pendingSessions.remove(sessionId);
      if (pending != null) {
        try {
          targetSessionId = await pending;
        } catch (_) {
          return;
        }
        _connectionSessions.remove(sessionId);
      }
    }
    if (targetSessionId == null) {
      _connectionSessions.removeWhere(
        (String _, String value) => value == sessionId,
      );
      targetSessionId = sessionId;
    }
    try {
      await runner.sessionService.deleteSession(
        appName: runner.appName,
        userId: mcpUserId,
        sessionId: targetSessionId,
      );
    } catch (_) {
      // Ignore deletion errors during session cleanup.
    }
  }

  /// Runs the agent for one MCP tool request and returns final content blocks.
  Future<List<McpContentBlock>> runAgent({
    required String request,
    String? connectionId,
  }) async {
    final String sessionId = await _getOrCreateSession(connectionId);

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
