/// Deterministic escalation triggers for model consultation.
library;

import 'dart:convert';

import '../../agents/callback_context.dart';
import '../../agents/invocation_context.dart';
import '../../events/event.dart';
import '../../models/llm_request.dart';
import '../../models/llm_response.dart';
import '../../plugins/base_plugin.dart';
import '../../tools/base_tool.dart';
import '../../tools/tool_context.dart';
import '../../types/content.dart';
import 'model_consult_tool.dart';

/// Status string returned when a gated tool call is refused.
const String consultRequiredStatus = 'consult_required';

const String _defaultForceEscalationPluginName =
    'model_consult_force_escalation';
const int _maxTrackedInvocations = 1024;

class _InvocationState {
  int modelCalls = 0;
  int consults = 0;
  int forced = 0;
  int refusals = 0;
  int pendingRefusals = 0;
  bool pendingForce = false;
  bool budgetExhausted = false;
  bool activeAgentHasTool = true;
  bool turnConsulted = false;
  bool consultedBeforeTurn = false;
  final Map<String, bool> agentHasTool = <String, bool>{};
  final Map<String, int> repeats = <String, int>{};
}

bool _hasPriorModelTurn(CallbackContext context) {
  for (final Event event in context.session.events) {
    if (event.invocationId == context.invocationId &&
        event.author == context.agentName &&
        event.content != null &&
        event.content!.role == 'model') {
      return true;
    }
  }
  return false;
}

String _signature(String name, Map<String, dynamic>? args) {
  try {
    final String rendered = jsonEncode(args ?? <String, dynamic>{});
    return '$name:$rendered';
  } catch (_) {
    return '$name:$args';
  }
}

/// Enforces deterministic model escalation triggers for [ModelConsultTool].
///
/// Escalates weak executor models based on mechanical criteria:
/// * [forceFirstConsult]: Forces a consultation on the first model turn.
/// * [forceOnRepeat]: Forces a consultation when a tool call is repeated identically.
/// * [requireConsultBefore]: Refuses execution of specified tools until a consultation occurs.
///
/// ```dart
/// final plugin = ForceEscalationPlugin(
///   forceFirstConsult: true,
///   forceOnRepeat: 3,
///   requireConsultBefore: {'execute_code', 'deploy_service'},
/// );
/// ```
class ForceEscalationPlugin extends BasePlugin {
  /// Creates a [ForceEscalationPlugin] instance.
  ForceEscalationPlugin({
    super.name = _defaultForceEscalationPluginName,
    this.toolName = ModelConsultTool.defaultToolName,
    this.forceFirstConsult = true,
    this.forceOnRepeat = 3,
    this.maxForced = 2,
    Iterable<String>? requireConsultBefore,
    this.maxRefusals = 2,
  }) : requireConsultBefore = requireConsultBefore != null
            ? Set<String>.unmodifiable(requireConsultBefore)
            : const <String>{} {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
    if (toolName.trim().isEmpty) {
      throw ArgumentError.value(toolName, 'toolName', 'Must not be empty.');
    }
    if (forceOnRepeat != null && forceOnRepeat! <= 0) {
      throw ArgumentError.value(
        forceOnRepeat,
        'forceOnRepeat',
        'Must be positive or null.',
      );
    }
    if (maxForced != null && maxForced! < 0) {
      throw ArgumentError.value(
        maxForced,
        'maxForced',
        'Must be non-negative or null.',
      );
    }
    if (maxRefusals != null && maxRefusals! < 0) {
      throw ArgumentError.value(
        maxRefusals,
        'maxRefusals',
        'Must be non-negative or null.',
      );
    }
    for (final String gated in this.requireConsultBefore) {
      if (gated.trim().isEmpty) {
        throw ArgumentError(
          'requireConsultBefore entries must be non-empty strings.',
        );
      }
      if (gated == toolName) {
        throw ArgumentError(
          'requireConsultBefore cannot contain the consultation tool ($toolName).',
        );
      }
    }
  }

  /// Target consultation tool name.
  final String toolName;

  /// Whether to require a consult on the first model turn of an invocation.
  final bool forceFirstConsult;

  /// Repeat threshold for identical tool calls before forcing a consult.
  final int? forceOnRepeat;

  /// Maximum forced consultations allowed per invocation.
  final int? maxForced;

  /// Tool names that are refused until at least one consultation occurs in the session.
  final Set<String> requireConsultBefore;

  /// Maximum number of refusals before gating gives up and allows the tool to run.
  final int? maxRefusals;

  final Map<String, _InvocationState> _states = <String, _InvocationState>{};

  _InvocationState _state(Object context, String invocationId, List<Event> events) {
    final _InvocationState? existing = _states[invocationId];
    if (existing != null) return existing;

    final _InvocationState state = _InvocationState();
    for (final Event event in events) {
      if (event.invocationId != invocationId) continue;
      final Content? content = event.content;
      if (content == null || content.parts.isEmpty) continue;

      for (final Part part in content.parts) {
        final FunctionResponse? fr = part.functionResponse;
        if (fr == null) continue;
        final Map<String, dynamic> response = fr.response;
        final Object? status = response['status'];

        if (fr.name == toolName) {
          if (status == 'ok' || status == 'error') {
            state.consults += 1;
            final Object? meta = response['consults'];
            if (meta is Map && meta['remaining'] == 0) {
              state.budgetExhausted = true;
            }
          } else if (status == 'limit_reached') {
            state.budgetExhausted = true;
          }
        } else if (requireConsultBefore.contains(fr.name) &&
            status == consultRequiredStatus) {
          state.refusals += 1;
        }
      }
    }

    if (_states.length >= _maxTrackedInvocations) {
      _states.remove(_states.keys.first);
    }
    _states[invocationId] = state;
    return state;
  }

