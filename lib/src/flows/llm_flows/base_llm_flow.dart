import 'dart:async';

import '../../agents/base_agent.dart';
import '../../agents/callback_context.dart';
import '../../agents/context.dart';
import '../../agents/invocation_context.dart';
import '../../agents/live_request_queue.dart';
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
import '../../models/base_llm_connection.dart';
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
    final LiveRequestQueue? liveQueue = context.liveRequestQueue;
    if (liveQueue == null) {
      await for (final Event event in runAsync(context)) {
        yield event;
      }
      return;
    }

    final BaseLlm llm = _getLlm(context);
    if (!_supportsLiveConnect(llm)) {
      await for (final Event event in _runLiveFallback(context, liveQueue)) {
        yield event;
      }
      return;
    }

    final LlmRequest request = LlmRequest();
    await for (final Event event in _preprocessAsync(context, request)) {
      yield event;
    }
    if (context.endInvocation) {
      return;
    }

    _applyLiveSessionResumptionHandle(context, request);

    final BaseLlmConnection connection = _connectLive(llm, request);
    Future<void>? sendTask;
    try {
      if (request.contents.isNotEmpty) {
        await connection.sendHistory(
          request.contents
              .map((Content content) => content.copyWith())
              .toList(growable: false),
        );
      }

      sendTask = _sendToModel(connection, context);
      await for (final Event event in _receiveFromModel(
        connection,
        context,
        request,
      )) {
        yield event;
        if (event.getFunctionResponses().isNotEmpty && event.content != null) {
          context.liveRequestQueue?.sendContent(event.content!.copyWith());
        }
      }
    } finally {
      context.liveRequestQueue?.close();
      if (sendTask != null) {
        try {
          await sendTask;
        } catch (_) {}
      }
      await connection.close();
    }
  }

  bool _supportsLiveConnect(BaseLlm llm) {
    final dynamic dynamicLlm = llm;
    try {
      final Object? connectMethod = dynamicLlm.connect;
      return connectMethod is Function;
    } on NoSuchMethodError {
      return false;
    }
  }

  BaseLlmConnection _connectLive(BaseLlm llm, LlmRequest request) {
    final dynamic dynamicLlm = llm;
    final Object? value = dynamicLlm.connect(request);
    if (value is! BaseLlmConnection) {
      throw StateError(
        'Model `${llm.runtimeType}` returned an invalid live connection.',
      );
    }
    return value;
  }

  Stream<Event> _runLiveFallback(
    InvocationContext context,
    LiveRequestQueue liveQueue,
  ) async* {
    while (true) {
      final LiveRequest liveRequest = await liveQueue.get();
      _fanOutLiveRequest(context, liveRequest);

      if (liveRequest.close) {
        break;
      }

      if (liveRequest.activityStart != null) {
        yield _buildLiveSignalEvent(context, 'live_activity_start');
      } else if (liveRequest.activityEnd != null) {
        yield _buildLiveSignalEvent(context, 'live_activity_end');
      } else if (liveRequest.blob != null) {
        final Event blobEvent = await _handleLiveBlob(
          context,
          liveRequest.blob!,
        );
        yield blobEvent;
      }

      final Content? content = liveRequest.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }

      _normalizeLiveContentRole(content);
      await _appendLiveUserContent(context, content);

      final InvocationContext turnContext = context.copyWith(
        userContent: content.copyWith(),
      );
      await for (final Event event in runAsync(turnContext)) {
        _maybeUpdateLiveSessionResumptionHandle(context, event.customMetadata);
        yield event;
      }

      if (turnContext.endInvocation) {
        context.endInvocation = true;
        break;
      }
    }
  }

  Future<void> _sendToModel(
    BaseLlmConnection connection,
    InvocationContext context,
  ) async {
    while (true) {
      final LiveRequestQueue? liveQueue = context.liveRequestQueue;
      if (liveQueue == null) {
        return;
      }

      final LiveRequest liveRequest = await liveQueue.get();
      _fanOutLiveRequest(context, liveRequest);

      await Future<void>.delayed(Duration.zero);
      if (liveRequest.close) {
        await connection.close();
        return;
      }

      if (liveRequest.activityStart != null) {
        await connection.sendRealtime(
          RealtimeBlob(
            mimeType: 'application/vnd.adk.activity_start',
            data: const <int>[],
          ),
        );
      } else if (liveRequest.activityEnd != null) {
        await connection.sendRealtime(
          RealtimeBlob(
            mimeType: 'application/vnd.adk.activity_end',
            data: const <int>[],
          ),
        );
      } else if (liveRequest.blob != null) {
        final RealtimeBlob realtimeBlob = _coerceRealtimeBlob(
          liveRequest.blob!,
        );
        if (realtimeBlob.mimeType.startsWith('audio/')) {
          audioCacheManager.cacheAudio(
            context,
            InlineData(
              mimeType: realtimeBlob.mimeType,
              data: List<int>.from(realtimeBlob.data),
            ),
            cacheType: 'input',
          );
        }
        await connection.sendRealtime(realtimeBlob);
      }

      final Content? content = liveRequest.content;
      if (content == null || content.parts.isEmpty) {
        continue;
      }
      _normalizeLiveContentRole(content);
      await _appendLiveUserContent(context, content);
      await connection.sendContent(content.copyWith());
    }
  }

  Stream<Event> _receiveFromModel(
    BaseLlmConnection connection,
    InvocationContext context,
    LlmRequest request,
  ) async* {
    await for (final LlmResponse response in connection.receive()) {
      _maybeUpdateLiveSessionResumptionHandle(context, response.customMetadata);

      final Event modelResponseEvent = Event(
        id: Event.newId(),
        invocationId: context.invocationId,
        author: response.content?.role == 'user' ? 'user' : context.agent.name,
        branch: context.branch,
      );

      await for (final Event event in _postprocessLive(
        context,
        request,
        response,
        modelResponseEvent,
      )) {
        if ((context.runConfig?.saveLiveBlob ?? false) &&
            event.content?.parts.isNotEmpty == true &&
            event.content!.parts.first.inlineData != null &&
            event.content!.parts.first.inlineData!.mimeType.startsWith(
              'audio/',
            )) {
          audioCacheManager.cacheAudio(
            context,
            event.content!.parts.first.inlineData!.copyWith(),
            cacheType: 'output',
          );
        }
        yield event;
      }
    }
  }

  Stream<Event> _postprocessLive(
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
        response.interrupted != true &&
        response.turnComplete != true &&
        response.inputTranscription == null &&
        response.outputTranscription == null &&
        response.usageMetadata == null) {
      return;
    }

    if (response.inputTranscription != null) {
      modelResponseEvent.inputTranscription = response.inputTranscription;
      modelResponseEvent.partial = response.partial;
      yield modelResponseEvent;
      return;
    }

    if (response.outputTranscription != null) {
      modelResponseEvent.outputTranscription = response.outputTranscription;
      modelResponseEvent.partial = response.partial;
      yield modelResponseEvent;
      return;
    }

    if (context.runConfig?.saveLiveBlob == true) {
      final List<Event> flushed = await handleControlEventFlush(
        context,
        response,
      );
      if (flushed.isNotEmpty) {
        for (final Event event in flushed) {
          yield event;
        }
        return;
      }
    }

    final Event finalized = _finalizeModelResponseEvent(
      request,
      response,
      modelResponseEvent,
    );
    yield finalized;

    if (finalized.getFunctionCalls().isNotEmpty) {
      final Event? functionResponseEvent = await flow_functions
          .handleFunctionCallsAsync(context, finalized, request.toolsDict);
      if (functionResponseEvent != null) {
        yield functionResponseEvent;
        final String? jsonResponse = output_schema.getStructuredModelResponse(
          functionResponseEvent,
        );
        if (jsonResponse != null) {
          yield output_schema.createFinalModelResponseEvent(
            context,
            jsonResponse,
          );
        }
      }
    }
  }

  void _fanOutLiveRequest(InvocationContext context, LiveRequest liveRequest) {
    final activeStreams = context.activeStreamingTools;
    if (activeStreams == null || activeStreams.isEmpty) {
      return;
    }

    for (final dynamic activeStream in activeStreams.values) {
      final LiveRequestQueue? stream = activeStream.stream;
      if (stream == null || identical(stream, context.liveRequestQueue)) {
        continue;
      }
      stream.send(liveRequest);
    }
  }

  void _normalizeLiveContentRole(Content content) {
    content.role ??= 'user';
    if (content.role!.isEmpty) {
      content.role = 'user';
    }
  }

  RealtimeBlob _coerceRealtimeBlob(Object blob) {
    if (blob is RealtimeBlob) {
      return RealtimeBlob(
        mimeType: blob.mimeType,
        data: List<int>.from(blob.data),
      );
    }
    if (blob is InlineData) {
      return RealtimeBlob(
        mimeType: blob.mimeType,
        data: List<int>.from(blob.data),
      );
    }
    if (blob is List<int>) {
      return RealtimeBlob(
        mimeType: 'application/octet-stream',
        data: List<int>.from(blob),
      );
    }
    if (blob is Map) {
      final Object? rawMimeType = blob['mimeType'] ?? blob['mime_type'];
      final Object? rawData = blob['data'];
      if (rawMimeType is String && rawData is List<int>) {
        return RealtimeBlob(
          mimeType: rawMimeType,
          data: List<int>.from(rawData),
        );
      }
      if (rawMimeType is String && rawData is List) {
        final List<int> bytes = <int>[];
        for (final Object? item in rawData) {
          if (item is! int) {
            throw ArgumentError.value(
              blob,
              'blob',
              'Realtime blob map data must contain bytes.',
            );
          }
          bytes.add(item);
        }
        return RealtimeBlob(mimeType: rawMimeType, data: bytes);
      }
    }

    throw ArgumentError.value(
      blob,
      'blob',
      'Unsupported live realtime blob payload.',
    );
  }

  void _applyLiveSessionResumptionHandle(
    InvocationContext context,
    LlmRequest request,
  ) {
    final String? handle = context.liveSessionResumptionHandle;
    if (handle == null || handle.isEmpty) {
      return;
    }

    final Object? sessionResumption =
        request.liveConnectConfig.sessionResumption;
    final Map<String, Object?> mutable = sessionResumption is Map
        ? sessionResumption.map(
            (Object? key, Object? value) =>
                MapEntry<String, Object?>('$key', value),
          )
        : <String, Object?>{};
    mutable['handle'] = handle;
    mutable['transparent'] = true;
    request.liveConnectConfig.sessionResumption = mutable;
  }

  void _maybeUpdateLiveSessionResumptionHandle(
    InvocationContext context,
    Map<String, dynamic>? metadata,
  ) {
    if (metadata == null || metadata.isEmpty) {
      return;
    }

    final Object? update =
        metadata['live_session_resumption_update'] ??
        metadata['liveSessionResumptionUpdate'];
    if (update is String && update.isNotEmpty) {
      context.liveSessionResumptionHandle = update;
      return;
    }
    if (update is Map) {
      final Object? handle =
          update['new_handle'] ?? update['newHandle'] ?? update['handle'];
      if (handle is String && handle.isNotEmpty) {
        context.liveSessionResumptionHandle = handle;
      }
      return;
    }

    final Object? topLevelHandle =
        metadata['new_handle'] ?? metadata['newHandle'] ?? metadata['handle'];
    if (topLevelHandle is String && topLevelHandle.isNotEmpty) {
      context.liveSessionResumptionHandle = topLevelHandle;
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
    final bool isFunctionResponse = content.parts.any(
      (Part part) => part.functionResponse != null,
    );
    if (isFunctionResponse) {
      return;
    }

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
      groundingMetadata: response.groundingMetadata,
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
