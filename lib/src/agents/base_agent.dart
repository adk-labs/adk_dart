import 'dart:async';
import 'dart:developer' as developer;

import '../events/event.dart';
import '../events/event_actions.dart';
import '../types/content.dart';
import 'agent_state.dart';
import 'callback_context.dart';
import 'context.dart';
import 'invocation_context.dart';

typedef AgentLifecycleCallback =
    FutureOr<Content?> Function(CallbackContext callbackContext);

abstract class BaseAgent {
  BaseAgent({
    required this.name,
    this.description = '',
    List<BaseAgent>? subAgents,
    this.beforeAgentCallback,
    this.afterAgentCallback,
  }) : subAgents = subAgents ?? <BaseAgent>[] {
    _validateName(name);
    _setParentAgentForSubAgents();
    _validateSubAgentUniqueNames();
  }

  String name;
  String description;
  BaseAgent? parentAgent;
  List<BaseAgent> subAgents;

  Object? beforeAgentCallback;
  Object? afterAgentCallback;

  static const Set<String> baseCloneUpdateFields = <String>{
    'name',
    'description',
    'parentAgent',
    'subAgents',
    'beforeAgentCallback',
    'afterAgentCallback',
  };

  BaseAgentState? loadAgentState(InvocationContext context) {
    final Map<String, Object?>? raw = context.agentStates[name];
    if (raw == null) {
      return null;
    }
    return BaseAgentState(data: Map<String, Object?>.from(raw));
  }

  Event createAgentStateEvent(InvocationContext context) {
    final EventActions actions = EventActions();
    final Map<String, Object?>? state = context.agentStates[name];
    if (state != null) {
      actions.agentState = Map<String, Object?>.from(state);
    }
    if (context.endOfAgents[name] == true) {
      actions.endOfAgent = true;
    }

    return Event(
      invocationId: context.invocationId,
      author: name,
      branch: context.branch,
      actions: actions,
    );
  }

  Stream<Event> runAsync(InvocationContext parentContext) async* {
    final InvocationContext context = createInvocationContext(parentContext);

    final Event? before = await _handleBeforeAgentCallback(context);
    if (before != null) {
      yield before;
    }

    if (context.endInvocation) {
      return;
    }

    await for (final Event event in runAsyncImpl(context)) {
      yield event;
    }

    if (context.endInvocation) {
      return;
    }

    final Event? after = await _handleAfterAgentCallback(context);
    if (after != null) {
      yield after;
    }
  }

  Stream<Event> runLive(InvocationContext parentContext) async* {
    final InvocationContext context = createInvocationContext(parentContext);

    final Event? before = await _handleBeforeAgentCallback(context);
    if (before != null) {
      yield before;
    }

    if (context.endInvocation) {
      return;
    }

    await for (final Event event in runLiveImpl(context)) {
      yield event;
    }

    final Event? after = await _handleAfterAgentCallback(context);
    if (after != null) {
      yield after;
    }
  }

  Stream<Event> runAsyncImpl(InvocationContext context);

  Stream<Event> runLiveImpl(InvocationContext context) async* {
    // Default live behavior falls back to non-live execution.
    await for (final Event event in runAsyncImpl(context)) {
      yield event;
    }
  }

  BaseAgent clone({Map<String, Object?>? update}) {
    throw UnsupportedError('clone() is not implemented for `${runtimeType}`.');
  }

  BaseAgent get rootAgent {
    BaseAgent current = this;
    while (current.parentAgent != null) {
      current = current.parentAgent!;
    }
    return current;
  }

  BaseAgent? findAgent(String targetName) {
    if (name == targetName) {
      return this;
    }
    return findSubAgent(targetName);
  }