  int _sessionUses(Object context) {
    final String key = ModelConsultTool.sessionUsesStateKey(toolName: toolName);
    if (context is CallbackContext) {
      final Object? val = context.state[key];
      return val is num ? val.toInt() : 0;
    }
    if (context is ToolContext) {
      final Object? val = context.state[key];
      return val is num ? val.toInt() : 0;
    }
    return 0;
  }

  @override
  Future<LlmResponse?> beforeModelCallback({
    required CallbackContext callbackContext,
    required LlmRequest llmRequest,
  }) async {
    final _InvocationState state = _state(
      callbackContext,
      callbackContext.invocationId,
      callbackContext.session.events,
    );
    final Map<String, BaseTool> toolsDict =
        llmRequest.toolsDict;
    final BaseTool? tool = toolsDict[toolName];
    final bool hasTool = tool != null;
    state.activeAgentHasTool = hasTool;
    state.agentHasTool[callbackContext.agentName] = hasTool;
    if (!hasTool) return null;

    state.turnConsulted = false;
    state.consultedBeforeTurn =
        state.consults > 0 || _sessionUses(callbackContext) > 0;
    final bool isFirstCall =
        state.modelCalls == 0 && !_hasPriorModelTurn(callbackContext);
    state.modelCalls += 1;

    if (tool is ModelConsultTool && !tool.hasRemainingBudget(callbackContext)) {
      state.budgetExhausted = true;
    }
    if (state.budgetExhausted) return null;
    if (maxForced != null && state.forced >= maxForced!) return null;

    final bool wantsFirst =
        forceFirstConsult && isFirstCall && state.consults == 0;
    if (!wantsFirst && !state.pendingForce) return null;

    final FunctionCallingConfig fcConfig = FunctionCallingConfig(
      mode: FunctionCallingConfigMode.any,
      allowedFunctionNames: <String>[toolName],
    );

    llmRequest.config.toolConfig =
        (llmRequest.config.toolConfig ?? LlmToolConfig()).copyWith(
      functionCallingConfig: fcConfig,
    );

    state.forced += 1;
    state.pendingForce = false;
    return null;
  }

  @override
  Future<Map<String, dynamic>?> beforeToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
  }) async {
    if (requireConsultBefore.isEmpty ||
        !requireConsultBefore.contains(tool.name)) {
      return null;
    }

    final _InvocationState state = _state(
      toolContext,
      toolContext.invocationId,
      toolContext.session.events,
    );
    final bool agentHasTool = state.agentHasTool[toolContext.agentName] ??
        state.activeAgentHasTool;
    if (!agentHasTool || state.budgetExhausted) return null;

    final bool hasConsulted = state.modelCalls > 0
        ? state.consultedBeforeTurn
        : (state.consults > 0 || _sessionUses(toolContext) > 0);
    if (hasConsulted) return null;

    if (maxRefusals != null && state.refusals >= maxRefusals!) return null;

    state.refusals += 1;
    state.pendingRefusals += 1;

    return <String, dynamic>{
      'status': consultRequiredStatus,
      'message': 'Tool `${tool.name}` requires consulting `$toolName` at least '
          'once in this session before use. Call `$toolName` first, then retry `${tool.name}`.',
    };
  }

  @override
  Future<Map<String, dynamic>?> afterToolCallback({
    required BaseTool tool,
    required Map<String, dynamic> toolArgs,
    required ToolContext toolContext,
    required Map<String, dynamic> result,
  }) async {
    final _InvocationState state = _state(
      toolContext,
      toolContext.invocationId,
      toolContext.session.events,
    );

    if (tool.name == toolName) {
      final Object? status = result['status'];
      if (status == 'ok') {
        state.consults += 1;
        final Object? meta = result['consults'];
        if (meta is Map && meta['remaining'] == 0) {
          state.budgetExhausted = true;
        }
      } else if (status == 'error') {
        state.consults += 1;
      } else if (status == 'limit_reached') {
        state.budgetExhausted = true;
      }

      if (status != 'invalid_request') {
        state.repeats.clear();
        state.turnConsulted = state.modelCalls > 0;
      }
      state.pendingForce = false;
      return null;
    }

    if (state.pendingRefusals > 0 &&
        result['status'] == consultRequiredStatus) {
      state.pendingRefusals -= 1;
      return null;
    }

    final bool agentHasTool = state.agentHasTool[toolContext.agentName] ??
        state.activeAgentHasTool;
    if (forceOnRepeat == null || !agentHasTool || state.turnConsulted) {
      return null;
    }

    final String sig = _signature(tool.name, toolArgs);
    final int count = (state.repeats[sig] ?? 0) + 1;
    state.repeats[sig] = count;
    if (count >= forceOnRepeat!) {
      state.pendingForce = true;
      state.repeats[sig] = 0;
    }
    return null;
  }

  @override
  Future<void> afterRunCallback({
    required InvocationContext invocationContext,
  }) async {
    _states.remove(invocationContext.invocationId);
  }

  @override
  Future<void> close() async {
    _states.clear();
  }
}
