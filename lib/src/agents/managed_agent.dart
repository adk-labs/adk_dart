/// Managed Agent implementation backed by the Google GenAI Interactions API.
library;

import 'dart:async';

import '../events/event.dart';
import '../models/gemini_rest_api_client.dart';
import '../models/interactions_utils.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../tools/base_tool.dart';
import '../tools/remote_mcp_server.dart';
import '../tools/tool_context.dart';
import '../types/content.dart';
import '../utils/google_client_headers.dart';
import '../utils/system_environment/system_environment.dart';
import '../flows/llm_flows/interactions_processor.dart';
import 'base_agent.dart';
import 'invocation_context.dart';
import 'readonly_context.dart';
import 'run_config.dart';

/// An agent backed by the Managed Agents API (interactions.create).
class ManagedAgent extends BaseAgent {
  /// Creates a Managed Agent.
  ManagedAgent({
    required super.name,
    super.description = '',
    required this.agentId,
    this.environment,
    this.agentConfig,
    List<Object>? tools,
    this.mode,
    GeminiRestTransport? restClient,
    String? apiKey,
    String? baseUrl,
  }) : tools = tools ?? <Object>[],
       _restClient = restClient,
       _apiKey = apiKey,
       _baseUrl = baseUrl;

  /// The Managed Agent identifier (e.g. 'projects/PROJECT/locations/global/agents/AGENT').
  final String agentId;

  /// A sandbox environment specification or an existing environment ID string.
  final Object? environment;

  /// Runtime configuration passed to interactions.create.
  final Map<String, dynamic>? agentConfig;

  /// Composition mode (e.g. 'single_turn').
  final String? mode;

  /// Server-side tools: ADK built-in tools, ToolDeclarations, or RemoteMcpServers.
  final List<Object> tools;

  final GeminiRestTransport? _restClient;
  final String? _apiKey;
  final String? _baseUrl;

  /// The REST transport client wrapper used to send request payloads.
  GeminiRestTransport get restClient => _restClient ?? GeminiRestHttpTransport();

  String _resolveApiKey() {
    if (_apiKey != null && _apiKey.isNotEmpty) {
      return _apiKey;
    }
    final Map<String, String> env = readSystemEnvironment();
    final String? envKey = env['GEMINI_API_KEY'] ?? env['GOOGLE_API_KEY'];
    if (envKey == null || envKey.isEmpty) {
      throw StateError(
        'ManagedAgent requires GEMINI_API_KEY or GOOGLE_API_KEY to be set.',
      );
    }
    return envKey;
  }

  String _resolveBaseUrl() {
    if (_baseUrl != null && _baseUrl.isNotEmpty) {
      return _baseUrl;
    }
    final Map<String, String> env = readSystemEnvironment();
    final String? envUrl = env['GEMINI_API_BASE'] ?? env['GOOGLE_API_BASE'];
    return envUrl ?? GeminiRestHttpTransport.defaultBaseUrl;
  }

  /// Resolve tools into interaction ToolParams (server-side only).
  Future<List<Map<String, Object?>>> resolveBackendTools(InvocationContext ctx) async {
    final LlmRequest llmRequest = LlmRequest(config: GenerateContentConfig());
    llmRequest.isManagedAgent = true;
    final ToolContext toolContext = ToolContext(ctx);
    final List<Map<String, Object?>> mcpParams = <Map<String, Object?>>[];

    for (final Object tool in tools) {
      if (tool is RemoteMcpServer) {
        final Map<String, String> resolvedHeaders = Map<String, String>.from(tool.headers ?? <String, String>{});
        if (tool.headerProvider != null) {
          final Map<String, String>? dynamicHeaders = await tool.headerProvider!(ReadonlyContext(ctx));
          if (dynamicHeaders != null) {
            resolvedHeaders.addAll(dynamicHeaders);
          }
        }
        final Map<String, Object?> param = <String, Object?>{
          'type': 'mcp_server',
          'url': tool.url,
          if (tool.name != null) 'name': tool.name,
          if (resolvedHeaders.isNotEmpty) 'headers': resolvedHeaders,
          if (tool.allowedTools != null)
            'allowed_tools': <Map<String, Object?>>[
              <String, Object?>{'tools': tool.allowedTools}
            ],
        };
        mcpParams.add(param);
        continue;
      }

      if (tool is ToolDeclaration) {
        if (tool.functionDeclarations.isNotEmpty) {
          throw UnsupportedError(
            'Client-executed tools are not supported by ManagedAgent: ${tool.functionDeclarations}',
          );
        }
        llmRequest.config.tools ??= <ToolDeclaration>[];
        llmRequest.config.tools!.add(tool);
        continue;
      }

      if (tool is BaseTool) {
        final int before = llmRequest.toolsDict.length;
        await tool.processLlmRequest(
          toolContext: toolContext,
          llmRequest: llmRequest,
        );
        if (llmRequest.toolsDict.length > before) {
          throw UnsupportedError(
            'Client-executed tools are not supported by ManagedAgent: ${tool.name}',
          );
        }
        continue;
      }

      throw UnsupportedError('Unsupported tool type for ManagedAgent: $tool');
    }

    final List<Map<String, Object?>> interactionTools =
        convertToolsConfigToInteractionsFormat(llmRequest.config);
    return <Map<String, Object?>>[...interactionTools, ...mcpParams];
  }

