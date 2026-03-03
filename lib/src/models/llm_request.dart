/// Model request payload and tool declaration schemas.
library;

import 'dart:developer' as developer;

import '../tools/base_tool.dart';
import '../types/content.dart';

ToolDeclaration? _findToolWithFunctionDeclarations(LlmRequest request) {
  final List<ToolDeclaration>? tools = request.config.tools;
  if (tools == null) {
    return null;
  }
  for (final ToolDeclaration tool in tools) {
    if (tool.functionDeclarations.isNotEmpty) {
      return tool;
    }
  }
  return null;
}

/// Function-calling declaration exposed to the model.
class FunctionDeclaration {
  /// Creates a function declaration.
  FunctionDeclaration({
    required this.name,
    this.description = '',
    JsonMap? parameters,
  }) : parameters = parameters ?? <String, dynamic>{};

  /// The function name.
  String name;

  /// The function description shown to the model.
  String description;

  /// JSON schema parameters for the function.
  JsonMap parameters;

  /// Returns a copy of this declaration with optional overrides.
  FunctionDeclaration copyWith({
    String? name,
    String? description,
    JsonMap? parameters,
  }) {
    return FunctionDeclaration(
      name: name ?? this.name,
      description: description ?? this.description,
      parameters: parameters ?? Map<String, dynamic>.from(this.parameters),
    );
  }
}

/// Retry policy for HTTP model requests.
class HttpRetryOptions {
  /// Creates HTTP retry options.
  HttpRetryOptions({
    this.attempts,
    this.initialDelay,
    this.maxDelay,
    this.expBase,
    List<int>? httpStatusCodes,
  }) : httpStatusCodes = httpStatusCodes ?? <int>[];

  /// Maximum number of retry attempts.
  int? attempts;

  /// Initial retry delay in seconds.
  double? initialDelay;

  /// Maximum retry delay in seconds.
  double? maxDelay;

  /// Exponential backoff multiplier.
  double? expBase;

  /// HTTP status codes that should be retried.
  List<int> httpStatusCodes;

  /// Returns a copy of these retry options with optional overrides.
  HttpRetryOptions copyWith({
    Object? attempts = _sentinel,
    Object? initialDelay = _sentinel,
    Object? maxDelay = _sentinel,
    Object? expBase = _sentinel,
    List<int>? httpStatusCodes,
  }) {
    return HttpRetryOptions(
      attempts: identical(attempts, _sentinel)
          ? this.attempts
          : attempts as int?,
      initialDelay: identical(initialDelay, _sentinel)
          ? this.initialDelay
          : initialDelay as double?,
      maxDelay: identical(maxDelay, _sentinel)
          ? this.maxDelay
          : maxDelay as double?,
      expBase: identical(expBase, _sentinel)
          ? this.expBase
          : expBase as double?,
      httpStatusCodes: httpStatusCodes ?? List<int>.from(this.httpStatusCodes),
    );
  }
}

/// HTTP configuration for model API requests.
class HttpOptions {
  /// Creates HTTP options.
  HttpOptions({
    this.retryOptions,
    Map<String, String>? headers,
    this.apiVersion,
  }) : headers = headers ?? <String, String>{};

  /// Retry policy for outbound requests.
  HttpRetryOptions? retryOptions;

  /// Additional HTTP headers.
  Map<String, String> headers;

  /// Optional API version override.
  String? apiVersion;

  /// Returns a copy of these HTTP options with optional overrides.
  HttpOptions copyWith({
    Object? retryOptions = _sentinel,
    Map<String, String>? headers,
    Object? apiVersion = _sentinel,
  }) {
    return HttpOptions(
      retryOptions: identical(retryOptions, _sentinel)
          ? this.retryOptions?.copyWith()
          : retryOptions as HttpRetryOptions?,
      headers: headers ?? Map<String, String>.from(this.headers),
      apiVersion: identical(apiVersion, _sentinel)
          ? this.apiVersion
          : apiVersion as String?,
    );
  }
}

