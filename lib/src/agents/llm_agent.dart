import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../events/event.dart';
import '../flows/llm_flows/auto_flow.dart';
import '../flows/llm_flows/base_llm_flow.dart';
import '../flows/llm_flows/single_flow.dart';
import '../models/base_llm.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../models/registry.dart';
import '../planners/built_in_planner.dart';
import '../tools/base_tool.dart';
import '../tools/base_toolset.dart';
import '../tools/discovery_engine_search_tool.dart';
import '../tools/function_tool.dart';
import '../tools/google_search_agent_tool.dart';
import '../tools/google_search_tool.dart';
import '../tools/tool_context.dart';
import '../tools/vertex_ai_search_tool.dart';
import '../types/content.dart';
import 'agent_state.dart';
import 'base_agent.dart';
import 'callback_context.dart';
import 'invocation_context.dart';
import 'readonly_context.dart';

typedef BeforeModelCallback =
    FutureOr<LlmResponse?> Function(
      CallbackContext callbackContext,
      LlmRequest llmRequest,
    );

typedef AfterModelCallback =
    FutureOr<LlmResponse?> Function(
      CallbackContext callbackContext,
      LlmResponse llmResponse,
    );

typedef OnModelErrorCallback =
    FutureOr<LlmResponse?> Function(
      CallbackContext callbackContext,
      LlmRequest llmRequest,
      Exception error,
    );

typedef BeforeToolCallback =
    FutureOr<Map<String, dynamic>?> Function(
      BaseTool tool,
      Map<String, dynamic> args,
      ToolContext toolContext,
    );

typedef AfterToolCallback =
    FutureOr<Map<String, dynamic>?> Function(
      BaseTool tool,
      Map<String, dynamic> args,
      ToolContext toolContext,
      Map<String, dynamic> toolResponse,
    );

typedef OnToolErrorCallback =
    FutureOr<Map<String, dynamic>?> Function(
      BaseTool tool,
      Map<String, dynamic> args,
      ToolContext toolContext,
      Exception error,
    );

typedef InstructionProvider =
    FutureOr<String> Function(ReadonlyContext context);

class LlmAgent extends BaseAgent {
  LlmAgent({
    required super.name,
    super.description,
    super.subAgents,
    super.beforeAgentCallback,
    super.afterAgentCallback,
    this.model = '',
    this.instruction = '',
    this.globalInstruction = '',
    this.staticInstruction,
    List<Object>? tools,
    this.generateContentConfig,
    this.disallowTransferToParent = false,
    this.disallowTransferToPeers = false,
    this.includeContents = 'default',
    this.inputSchema,
    this.outputSchema,
    this.outputKey,
    this.planner,
    this.codeExecutor,
    this.beforeModelCallback,
    this.afterModelCallback,
    this.onModelErrorCallback,
    this.beforeToolCallback,
    this.afterToolCallback,
    this.onToolErrorCallback,
  }) : tools = tools ?? <Object>[] {
    _validateGenerateContentConfig(generateContentConfig);
    _warnOnThinkingConfigPrecedence();
  }

  static const String defaultModel = 'gemini-2.5-flash';
  static Object _defaultModel = defaultModel;

  Object model;
  Object instruction;
  Object globalInstruction;
  Object? staticInstruction;
  List<Object> tools;

  GenerateContentConfig? generateContentConfig;

  bool disallowTransferToParent;
  bool disallowTransferToPeers;

  String includeContents;

  Object? inputSchema;
  Object? outputSchema;
  String? outputKey;

  Object? planner;
  Object? codeExecutor;

  Object? beforeModelCallback;
  Object? afterModelCallback;
  Object? onModelErrorCallback;

  Object? beforeToolCallback;
  Object? afterToolCallback;
  Object? onToolErrorCallback;

