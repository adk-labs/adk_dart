/// Google Cloud Model Armor safety screening integration for ADK.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../agents/callback_context.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../plugins/base_plugin.dart';
import '../../tools/base_tool.dart';
import '../../tools/tool_context.dart';
import '../../types/content.dart';

/// Filter match state reported by Model Armor sanitization APIs.
enum ModelArmorFilterMatchState {
  /// Unspecified filter match state.
  unspecified,

  /// No safety filter matched the inspected content.
  noMatchFound,

  /// One or more safety filters matched the inspected content.
  matchFound,
}

/// Invocation execution state reported by Model Armor sanitization APIs.
enum ModelArmorInvocationResult {
  /// Unspecified invocation result.
  unspecified,

  /// All safety filters executed successfully.
  success,

  /// Some safety filters succeeded while others failed.
  partial,

  /// Safety filter invocation failed.
  failure,
}

/// Result returned by a single SDP (Sensitive Data Protection) filter check.
class ModelArmorSdpDeidentifyResult {
  /// Creates an SDP de-identification result.
  const ModelArmorSdpDeidentifyResult({
    this.executionState = ModelArmorInvocationResult.success,
    this.matchState = ModelArmorFilterMatchState.noMatchFound,
    this.deidentifiedText,
  });

  /// Execution state of the SDP de-identification filter.
  final ModelArmorInvocationResult executionState;

  /// Match state of the SDP de-identification filter.
  final ModelArmorFilterMatchState matchState;

  /// Redacted/de-identified text when [matchState] is
  /// [ModelArmorFilterMatchState.matchFound].
  final String? deidentifiedText;
}

/// Result returned by a Model Armor sanitization call.
class ModelArmorSanitizationResult {
  /// Creates a sanitization result.
  const ModelArmorSanitizationResult({
    this.filterMatchState = ModelArmorFilterMatchState.noMatchFound,
    this.invocationResult = ModelArmorInvocationResult.success,
    this.sdpDeidentifyResult,
    this.filterResults = const <String, Object?>{},
  });

  /// Overall filter match state across all active filters.
  final ModelArmorFilterMatchState filterMatchState;

  /// Overall invocation result across all active filters.
  final ModelArmorInvocationResult invocationResult;

  /// Optional Sensitive Data Protection (SDP) de-identification result.
  final ModelArmorSdpDeidentifyResult? sdpDeidentifyResult;

  /// Per-filter diagnostic results keyed by filter name (for example, `'sdp'`,
  /// `'rai'`, `'pi_and_jailbreak'`, `'malicious_uris'`, `'csam'`).
  final Map<String, Object?> filterResults;
}

/// Client interface for Google Cloud Model Armor sanitization operations.
abstract class ModelArmorClient {
  /// Sanitizes user prompt or tool output [text] against [templateName].
  Future<ModelArmorSanitizationResult> sanitizeUserPrompt({
    required String text,
    required String templateName,
  });

  /// Sanitizes model response [text] against [templateName].
  Future<ModelArmorSanitizationResult> sanitizeModelResponse({
    required String text,
    required String templateName,
  });
}

/// Custom screening callback used by [InMemoryModelArmorClient].
typedef ModelArmorScreenHandler = Future<ModelArmorSanitizationResult> Function({
  required String text,
  required String templateName,
  required bool isModelResponse,
});

/// In-memory [ModelArmorClient] implementation for local development and tests.
///
/// ```dart
/// final client = InMemoryModelArmorClient(
///   blockedSubstrings: <String>['DROP TABLE', 'ignore previous instructions'],
/// );
/// final result = await client.sanitizeUserPrompt(
///   text: 'Hello world',
///   templateName: 'projects/p/locations/us-central1/templates/t1',
/// );
/// ```
class InMemoryModelArmorClient implements ModelArmorClient {
  /// Creates an in-memory Model Armor client.
  InMemoryModelArmorClient({
    List<String>? blockedSubstrings,
    Map<String, String>? redactionPatterns,
    this.handler,
  }) : blockedSubstrings = blockedSubstrings ?? <String>[],
       redactionPatterns = redactionPatterns ?? <String, String>{};

  /// Case-insensitive substrings that trigger a non-SDP filter match.
  final List<String> blockedSubstrings;

  /// Exact or substring replacements simulated as SDP de-identification matches.
  final Map<String, String> redactionPatterns;

  /// Optional custom screening handler that overrides default rule evaluation.
  final ModelArmorScreenHandler? handler;

  /// Recorded user prompt sanitization calls for inspection in tests.
  final List<({String text, String templateName})> userPromptCalls =
      <({String text, String templateName})>[];

