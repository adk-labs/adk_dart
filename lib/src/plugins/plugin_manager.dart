import '../agents/base_agent.dart';
import '../agents/callback_context.dart';
import '../agents/invocation_context.dart';
import '../events/event.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../tools/base_tool.dart';
import '../tools/tool_context.dart';
import '../types/content.dart';
import 'base_plugin.dart';

class PluginManager {
  PluginManager({List<BasePlugin>? plugins, Duration? closeTimeout})
    : _closeTimeout = closeTimeout ?? const Duration(seconds: 5),
      _plugins = <BasePlugin>[] {
    if (plugins != null) {
      for (final BasePlugin plugin in plugins) {
        registerPlugin(plugin);
      }
    }
  }

  final Duration _closeTimeout;
  final List<BasePlugin> _plugins;

  List<BasePlugin> get plugins => List<BasePlugin>.unmodifiable(_plugins);

  void registerPlugin(BasePlugin plugin) {
    if (_plugins.any((BasePlugin item) => item.name == plugin.name)) {
      throw ArgumentError(
        'Plugin with name `${plugin.name}` already registered.',
      );
    }
    _plugins.add(plugin);
  }

  BasePlugin? getPlugin(String pluginName) {
    for (final BasePlugin plugin in _plugins) {
      if (plugin.name == pluginName) {
        return plugin;
      }
    }
    return null;
  }

  Future<Content?> runOnUserMessageCallback({
    required Content userMessage,
    required InvocationContext invocationContext,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      final Content? result = await plugin.onUserMessageCallback(
        userMessage: userMessage,
        invocationContext: invocationContext,
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<Content?> runBeforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      final Content? result = await plugin.beforeRunCallback(
        invocationContext: invocationContext,
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<void> runAfterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      await plugin.afterRunCallback(invocationContext: invocationContext);
    }
  }

  Future<Event?> runOnEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      final Event? result = await plugin.onEventCallback(
        invocationContext: invocationContext,
        event: event,
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<Content?> runBeforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      final Content? result = await plugin.beforeAgentCallback(
        agent: agent,
        callbackContext: callbackContext,
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<Content?> runAfterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      final Content? result = await plugin.afterAgentCallback(
        agent: agent,
        callbackContext: callbackContext,
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<LlmResponse?> runBeforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      final LlmResponse? result = await plugin.beforeModelCallback(
        callbackContext: callbackContext,
        llmRequest: llmRequest,
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<LlmResponse?> runAfterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      final LlmResponse? result = await plugin.afterModelCallback(
        callbackContext: callbackContext,
        llmResponse: llmResponse,
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<LlmResponse?> runOnModelErrorCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
    required Exception error,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      final LlmResponse? result = await plugin.onModelErrorCallback(
        callbackContext: callbackContext,
        llmRequest: llmRequest,
        error: error,
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> runBeforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      final Map<String, dynamic>? result = await plugin.beforeToolCallback(
        tool: tool,
        toolArgs: toolArgs,
        toolContext: toolContext,
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> runAfterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      final Map<String, dynamic>? altered = await plugin.afterToolCallback(
        tool: tool,
        toolArgs: toolArgs,
        toolContext: toolContext,
        result: result,
      );
      if (altered != null) {
        return altered;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> runOnToolErrorCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Exception error,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      final Map<String, dynamic>? result = await plugin.onToolErrorCallback(
        tool: tool,
        toolArgs: toolArgs,
        toolContext: toolContext,
        error: error,
      );
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<void> close() async {
    final List<String> errors = <String>[];
    for (final BasePlugin plugin in _plugins) {
      try {
        await plugin.close().timeout(_closeTimeout);
      } catch (error) {
        errors.add('${plugin.name}: $error');
      }
    }

    if (errors.isNotEmpty) {
      throw StateError('Failed to close plugins: ${errors.join(', ')}');
    }
  }
}
