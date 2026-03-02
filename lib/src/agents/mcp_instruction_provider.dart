/// Helpers for loading MCP-backed dynamic instructions.
library;

import '../tools/mcp_tool/mcp_session_manager.dart';
import 'readonly_context.dart';

/// Instruction provider that resolves prompts from MCP resources.
class McpInstructionProvider {
  /// Creates an MCP instruction provider.
  McpInstructionProvider({
    required this.connectionParams,
    required this.promptName,
    Object? errlog,
    McpSessionManager? sessionManager,
  }) : _errlog = errlog,
       _mcpSessionManager = sessionManager ?? McpSessionManager.instance;

  /// MCP connection parameters used to access resources.
  final McpConnectionParams connectionParams;

  /// Prompt/resource name to load.
  final String promptName;

  final Object? _errlog;
  final McpSessionManager _mcpSessionManager;

  /// Loads and concatenates instruction text for [context].
  ///
  /// Throws a [StateError] when the resolved instruction is empty.
  Future<String> call(ReadonlyContext context) async {
    final Set<String> promptArgumentNames = await _mcpSessionManager
        .listPromptArgumentNames(
          connectionParams: connectionParams,
          promptName: promptName,
        );
    final Map<String, Object?> promptArguments = <String, Object?>{
      for (final MapEntry<String, Object?> entry in context.state.entries)
        if (promptArgumentNames.contains(entry.key)) entry.key: entry.value,
    };

    final List<McpResourceContent> resources = await _mcpSessionManager
        .readResourceAsync(
          connectionParams: connectionParams,
          resourceName: promptName,
          promptArguments: promptArguments,
        );
    final String instruction = resources
        .map((McpResourceContent resource) => resource.text ?? '')
        .where((String text) => text.isNotEmpty)
        .join();
    if (instruction.isEmpty) {
      throw StateError("Failed to load MCP prompt '$promptName'.");
    }
    return instruction;
  }

  /// Optional error logging sink.
  Object? get errlog => _errlog;
}