  /// Recorded model response sanitization calls for inspection in tests.
  final List<({String text, String templateName})> modelResponseCalls =
      <({String text, String templateName})>[];

  @override
  Future<ModelArmorSanitizationResult> sanitizeUserPrompt({
    required String text,
    required String templateName,
  }) {
    userPromptCalls.add((text: text, templateName: templateName));
    return _evaluate(
      text: text,
      templateName: templateName,
      isModelResponse: false,
    );
  }

  @override
  Future<ModelArmorSanitizationResult> sanitizeModelResponse({
    required String text,
    required String templateName,
  }) {
    modelResponseCalls.add((text: text, templateName: templateName));
    return _evaluate(
      text: text,
      templateName: templateName,
      isModelResponse: true,
    );
  }

  Future<ModelArmorSanitizationResult> _evaluate({
    required String text,
    required String templateName,
    required bool isModelResponse,
  }) async {
    if (handler != null) {
      return handler!(
        text: text,
        templateName: templateName,
        isModelResponse: isModelResponse,
      );
    }

    final String lower = text.toLowerCase();
    for (final String blocked in blockedSubstrings) {
      if (blocked.isNotEmpty && lower.contains(blocked.toLowerCase())) {
        return const ModelArmorSanitizationResult(
          filterMatchState: ModelArmorFilterMatchState.matchFound,
          invocationResult: ModelArmorInvocationResult.success,
          filterResults: <String, Object?>{
            'pi_and_jailbreak': true,
          },
        );
      }
    }

    String redacted = text;
    bool sdpMatched = false;
    redactionPatterns.forEach((String pattern, String replacement) {
      if (pattern.isNotEmpty && redacted.contains(pattern)) {
        redacted = redacted.replaceAll(pattern, replacement);
        sdpMatched = true;
      }
    });

    if (sdpMatched) {
      return ModelArmorSanitizationResult(
        filterMatchState: ModelArmorFilterMatchState.matchFound,
        invocationResult: ModelArmorInvocationResult.success,
        sdpDeidentifyResult: ModelArmorSdpDeidentifyResult(
          executionState: ModelArmorInvocationResult.success,
          matchState: ModelArmorFilterMatchState.matchFound,
          deidentifiedText: redacted,
        ),
        filterResults: const <String, Object?>{
          'sdp': true,
        },
      );
    }

    return const ModelArmorSanitizationResult(
      filterMatchState: ModelArmorFilterMatchState.noMatchFound,
      invocationResult: ModelArmorInvocationResult.success,
    );
  }
}

/// Configuration for [ModelArmorPlugin].
///
/// At least one of [promptTemplateName], [responseTemplateName], or
/// [toolOutputTemplateName] must be provided.
///
/// ```dart
/// final config = ModelArmorConfig(
///   promptTemplateName:
///       'projects/my-project/locations/us-central1/templates/my-prompt-template',
///   responseTemplateName:
///       'projects/my-project/locations/us-central1/templates/my-response-template',
/// );
/// ```
class ModelArmorConfig {
  /// Creates a validated Model Armor configuration.
  ModelArmorConfig({
    this.promptTemplateName,
    this.responseTemplateName,
    this.toolOutputTemplateName,
    this.inputBlockedMessage = "I'm sorry, but I can't help with that request.",
    this.outputBlockedMessage =
        "I'm sorry, but I can't help with that request.",
    this.toolOutputBlockedMessage = 'Tool output was blocked by Model Armor.',
    this.blockOnScreeningFailure = true,
    this.deidentifySensitiveData = false,
  }) {
    final bool hasPrompt =
        promptTemplateName != null && promptTemplateName!.trim().isNotEmpty;
    final bool hasResponse =
        responseTemplateName != null && responseTemplateName!.trim().isNotEmpty;
    final bool hasToolOutput =
        toolOutputTemplateName != null &&
        toolOutputTemplateName!.trim().isNotEmpty;
    if (!hasPrompt && !hasResponse && !hasToolOutput) {
      throw ArgumentError(
        'At least one of promptTemplateName, responseTemplateName, or '
        'toolOutputTemplateName must be set.',
      );
    }
  }

  /// Full resource name of the Model Armor template for screening user prompts.
  ///
  /// Format: `projects/{project}/locations/{location}/templates/{template}`.
  /// If `null`, user prompts are not screened.
  final String? promptTemplateName;

  /// Full resource name of the Model Armor template for screening model
  /// responses.
  ///
  /// Format: `projects/{project}/locations/{location}/templates/{template}`.
  /// If `null`, model responses are not screened.
  final String? responseTemplateName;

