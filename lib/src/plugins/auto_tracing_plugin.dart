/// Plugin that records ADK callback spans using the Dart telemetry tracer.
library;

import '../agents/base_agent.dart';
import '../agents/callback_context.dart';
import '../agents/invocation_context.dart';
import '../events/event.dart';
import '../models/llm_request.dart';
import '../models/llm_response.dart';
import '../telemetry/metrics.dart' as adk_metrics;
import '../telemetry/tracing.dart' as adk_tracing;
import '../tools/base_tool.dart';
import '../tools/tool_context.dart';
import '../types/content.dart';
import 'base_plugin.dart';

const int _defaultMaxReprLen = 4096;

String _safeRepr(Object? value, int maxLen) {
  String repr;
  try {
    repr = '$value';
  } catch (error) {
    repr = '<unrepresentable ${value.runtimeType}: $error>';
  }
  if (repr.length <= maxLen) {
    return repr;
  }
  return '${repr.substring(0, maxLen)}...[${repr.length - maxLen} more chars]';
}

String _spanKey(String invocationId, String kind) => '$invocationId:$kind';

class _ActiveSpan {
  _ActiveSpan({
    required this.kind,
    required this.span,
    required this.stopwatch,
    this.agentName,
    this.toolName,
    this.toolArgs,
    this.userContent,
    this.functionCallId,
  });

  final String kind;
  final adk_tracing.TraceSpanRecord span;
  final Stopwatch stopwatch;
  final String? agentName;
  final String? toolName;
  final Map<String, dynamic>? toolArgs;
  final Content? userContent;
  final String? functionCallId;
  final List<Event> events = <Event>[];
}

class _PendingToolResponseMetric {
  _PendingToolResponseMetric({
    required this.toolName,
    required this.agentName,
    required this.functionCallId,
  });

  final String toolName;
  final String agentName;
  final String? functionCallId;
}

/// Automatically records run, agent, model, and tool spans.
///
/// Python ADK's `AutoTracingPlugin` instruments Python functions by monkey
/// patching in-scope modules. Dart does not support that runtime pattern, so
/// this plugin records the equivalent ADK lifecycle spans through plugin hooks.
class AutoTracingPlugin extends BasePlugin {
  /// Creates an auto-tracing plugin.
  AutoTracingPlugin({
    super.name = 'AutoTracingPlugin',
    adk_tracing.AdkTracer? tracer,
    this.maxReprLen = _defaultMaxReprLen,
    this.capturePayloads = true,
    this.traceRuns = true,
    this.traceAgents = true,
    this.traceModels = true,
    this.traceTools = true,
    this.recordMetrics = true,
    adk_metrics.AdkMetricsRecorder? metricsRecorder,
  }) : _tracer = tracer ?? adk_tracing.tracer,
       _metricsRecorder = metricsRecorder;

  final adk_tracing.AdkTracer _tracer;

  /// Maximum string length captured for request, response, args, and errors.
  final int maxReprLen;

  /// Whether request/response payload summaries should be captured.
  final bool capturePayloads;

  /// Enables invocation-level spans.
  final bool traceRuns;

  /// Enables agent lifecycle spans.
  final bool traceAgents;

  /// Enables model callback spans.
  final bool traceModels;

  /// Enables tool callback spans.
  final bool traceTools;

  /// Enables Java-compatible `gen_ai.*` metrics for traced agents and tools.
  final bool recordMetrics;

  final Map<String, List<_ActiveSpan>> _spansByKey =
      <String, List<_ActiveSpan>>{};
  final Map<String, List<_ActiveSpan>> _spansByInvocation =
      <String, List<_ActiveSpan>>{};
  final Map<String, List<_PendingToolResponseMetric>>
  _pendingToolResponsesByInvocation =
      <String, List<_PendingToolResponseMetric>>{};
  final adk_metrics.AdkMetricsRecorder? _metricsRecorder;