  Event _responseToEvent(InvocationContext ctx, LlmResponse llmResponse) {
    return Event(
      invocationId: ctx.invocationId,
      author: name,
      branch: ctx.branch,
      isolationScope: ctx.isolationScope,
      modelVersion: llmResponse.modelVersion,
      content: llmResponse.content,
      partial: llmResponse.partial,
      turnComplete: llmResponse.turnComplete,
      finishReason: llmResponse.finishReason,
      errorCode: llmResponse.errorCode,
      errorMessage: llmResponse.errorMessage,
      interrupted: llmResponse.interrupted,
      customMetadata: llmResponse.customMetadata,
      usageMetadata: llmResponse.usageMetadata,
      inputTranscription: llmResponse.inputTranscription,
      outputTranscription: llmResponse.outputTranscription,
      avgLogprobs: llmResponse.avgLogprobs,
      logprobsResult: llmResponse.logprobsResult,
      cacheMetadata: llmResponse.cacheMetadata,
      citationMetadata: llmResponse.citationMetadata,
      groundingMetadata: llmResponse.groundingMetadata,
      interactionId: llmResponse.interactionId,
      environmentId: llmResponse.environmentId,
      liveSessionId: llmResponse.liveSessionId,
      liveSessionResumptionUpdate: llmResponse.liveSessionResumptionUpdate,
      goAway: llmResponse.goAway,
    );
  }

  Event _errorEvent(
    InvocationContext ctx, {
    required String errorCode,
    required String errorMessage,
  }) {
    return Event(
      invocationId: ctx.invocationId,
      author: name,
      branch: ctx.branch,
      isolationScope: ctx.isolationScope,
      errorCode: errorCode,
      errorMessage: errorMessage,
      turnComplete: true,
    );
  }

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    final String apiKey = _resolveApiKey();
    final String baseUrl = _resolveBaseUrl();

    final (String? prevInteractionId, String? prevEnvironmentId) =
        findPreviousInteractionState(
      events: context.session.events,
      agentName: name,
      currentBranch: context.branch,
    );

    final Object? activeEnvironment = prevEnvironmentId ?? environment;

    final List<Map<String, Object?>> inputSteps = context.userContent == null
        ? const <Map<String, Object?>>[]
        : convertContentsToTurns(<Content>[context.userContent!]);

    final List<Map<String, Object?>> interactionTools =
        await resolveBackendTools(context);

    final Map<String, Object?> payload = <String, Object?>{
      'agent': agentId,
      'input': inputSteps,
      'background': true,
      if (interactionTools.isNotEmpty) 'tools': interactionTools,
      'environment': ?activeEnvironment,
      'agent_config': ?agentConfig,
      if (prevInteractionId != null && prevInteractionId.isNotEmpty)
        'previous_interaction_id': prevInteractionId,
    };

    final Map<String, String> headers = <String, String>{};
    // Include ADK tracking headers
    final Map<String, String> trackingHeaders = getTrackingHeaders();
    headers.addAll(trackingHeaders);

    final RunConfig? runConfig = context.runConfig;
    final bool isSse = runConfig != null && runConfig.streamingMode == StreamingMode.sse;

    try {
      final List<Part> aggregatedParts = <Part>[];
      String? currentInteractionId;
      String? currentEnvironmentId;
      bool emittedTerminal = false;

      await for (final Map<String, Object?> event
          in restClient.streamCreateInteraction(
            apiKey: apiKey,
            payload: payload,
            baseUrl: baseUrl,
            headers: headers,
          )) {
        currentInteractionId ??= _stringValue(event['id']) ??
            _stringValue(event['interaction_id']) ??
            _stringValue(event['interactionId']) ??
            _stringValue(_asMap(event['interaction'])['id']);

        currentEnvironmentId ??= _stringValue(event['environment_id']) ??
            _stringValue(event['environmentId']) ??
            _stringValue(_asMap(event['environment'])['id']);

        final LlmResponse? response = convertInteractionEventToLlmResponse(
          event,
          aggregatedParts,
          interactionId: currentInteractionId,
          fallbackModelVersion: agentId,
        );
        if (response == null) {
          continue;
        }
        response.interactionId ??= currentInteractionId;
        currentInteractionId ??= response.interactionId;
        response.environmentId = currentEnvironmentId;
        emittedTerminal = emittedTerminal || response.turnComplete == true;

        if (isSse || response.partial != true) {
          yield _responseToEvent(context, response);
        }
      }

      if (!emittedTerminal && aggregatedParts.isNotEmpty) {
        yield _responseToEvent(
          context,
          LlmResponse(
            modelVersion: agentId,
            content: Content(
              role: 'model',
              parts: aggregatedParts.map((Part p) => p.copyWith()).toList(),
            ),
            partial: false,
            turnComplete: true,
            finishReason: 'STOP',
            interactionId: currentInteractionId,
            environmentId: currentEnvironmentId,
          ),
        );
      }
    } catch (e) {
      yield _errorEvent(
        context,
        errorCode: 'UNKNOWN_ERROR',
        errorMessage: e.toString(),
      );
    }
  }
}

String? _stringValue(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return const <String, Object?>{};
}