/// Tool declaration payload sent to model backends.
class ToolDeclaration {
  /// Creates a tool declaration.
  ToolDeclaration({
    List<FunctionDeclaration>? functionDeclarations,
    this.googleSearch,
    this.googleSearchRetrieval,
    this.urlContext,
    this.codeExecution,
    this.googleMaps,
    this.enterpriseWebSearch,
    this.retrieval,
    this.computerUse,
  }) : functionDeclarations = functionDeclarations ?? <FunctionDeclaration>[];

  /// Function-calling declarations exposed under this tool entry.
  List<FunctionDeclaration> functionDeclarations;

  /// Backend-specific Google Search tool config.
  Object? googleSearch;

  /// Backend-specific Google Search Retrieval tool config.
  Object? googleSearchRetrieval;

  /// Backend-specific URL Context tool config.
  Object? urlContext;

  /// Backend-specific code execution tool config.
  Object? codeExecution;

  /// Backend-specific Google Maps tool config.
  Object? googleMaps;

  /// Backend-specific enterprise web search tool config.
  Object? enterpriseWebSearch;

  /// Backend-specific retrieval tool config.
  Object? retrieval;

  /// Backend-specific computer use tool config.
  Object? computerUse;

  /// Returns a copy of this tool declaration with optional overrides.
  ToolDeclaration copyWith({
    List<FunctionDeclaration>? functionDeclarations,
    Object? googleSearch = _sentinel,
    Object? googleSearchRetrieval = _sentinel,
    Object? urlContext = _sentinel,
    Object? codeExecution = _sentinel,
    Object? googleMaps = _sentinel,
    Object? enterpriseWebSearch = _sentinel,
    Object? retrieval = _sentinel,
    Object? computerUse = _sentinel,
  }) {
    return ToolDeclaration(
      functionDeclarations:
          functionDeclarations ??
          this.functionDeclarations
              .map((declaration) => declaration.copyWith())
              .toList(),
      googleSearch: identical(googleSearch, _sentinel)
          ? this.googleSearch
          : googleSearch,
      googleSearchRetrieval: identical(googleSearchRetrieval, _sentinel)
          ? this.googleSearchRetrieval
          : googleSearchRetrieval,
      urlContext: identical(urlContext, _sentinel)
          ? this.urlContext
          : urlContext,
      codeExecution: identical(codeExecution, _sentinel)
          ? this.codeExecution
          : codeExecution,
      googleMaps: identical(googleMaps, _sentinel)
          ? this.googleMaps
          : googleMaps,
      enterpriseWebSearch: identical(enterpriseWebSearch, _sentinel)
          ? this.enterpriseWebSearch
          : enterpriseWebSearch,
      retrieval: identical(retrieval, _sentinel) ? this.retrieval : retrieval,
      computerUse: identical(computerUse, _sentinel)
          ? this.computerUse
          : computerUse,
    );
  }
}

/// Function-calling modes recognized by model providers.
enum FunctionCallingConfigMode { modeUnspecified, auto, any, none }

/// Function-calling configuration attached to tool settings.
class FunctionCallingConfig {
  /// Creates a function-calling configuration.
  FunctionCallingConfig({
    this.mode = FunctionCallingConfigMode.modeUnspecified,
    List<String>? allowedFunctionNames,
  }) : allowedFunctionNames = allowedFunctionNames ?? <String>[];

  /// Provider mode controlling function-calling behavior.
  FunctionCallingConfigMode mode;

  /// Allowed function names when mode constrains the callable set.
  List<String> allowedFunctionNames;

  /// Returns a copy of this function-calling configuration.
  FunctionCallingConfig copyWith({
    FunctionCallingConfigMode? mode,
    List<String>? allowedFunctionNames,
  }) {
    return FunctionCallingConfig(
      mode: mode ?? this.mode,
      allowedFunctionNames:
          allowedFunctionNames ?? List<String>.from(this.allowedFunctionNames),
    );
  }
}

