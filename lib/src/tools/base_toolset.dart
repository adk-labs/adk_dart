/// Base abstractions for grouped tool providers.
library;

import '../agents/readonly_context.dart';
import '../auth/auth_tool.dart';
import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

/// Predicate signature used to decide whether a tool is selectable.
typedef ToolPredicate =
    bool Function(BaseTool tool, ReadonlyContext? readonlyContext);

/// Base contract for grouped tool providers.
abstract class BaseToolset {
  /// Creates a toolset with optional filtering and name-prefix behavior.
  BaseToolset({this.toolFilter, this.toolNamePrefix});

  /// Tool filter expressed as a [ToolPredicate] or a list of tool names.
  Object? toolFilter;

  /// Optional prefix added by [getToolsWithPrefix].
  String? toolNamePrefix;

  /// Returns tools available for the current [readonlyContext].
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext});

  /// Returns [getTools] with an optional [toolNamePrefix] applied.
  Future<List<BaseTool>> getToolsWithPrefix({
    ReadonlyContext? readonlyContext,
  }) async {
    final List<BaseTool> tools = await getTools(
      readonlyContext: readonlyContext,
    );

    if (toolNamePrefix == null || toolNamePrefix!.isEmpty) {
      return tools;
    }

    final String prefix = toolNamePrefix!;
    return tools
        .map((BaseTool tool) => _PrefixedTool(delegate: tool, prefix: prefix))
        .toList();
  }

  /// Mutates outgoing [llmRequest] before model execution.
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    // Intentionally empty. Toolsets can override.
  }

  /// Returns auth config for this toolset, if tool listing/calls require auth.
  ///
  /// When non-null, the LLM flow resolves credentials before calling
  /// `getTools*` and can emit `adk_request_credential` interruption events.
  AuthConfig? getAuthConfig() => null;

  /// Releases resources held by this toolset.
  Future<void> close() async {}

  /// Returns whether [tool] should be visible in [readonlyContext].
  bool isToolSelected(BaseTool tool, ReadonlyContext? readonlyContext) {
    if (toolFilter == null) {
      return true;
    }

    if (toolFilter is ToolPredicate) {
      final ToolPredicate predicate = toolFilter as ToolPredicate;
      return predicate(tool, readonlyContext);
    }

    if (toolFilter is List<String>) {
      return (toolFilter as List<String>).contains(tool.name);
    }

    return false;
  }
}

class _PrefixedTool extends BaseTool {
  _PrefixedTool({required this.delegate, required this.prefix})
    : super(
        name: '${prefix}_${delegate.name}',
        description: delegate.description,
        isLongRunning: delegate.isLongRunning,
        customMetadata: delegate.customMetadata == null
            ? null
            : Map<String, dynamic>.from(delegate.customMetadata!),
      );

  final BaseTool delegate;
  final String prefix;

  @override
  FunctionDeclaration? getDeclaration() {
    final FunctionDeclaration? declaration = delegate.getDeclaration();
    if (declaration == null) {
      return null;
    }

    return declaration.copyWith(name: '${prefix}_${declaration.name}');
  }

  @override
  Future<Object?> run({
    required Map<String, dynamic> args,
    required ToolContext toolContext,
  }) {
    return delegate.run(args: args, toolContext: toolContext);
  }

  @override
  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    llmRequest.appendTools(<BaseTool>[this]);
  }
}
