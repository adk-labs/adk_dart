import '../agents/readonly_context.dart';
import '../models/llm_request.dart';
import 'base_tool.dart';
import 'tool_context.dart';

typedef ToolPredicate =
    bool Function(BaseTool tool, ReadonlyContext? readonlyContext);

abstract class BaseToolset {
  BaseToolset({this.toolFilter, this.toolNamePrefix});

  Object? toolFilter;
  String? toolNamePrefix;

  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext});

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

  Future<void> processLlmRequest({
    required ToolContext toolContext,
    required LlmRequest llmRequest,
  }) async {
    // Intentionally empty. Toolsets can override.
  }

  Future<void> close() async {}

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
