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

class PluginManagerException implements Exception {
  PluginManagerException(this.message);

  final String message;

  @override
  String toString() => 'PluginManagerException: $message';
}

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

  Future<T?> _runCallbacks<T>({
    required String callbackName,
    required Future<T?> Function(BasePlugin plugin) invoke,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      try {
        final T? result = await invoke(plugin);
        if (result != null) {
          return result;
        }
      } catch (error) {
        throw PluginManagerException(
          "Error in plugin '${plugin.name}' during "
          "'$callbackName' callback: $error",
        );
      }
    }
    return null;
  }

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
    return _runCallbacks<Content>(
      callbackName: 'on_user_message_callback',
      invoke: (BasePlugin plugin) {
        return plugin.onUserMessageCallback(
          userMessage: userMessage,
          invocationContext: invocationContext,
        );
      },
    );
  }

  Future<Content?> runBeforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    return _runCallbacks<Content>(
      callbackName: 'before_run_callback',
      invoke: (BasePlugin plugin) {
        return plugin.beforeRunCallback(invocationContext: invocationContext);
      },
    );
  }

  Future<void> runAfterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    for (final BasePlugin plugin in _plugins) {
      try {
        await plugin.afterRunCallback(invocationContext: invocationContext);
      } catch (error) {
        throw PluginManagerException(
          "Error in plugin '${plugin.name}' during "
          "'after_run_callback' callback: $error",
        );
      }
    }
  }

  Future<Event?> runOnEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    return _runCallbacks<Event>(
      callbackName: 'on_event_callback',
      invoke: (BasePlugin plugin) {
        return plugin.onEventCallback(
          invocationContext: invocationContext,
          event: event,
        );
      },
    );
  }

  Future<Content?> runBeforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    return _runCallbacks<Content>(
      callbackName: 'before_agent_callback',
      invoke: (BasePlugin plugin) {
        return plugin.beforeAgentCallback(
          agent: agent,
          callbackContext: callbackContext,
        );
      },
    );
  }

  Future<Content?> runAfterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    return _runCallbacks<Content>(
      callbackName: 'after_agent_callback',
      invoke: (BasePlugin plugin) {
        return plugin.afterAgentCallback(
          agent: agent,
          callbackContext: callbackContext,
        );
      },
    );
  }

  Future<LlmResponse?> runBeforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    return _runCallbacks<LlmResponse>(
      callbackName: 'before_model_callback',
      invoke: (BasePlugin plugin) {
        return plugin.beforeModelCallback(
          callbackContext: callbackContext,
          llmRequest: llmRequest,
        );
      },
    );
  }

  Future<LlmResponse?> runAfterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    return _runCallbacks<LlmResponse>(
      callbackName: 'after_model_callback',
      invoke: (BasePlugin plugin) {
        return plugin.afterModelCallback(
          callbackContext: callbackContext,
          llmResponse: llmResponse,
        );
      },
    );
  }

  Future<LlmResponse?> runOnModelErrorCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
    required Exception error,
  }) async {
    return _runCallbacks<LlmResponse>(
      callbackName: 'on_model_error_callback',
      invoke: (BasePlugin plugin) {
        return plugin.onModelErrorCallback(
          callbackContext: callbackContext,
          llmRequest: llmRequest,
          error: error,
        );
      },
    );
  }

  Future<Map<String, dynamic>?> runBeforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    return _runCallbacks<Map<String, dynamic>>(
      callbackName: 'before_tool_callback',
      invoke: (BasePlugin plugin) {
        return plugin.beforeToolCallback(
          tool: tool,
          toolArgs: toolArgs,
          toolContext: toolContext,
        );
      },
    );
  }

  Future<Map<String, dynamic>?> runAfterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    return _runCallbacks<Map<String, dynamic>>(
      callbackName: 'after_tool_callback',
      invoke: (BasePlugin plugin) {
        return plugin.afterToolCallback(
          tool: tool,
          toolArgs: toolArgs,
          toolContext: toolContext,
          result: result,
        );
      },
    );
  }

  Future<Map<String, dynamic>?> runOnToolErrorCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Exception error,
  }) async {
    return _runCallbacks<Map<String, dynamic>>(
      callbackName: 'on_tool_error_callback',
      invoke: (BasePlugin plugin) {
        return plugin.onToolErrorCallback(
          tool: tool,
          toolArgs: toolArgs,
          toolContext: toolContext,
          error: error,
        );
      },
    );
  }

  Future<void> close() async {
    final Map<String, Object> errors = <String, Object>{};
    for (final BasePlugin plugin in _plugins) {
      try {
        await plugin.close().timeout(_closeTimeout);
      } catch (error) {
        errors[plugin.name] = error;
      }
    }

    if (errors.isNotEmpty) {
      final String summary = errors.entries
          .map((MapEntry<String, Object> entry) {
            return "'${entry.key}': ${entry.value.runtimeType}";
          })
          .join(', ');
      throw PluginManagerException('Failed to close plugins: $summary');
    }
  }
}
