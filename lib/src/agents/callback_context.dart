/// Type aliases and metadata for callback-facing context values.
library;

import 'dart:async';

import 'context.dart';

/// Mutable agent context exposed to callbacks.
typedef CallbackContext = Context;

/// Identifies the lifecycle stage of an executing callback.
enum CallbackType {
  /// Invoked before an agent runs.
  beforeAgent('before_agent'),

  /// Invoked after an agent finishes running.
  afterAgent('after_agent'),

  /// Invoked before a model request is sent.
  beforeModel('before_model'),

  /// Invoked after a model response is received.
  afterModel('after_model'),

  /// Invoked when a model call throws an error.
  onModelError('on_model_error'),

  /// Invoked before a tool is executed.
  beforeTool('before_tool'),

  /// Invoked after a tool finishes executing.
  afterTool('after_tool'),

  /// Invoked when a tool execution throws an error.
  onToolError('on_tool_error'),

  /// Invoked when an agent execution throws an error.
  onAgentError('on_agent_error'),

  /// Invoked when a user message is received by a plugin.
  onUserMessage('on_user_message'),

  /// Invoked before a runner invocation starts.
  beforeRun('before_run'),

  /// Invoked after a runner invocation completes.
  afterRun('after_run'),

  /// Invoked when an event is emitted during a runner invocation.
  onEvent('on_event'),

  /// Invoked when a runner invocation encounters an unhandled error.
  onRunError('on_run_error');

  const CallbackType(this.value);

  /// The canonical snake_case name of the callback hook.
  final String value;

  /// Looks up a [CallbackType] by its canonical [value] or `_callback`-suffixed
  /// alias, or returns `null` if unknown.
  static CallbackType? fromValue(String value) {
    for (final CallbackType type in CallbackType.values) {
      if (type.value == value || '${type.value}_callback' == value) {
        return type;
      }
    }
    return null;
  }
}

/// Metadata describing the currently executing callback.
class CallbackInfo {
  /// Creates callback metadata.
  const CallbackInfo({
    required this.type,
    required this.name,
    this.pluginName,
  });

  /// Lifecycle stage of the callback.
  final CallbackType type;

  /// Display name of the callback function or plugin hook.
  final String name;

  /// Name of the owning plugin when invoked from a plugin, or `null` otherwise.
  final String? pluginName;

  /// Whether this callback is executing from a plugin rather than an agent.
  bool get isFromPlugin => pluginName != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallbackInfo &&
          type == other.type &&
          name == other.name &&
          pluginName == other.pluginName;

  @override
  int get hashCode => Object.hash(type, name, pluginName);

  @override
  String toString() =>
      'CallbackInfo(type: $type, name: $name, pluginName: $pluginName)';
}

final Object _callbackScopeZoneKey = Object();
final RegExp _functionNamePattern = RegExp(r"Function '([^']+)'");

/// Returns the active [CallbackInfo] in the current async [Zone], if any.
CallbackInfo? get currentCallbackInfo =>
    Zone.current[_callbackScopeZoneKey] as CallbackInfo?;

/// Resolves a human-readable callback name for [callback].
String resolveCallbackName(Object callback, {String fallback = '<anonymous>'}) {
  final Match? match = _functionNamePattern.firstMatch(callback.toString());
  if (match != null) {
    final String rawName = match.group(1)!;
    final int atIndex = rawName.indexOf('@');
    return atIndex >= 0 ? rawName.substring(0, atIndex) : rawName;
  }
  if (callback is Function) {
    return fallback;
  }
  return callback.runtimeType.toString();
}

/// Runs [fn] within a [Zone] bound to [info] and binds [callbackContext]'s
/// scoped [Context.callbackInfo] when provided.
Future<T> runWithCallbackScope<T>(
  CallbackInfo info,
  FutureOr<T> Function() fn, {
  Context? callbackContext,
}) async {
  if (callbackContext == null) {
    return runZoned(
      () async => await fn(),
      zoneValues: <Object?, Object?>{_callbackScopeZoneKey: info},
    );
  }
  final CallbackInfo? previous = callbackContext.swapCallbackInfo(info);
  try {
    return await runZoned(
      () async => await fn(),
      zoneValues: <Object?, Object?>{_callbackScopeZoneKey: info},
    );
  } finally {
    callbackContext.swapCallbackInfo(previous);
  }
}