  @override
  LlmAgent clone({Map<String, Object?>? update}) {
    final Map<String, Object?> cloneUpdate = normalizeCloneUpdate(update);
    validateCloneUpdateFields(
      update: cloneUpdate,
      allowedFields: <String>{
        ...BaseAgent.baseCloneUpdateFields,
        'model',
        'instruction',
        'globalInstruction',
        'staticInstruction',
        'tools',
        'generateContentConfig',
        'disallowTransferToParent',
        'disallowTransferToPeers',
        'includeContents',
        'inputSchema',
        'outputSchema',
        'outputKey',
        'planner',
        'codeExecutor',
        'beforeModelCallback',
        'afterModelCallback',
        'onModelErrorCallback',
        'beforeToolCallback',
        'afterToolCallback',
        'onToolErrorCallback',
      },
    );

    final List<BaseAgent> clonedSubAgents = cloneSubAgentsField(cloneUpdate);
    final LlmAgent clonedAgent = LlmAgent(
      name: cloneFieldValue<String>(
        update: cloneUpdate,
        fieldName: 'name',
        currentValue: name,
      ),
      description: cloneFieldValue<String>(
        update: cloneUpdate,
        fieldName: 'description',
        currentValue: description,
      ),
      subAgents: <BaseAgent>[],
      beforeAgentCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'beforeAgentCallback',
        currentValue: beforeAgentCallback,
      ),
      afterAgentCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'afterAgentCallback',
        currentValue: afterAgentCallback,
      ),
      model:
          cloneObjectFieldValue(
                update: cloneUpdate,
                fieldName: 'model',
                currentValue: model,
              )
              as Object,
      instruction:
          cloneObjectFieldValue(
                update: cloneUpdate,
                fieldName: 'instruction',
                currentValue: instruction,
              )
              as Object,
      globalInstruction:
          cloneObjectFieldValue(
                update: cloneUpdate,
                fieldName: 'globalInstruction',
                currentValue: globalInstruction,
              )
              as Object,
      staticInstruction: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'staticInstruction',
        currentValue: staticInstruction,
      ),
      tools: cloneListFieldValue<Object>(
        update: cloneUpdate,
        fieldName: 'tools',
        currentValue: tools,
      ),
      generateContentConfig: cloneFieldValue<GenerateContentConfig?>(
        update: cloneUpdate,
        fieldName: 'generateContentConfig',
        currentValue: generateContentConfig,
      ),
      disallowTransferToParent: cloneFieldValue<bool>(
        update: cloneUpdate,
        fieldName: 'disallowTransferToParent',
        currentValue: disallowTransferToParent,
      ),
      disallowTransferToPeers: cloneFieldValue<bool>(
        update: cloneUpdate,
        fieldName: 'disallowTransferToPeers',
        currentValue: disallowTransferToPeers,
      ),
      includeContents: cloneFieldValue<String>(
        update: cloneUpdate,
        fieldName: 'includeContents',
        currentValue: includeContents,
      ),
      inputSchema: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'inputSchema',
        currentValue: inputSchema,
      ),
      outputSchema: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'outputSchema',
        currentValue: outputSchema,
      ),
      outputKey: cloneFieldValue<String?>(
        update: cloneUpdate,
        fieldName: 'outputKey',
        currentValue: outputKey,
      ),
      planner: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'planner',
        currentValue: planner,
      ),
      codeExecutor: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'codeExecutor',
        currentValue: codeExecutor,
      ),
      beforeModelCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'beforeModelCallback',
        currentValue: beforeModelCallback,
      ),
      afterModelCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'afterModelCallback',
        currentValue: afterModelCallback,
      ),
      onModelErrorCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'onModelErrorCallback',
        currentValue: onModelErrorCallback,
      ),
      beforeToolCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'beforeToolCallback',
        currentValue: beforeToolCallback,
      ),
      afterToolCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'afterToolCallback',
        currentValue: afterToolCallback,
      ),
      onToolErrorCallback: cloneObjectFieldValue(
        update: cloneUpdate,
        fieldName: 'onToolErrorCallback',
        currentValue: onToolErrorCallback,
      ),
    );
    clonedAgent.subAgents = clonedSubAgents;
    relinkClonedSubAgents(clonedAgent);
    return clonedAgent;
  }

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    final BaseAgentState? agentState = loadAgentState(context);

    if (agentState != null) {
      final BaseAgent? agentToResume = _getSubagentToResume(context);
      if (agentToResume != null) {
        await for (final Event event in agentToResume.runAsync(context)) {
          yield event;
        }
        context.setAgentState(name, endOfAgent: true);
        yield createAgentStateEvent(context);
        return;
      }
    }

    bool shouldPause = false;
    await for (final Event event in llmFlow.runAsync(context)) {
      _maybeSaveOutputToState(event);
      yield event;
      if (context.shouldPauseInvocation(event)) {
        shouldPause = true;
      }
    }

    if (shouldPause) {
      return;
    }

    if (context.isResumable) {
      final List<Event> events = context.getEvents(
        currentInvocation: true,
        currentBranch: true,
      );
      if (events.isNotEmpty &&
          events
              .skip(events.length > 2 ? events.length - 2 : 0)
              .any(context.shouldPauseInvocation)) {
        return;
      }
      context.setAgentState(name, endOfAgent: true);
      yield createAgentStateEvent(context);
    }
  }

  @override
  Stream<Event> runLiveImpl(InvocationContext context) async* {
    await for (final Event event in llmFlow.runLive(context)) {
      _maybeSaveOutputToState(event);
      yield event;
    }
  }

  BaseLlm get canonicalModel {
    if (model is BaseLlm) {
      return model as BaseLlm;
    }

    if (model is String && (model as String).isNotEmpty) {
      return LLMRegistry.newLlm(model as String);
    }

    BaseAgent? ancestor = parentAgent;
    while (ancestor != null) {
      if (ancestor is LlmAgent) {
        return ancestor.canonicalModel;
      }
      ancestor = ancestor.parentAgent;
    }

    return _resolveDefaultModel();
  }

  static void setDefaultModel(Object model) {
    if (model is! String && model is! BaseLlm) {
      throw ArgumentError('Default model must be a model name or BaseLlm.');
    }
    if (model is String && model.isEmpty) {
      throw ArgumentError('Default model must be a non-empty string.');
    }
    _defaultModel = model;
  }

  static BaseLlm _resolveDefaultModel() {
    final Object defaultValue = _defaultModel;
    if (defaultValue is BaseLlm) {
      return defaultValue;
    }
    return LLMRegistry.newLlm(defaultValue as String);
  }

  Future<(String, bool)> canonicalInstruction(ReadonlyContext context) async {
    final Object value = instruction;
    if (value is String) {
      return (value, false);
    }
    if (value is InstructionProvider) {
      return (await Future<String>.value(value(context)), true);
    }
    throw ArgumentError('instruction must be String or InstructionProvider.');
  }

  Future<(String, bool)> canonicalGlobalInstruction(
    ReadonlyContext context,
  ) async {
    final Object value = globalInstruction;
    if (value is String) {
      return (value, false);
    }
    if (value is InstructionProvider) {
      return (await Future<String>.value(value(context)), true);
    }
    throw ArgumentError(
      'globalInstruction must be String or InstructionProvider.',
    );
  }

  Future<List<BaseTool>> canonicalTools([ReadonlyContext? context]) async {
    final bool multipleTools = tools.length > 1;
    final List<Future<List<BaseTool>>> futures = tools
        .map(
          (Object toolUnion) => _convertToolUnionToTools(
            toolUnion,
            context,
            canonicalModel,
            multipleTools,
          ),
        )
        .toList();

    final List<List<BaseTool>> resolved = await Future.wait(futures);
    return resolved.expand((List<BaseTool> list) => list).toList();
  }

  List<BeforeModelCallback> get canonicalBeforeModelCallbacks {
    return _coerceCallbacks<BeforeModelCallback>(beforeModelCallback);
  }

  List<AfterModelCallback> get canonicalAfterModelCallbacks {
    return _coerceCallbacks<AfterModelCallback>(afterModelCallback);
  }

  List<OnModelErrorCallback> get canonicalOnModelErrorCallbacks {
    return _coerceCallbacks<OnModelErrorCallback>(onModelErrorCallback);
  }

  List<BeforeToolCallback> get canonicalBeforeToolCallbacks {
    return _coerceCallbacks<BeforeToolCallback>(beforeToolCallback);
  }

  List<AfterToolCallback> get canonicalAfterToolCallbacks {
    return _coerceCallbacks<AfterToolCallback>(afterToolCallback);
  }

  List<OnToolErrorCallback> get canonicalOnToolErrorCallbacks {
    return _coerceCallbacks<OnToolErrorCallback>(onToolErrorCallback);
  }

  BaseLlmFlow get llmFlow {
    if (disallowTransferToParent &&
        disallowTransferToPeers &&
        subAgents.isEmpty) {
      return SingleFlow();
    } else {
      return AutoFlow();
    }
  }

  BaseAgent? _getSubagentToResume(InvocationContext context) {
    final List<Event> events = context.getEvents(
      currentInvocation: true,
      currentBranch: true,
    );
    if (events.isEmpty) {
      return null;
    }

    final Event last = events.last;
    if (last.author == name) {
      return _getTransferToAgentOrNone(last, name);
    }

    if (last.author == 'user') {
      final Event? functionCallEvent = context.findMatchingFunctionCall(last);
      if (functionCallEvent == null) {
        throw StateError(
          'No agent to transfer to for resuming agent from function response $name',
        );
      }
      if (functionCallEvent.author == name) {
        return null;
      }
    }

    for (final Event event in events.reversed) {
      final BaseAgent? found = _getTransferToAgentOrNone(event, name);
      if (found != null) {
        return found;
      }
    }

    return null;
  }

  BaseAgent? _getTransferToAgentOrNone(Event event, String fromAgent) {
    final List<FunctionResponse> responses = event.getFunctionResponses();
    if (responses.isEmpty) {
      return null;
    }

    for (final FunctionResponse response in responses) {
      if (response.name == 'transfer_to_agent' &&
          event.author == fromAgent &&
          event.actions.transferToAgent != fromAgent) {
        final String? transferTo = event.actions.transferToAgent;
        if (transferTo == null) {
          return null;
        }
        return _getAgentToRun(transferTo);
      }
    }

    return null;
  }

  BaseAgent _getAgentToRun(String agentName) {
    final BaseAgent? agentToRun = rootAgent.findAgent(agentName);
    if (agentToRun == null) {
      throw StateError('Agent `$agentName` not found.');
    }
    return agentToRun;
  }

  void _maybeSaveOutputToState(Event event) {
    if (event.author != name) {
      return;
    }

    if (outputKey == null ||
        !event.isFinalResponse() ||
        event.content == null ||
        event.content!.parts.isEmpty) {
      return;
    }

    final String value = event.content!.parts
        .where((Part part) => part.text != null && !part.thought)
        .map((Part part) => part.text!)
        .join();

    if (outputSchema != null) {
      if (value.trim().isEmpty) {
        return;
      }
      event.actions.stateDelta[outputKey!] = jsonDecode(value);
      return;
    }

    event.actions.stateDelta[outputKey!] = value;
  }

  List<T> _coerceCallbacks<T>(Object? value) {
    if (value == null) {
      return <T>[];
    }
    if (value is T) {
      return <T>[value as T];
    }
    if (value is List<T>) {
      return value;
    }
    if (value is List) {
      final List<T> callbacks = <T>[];
      for (final Object? item in value) {
        if (item is! T) {
          throw ArgumentError(
            'Invalid callback entry type `${item.runtimeType}`.',
          );
        }
        callbacks.add(item);
      }
      return callbacks;
    }
    throw ArgumentError('Invalid callback value type `${value.runtimeType}`.');
  }

  void _validateGenerateContentConfig(GenerateContentConfig? config) {
    if (config == null) {
      return;
    }

    if (config.tools != null && config.tools!.isNotEmpty) {
      throw ArgumentError('All tools must be set via LlmAgent.tools.');
    }

    if (config.systemInstruction != null &&
        config.systemInstruction!.isNotEmpty) {
      throw ArgumentError(
        'System instruction must be set via LlmAgent.instruction.',
      );
    }

    if (config.responseSchema != null) {
      throw ArgumentError(
        'Response schema must be set via LlmAgent.outputSchema.',
      );
    }
  }

  void _warnOnThinkingConfigPrecedence() {
    if (generateContentConfig?.thinkingConfig == null) {
      return;
    }
    final Object? plannerConfig = planner;
    if (plannerConfig == null) {
      return;
    }

    Object? plannerThinkingConfig;
    if (plannerConfig is BuiltInPlanner) {
      plannerThinkingConfig = plannerConfig.thinkingConfig;
    } else {
      final dynamic dynamicPlanner = plannerConfig;
      try {
        plannerThinkingConfig = dynamicPlanner.thinkingConfig;
      } catch (_) {
        plannerThinkingConfig = null;
      }
    }

    if (plannerThinkingConfig != null) {
      developer.log(
        'Both `thinkingConfig` in `generateContentConfig` and planner '
        '`thinkingConfig` are provided. Planner thinkingConfig takes '
        'precedence.',
        name: 'adk_dart.agents',
      );
    }
  }
}