/// Tool-level configuration wrapper for model requests.
class LlmToolConfig {
  /// Creates an LLM tool configuration.
  LlmToolConfig({this.functionCallingConfig});

  /// Function-calling behavior for tool execution.
  FunctionCallingConfig? functionCallingConfig;

  /// Returns a copy of this tool configuration with optional overrides.
  LlmToolConfig copyWith({Object? functionCallingConfig = _sentinel}) {
    return LlmToolConfig(
      functionCallingConfig: identical(functionCallingConfig, _sentinel)
          ? this.functionCallingConfig?.copyWith()
          : functionCallingConfig as FunctionCallingConfig?,
    );
  }
}

/// Generation configuration for text/content model calls.
class GenerateContentConfig {
  /// Creates generation settings for content requests.
  GenerateContentConfig({
    this.tools,
    this.systemInstruction,
    this.temperature,
    this.topP,
    this.topK,
    this.maxOutputTokens,
    List<String>? stopSequences,
    this.frequencyPenalty,
    this.presencePenalty,
    this.seed,
    this.candidateCount,
    this.responseLogprobs,
    this.logprobs,
    this.thinkingConfig,
    this.responseSchema,
    this.responseJsonSchema,
    this.responseMimeType,
    this.toolConfig,
    this.cachedContent,
    this.httpOptions,
    Map<String, String>? labels,
  }) : stopSequences = stopSequences ?? <String>[],
       labels = labels ?? <String, String>{};

  /// Tool declarations available to the model.
  List<ToolDeclaration>? tools;

  /// System instruction text sent with the request.
  String? systemInstruction;

  /// Sampling temperature.
  double? temperature;

  /// Nucleus sampling parameter.
  double? topP;

  /// Top-k sampling parameter.
  int? topK;

  /// Maximum output token count.
  int? maxOutputTokens;

  /// Stop sequences that terminate generation.
  List<String> stopSequences;

  /// Frequency penalty parameter.
  double? frequencyPenalty;

  /// Presence penalty parameter.
  double? presencePenalty;

  /// Seed used for deterministic sampling.
  int? seed;

  /// Number of response candidates to request.
  int? candidateCount;

  /// Whether to include response log probabilities.
  bool? responseLogprobs;

  /// Number of top log probabilities to return.
  int? logprobs;

  /// Provider-specific thinking configuration.
  Object? thinkingConfig;

  /// Provider-specific structured response schema.
  Object? responseSchema;

  /// Raw JSON schema payload for structured outputs.
  Object? responseJsonSchema;

  /// Preferred response MIME type.
  String? responseMimeType;

  /// Tool execution configuration.
  LlmToolConfig? toolConfig;

  /// Cached content resource identifier.
  String? cachedContent;

  /// HTTP options for outbound model calls.
  HttpOptions? httpOptions;

  /// Provider labels attached to this request.
  Map<String, String> labels;