  /// Full resource name of the Model Armor template for screening tool outputs.
  ///
  /// Format: `projects/{project}/locations/{location}/templates/{template}`.
  /// If `null`, tool outputs are not screened.
  final String? toolOutputTemplateName;

  /// Message returned to the user when an input prompt is blocked.
  final String inputBlockedMessage;

  /// Message returned to the user when a model response is blocked.
  final String outputBlockedMessage;

  /// Error message returned in `{'error': ...}` when a tool output is blocked.
  final String toolOutputBlockedMessage;

  /// Whether to block content if the Model Armor API call fails or returns a
  /// partial result.
  ///
  /// Defaults to `true` (fail-closed). Set to `false` to allow content through
  /// on API errors (fail-open).
  final bool blockOnScreeningFailure;

  /// Whether to replace sensitive data in user prompts and model responses with
  /// the de-identified text returned by Model Armor's SDP filter instead of
  /// blocking.
  final bool deidentifySensitiveData;
}

final RegExp _templatePattern = RegExp(
  r'^projects/[^/]+/locations/([^/]+)/templates/[^/]+$',
);

/// Maximum characters per Model Armor API call for tool output chunking.
const int maxToolOutputChunkChars = 65536;

/// Overlap between consecutive tool output chunks so split payloads are still
/// caught.
const int toolOutputChunkOverlap = 4096;

/// Plugin that screens user prompts, model responses, and tool outputs via
/// Google Cloud Model Armor.
///
/// ```dart
/// final plugin = ModelArmorPlugin(
///   config: ModelArmorConfig(
///     promptTemplateName:
///         'projects/my-project/locations/us-central1/templates/prompt-tmpl',
///     responseTemplateName:
///         'projects/my-project/locations/us-central1/templates/resp-tmpl',
///   ),
/// );
/// ```
class ModelArmorPlugin extends BasePlugin {
  /// Creates a [ModelArmorPlugin] instance.
  ModelArmorPlugin({
    required ModelArmorConfig config,
    ModelArmorClient? client,
    super.name = 'model_armor_plugin',
  }) : _config = config,
       _client = client ?? InMemoryModelArmorClient() {
    _extractLocation(_config);
  }

  final ModelArmorConfig _config;
  final ModelArmorClient _client;

  /// Active Model Armor configuration for this plugin.
  ModelArmorConfig get config => _config;

  /// Underlying Model Armor client used to perform screening requests.
  ModelArmorClient get client => _client;

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    final String? templateName = _config.promptTemplateName;
    if (templateName == null || templateName.isEmpty) {
      return null;
    }

    final Content? userContent = _findLatestUserContentWithText(llmRequest);
    if (userContent == null) {
      return null;
    }

    final String userText = _extractPartsText(userContent.parts);
    if (userText.isEmpty) {
      return null;
    }

    final (:bool shouldBlock, :String? deidentifiedText) = await _screenText(
      text: userText,
      templateName: templateName,
      isModelResponse: false,
      allowDeidentify: _config.deidentifySensitiveData,
    );

    if (deidentifiedText != null) {
      _replaceTextInContent(userContent, deidentifiedText);
      return null;
    }

