import 'dart:async';

import '../../agents/base_agent.dart';
import '../../agents/callback_context.dart';
import '../../agents/context.dart';
import '../../agents/invocation_context.dart';
import '../../agents/llm_agent.dart';
import '../../agents/readonly_context.dart';
import '../../agents/run_config.dart';
import '../../auth/auth_credential.dart';
import '../../auth/auth_handler.dart';
import '../../auth/auth_tool.dart';
import '../../auth/credential_manager.dart';
import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../models/base_llm.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../tools/base_tool.dart';
import '../../tools/base_toolset.dart';
import '../../tools/tool_context.dart';
import '../../types/content.dart';
import 'audio_cache_manager.dart';
import 'functions.dart' as flow_functions;
import 'output_schema_processor.dart' as output_schema;

abstract class BaseLlmRequestProcessor {
  Stream<Event> runAsync(InvocationContext context, LlmRequest request);
}

abstract class BaseLlmResponseProcessor {
  Stream<Event> runAsync(InvocationContext context, LlmResponse response);
}

class BaseLlmFlow {
  BaseLlmFlow();

  final List<BaseLlmRequestProcessor> requestProcessors =
      <BaseLlmRequestProcessor>[];
  final List<BaseLlmResponseProcessor> responseProcessors =
      <BaseLlmResponseProcessor>[];
  final AudioCacheManager audioCacheManager = AudioCacheManager();