  @override
  Future<Content?> beforeRunCallback({
    required InvocationContext invocationContext,
  }) async {
    if (!traceRuns) {
      return null;
    }
    _startSpan(
      invocationContext.invocationId,
      'run',
      'adk.run ${invocationContext.agent.name}',
      <String, Object?>{
        'adk.auto_tracing.kind': 'run',
        'gcp.vertex.agent.invocation_id': invocationContext.invocationId,
        'gcp.vertex.agent.session_id': invocationContext.session.id,
        'gen_ai.agent.name': invocationContext.agent.name,
      },
    );
    return null;
  }

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    if (traceRuns) {
      _closeLatest(invocationContext.invocationId, 'run', <String, Object?>{
        'adk.auto_tracing.completed': true,
      });
    }
    _closeRemaining(invocationContext.invocationId);
  }

  @override
  Future<Content?> beforeAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    if (!traceAgents) {
      return null;
    }
    final adk_tracing.TraceSpanRecord span = _startSpan(
      callbackContext.invocationId,
      'agent',
      'adk.agent ${agent.name}',
      <String, Object?>{
        'adk.auto_tracing.kind': 'agent',
        'gcp.vertex.agent.invocation_id': callbackContext.invocationId,
        'gen_ai.agent.name': agent.name,
      },
      agentName: agent.name,
      userContent: callbackContext.userContent,
    );
    adk_tracing.traceAgentInvocation(
      span,
      agent,
      callbackContext.invocationContext,
    );
    return null;
  }

  @override
  Future<Content?> afterAgentCallback({
    required BaseAgent agent,
    required CallbackContext callbackContext,
  }) async {
    if (!traceAgents) {
      return null;
    }
    _closeLatest(callbackContext.invocationId, 'agent', <String, Object?>{
      'adk.auto_tracing.completed': true,
      'gen_ai.agent.name': agent.name,
    });
    return null;
  }

  @override
  Future<Event?> onEventCallback({
    required InvocationContext invocationContext,
    required Event event,
  }) async {
    if (!recordMetrics) {
      return null;
    }
    _recordAgentEvent(invocationContext.invocationId, event);
    _recordPendingToolResponse(invocationContext.invocationId, event);
    return null;
  }

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    if (!traceModels) {
      return null;
    }
    final Map<String, Object?> attributes = <String, Object?>{
      'adk.auto_tracing.kind': 'model',
      'gcp.vertex.agent.invocation_id': callbackContext.invocationId,
      'gen_ai.request.model': llmRequest.model,
    };
    if (capturePayloads) {
      attributes['adk.fn.arg.llm_request'] = _safeRepr(llmRequest, maxReprLen);
    }
    _startSpan(
      callbackContext.invocationId,
      'model',
      'adk.model ${llmRequest.model ?? ''}'.trimRight(),
      attributes,
    );
    return null;
  }

  @override
  Future<LlmResponse?> afterModelCallback({
    required CallbackContext callbackContext,
    required LlmResponse llmResponse,
  }) async {
    if (!traceModels) {
      return null;
    }
    final Map<String, Object?> attributes = <String, Object?>{
      'adk.auto_tracing.completed': true,
      'gen_ai.response.finish_reasons': llmResponse.finishReason == null
          ? null
          : <String>[llmResponse.finishReason!.toLowerCase()],
    };
    if (capturePayloads) {
      attributes['adk.fn.return'] = _safeRepr(llmResponse, maxReprLen);
    }
    _closeLatest(callbackContext.invocationId, 'model', attributes);
    return null;
  }

  @override
  Future<LlmResponse?> onModelErrorCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
    required Exception error,
  }) async {
    if (!traceModels) {
      return null;
    }
    _closeLatest(callbackContext.invocationId, 'model', <String, Object?>{
      'adk.auto_tracing.completed': false,
      'error.type': error.runtimeType.toString(),
      'adk.fn.exc_repr': _safeRepr(error, maxReprLen),
    });
    return null;
  }

  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    if (!traceTools) {
      return null;
    }
    final Map<String, Object?> attributes = <String, Object?>{
      'adk.auto_tracing.kind': 'tool',
      'gcp.vertex.agent.invocation_id': toolContext.invocationId,
      'gen_ai.tool.name': tool.name,
      'gen_ai.tool.description': tool.description,
      'gen_ai.tool.type': tool.runtimeType.toString(),
    };
    if (capturePayloads) {
      attributes['adk.fn.arg.tool_args'] = _safeRepr(toolArgs, maxReprLen);
    }
    _startSpan(
      toolContext.invocationId,
      'tool',
      'adk.tool ${tool.name}',
      attributes,
      agentName: toolContext.agentName,
      toolName: tool.name,
      toolArgs: toolArgs,
      functionCallId: toolContext.functionCallId,
    );
    return null;
  }

  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    if (!traceTools) {
      return null;
    }
    final Map<String, Object?> attributes = <String, Object?>{
      'adk.auto_tracing.completed': true,
      'gen_ai.tool.name': tool.name,
    };
    if (capturePayloads) {
      attributes['adk.fn.return'] = _safeRepr(result, maxReprLen);
    }
    _queueToolResponseMetric(
      toolContext.invocationId,
      tool.name,
      toolContext.agentName,
      toolContext.functionCallId,
    );
    _closeLatest(toolContext.invocationId, 'tool', attributes);
    return null;
  }

  @override
  Future<Map<String, dynamic>?> onToolErrorCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Exception error,
  }) async {
    if (!traceTools) {
      return null;
    }
    _closeLatest(toolContext.invocationId, 'tool', <String, Object?>{
      'adk.auto_tracing.completed': false,
      'gen_ai.tool.name': tool.name,
      'error.type': error.runtimeType.toString(),
      'adk.fn.exc_repr': _safeRepr(error, maxReprLen),
    }, error: error);
    return null;
  }

  adk_tracing.TraceSpanRecord _startSpan(
    String invocationId,
    String kind,
    String name,
    Map<String, Object?> attributes, {
    String? agentName,
    String? toolName,
    Map<String, dynamic>? toolArgs,
    Content? userContent,
    String? functionCallId,
  }) {
    final adk_tracing.TraceSpanRecord span = _tracer.startAsCurrentSpan(
      name,
      attributes: Map<String, Object?>.from(attributes)
        ..removeWhere((String _, Object? value) => value == null),
    );
    final _ActiveSpan active = _ActiveSpan(
      kind: kind,
      span: span,
      stopwatch: Stopwatch()..start(),
      agentName: agentName,
      toolName: toolName,
      toolArgs: toolArgs == null ? null : Map<String, dynamic>.from(toolArgs),
      userContent: userContent,
      functionCallId: functionCallId,
    );
    _spansByKey
        .putIfAbsent(_spanKey(invocationId, kind), () {
          return <_ActiveSpan>[];
        })
        .add(active);
    _spansByInvocation
        .putIfAbsent(invocationId, () {
          return <_ActiveSpan>[];
        })
        .add(active);
    return span;
  }

  void _closeLatest(
    String invocationId,
    String kind,
    Map<String, Object?> attributes, {
    Object? error,
  }) {
    final String key = _spanKey(invocationId, kind);
    final List<_ActiveSpan>? spansForKind = _spansByKey[key];
    if (spansForKind == null || spansForKind.isEmpty) {
      return;
    }
    final _ActiveSpan active = spansForKind.removeLast();
    if (spansForKind.isEmpty) {
      _spansByKey.remove(key);
    }
    _closeNestedBefore(invocationId, active);
    _closeActive(invocationId, active, attributes, error: error);
  }

  void _closeNestedBefore(String invocationId, _ActiveSpan active) {
    final List<_ActiveSpan>? spans = _spansByInvocation[invocationId];
    if (spans == null) {
      return;
    }
    final int index = spans.indexOf(active);
    if (index < 0) {
      return;
    }
    for (int i = spans.length - 1; i > index; i -= 1) {
      final _ActiveSpan leaked = spans.removeLast();
      _removeFromKindStack(invocationId, leaked);
      leaked.span.setAttribute('adk.auto_tracing.closed_by_cleanup', true);
      _tracer.endSpan(leaked.span);
    }
  }

  void _closeActive(
    String invocationId,
    _ActiveSpan active,
    Map<String, Object?> attributes, {
    Object? error,
  }) {
    active.stopwatch.stop();
    active.span.setAttributes(
      Map<String, Object?>.from(attributes)
        ..removeWhere((String _, Object? value) => value == null),
    );
    _recordClosedSpanMetrics(active, error: error);
    _tracer.endSpan(active.span);
    final List<_ActiveSpan>? spans = _spansByInvocation[invocationId];
    spans?.remove(active);
    if (spans != null && spans.isEmpty) {
      _spansByInvocation.remove(invocationId);
    }
  }

  void _closeRemaining(String invocationId) {
    final List<_ActiveSpan>? spans = _spansByInvocation.remove(invocationId);
    if (spans == null) {
      _flushPendingToolResponses(invocationId);
      return;
    }
    for (int i = spans.length - 1; i >= 0; i -= 1) {
      final _ActiveSpan active = spans[i];
      _removeFromKindStack(invocationId, active);
      active.span.setAttribute('adk.auto_tracing.closed_by_cleanup', true);
      active.stopwatch.stop();
      _tracer.endSpan(active.span);
    }
    _flushPendingToolResponses(invocationId);
  }

  void _removeFromKindStack(String invocationId, _ActiveSpan active) {
    final String key = _spanKey(invocationId, active.kind);
    final List<_ActiveSpan>? spansForKind = _spansByKey[key];
    if (spansForKind == null) {
      return;
    }
    spansForKind.remove(active);
    if (spansForKind.isEmpty) {
      _spansByKey.remove(key);
    }
  }

  void _recordClosedSpanMetrics(_ActiveSpan active, {Object? error}) {
    if (!recordMetrics) {
      return;
    }
    final adk_metrics.AdkMetricsRecorder recorder =
        _metricsRecorder ?? adk_metrics.adkMetricsRecorder;
    switch (active.kind) {
      case 'agent':
        final String? agentName = active.agentName;
        if (agentName == null) {
          return;
        }
        adk_metrics.recordAgentInvocationDuration(
          agentName,
          active.stopwatch.elapsed,
          error: error,
          recorder: recorder,
        );
        adk_metrics.recordAgentRequestSize(
          agentName,
          active.userContent,
          recorder: recorder,
        );
        adk_metrics.recordAgentResponseSize(
          agentName,
          active.events,
          recorder: recorder,
        );
        adk_metrics.recordAgentWorkflowSteps(
          agentName,
          active.events,
          recorder: recorder,
        );
      case 'tool':
        final String? toolName = active.toolName;
        final String? agentName = active.agentName;
        if (toolName == null || agentName == null) {
          return;
        }
        adk_metrics.recordToolExecutionDuration(
          toolName,
          agentName,
          active.stopwatch.elapsed,
          error: error,
          recorder: recorder,
        );
        adk_metrics.recordToolRequestSize(
          toolName,
          agentName,
          active.toolArgs ?? const <String, Object?>{},
          recorder: recorder,
        );
        if (error != null) {
          adk_metrics.recordToolResponseSize(
            toolName,
            agentName,
            null,
            recorder: recorder,
          );
        }
      default:
        return;
    }
  }

  void _recordAgentEvent(String invocationId, Event event) {
    final List<_ActiveSpan>? spans = _spansByInvocation[invocationId];
    if (spans == null) {
      return;
    }
    for (final _ActiveSpan active in spans) {
      if (active.kind == 'agent') {
        active.events.add(event);
      }
    }
  }

  void _queueToolResponseMetric(
    String invocationId,
    String toolName,
    String agentName,
    String? functionCallId,
  ) {
    if (!recordMetrics) {
      return;
    }
    _pendingToolResponsesByInvocation
        .putIfAbsent(invocationId, () => <_PendingToolResponseMetric>[])
        .add(
          _PendingToolResponseMetric(
            toolName: toolName,
            agentName: agentName,
            functionCallId: functionCallId,
          ),
        );
  }

  void _recordPendingToolResponse(String invocationId, Event event) {
    final List<_PendingToolResponseMetric>? pending =
        _pendingToolResponsesByInvocation[invocationId];
    if (pending == null || pending.isEmpty) {
      return;
    }
    for (final FunctionResponse response in event.getFunctionResponses()) {
      final int index = pending.indexWhere((_PendingToolResponseMetric item) {
        if (item.toolName != response.name) {
          return false;
        }
        final String? functionCallId = item.functionCallId;
        return functionCallId == null ||
            functionCallId.isEmpty ||
            functionCallId == response.id;
      });
      if (index < 0) {
        continue;
      }
      final _PendingToolResponseMetric item = pending.removeAt(index);
      adk_metrics.recordToolResponseSize(
        item.toolName,
        item.agentName,
        event,
        recorder: _metricsRecorder ?? adk_metrics.adkMetricsRecorder,
      );
    }
    if (pending.isEmpty) {
      _pendingToolResponsesByInvocation.remove(invocationId);
    }
  }

  void _flushPendingToolResponses(String invocationId) {
    final List<_PendingToolResponseMetric>? pending =
        _pendingToolResponsesByInvocation.remove(invocationId);
    if (pending == null) {
      return;
    }
    final adk_metrics.AdkMetricsRecorder recorder =
        _metricsRecorder ?? adk_metrics.adkMetricsRecorder;
    for (final _PendingToolResponseMetric item in pending) {
      adk_metrics.recordToolResponseSize(
        item.toolName,
        item.agentName,
        null,
        recorder: recorder,
      );
    }
  }
}
