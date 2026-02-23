import '../agents/readonly_context.dart';
import 'base_tool.dart';
import 'base_toolset.dart';

typedef AuthTokenGetter = String Function();
typedef BoundParamProvider = Object? Function();

/// Delegate contract for toolbox SDK integrations.
abstract class ToolboxToolsetDelegate {
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext});

  Future<void> close();
}

class _MissingToolboxToolsetDelegate implements ToolboxToolsetDelegate {
  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    throw StateError(
      "ToolboxToolset requires a toolbox delegate. "
      'Please provide a ToolboxToolsetDelegate implementation backed by your toolbox SDK.',
    );
  }

  @override
  Future<void> close() async {}
}

class ToolboxToolset extends BaseToolset {
  ToolboxToolset({
    required this.serverUrl,
    this.toolsetName,
    this.toolNames,
    this.authTokenGetters,
    this.boundParams,
    this.credentials,
    this.additionalHeaders,
    this.additionalOptions,
    ToolboxToolsetDelegate? delegate,
  }) : _delegate = delegate ?? _MissingToolboxToolsetDelegate();

  final String serverUrl;
  final String? toolsetName;
  final List<String>? toolNames;
  final Map<String, AuthTokenGetter>? authTokenGetters;
  final Map<String, Object?>? boundParams;
  final Object? credentials;
  final Map<String, String>? additionalHeaders;
  final Map<String, Object?>? additionalOptions;

  final ToolboxToolsetDelegate _delegate;

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return _delegate.getTools(readonlyContext: readonlyContext);
  }

  @override
  Future<void> close() async {
    await _delegate.close();
  }
}