  /// Returns a copy of this generation configuration.
  GenerateContentConfig copyWith({
    Object? tools = _sentinel,
    Object? systemInstruction = _sentinel,
    Object? temperature = _sentinel,
    Object? topP = _sentinel,
    Object? topK = _sentinel,
    Object? maxOutputTokens = _sentinel,
    List<String>? stopSequences,
    Object? frequencyPenalty = _sentinel,
    Object? presencePenalty = _sentinel,
    Object? seed = _sentinel,
    Object? candidateCount = _sentinel,
    Object? responseLogprobs = _sentinel,
    Object? logprobs = _sentinel,
    Object? thinkingConfig = _sentinel,
    Object? responseSchema = _sentinel,
    Object? responseJsonSchema = _sentinel,
    Object? responseMimeType = _sentinel,
    Object? toolConfig = _sentinel,
    Object? cachedContent = _sentinel,
    Object? httpOptions = _sentinel,
    Map<String, String>? labels,
  }) {
    return GenerateContentConfig(
      tools: identical(tools, _sentinel)
          ? this.tools?.map((declaration) => declaration.copyWith()).toList()
          : tools as List<ToolDeclaration>?,
      systemInstruction: identical(systemInstruction, _sentinel)
          ? this.systemInstruction
          : systemInstruction as String?,
      temperature: identical(temperature, _sentinel)
          ? this.temperature
          : temperature as double?,
      topP: identical(topP, _sentinel) ? this.topP : topP as double?,
      topK: identical(topK, _sentinel) ? this.topK : topK as int?,
      maxOutputTokens: identical(maxOutputTokens, _sentinel)
          ? this.maxOutputTokens
          : maxOutputTokens as int?,
      stopSequences: stopSequences ?? List<String>.from(this.stopSequences),
      frequencyPenalty: identical(frequencyPenalty, _sentinel)
          ? this.frequencyPenalty
          : frequencyPenalty as double?,
      presencePenalty: identical(presencePenalty, _sentinel)
          ? this.presencePenalty
          : presencePenalty as double?,
      seed: identical(seed, _sentinel) ? this.seed : seed as int?,
      candidateCount: identical(candidateCount, _sentinel)
          ? this.candidateCount
          : candidateCount as int?,
      responseLogprobs: identical(responseLogprobs, _sentinel)
          ? this.responseLogprobs
          : responseLogprobs as bool?,
      logprobs: identical(logprobs, _sentinel)
          ? this.logprobs
          : logprobs as int?,
      thinkingConfig: identical(thinkingConfig, _sentinel)
          ? this.thinkingConfig
          : thinkingConfig,
      responseSchema: identical(responseSchema, _sentinel)
          ? this.responseSchema
          : responseSchema,
      responseJsonSchema: identical(responseJsonSchema, _sentinel)
          ? this.responseJsonSchema
          : responseJsonSchema,
      responseMimeType: identical(responseMimeType, _sentinel)
          ? this.responseMimeType
          : responseMimeType as String?,
      toolConfig: identical(toolConfig, _sentinel)
          ? this.toolConfig?.copyWith()
          : toolConfig as LlmToolConfig?,
      cachedContent: identical(cachedContent, _sentinel)
          ? this.cachedContent
          : cachedContent as String?,
      httpOptions: identical(httpOptions, _sentinel)
          ? this.httpOptions?.copyWith()
          : httpOptions as HttpOptions?,
      labels: labels ?? Map<String, String>.from(this.labels),
    );
  }
}

/// Realtime connection configuration for live model sessions.
class LiveConnectConfig {
  /// Creates live connection settings.
  LiveConnectConfig({
    this.responseModalities,
    this.speechConfig,
    this.outputAudioTranscription,
    this.inputAudioTranscription,
    this.systemInstruction,
    this.tools,
    this.httpOptions,
    this.realtimeInputConfig,
    this.enableAffectiveDialog,
    this.proactivity,
    this.sessionResumption,
    this.contextWindowCompression,
  });

  /// Requested response modalities, such as text or audio.
  List<String>? responseModalities;

  /// Provider-specific speech configuration.
  Object? speechConfig;

  /// Provider output transcription configuration.
  Object? outputAudioTranscription;

  /// Provider input transcription configuration.
  Object? inputAudioTranscription;

  /// System instruction payload for the live session.
  Object? systemInstruction;

  /// Tool declarations available during live sessions.
  List<ToolDeclaration>? tools;

  /// HTTP options for the live session.
  HttpOptions? httpOptions;

  /// Provider realtime input configuration.
  Object? realtimeInputConfig;

  /// Whether affective dialog behavior is enabled.
  bool? enableAffectiveDialog;

  /// Provider proactivity configuration.
  Object? proactivity;

  /// Provider session resumption configuration.
  Object? sessionResumption;

  /// Provider context window compression configuration.
  Object? contextWindowCompression;

