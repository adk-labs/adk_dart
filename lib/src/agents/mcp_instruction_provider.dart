/// Helpers for loading MCP-backed dynamic instructions.
library;

import '../tools/mcp_tool/mcp_session_manager.dart';
import 'readonly_context.dart';

/// Builder signature for dynamically computing MCP prompt arguments from
/// [ReadonlyContext].
typedef McpPromptArgumentsProvider =
    Map<String, String> Function(ReadonlyContext context);

/// Instruction provider that resolves prompts from MCP resources.
class McpInstructionProvider {
  /// Creates an MCP instruction provider.
  ///
  /// [arguments] specifies the arguments to send with the prompt request,
  /// either a fixed `Map<String, String>` (or `Map<String, Object?>`) or a
  /// callable taking [ReadonlyContext] and returning a map. When `null`, no
  /// arguments are sent — the server's declared argument names are never
  /// consulted to read session state.
  McpInstructionProvider({
    required this.connectionParams,
    required this.promptName,
    Object? errlog,
    Object? arguments,
    McpSessionManager? sessionManager,
  }) : _errlog = errlog,
       _arguments = arguments,
       _mcpSessionManager = sessionManager ?? McpSessionManager.instance;

  /// MCP connection parameters used to access resources.
  final McpConnectionParams connectionParams;

  /// Prompt/resource name to load.
  final String promptName;

  final Object? _errlog;
  final Object? _arguments;
  final McpSessionManager _mcpSessionManager;

  /// Loads and concatenates instruction text for [context].
  ///
  /// Throws a [StateError] when the resolved instruction is empty.
  Future<String> call(ReadonlyContext context) async {
    // The caller decides what is sent; the server's declared argument names are
    // not consulted, so it cannot pick which session values it receives.
    final Map<String, Object?>? promptArguments = _resolveArguments(context);

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

  Map<String, Object?>? _resolveArguments(ReadonlyContext context) {
    final Object? raw;
    if (_arguments == null) {
      raw = null;
    } else if (_arguments is Map<String, String> Function(ReadonlyContext)) {
      raw = _arguments(context);
    } else if (_arguments is Map<String, Object?> Function(ReadonlyContext)) {
      raw = _arguments(context);
    } else if (_arguments is Map Function(ReadonlyContext)) {
      raw = _arguments(context);
    } else {
      raw = _arguments;
    }
    if (raw == null) {
      return null;
    }
    if (raw is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in raw.entries)
          '${entry.key}': entry.value,
      };
    }
    throw ArgumentError.value(
      raw,
      'arguments',
      'Expected a Map or a Function(ReadonlyContext) returning a Map.',
    );
  }

  /// Optional error logging sink.
  Object? get errlog => _errlog;
}