    if (shouldBlock) {
      return LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[Part.text(_config.inputBlockedMessage)],
        ),
        customMetadata: <String, dynamic>{'model_armor_blocked': true},
      );
    }

    return null;
  }

  @override
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    final String? templateName = _config.responseTemplateName;
    if (templateName == null || templateName.isEmpty) {
      return null;
    }

    final String responseText = _extractResponseText(llmResponse);
    if (responseText.isEmpty) {
      return null;
    }

    final (:bool shouldBlock, :String? deidentifiedText) = await _screenText(
      text: responseText,
      templateName: templateName,
      isModelResponse: true,
      allowDeidentify: _config.deidentifySensitiveData,
    );

    if (deidentifiedText != null) {
      final LlmResponse modified = llmResponse.copyWith();
      if (modified.content != null && modified.content!.parts.isNotEmpty) {
        final Content contentCopy = modified.content!.copyWith();
        _replaceTextInContent(contentCopy, deidentifiedText);
        modified.content = contentCopy;
      }
      if (modified.outputTranscription is Map<String, dynamic>) {
        final Map<String, dynamic> transcription =
            Map<String, dynamic>.from(
              modified.outputTranscription as Map<String, dynamic>,
            );
        if (transcription['text'] is String &&
            (transcription['text'] as String).isNotEmpty) {
          transcription['text'] = deidentifiedText;
          modified.outputTranscription = transcription;
        }
      }
      modified.customMetadata = <String, dynamic>{
        ...?modified.customMetadata,
        'model_armor_deidentified': true,
      };
      return modified;
    }

    if (shouldBlock) {
      return LlmResponse(
        content: Content(
          role: 'model',
          parts: <Part>[Part.text(_config.outputBlockedMessage)],
        ),
        customMetadata: <String, dynamic>{'model_armor_blocked': true},
      );
    }

    return null;
  }

  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    final String? templateName = _config.toolOutputTemplateName;
    if (templateName == null || templateName.isEmpty) {
      return null;
    }

    final String toolText = _extractToolOutputText(result);
    if (toolText.isEmpty) {
      return null;
    }

    for (final String chunk in _chunkText(toolText)) {
      final (:bool shouldBlock, deidentifiedText: _) = await _screenText(
        text: chunk,
        templateName: templateName,
        isModelResponse: false,
        allowDeidentify: false,
      );
      if (shouldBlock) {
        return <String, dynamic>{'error': _config.toolOutputBlockedMessage};
      }
    }

    return null;
  }

  Future<({bool shouldBlock, String? deidentifiedText})> _screenText({
    required String text,
    required String templateName,
    required bool isModelResponse,
    required bool allowDeidentify,
  }) async {
    ModelArmorSanitizationResult sanitizationResult;
    try {
      if (isModelResponse) {
        sanitizationResult = await _client.sanitizeModelResponse(
          text: text,
          templateName: templateName,
        );
      } else {
        sanitizationResult = await _client.sanitizeUserPrompt(
          text: text,
          templateName: templateName,
        );
      }
    } catch (_) {
      return (shouldBlock: _config.blockOnScreeningFailure, deidentifiedText: null);
    }

    final bool matched =
        sanitizationResult.filterMatchState ==
        ModelArmorFilterMatchState.matchFound;

    if (allowDeidentify && matched) {
      final String? deidentified = _tryExtractDeidentifiedData(
        sanitizationResult,
      );
      if (deidentified != null) {
        return (shouldBlock: false, deidentifiedText: deidentified);
      }
    }

    if (matched) {
      return (shouldBlock: true, deidentifiedText: null);
    }

    if (sanitizationResult.invocationResult !=
        ModelArmorInvocationResult.success) {
      return (
        shouldBlock: _config.blockOnScreeningFailure,
        deidentifiedText: null,
      );
    }

    return (shouldBlock: false, deidentifiedText: null);
  }
}

String _extractLocation(ModelArmorConfig config) {
  final Set<String> locations = <String>{};
  final List<String?> names = <String?>[
    config.promptTemplateName,
    config.responseTemplateName,
    config.toolOutputTemplateName,
  ];
  for (final String? name in names) {
    if (name == null || name.isEmpty) {
      continue;
    }
    final RegExpMatch? match = _templatePattern.firstMatch(name);
    if (match == null) {
      throw ArgumentError(
        "Invalid template name '$name'. Expected format: "
        "'projects/{project}/locations/{location}/templates/{template}'.",
      );
    }
    locations.add(match.group(1)!);
  }
  if (locations.length > 1) {
    final List<String> sorted = locations.toList()..sort();
    throw ArgumentError(
      'All template names must use the same location, found: $sorted.',
    );
  }
  return locations.first;
}

String? _tryExtractDeidentifiedData(ModelArmorSanitizationResult result) {
  String? deidentifiedText;
  final ModelArmorSdpDeidentifyResult? sdp = result.sdpDeidentifyResult;
  if (sdp != null &&
      sdp.executionState == ModelArmorInvocationResult.success &&
      sdp.matchState == ModelArmorFilterMatchState.matchFound &&
      sdp.deidentifiedText != null &&
      sdp.deidentifiedText!.isNotEmpty) {
    deidentifiedText = sdp.deidentifiedText;
  }

  for (final MapEntry<String, Object?> entry in result.filterResults.entries) {
    if (entry.key == 'sdp') {
      final Object? val = entry.value;
      if (val is ModelArmorSdpDeidentifyResult) {
        if (val.executionState == ModelArmorInvocationResult.success &&
            val.matchState == ModelArmorFilterMatchState.matchFound &&
            val.deidentifiedText != null &&
            val.deidentifiedText!.isNotEmpty) {
          deidentifiedText = val.deidentifiedText;
        }
      } else if (val is Map) {
        final Object? data = val['deidentifiedText'] ?? val['data'];
        if (data is String && data.isNotEmpty) {
          deidentifiedText = data;
        }
      }
      continue;
    }
    if (_subFilterMatched(entry.value)) {
      return null;
    }
  }

  return deidentifiedText;
}