  /// Returns a copy of this live configuration.
  LiveConnectConfig copyWith({
    List<String>? responseModalities,
    Object? speechConfig = _sentinel,
    Object? outputAudioTranscription = _sentinel,
    Object? inputAudioTranscription = _sentinel,
    Object? systemInstruction = _sentinel,
    Object? tools = _sentinel,
    Object? httpOptions = _sentinel,
    Object? realtimeInputConfig = _sentinel,
    Object? enableAffectiveDialog = _sentinel,
    Object? proactivity = _sentinel,
    Object? sessionResumption = _sentinel,
    Object? contextWindowCompression = _sentinel,
  }) {
    return LiveConnectConfig(
      responseModalities:
          responseModalities ??
          (this.responseModalities == null
              ? null
              : List<String>.from(this.responseModalities!)),
      speechConfig: identical(speechConfig, _sentinel)
          ? this.speechConfig
          : speechConfig,
      outputAudioTranscription: identical(outputAudioTranscription, _sentinel)
          ? this.outputAudioTranscription
          : outputAudioTranscription,
      inputAudioTranscription: identical(inputAudioTranscription, _sentinel)
          ? this.inputAudioTranscription
          : inputAudioTranscription,
      systemInstruction: identical(systemInstruction, _sentinel)
          ? this.systemInstruction
          : systemInstruction,
      tools: identical(tools, _sentinel)
          ? this.tools?.map((ToolDeclaration tool) => tool.copyWith()).toList()
          : tools as List<ToolDeclaration>?,
      httpOptions: identical(httpOptions, _sentinel)
          ? this.httpOptions?.copyWith()
          : httpOptions as HttpOptions?,
      realtimeInputConfig: identical(realtimeInputConfig, _sentinel)
          ? this.realtimeInputConfig
          : realtimeInputConfig,
      enableAffectiveDialog: identical(enableAffectiveDialog, _sentinel)
          ? this.enableAffectiveDialog
          : enableAffectiveDialog as bool?,
      proactivity: identical(proactivity, _sentinel)
          ? this.proactivity
          : proactivity,
      sessionResumption: identical(sessionResumption, _sentinel)
          ? this.sessionResumption
          : sessionResumption,
      contextWindowCompression: identical(contextWindowCompression, _sentinel)
          ? this.contextWindowCompression
          : contextWindowCompression,
    );
  }
}

/// Full model request payload used by LLM adapters.
class LlmRequest {
  /// Creates an LLM request.
  LlmRequest({
    this.model,
    List<Content>? contents,
    GenerateContentConfig? config,
    LiveConnectConfig? liveConnectConfig,
    Map<String, BaseTool>? toolsDict,
    this.cacheConfig,
    this.cacheMetadata,
    this.cacheableContentsTokenCount,
    this.previousInteractionId,
  }) : contents = contents ?? <Content>[],
       config = config ?? GenerateContentConfig(),
       liveConnectConfig = liveConnectConfig ?? LiveConnectConfig(),
       toolsDict = toolsDict ?? <String, BaseTool>{};

  /// Target model identifier.
  String? model;

  /// Conversation contents sent to the model.
  List<Content> contents;

  /// Generation config for standard model calls.
  GenerateContentConfig config;

  /// Connection config for realtime model calls.
  LiveConnectConfig liveConnectConfig;

  /// Runtime lookup map for declared tools by name.
  Map<String, BaseTool> toolsDict;

  /// Cache creation/update configuration payload.
  Object? cacheConfig;

  /// Cache metadata returned by providers.
  Object? cacheMetadata;

  /// Number of tokens eligible for caching.
  int? cacheableContentsTokenCount;

  /// Previous interaction ID for conversational continuity.
  String? previousInteractionId;

