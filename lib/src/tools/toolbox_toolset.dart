import '../agents/readonly_context.dart';
import 'base_tool.dart';
import 'base_toolset.dart';

typedef AuthTokenGetter = String Function();
typedef BoundParamProvider = Object? Function();
typedef ToolboxToolsetDelegateFactory = ToolboxToolsetDelegate Function({
  required String serverUrl,
  String? toolsetName,
  List<String>? toolNames,
  Map<String, AuthTokenGetter>? authTokenGetters,
  Map<String, Object?>? boundParams,
  Object? credentials,
  Map<String, String>? additionalHeaders,
  Map<String, Object?>? additionalOptions,
});

/// Delegate contract for toolbox SDK integrations.
abstract class ToolboxToolsetDelegate {
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext});

  Future<void> close();
}

class ToolboxToolset extends BaseToolset {
  static ToolboxToolsetDelegateFactory? _defaultDelegateFactory;

  /// Registers a default toolbox delegate factory used when [delegate] is not
  /// provided. Integrations can call this during startup.
  static void registerDefaultDelegateFactory(
    ToolboxToolsetDelegateFactory factory,
  ) {
    _defaultDelegateFactory = factory;
  }

  /// Clears the registered default toolbox delegate factory.
  static void clearDefaultDelegateFactory() {
    _defaultDelegateFactory = null;
  }

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
  }) : _delegate =
           delegate ??
           _createDefaultDelegateOrThrow(
             serverUrl: serverUrl,
             toolsetName: toolsetName,
             toolNames: toolNames,
             authTokenGetters: authTokenGetters,
             boundParams: boundParams,
             credentials: credentials,
             additionalHeaders: additionalHeaders,
             additionalOptions: additionalOptions,
           );

  final String serverUrl;
  final String? toolsetName;
  final List<String>? toolNames;
  final Map<String, AuthTokenGetter>? authTokenGetters;
  final Map<String, Object?>? boundParams;
  final Object? credentials;
  final Map<String, String>? additionalHeaders;
  final Map<String, Object?>? additionalOptions;

  final ToolboxToolsetDelegate _delegate;

  static ToolboxToolsetDelegate _createDefaultDelegateOrThrow({
    required String serverUrl,
    String? toolsetName,
    List<String>? toolNames,
    Map<String, AuthTokenGetter>? authTokenGetters,
    Map<String, Object?>? boundParams,
    Object? credentials,
    Map<String, String>? additionalHeaders,
    Map<String, Object?>? additionalOptions,
  }) {
    final ToolboxToolsetDelegateFactory? factory = _defaultDelegateFactory;
    if (factory == null) {
      throw StateError(
        "ToolboxToolset requires toolbox integration. "
        'Provide a ToolboxToolsetDelegate via `delegate`, '
        'or register a default toolbox delegate factory.',
      );
    }
    return factory(
      serverUrl: serverUrl,
      toolsetName: toolsetName,
      toolNames: toolNames == null ? null : List<String>.from(toolNames),
      authTokenGetters: authTokenGetters == null
          ? null
          : Map<String, AuthTokenGetter>.from(authTokenGetters),
      boundParams: boundParams == null
          ? null
          : Map<String, Object?>.from(boundParams),
      credentials: credentials,
      additionalHeaders: additionalHeaders == null
          ? null
          : Map<String, String>.from(additionalHeaders),
      additionalOptions: additionalOptions == null
          ? null
          : Map<String, Object?>.from(additionalOptions),
    );
  }

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    return _delegate.getTools(readonlyContext: readonlyContext);
  }

  @override
  Future<void> close() async {
    await _delegate.close();
  }
}