  Stream<Event> runLive(InvocationContext context) async* {
    final liveQueue = context.liveRequestQueue;
    if (liveQueue == null) {
      await for (final Event event in runAsync(context)) {
        yield event;
      }
      return;
    }

    while (true) {
      final liveRequest = await liveQueue.get();
      if (liveRequest.close) {
        break;
      }

      if (liveRequest.activityStart) {
        yield _buildLiveSignalEvent(context, 'live_activity_start');
        continue;
      }
      if (liveRequest.activityEnd) {
        yield _buildLiveSignalEvent(context, 'live_activity_end');
        continue;
      }
      if (liveRequest.blob != null) {
        final Event blobEvent = await _handleLiveBlob(
          context,
          liveRequest.blob!,
        );
        yield blobEvent;
        continue;
      }

      final Content? content = liveRequest.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }

      content.role ??= 'user';
      if (content.role!.isEmpty) {
        content.role = 'user';
      }

      await _appendLiveUserContent(context, content);

      final InvocationContext turnContext = context.copyWith(
        userContent: content.copyWith(),
      );
      await for (final Event event in runAsync(turnContext)) {
        yield event;
      }

      if (turnContext.endInvocation) {
        break;
      }
    }
  }

  Event _buildLiveSignalEvent(InvocationContext context, String signal) {
    return Event(
      invocationId: context.invocationId,
      author: 'user',
      branch: context.branch,
      content: Content(role: 'user', parts: <Part>[Part.text(signal)]),
    );
  }

  Future<Event> _handleLiveBlob(InvocationContext context, Object blob) async {
    final String blobText = blob is List<int>
        ? '[binary:${blob.length}]'
        : '$blob';
    final bool saveBlob = context.runConfig?.saveLiveBlob ?? false;
    if (!saveBlob || context.artifactService == null) {
      return Event(
        invocationId: context.invocationId,
        author: 'user',
        branch: context.branch,
        content: Content(
          role: 'user',
          parts: <Part>[Part.text('live_blob:$blobText')],
        ),
      );
    }

    final String filename =
        '_adk_live/live_blob_${DateTime.now().microsecondsSinceEpoch}.txt';
    final int version = await context.saveArtifact(
      filename: filename,
      artifact: Part.text(blobText),
    );

    return Event(
      invocationId: context.invocationId,
      author: 'user',
      branch: context.branch,
      content: Content(
        role: 'user',
        parts: <Part>[Part.text('Saved live blob as artifact: $filename')],
      ),
      actions: EventActions(artifactDelta: <String, int>{filename: version}),
    );
  }

  Future<void> _appendLiveUserContent(
    InvocationContext context,
    Content content,
  ) async {
    final Event event = Event(
      invocationId: context.invocationId,
      author: 'user',
      branch: context.branch,
      content: content.copyWith(),
    );
    await context.sessionService.appendEvent(
      session: context.session,
      event: event,
    );
  }

  Stream<Event> runAsync(InvocationContext context) async* {
    while (true) {
      Event? lastEvent;
      await for (final Event event in _runOneStepAsync(context)) {
        lastEvent = event;
        yield event;
      }

      if (lastEvent == null ||
          lastEvent.isFinalResponse() ||
          lastEvent.partial == true) {
        break;
      }
    }
  }

  Stream<Event> _runOneStepAsync(InvocationContext context) async* {
    final LlmRequest request = LlmRequest();

    await for (final Event event in _preprocessAsync(context, request)) {
      yield event;
    }

    if (context.endInvocation) {
      return;
    }

    final List<Event> events = context.getEvents(
      currentInvocation: true,
      currentBranch: true,
    );

    if (context.isResumable &&
        events.isNotEmpty &&
        context.shouldPauseInvocation(events.last)) {
      return;
    }

    if (context.isResumable &&
        events.isNotEmpty &&
        events.last.getFunctionCalls().isNotEmpty) {
      final Event functionCallEvent = events.last;
      await for (final Event event in _postprocessHandleFunctionCallsAsync(
        context,
        functionCallEvent,
        request,
      )) {
        yield event;
      }
      return;
    }

    final Event modelResponseEvent = Event(
      id: Event.newId(),
      invocationId: context.invocationId,
      author: context.agent.name,
      branch: context.branch,
    );

    await for (final LlmResponse response in _callLlmAsync(
      context,
      request,
      modelResponseEvent,
    )) {
      await for (final Event event in _postprocessAsync(
        context,
        request,
        response,
        modelResponseEvent,
      )) {
        modelResponseEvent.id = Event.newId();
        modelResponseEvent.timestamp =
            DateTime.now().millisecondsSinceEpoch / 1000;
        yield event;
      }
    }
  }

  Stream<Event> _preprocessAsync(
    InvocationContext context,
    LlmRequest request,
  ) async* {
    for (final BaseLlmRequestProcessor processor in requestProcessors) {
      await for (final Event event in processor.runAsync(context, request)) {
        yield event;
      }
    }

    if (context.endInvocation) {
      return;
    }

    await for (final Event event in _resolveToolsetAuth(context)) {
      yield event;
    }

    if (context.endInvocation) {
      return;
    }

    if (request.contents.isEmpty) {
      final LlmAgent agent = context.agent as LlmAgent;
      final List<Event> sourceEvents = switch (agent.includeContents) {
        'none' => const <Event>[],
        'current_turn' => context.getEvents(
          currentInvocation: true,
          currentBranch: true,
        ),
        _ => context.getEvents(currentBranch: true),
      };

      for (final Event event in sourceEvents) {
        final Content? content = event.content;
        if (content != null) {
          request.contents.add(content.copyWith());
        }
      }
    }

    await _processAgentTools(context, request);
  }

  Stream<Event> _resolveToolsetAuth(InvocationContext context) async* {
    final BaseAgent current = context.agent;
    if (current is! LlmAgent || current.tools.isEmpty) {
      return;
    }

    final Map<String, AuthConfig> pendingAuthRequests = <String, AuthConfig>{};
    final Context callbackContext = Context(context);

    for (final Object toolUnion in current.tools) {
      if (toolUnion is! BaseToolset) {
        continue;
      }

      final AuthConfig? authConfig = toolUnion.getAuthConfig();
      if (authConfig == null) {
        continue;
      }

      AuthCredential? credential;
      try {
        credential = await CredentialManager(
          authConfig: authConfig,
        ).getAuthCredential(callbackContext);
      } catch (_) {
        // Keep toolset execution tolerant to auth validation errors.
        continue;
      }

      if (credential != null) {
        authConfig.exchangedAuthCredential = credential;
        continue;
      }

      final String toolsetCredentialId =
          '$toolsetAuthCredentialIdPrefix${toolUnion.runtimeType}';
      try {
        pendingAuthRequests[toolsetCredentialId] = AuthHandler(
          authConfig: authConfig,
        ).generateAuthRequest();
      } on ArgumentError {
        // Invalid auth config should not block tools that can still run unauthenticated.
        continue;
      }
    }

    if (pendingAuthRequests.isEmpty) {
      return;
    }

    yield flow_functions.buildAuthRequestEvent(
      context,
      pendingAuthRequests,
      author: current.name,
    );
    context.endInvocation = true;
  }

  Future<void> _processAgentTools(
    InvocationContext context,
    LlmRequest request,
  ) async {
    final LlmAgent agent = context.agent as LlmAgent;
    final ToolContext toolContext = Context(context);
    if (agent.tools.isNotEmpty) {
      for (final Object toolUnion in agent.tools) {
        if (toolUnion is BaseToolset) {
          await toolUnion.processLlmRequest(
            toolContext: toolContext,
            llmRequest: request,
          );
        }
      }

      final List<BaseTool> tools = await agent.canonicalTools(
        ReadonlyContext(context),
      );
      for (final BaseTool tool in tools) {
        await tool.processLlmRequest(
          toolContext: toolContext,
          llmRequest: request,
        );
      }
    }
  }

  Stream<Event> _postprocessAsync(
    InvocationContext context,
    LlmRequest request,
    LlmResponse response,
    Event modelResponseEvent,
  ) async* {
    await for (final Event event in _postprocessRunProcessorsAsync(
      context,
      response,
    )) {
      yield event;
    }

    if (response.content == null &&
        response.errorCode == null &&
        response.interrupted != true) {
      return;
    }

    final Event finalized = _finalizeModelResponseEvent(
      request,
      response,
      modelResponseEvent,
    );
    yield finalized;

    if (finalized.getFunctionCalls().isNotEmpty) {
      if (finalized.partial == true) {
        return;
      }

      await for (final Event event in _postprocessHandleFunctionCallsAsync(
        context,
        finalized,
        request,
      )) {
        yield event;
      }
    }
  }

  Stream<Event> _postprocessRunProcessorsAsync(
    InvocationContext context,
    LlmResponse response,
  ) async* {
    for (final BaseLlmResponseProcessor processor in responseProcessors) {
      await for (final Event event in processor.runAsync(context, response)) {
        yield event;
      }
    }
  }

  Stream<Event> _postprocessHandleFunctionCallsAsync(
    InvocationContext context,
    Event functionCallEvent,
    LlmRequest request,
  ) async* {
    final Event? functionResponseEvent = await flow_functions
        .handleFunctionCallsAsync(
          context,
          functionCallEvent,
          request.toolsDict,
        );

    if (functionResponseEvent == null) {
      return;
    }

    final Event? authEvent = flow_functions.generateAuthEvent(
      context,
      functionResponseEvent,
    );
    if (authEvent != null) {
      yield authEvent;
    }

    final Event? confirmationEvent = flow_functions
        .generateRequestConfirmationEvent(
          context,
          functionCallEvent,
          functionResponseEvent,
        );
    if (confirmationEvent != null) {
      yield confirmationEvent;
    }

    yield functionResponseEvent;

    final String? jsonResponse = output_schema.getStructuredModelResponse(
      functionResponseEvent,
    );
    if (jsonResponse != null) {
      yield output_schema.createFinalModelResponseEvent(context, jsonResponse);
    }

    final String? transferToAgent =
        functionResponseEvent.actions.transferToAgent;
    if (transferToAgent != null && transferToAgent.isNotEmpty) {
      final BaseAgent agentToRun = _getAgentToRun(context, transferToAgent);
      await for (final Event event in agentToRun.runAsync(context)) {
        yield event;
      }
    }
  }

  Stream<LlmResponse> _callLlmAsync(
    InvocationContext context,
    LlmRequest request,
    Event modelResponseEvent,
  ) async* {
    final LlmResponse? beforeResponse = await _handleBeforeModelCallback(
      context,
      request,
      modelResponseEvent,
    );
    if (beforeResponse != null) {
      yield beforeResponse;
      return;
    }

    request.config.labels['adk_agent_name'] ??= context.agent.name;

    final BaseLlm llm = _getLlm(context);
    context.incrementLlmCallCount();

    try {
      await for (LlmResponse response in llm.generateContent(
        request.sanitizedForModelCall(),
        stream: context.runConfig?.streamingMode == StreamingMode.sse,
      )) {
        final LlmResponse? altered = await _handleAfterModelCallback(
          context,
          response,
          modelResponseEvent,
        );
        if (altered != null) {
          response = altered;
        }
        yield response;
      }
    } catch (error) {
      final Exception exception = error is Exception
          ? error
          : Exception(error.toString());
      final LlmResponse? handled = await _handleModelErrorCallbacks(
        context,
        request,
        modelResponseEvent,
        exception,
      );
      if (handled != null) {
        yield handled;
        return;
      }
      rethrow;
    }
  }

  Future<LlmResponse?> _handleBeforeModelCallback(
    InvocationContext context,
    LlmRequest request,
    Event modelResponseEvent,
  ) async {
    final LlmAgent agent = context.agent as LlmAgent;
    final CallbackContext callbackContext = Context(
      context,
      eventActions: modelResponseEvent.actions,
    );

    final LlmResponse? pluginOverride = await context.pluginManager
        .runBeforeModelCallback(
          callbackContext: callbackContext,
          llmRequest: request,
        );
    if (pluginOverride != null) {
      return pluginOverride;
    }

    for (final BeforeModelCallback callback
        in agent.canonicalBeforeModelCallbacks) {
      final LlmResponse? response = await Future<LlmResponse?>.value(
        callback(callbackContext, request),
      );
      if (response != null) {
        return response;
      }
    }

    return null;
  }

  Future<LlmResponse?> _handleAfterModelCallback(
    InvocationContext context,
    LlmResponse response,
    Event modelResponseEvent,
  ) async {
    final LlmAgent agent = context.agent as LlmAgent;
    final CallbackContext callbackContext = Context(
      context,
      eventActions: modelResponseEvent.actions,
    );

    final LlmResponse? pluginOverride = await context.pluginManager
        .runAfterModelCallback(
          callbackContext: callbackContext,
          llmResponse: response,
        );
    if (pluginOverride != null) {
      return pluginOverride;
    }

    for (final AfterModelCallback callback
        in agent.canonicalAfterModelCallbacks) {
      final LlmResponse? altered = await Future<LlmResponse?>.value(
        callback(callbackContext, response),
      );
      if (altered != null) {
        return altered;
      }
    }

    return null;
  }

  Future<LlmResponse?> _handleModelErrorCallbacks(
    InvocationContext context,
    LlmRequest request,
    Event modelResponseEvent,
    Exception error,
  ) async {
    final LlmAgent agent = context.agent as LlmAgent;
    final CallbackContext callbackContext = Context(
      context,
      eventActions: modelResponseEvent.actions,
    );

    final LlmResponse? pluginHandled = await context.pluginManager
        .runOnModelErrorCallback(
          callbackContext: callbackContext,
          llmRequest: request,
          error: error,
        );
    if (pluginHandled != null) {
      return pluginHandled;
    }

    for (final OnModelErrorCallback callback
        in agent.canonicalOnModelErrorCallbacks) {
      final LlmResponse? handled = await Future<LlmResponse?>.value(
        callback(callbackContext, request, error),
      );
      if (handled != null) {
        return handled;
      }
    }

    return null;
  }

  Event _finalizeModelResponseEvent(
    LlmRequest request,
    LlmResponse response,
    Event modelResponseEvent,
  ) {
    final Event finalized = modelResponseEvent.copyWith(
      modelVersion: response.modelVersion,
      content: response.content?.copyWith(),
      partial: response.partial,
      turnComplete: response.turnComplete,
      finishReason: response.finishReason,
      errorCode: response.errorCode,
      errorMessage: response.errorMessage,
      interrupted: response.interrupted,
      customMetadata: response.customMetadata,
      usageMetadata: response.usageMetadata,
      inputTranscription: response.inputTranscription,
      outputTranscription: response.outputTranscription,
      avgLogprobs: response.avgLogprobs,
      logprobsResult: response.logprobsResult,
      cacheMetadata: response.cacheMetadata,
      citationMetadata: response.citationMetadata,
      interactionId: response.interactionId,
    );

    if (finalized.content != null) {
      final List<FunctionCall> calls = finalized.getFunctionCalls();
      if (calls.isNotEmpty) {
        flow_functions.populateClientFunctionCallId(finalized);
        finalized.longRunningToolIds = flow_functions
            .getLongRunningFunctionCalls(calls, request.toolsDict);
      }
    }

    return finalized;
  }

  Future<List<Event>> handleControlEventFlush(
    InvocationContext context,
    LlmResponse response,
  ) async {
    if (response.interrupted == true) {
      return audioCacheManager.flushCaches(
        context,
        flushUserAudio: false,
        flushModelAudio: true,
      );
    }
    if (response.turnComplete == true) {
      return audioCacheManager.flushCaches(
        context,
        flushUserAudio: true,
        flushModelAudio: true,
      );
    }
    return const <Event>[];
  }

  BaseLlm _getLlm(InvocationContext context) {
    final LlmAgent agent = context.agent as LlmAgent;
    return agent.canonicalModel;
  }

  BaseAgent _getAgentToRun(InvocationContext context, String agentName) {
    final BaseAgent? agent = context.agent.rootAgent.findAgent(agentName);
    if (agent == null) {
      throw StateError('Agent $agentName not found in the agent tree.');
    }
    return agent;
  }
}