  /// Appends [instructions] to this request as system text and user content.
  ///
  /// Accepts either a [Content] payload or a `List<String>`.
  ///
  /// Throws an [ArgumentError] for unsupported instruction types.
  List<Content> appendInstructions(Object instructions) {
    if (instructions is Content) {
      final List<String> textParts = <String>[];
      final List<Content> userContents = <Content>[];
      int nonTextIndex = 0;

      for (final Part part in instructions.parts) {
        if (part.text != null && part.text!.isNotEmpty) {
          textParts.add(part.text!);
          continue;
        }

        nonTextIndex += 1;
        textParts.add('[Reference to non-text content: ref_$nonTextIndex]');
        userContents.add(
          Content(
            role: 'user',
            parts: <Part>[
              Part.text('Referenced content: ref_$nonTextIndex'),
              part.copyWith(),
            ],
          ),
        );
      }

      if (textParts.isNotEmpty) {
        final String text = textParts.join('\n\n');
        if (config.systemInstruction == null ||
            config.systemInstruction!.isEmpty) {
          config.systemInstruction = text;
        } else {
          config.systemInstruction = '${config.systemInstruction}\n\n$text';
        }
      }

      if (userContents.isNotEmpty) {
        contents.addAll(userContents);
      }
      return userContents;
    }

    if (instructions is List<String>) {
      if (instructions.isEmpty) {
        return const <Content>[];
      }

      final String text = instructions.join('\n\n');
      if (config.systemInstruction == null ||
          config.systemInstruction!.isEmpty) {
        config.systemInstruction = text;
      } else {
        config.systemInstruction = '${config.systemInstruction}\n\n$text';
      }
      return const <Content>[];
    }

    throw ArgumentError.value(
      instructions,
      'instructions',
      'instructions must be List<String> or Content',
    );
  }

  /// Appends tool declarations from [tools] to this request.
  void appendTools(List<BaseTool> tools) {
    if (tools.isEmpty) {
      return;
    }

    final List<FunctionDeclaration> declarations = <FunctionDeclaration>[];
    for (final BaseTool tool in tools) {
      final FunctionDeclaration? declaration = tool.getDeclaration();
      if (declaration != null) {
        declarations.add(declaration);
        toolsDict[tool.name] = tool;
      }
    }

    if (declarations.isEmpty) {
      return;
    }

    config.tools ??= <ToolDeclaration>[];
    final ToolDeclaration? toolWithDeclarations =
        _findToolWithFunctionDeclarations(this);
    if (toolWithDeclarations != null) {
      toolWithDeclarations.functionDeclarations.addAll(declarations);
      return;
    }

    config.tools!.add(ToolDeclaration(functionDeclarations: declarations));
  }

  /// Sets structured output [schema] and JSON response MIME type.
  void setOutputSchema(Object schema) {
    config.responseSchema = schema;
    config.responseMimeType = 'application/json';
  }

  /// Returns a sanitized clone safe for backend model calls.
  ///
  /// ADK-generated function IDs are stripped to match provider expectations.
  LlmRequest sanitizedForModelCall() {
    final LlmRequest clone = LlmRequest(
      model: model,
      contents: contents.map((content) => content.copyWith()).toList(),
      config: config.copyWith(),
      liveConnectConfig: liveConnectConfig.copyWith(),
      toolsDict: Map<String, BaseTool>.from(toolsDict),
      cacheConfig: cacheConfig,
      cacheMetadata: cacheMetadata,
      cacheableContentsTokenCount: cacheableContentsTokenCount,
      previousInteractionId: previousInteractionId,
    );

    for (final Content content in clone.contents) {
      for (final Part part in content.parts) {
        final FunctionCall? call = part.functionCall;
        if (call != null && call.id != null && call.id!.startsWith('adk-')) {
          call.id = null;
        }
        final FunctionResponse? response = part.functionResponse;
        if (response != null &&
            response.id != null &&
            response.id!.startsWith('adk-')) {
          response.id = null;
        }
      }
    }

    developer.log('Sanitized request for model call.', name: 'adk_dart.models');
    return clone;
  }
}

const Object _sentinel = Object();