  BaseAgent? findSubAgent(String targetName) {
    for (final BaseAgent subAgent in subAgents) {
      final BaseAgent? found = subAgent.findAgent(targetName);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  InvocationContext createInvocationContext(InvocationContext parentContext) {
    return parentContext.copyWith(agent: this);
  }

  Map<String, Object?> normalizeCloneUpdate(Map<String, Object?>? update) {
    if (update == null) {
      return <String, Object?>{};
    }
    return Map<String, Object?>.from(update);
  }

  void validateCloneUpdateFields({
    required Map<String, Object?> update,
    required Set<String> allowedFields,
  }) {
    if (update.containsKey('parentAgent')) {
      throw ArgumentError(
        'Cannot update `parentAgent` field in clone. Parent agent is set only '
        'when the parent agent is instantiated with the sub-agents.',
      );
    }

    final Set<String> invalidFields = update.keys
        .where((String field) => !allowedFields.contains(field))
        .toSet();
    if (invalidFields.isNotEmpty) {
      throw ArgumentError(
        'Cannot update nonexistent fields in ${runtimeType}: $invalidFields',
      );
    }
  }

  T cloneFieldValue<T>({
    required Map<String, Object?> update,
    required String fieldName,
    required T currentValue,
  }) {
    if (!update.containsKey(fieldName)) {
      return currentValue;
    }
    return update[fieldName] as T;
  }

  Object? cloneObjectFieldValue({
    required Map<String, Object?> update,
    required String fieldName,
    required Object? currentValue,
  }) {
    if (update.containsKey(fieldName)) {
      return update[fieldName];
    }
    if (currentValue is List) {
      return List<Object?>.from(currentValue);
    }
    return currentValue;
  }

  List<T> cloneListFieldValue<T>({
    required Map<String, Object?> update,
    required String fieldName,
    required List<T> currentValue,
  }) {
    if (!update.containsKey(fieldName)) {
      return List<T>.from(currentValue);
    }

    final Object? updatedValue = update[fieldName];
    if (updatedValue is! List<T>) {
      throw ArgumentError.value(
        updatedValue,
        fieldName,
        'Expected `List<$T>` for `$fieldName`.',
      );
    }
    return updatedValue;
  }

  List<BaseAgent> cloneSubAgentsField(Map<String, Object?> update) {
    if (update.containsKey('subAgents')) {
      final Object? updatedValue = update['subAgents'];
      if (updatedValue is! List<BaseAgent>) {
        throw ArgumentError.value(
          updatedValue,
          'subAgents',
          'Expected `List<BaseAgent>` for `subAgents`.',
        );
      }
      return updatedValue;
    }

    return subAgents
        .map((BaseAgent subAgent) => subAgent.clone())
        .toList(growable: true);
  }

  void relinkClonedSubAgents(BaseAgent clonedAgent) {
    for (final BaseAgent subAgent in clonedAgent.subAgents) {
      subAgent.parentAgent = clonedAgent;
    }
    clonedAgent.parentAgent = null;
  }

  List<AgentLifecycleCallback> get canonicalBeforeAgentCallbacks {
    return _coerceAgentCallbacks(beforeAgentCallback);
  }

  List<AgentLifecycleCallback> get canonicalAfterAgentCallbacks {
    return _coerceAgentCallbacks(afterAgentCallback);
  }

  Future<Event?> _handleBeforeAgentCallback(InvocationContext context) async {
    final CallbackContext callbackContext = Context(context);

    Content? callbackContent = await context.pluginManager
        .runBeforeAgentCallback(agent: this, callbackContext: callbackContext);

    if (callbackContent == null) {
      for (final AgentLifecycleCallback callback
          in canonicalBeforeAgentCallbacks) {
        final Content? value = await Future<Content?>.value(
          callback(callbackContext),
        );
        if (value != null) {
          callbackContent = value;
          break;
        }
      }
    }

    if (callbackContent != null) {
      context.endInvocation = true;
      return Event(
        invocationId: context.invocationId,
        author: name,
        branch: context.branch,
        content: callbackContent,
        actions: callbackContext.actions,
      );
    }

    if (callbackContext.state.hasDelta()) {
      return Event(
        invocationId: context.invocationId,
        author: name,
        branch: context.branch,
        actions: callbackContext.actions,
      );
    }

    return null;
  }

  Future<Event?> _handleAfterAgentCallback(InvocationContext context) async {
    final CallbackContext callbackContext = Context(context);

    Content? callbackContent = await context.pluginManager
        .runAfterAgentCallback(agent: this, callbackContext: callbackContext);

    if (callbackContent == null) {
      for (final AgentLifecycleCallback callback
          in canonicalAfterAgentCallbacks) {
        final Content? value = await Future<Content?>.value(
          callback(callbackContext),
        );
        if (value != null) {
          callbackContent = value;
          break;
        }
      }
    }

    if (callbackContent != null) {
      return Event(
        invocationId: context.invocationId,
        author: name,
        branch: context.branch,
        content: callbackContent,
        actions: callbackContext.actions,
      );
    }

    if (callbackContext.state.hasDelta()) {
      return Event(
        invocationId: context.invocationId,
        author: name,
        branch: context.branch,
        actions: callbackContext.actions,
      );
    }

    return null;
  }

  List<AgentLifecycleCallback> _coerceAgentCallbacks(Object? callback) {
    if (callback == null) {
      return const <AgentLifecycleCallback>[];
    }
    if (callback is AgentLifecycleCallback) {
      return <AgentLifecycleCallback>[callback];
    }
    if (callback is List<AgentLifecycleCallback>) {
      return callback;
    }
    if (callback is List) {
      final List<AgentLifecycleCallback> callbacks = <AgentLifecycleCallback>[];
      for (final Object? entry in callback) {
        if (entry is! AgentLifecycleCallback) {
          throw ArgumentError(
            'Invalid callback entry type `${entry.runtimeType}` for '
            'agent `$name`.',
          );
        }
        callbacks.add(entry);
      }
      return callbacks;
    }
    throw ArgumentError(
      'Invalid callback type `${callback.runtimeType}` for agent `$name`.',
    );
  }

  void _validateName(String value) {
    final RegExp identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    if (!identifier.hasMatch(value)) {
      throw ArgumentError(
        'Invalid agent name `$value`. Agent name must be a valid identifier.',
      );
    }
    if (value == 'user') {
      throw ArgumentError(
        'Agent name cannot be `user`. `user` is reserved for end-user input.',
      );
    }
  }

  void _setParentAgentForSubAgents() {
    for (final BaseAgent subAgent in subAgents) {
      if (subAgent.parentAgent != null) {
        throw ArgumentError(
          'Agent `${subAgent.name}` already has a parent `${subAgent.parentAgent!.name}`.',
        );
      }
      subAgent.parentAgent = this;
    }
  }

  void _validateSubAgentUniqueNames() {
    final Set<String> seen = <String>{};
    final Set<String> duplicates = <String>{};
    for (final BaseAgent subAgent in subAgents) {
      if (!seen.add(subAgent.name)) {
        duplicates.add(subAgent.name);
      }
    }
    if (duplicates.isNotEmpty) {
      developer.log(
        'Found duplicate sub-agent names under `$name`: '
        '${duplicates.toList(growable: false)..sort()}',
        name: 'adk_dart.agents',
      );
    }
  }
}
