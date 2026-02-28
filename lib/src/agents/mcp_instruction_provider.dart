import '../tools/mcp_tool/mcp_session_manager.dart';
import 'readonly_context.dart';

class McpInstructionProvider {
  McpInstructionProvider({
    required this.connectionParams,
    required this.promptName,
    Object? errlog,
    McpSessionManager? sessionManager,
  }) : _errlog = errlog,
       _mcpSessionManager = sessionManager ?? McpSessionManager.instance;

  final McpConnectionParams connectionParams;
  final String promptName;
  final Object? _errlog;
  final McpSessionManager _mcpSessionManager;

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

  Object? get errlog => _errlog;
}