Future<List<BaseTool>> _convertToolUnionToTools(
  Object toolUnion,
  ReadonlyContext? context,
  BaseLlm model,
  bool multipleTools,
) async {
  if (multipleTools && toolUnion is GoogleSearchTool) {
    if (toolUnion.bypassMultiToolsLimit) {
      return <BaseTool>[
        GoogleSearchAgentTool(agent: createGoogleSearchAgent(model)),
      ];
    }
  }

  if (multipleTools && toolUnion is VertexAiSearchTool) {
    if (toolUnion.bypassMultiToolsLimit) {
      return <BaseTool>[
        DiscoveryEngineSearchTool(
          dataStoreId: toolUnion.dataStoreId,
          dataStoreSpecs: toolUnion.dataStoreSpecs,
          searchEngineId: toolUnion.searchEngineId,
          filter: toolUnion.filter,
          maxResults: toolUnion.maxResults,
        ),
      ];
    }
  }

  if (toolUnion is BaseTool) {
    return <BaseTool>[toolUnion];
  }

  if (toolUnion is Function) {
    final String generatedName =
        'tool_${toolUnion.hashCode.toUnsigned(32).toRadixString(16)}';
    return <BaseTool>[FunctionTool(func: toolUnion, name: generatedName)];
  }

  if (toolUnion is BaseToolset) {
    return toolUnion.getToolsWithPrefix(readonlyContext: context);
  }

  throw ArgumentError(
    'Unsupported tool union type `${toolUnion.runtimeType}` for model `${model.model}`.',
  );
}

typedef Agent = LlmAgent;