bool _subFilterMatched(Object? filterValue) {
  if (filterValue == null) {
    return false;
  }
  if (filterValue is bool) {
    return filterValue;
  }
  if (filterValue is ModelArmorFilterMatchState) {
    return filterValue == ModelArmorFilterMatchState.matchFound;
  }
  if (filterValue is Map) {
    final Object? matchState = filterValue['matchState'];
    if (matchState == ModelArmorFilterMatchState.matchFound ||
        matchState == 'MATCH_FOUND' ||
        matchState == true) {
      return true;
    }
  }
  return false;
}

String _extractPartsText(List<Part> parts) {
  final List<String> texts = <String>[];
  for (final Part part in parts) {
    if (part.thought) {
      continue;
    }
    if (part.text != null && part.text!.isNotEmpty) {
      texts.add(part.text!);
    }
  }
  return texts.join('\n');
}

Content? _findLatestUserContentWithText(LlmRequest llmRequest) {
  for (int i = llmRequest.contents.length - 1; i >= 0; i--) {
    final Content content = llmRequest.contents[i];
    if (content.role != 'user') {
      continue;
    }
    final bool hasNonThoughtText = content.parts.any(
      (Part part) => !part.thought && part.text != null && part.text!.isNotEmpty,
    );
    if (hasNonThoughtText) {
      return content;
    }
  }
  return null;
}

void _replaceTextInContent(Content content, String newText) {
  bool replaced = false;
  final List<Part> newParts = <Part>[];
  for (final Part part in content.parts) {
    if (!part.thought && part.text != null && part.text!.isNotEmpty) {
      if (!replaced) {
        final Part updated = part.copyWith(text: newText);
        newParts.add(updated);
        replaced = true;
      }
      // Drop remaining text parts; their content is already merged into newText.
    } else {
      newParts.add(part);
    }
  }
  content.parts = newParts;
}

String _extractResponseText(LlmResponse llmResponse) {
  final Object? transcription = llmResponse.outputTranscription;
  if (transcription is Map) {
    final Object? text = transcription['text'];
    if (text is String && text.isNotEmpty) {
      return text;
    }
  } else if (transcription is String && transcription.isNotEmpty) {
    return transcription;
  }
  final Content? content = llmResponse.content;
  if (content == null || content.parts.isEmpty) {
    return '';
  }
  return _extractPartsText(content.parts);
}

List<String> _chunkText(
  String text, {
  int maxChars = maxToolOutputChunkChars,
  int overlap = toolOutputChunkOverlap,
}) {
  if (text.length <= maxChars) {
    return <String>[text];
  }
  final int step = maxChars - overlap;
  final List<String> chunks = <String>[];
  for (int start = 0; start < text.length; start += step) {
    final int end =
        (start + maxChars) < text.length ? (start + maxChars) : text.length;
    chunks.add(text.substring(start, end));
  }
  return chunks;
}

Object? _filterScreenable(Object? obj) {
  if (obj is Uint8List || obj is InlineData || obj is FileData) {
    return null;
  }
  if (obj is Part) {
    if (obj.thought) {
      return null;
    }
    return obj.text != null && obj.text!.isNotEmpty ? obj.text : null;
  }
  if (obj is Content) {
    if (obj.parts.isEmpty) {
      return null;
    }
    final Object? filtered = _filterScreenable(obj.parts);
    return filtered;
  }
  if (obj is Map) {
    final Map<String, Object?> cleaned = <String, Object?>{};
    obj.forEach((Object? key, Object? value) {
      final Object? filtered = _filterScreenable(value);
      if (filtered != null) {
        cleaned['$key'] = filtered;
      }
    });
    return cleaned.isEmpty ? null : cleaned;
  }
  if (obj is Iterable) {
    final List<Object?> items = <Object?>[];
    for (final Object? item in obj) {
      final Object? filtered = _filterScreenable(item);
      if (filtered != null) {
        items.add(filtered);
      }
    }
    return items.isEmpty ? null : items;
  }
  return obj;
}

String _extractToolOutputText(Object? toolResponse) {
  if (toolResponse == null) {
    return '';
  }
  if (toolResponse is String) {
    return toolResponse;
  }
  final Object? filtered = _filterScreenable(toolResponse);
  if (filtered == null) {
    return '';
  }
  if (filtered is String) {
    return filtered;
  }
  try {
    return jsonEncode(filtered);
  } catch (_) {
    return '$filtered';
  }
}
