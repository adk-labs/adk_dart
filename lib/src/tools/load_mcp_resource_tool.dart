import 'dart:convert';

import '../models/llm_request.dart';
import '../types/content.dart';
import 'base_tool.dart';
import 'mcp_tool/mcp_session_manager.dart';
import 'mcp_tool/mcp_toolset.dart';
import 'tool_context.dart';

class LoadMcpResourceTool extends BaseTool {
  LoadMcpResourceTool(this._mcpToolset)
    : super(
        name: 'load_mcp_resource',
        description: '''Loads resources from the MCP server.

NOTE: Call when you need access to resources.''',
      );

  final McpToolset _mcpToolset;

  @override
  FunctionDeclaration? getDeclaration() {
    return FunctionDeclaration(
      name: name,
      description: description,
      parameters: <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'resource_names': <String, dynamic>{
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
    final List<String> resourceNames = <String>[
      for (final Object? value
          in (args['resource_names'] as List? ?? <Object?>[]))
        if (value is String) value,
    ];
    return <String, Object?>{
      'resource_names': resourceNames,
      'status':
          'resource contents temporarily inserted and removed. to access these resources, call load_mcp_resource tool again.',
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
    await _appendResourcesToLlmRequest(llmRequest);
  }

  Future<void> _appendResourcesToLlmRequest(LlmRequest llmRequest) async {
    final List<String> resourceNames = await _mcpToolset.listResources();
    if (resourceNames.isNotEmpty) {
      llmRequest.appendInstructions(<String>[
        '''You have a list of MCP resources:
${jsonEncode(resourceNames)}

When the user asks questions about any of the resources, you should call the
`load_mcp_resource` function to load the resource. Always call load_mcp_resource
before answering questions related to the resources.''',
      ]);
    }

    final List<String> requestedNames = _extractRequestedResourceNames(
      llmRequest,
    );
    if (requestedNames.isEmpty) {
      return;
    }

    for (final String resourceName in requestedNames) {
      final List<McpResourceContent> contents = await _mcpToolset.readResource(
        resourceName,
      );
      for (final McpResourceContent content in contents) {
        final Part part = _mcpContentToPart(content, resourceName);
        llmRequest.contents.add(
          Content(
            role: 'user',
            parts: <Part>[Part.text('Resource $resourceName is:'), part],
          ),
        );
      }
    }
  }

  List<String> _extractRequestedResourceNames(LlmRequest llmRequest) {
    if (llmRequest.contents.isEmpty) {
      return const <String>[];
    }
    final Content last = llmRequest.contents.last;
    final List<String> names = <String>[];
    for (final Part part in last.parts) {
      final FunctionResponse? response = part.functionResponse;
      if (response == null || response.name != name) {
        continue;
      }
      final Object? raw = response.response['resource_names'];
      if (raw is List) {
        for (final Object? item in raw) {
          if (item is String && item.isNotEmpty) {
            names.add(item);
          }
        }
      }
    }
    return names;
  }

  Part _mcpContentToPart(McpResourceContent content, String resourceName) {
    if (content.text != null) {
      return Part.text(content.text!);
    }
    if (content.blob != null) {
      try {
        final List<int> data = base64Decode(content.blob!);
        return Part(
          codeExecutionResult: <String, Object?>{
            'bytes': data,
            'mime_type': content.mimeType ?? 'application/octet-stream',
          },
        );
      } catch (_) {
        return Part.text(
          '[Binary content for $resourceName could not be decoded]',
        );
      }
    }
    return Part.text('[Unknown content type for $resourceName]');
  }
}
