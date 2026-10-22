/// Antigravity SDK agent wrapper for ADK.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import '../../agents/base_agent.dart';
import '../../agents/invocation_context.dart';
import '../../agents/run_config.dart';
import '../../events/event.dart';
import '../../events/event_actions.dart';
import '../../tools/base_tool.dart';
import '../../types/content.dart';
import 'event_converter.dart';
import 'sub_agent_tools.dart';
import 'tool_result_capture.dart';

/// Error message thrown when an [AntigravityAgent] is nested inside a parent
/// agent without `mode: 'single_turn'`.
const String parentRequiresSingleTurnMessage =
    "AntigravityAgent was attached to a parent agent with mode != "
    "'single_turn'. Multi-turn session tracking is unsupported when nested "
    'inside a workflow or parent agent because the parent may loop or '
    "re-invoke the child within the same session. Set mode='single_turn' on "
    'nested AntigravityAgents.';

/// Sub-agent configuration passed to the Antigravity SDK.
class AntigravitySubagentConfig {
  /// Creates a native Antigravity sub-agent configuration.
  const AntigravitySubagentConfig({
    required this.name,
    this.tools = const <Object>[],
    this.description = '',
  });

  /// Unique name of the sub-agent.
  final String name;

  /// Tools available to this sub-agent.
  final List<Object> tools;

  /// Description of when to delegate to this sub-agent.
  final String description;
}

/// Alias for [AntigravitySubagentConfig] matching the SDK `SubagentConfig` type.
typedef SubagentConfig = AntigravitySubagentConfig;

/// Base configuration for an Antigravity SDK agent.
class AgentConfig {
  /// Creates an Antigravity SDK agent configuration.
  AgentConfig({
    List<Object>? tools,
    List<Object>? hooks,
    List<AntigravitySubagentConfig>? subagents,
  }) : tools = List<Object>.unmodifiable(tools ?? const <Object>[]),
       hooks = List<Object>.unmodifiable(hooks ?? const <Object>[]),
       subagents = List<AntigravitySubagentConfig>.unmodifiable(
         subagents ?? const <AntigravitySubagentConfig>[],
       );

  /// Tools registered on the SDK agent.
  final List<Object> tools;

  /// Lifecycle/tool hooks registered on the SDK agent.
  final List<Object> hooks;

  /// Native sub-agent configurations registered on the SDK agent.
  final List<AntigravitySubagentConfig> subagents;

  /// Returns a copy of this configuration with the specified overrides.
  AgentConfig copyWith({
    List<Object>? tools,
    List<Object>? hooks,
    List<AntigravitySubagentConfig>? subagents,
  }) {
    return AgentConfig(
      tools: tools ?? this.tools,
      hooks: hooks ?? this.hooks,
      subagents: subagents ?? this.subagents,
    );
  }
}

/// Base configuration for local Antigravity SDK agents supporting persistence
/// and session continuation.
class BaseLocalAgentConfig extends AgentConfig {
  /// Creates a base local agent configuration.
  BaseLocalAgentConfig({
    super.tools,
    super.hooks,
    super.subagents,
    this.saveDir,
    this.conversationId,
    this.sessionContinuationMode = SessionContinuationMode.unspecified,
  });

  /// Optional directory where local conversation trajectories are persisted.
  final String? saveDir;

  /// Conversation ID to create or resume.
  final String? conversationId;

  /// Mode governing whether an existing conversation is resumed or created.
  final SessionContinuationMode sessionContinuationMode;

  @override
  BaseLocalAgentConfig copyWith({
    List<Object>? tools,
    List<Object>? hooks,
    List<AntigravitySubagentConfig>? subagents,
    Object? saveDir = _sentinel,
    Object? conversationId = _sentinel,
    SessionContinuationMode? sessionContinuationMode,
  }) {
    return BaseLocalAgentConfig(
      tools: tools ?? this.tools,
      hooks: hooks ?? this.hooks,
      subagents: subagents ?? this.subagents,
      saveDir: identical(saveDir, _sentinel)
          ? this.saveDir
          : saveDir as String?,
      conversationId: identical(conversationId, _sentinel)
          ? this.conversationId
          : conversationId as String?,
      sessionContinuationMode:
          sessionContinuationMode ?? this.sessionContinuationMode,
    );
  }
}

/// Concrete local Antigravity SDK agent configuration.
class LocalAgentConfig extends BaseLocalAgentConfig {
  /// Creates a local Antigravity SDK agent configuration.
  LocalAgentConfig({
    super.tools,
    super.hooks,
    super.subagents,
    super.saveDir,
    super.conversationId,
    super.sessionContinuationMode,
  });

  @override
  LocalAgentConfig copyWith({
    List<Object>? tools,
    List<Object>? hooks,
    List<AntigravitySubagentConfig>? subagents,
    Object? saveDir = _sentinel,
    Object? conversationId = _sentinel,
    SessionContinuationMode? sessionContinuationMode,
  }) {
    return LocalAgentConfig(
      tools: tools ?? this.tools,
      hooks: hooks ?? this.hooks,
      subagents: subagents ?? this.subagents,
      saveDir: identical(saveDir, _sentinel)
          ? this.saveDir
          : saveDir as String?,
      conversationId: identical(conversationId, _sentinel)
          ? this.conversationId
          : conversationId as String?,
      sessionContinuationMode:
          sessionContinuationMode ?? this.sessionContinuationMode,
    );
  }
}

const Object _sentinel = Object();

/// Interface representing an active Antigravity SDK conversation.
abstract class SdkConversation {
  /// Creates an SDK conversation interface.
  const SdkConversation();

  /// Unique identifier for this conversation.
  String? get conversationId;

  /// History of steps prior to or including the current turn.
  List<AntigravityStep> get history;

  /// Token usage statistics for the most recently completed turn.
  AntigravityTurnUsage? get lastTurnUsage;

  /// Map of sub-agent trajectory IDs to their recorded steps.
  Map<String, List<AntigravityStep>> get subagentSteps;

  /// Sends [prompt] to the Antigravity runtime and streams [AntigravityStep]s.
  Stream<AntigravityStep> sendStream(String prompt);
}

/// Interface representing an Antigravity SDK agent session handle.
abstract class SdkAgent {
  /// Creates an SDK agent interface.
  const SdkAgent();

  /// Active agent configuration.
  AgentConfig get config;

  /// Active conversation handle.
  SdkConversation get conversation;

  /// Opens / initializes the underlying SDK session.
  Future<void> enter();

  /// Closes / tears down the underlying SDK session.
  Future<void> exit();
}

/// Factory signature for creating [SdkAgent] instances from [AgentConfig].
typedef SdkAgentFactory = SdkAgent Function(AgentConfig config);

/// In-memory [SdkConversation] implementation for testing and local simulation.
class InMemorySdkConversation extends SdkConversation {
  /// Creates an in-memory SDK conversation.
  InMemorySdkConversation({
    this.conversationId = 'antigravity_conv_default',
    List<AntigravityStep>? initialHistory,
    this.lastTurnUsage,
    Map<String, List<AntigravityStep>>? subagentSteps,
    Stream<AntigravityStep> Function(String prompt)? onSendStream,
  }) : _history = List<AntigravityStep>.from(
         initialHistory ?? const <AntigravityStep>[],
       ),
       _subagentSteps = <String, List<AntigravityStep>>{
         if (subagentSteps != null)
           for (final MapEntry<String, List<AntigravityStep>> e
               in subagentSteps.entries)
             e.key: List<AntigravityStep>.from(e.value),
       },
       _onSendStream = onSendStream;

  @override
  final String? conversationId;

  final List<AntigravityStep> _history;

  @override
  List<AntigravityStep> get history => _history;

  @override
  AntigravityTurnUsage? lastTurnUsage;

  final Map<String, List<AntigravityStep>> _subagentSteps;

  @override
  Map<String, List<AntigravityStep>> get subagentSteps => _subagentSteps;

  final Stream<AntigravityStep> Function(String prompt)? _onSendStream;

  @override
  Stream<AntigravityStep> sendStream(String prompt) async* {
    if (_onSendStream != null) {
      await for (final AntigravityStep step in _onSendStream(prompt)) {
        _history.add(step);
        yield step;
      }
      return;
    }
    final AntigravityStep defaultStep = AntigravityStep(
      stepIndex: _history.length,
      source: StepSource.model,
      type: StepType.textResponse,
      status: StepStatus.done,
      content: prompt,
    );
    _history.add(defaultStep);
    yield defaultStep;
  }
}

/// In-memory [SdkAgent] implementation for testing and local simulation.
class InMemorySdkAgent extends SdkAgent {
  /// Creates an in-memory SDK agent.
  InMemorySdkAgent({
    required this.config,
    SdkConversation? conversation,
  }) : conversation =
           conversation ??
           InMemorySdkConversation(
             conversationId: config is BaseLocalAgentConfig
                 ? (config.conversationId ?? 'antigravity_conv_default')
                 : 'antigravity_conv_default',
           );

  @override
  final AgentConfig config;

  @override
  final SdkConversation conversation;

  /// Whether [enter] has been called without a matching [exit].
  bool isEntered = false;

  @override
  Future<void> enter() async {
    isEntered = true;
  }

  @override
  Future<void> exit() async {
    isEntered = false;
  }
}

class _ActiveTurnSession {
  _ActiveTurnSession({
    required this.agent,
    required this.resultBuffer,
  });

  final SdkAgent agent;
  final ToolResultCapture resultBuffer;
}

String _toolIdentifier(Object tool) {
  if (tool is BaseTool) {
    return tool.name;
  }
  if (tool is Function) {
    final String str = tool.toString();
    final RegExp fnName = RegExp(r"Function '([^']+)'");
    final RegExpMatch? match = fnName.firstMatch(str);
    if (match != null && match.group(1) != null) {
      return match.group(1)!;
    }
  }
  try {
    final dynamic dyn = tool;
    final Object? n = dyn.name;
    if (n is String && n.isNotEmpty) {
      return n;
    }
  } catch (_) {
    // Ignore missing name property.
  }
  return '$tool';
}

/// ADK agent that delegates execution to an Antigravity SDK agent and
/// translates its streaming trajectory steps and tool hooks into ADK [Event]s.
///
/// ```dart
/// final agent = AntigravityAgent(
///   name: 'code_assistant',
///   description: 'Executes coding tasks via Antigravity.',
///   config: LocalAgentConfig(),
/// );
/// ```
class AntigravityAgent extends BaseAgent {
  /// Creates an [AntigravityAgent].
  AntigravityAgent({
    required super.name,
    super.description,
    super.subAgents,
    super.beforeAgentCallback,
    super.afterAgentCallback,
    AgentConfig? config,
    this.mode,
    SdkAgentFactory? sdkAgentFactory,
  }) : config = config ?? LocalAgentConfig(),
       _sdkAgentFactory =
           sdkAgentFactory ??
           ((AgentConfig cfg) => InMemorySdkAgent(config: cfg)) {
    _validateConfiguration();
  }

  /// Antigravity SDK agent configuration.
  final AgentConfig config;

  /// Optional execution mode (`'single_turn'` disables multi-turn session tracking).
  final String? mode;

  final SdkAgentFactory _sdkAgentFactory;

  late final Map<String, Set<String>> _subagentNamesByTool;
  late final Set<String> _configuredSubagentNames;

  @override
  set parentAgent(BaseAgent? value) {
    if (value != null && mode != 'single_turn') {
      throw ArgumentError(parentRequiresSingleTurnMessage);
    }
    super.parentAgent = value;
  }

  String get _stateConversationKey => '_antigravity_conversation_id_$name';

  void _validateConfiguration() {
    if (parentAgent != null && mode != 'single_turn') {
      throw ArgumentError(parentRequiresSingleTurnMessage);
    }

    final Map<String, Set<String>> byTool = <String, Set<String>>{};
    for (final AntigravitySubagentConfig sub in config.subagents) {
      for (final Object t in sub.tools) {
        final String id = _toolIdentifier(t);
        byTool.putIfAbsent(id, () => <String>{}).add(sub.name);
      }
    }
    _subagentNamesByTool = byTool;
    _configuredSubagentNames = <String>{
      for (final AntigravitySubagentConfig sub in config.subagents) sub.name,
    };

    final Set<String> existingToolNames = <String>{
      for (final Object t in config.tools) _toolIdentifier(t),
    };
    final Set<String> seenSubAgents = <String>{};
    for (final BaseAgent child in subAgents) {
      if (child.description.trim().isEmpty) {
        throw ArgumentError(
          "Sub-agent '${child.name}' of AntigravityAgent '$name' has an empty "
          'description. Antigravity uses the description to decide when to '
          "delegate to the sub-agent; set description=... on '${child.name}'.",
        );
      }
      if (!seenSubAgents.add(child.name)) {
        throw ArgumentError(
          "AntigravityAgent '$name' has duplicate sub-agent name "
          "'${child.name}'. Every sub_agents entry must have a unique name.",
        );
      }
      if (existingToolNames.contains(child.name)) {
        throw ArgumentError(
          "Sub-agent '${child.name}' of AntigravityAgent '$name' collides "
          'with a tool of the same name in config.tools. Rename the '
          'sub-agent or the tool.',
        );
      }
    }
  }

  String? _matchingSubagentByTool(String toolName) {
    final Set<String>? candidates = _subagentNamesByTool[toolName];
    if (candidates != null && candidates.length == 1) {
      return candidates.first;
    }
    return null;
  }

  AgentConfig _effectiveConfig({
    required ToolResultCapture resultCapture,
    required ToolErrorCapture errorCapture,
    required SubagentCallCapture subagentCapture,
    required String? storedId,
  }) {
    final List<Object> subTools = <Object>[
      for (final BaseAgent child in subAgents) makeSubAgentTool(child),
    ];
    final List<Object> combinedTools = <Object>[
      ...config.tools,
      ...subTools,
    ];
    final List<Object> combinedHooks = <Object>[
      ...config.hooks,
      resultCapture,
      errorCapture,
      subagentCapture,
    ];

    AgentConfig effective = config.copyWith(
      tools: combinedTools,
      hooks: combinedHooks,
    );

    if (effective is BaseLocalAgentConfig &&
        storedId != null &&
        storedId.isNotEmpty) {
      SessionContinuationMode contMode = effective.sessionContinuationMode;
      if (contMode == SessionContinuationMode.unspecified) {
        contMode = SessionContinuationMode.createOrResume;
      }
      effective = effective.copyWith(
        conversationId: storedId,
        sessionContinuationMode: contMode,
      );
    }

    return effective;
  }

  Future<_ActiveTurnSession> _openTurnSession(String? storedId) async {
    final ToolResultCapture resultCapture = ToolResultCapture();
    final ToolErrorCapture errorCapture = ToolErrorCapture(resultCapture);
    final SubagentCallCapture subagentCapture = SubagentCallCapture(
      resultCapture,
    );
    final AgentConfig effective = _effectiveConfig(
      resultCapture: resultCapture,
      errorCapture: errorCapture,
      subagentCapture: subagentCapture,
      storedId: storedId,
    );
    final SdkAgent sdkAgent = _sdkAgentFactory(effective);
    await sdkAgent.enter();
    return _ActiveTurnSession(
      agent: sdkAgent,
      resultBuffer: resultCapture,
    );
  }

  static String? _extractLastUserText(InvocationContext context) {
    final List<Part>? userParts = context.userContent?.parts;
    if (userParts != null && userParts.isNotEmpty) {
      final List<String> texts = <String>[
        for (final Part p in userParts)
          if (p.text != null && p.text!.isNotEmpty) p.text!,
      ];
      if (texts.isNotEmpty) {
        return texts.join('\n');
      }
    }
    for (int i = context.session.events.length - 1; i >= 0; i--) {
      final Event event = context.session.events[i];
      final List<Part>? parts = event.content?.parts;
      if (event.author == 'user' && parts != null && parts.isNotEmpty) {
        final List<String> texts = <String>[
          for (final Part p in parts)
            if (p.text != null && p.text!.isNotEmpty) p.text!,
        ];
        if (texts.isNotEmpty) {
          return texts.join('\n');
        }
      }
    }
    return null;
  }

  Map<String, String> _extractSessionSubagentAuthors(
    InvocationContext context,
  ) {
    final Map<String, String> resolved = <String, String>{};
    for (final Event event in context.session.events) {
      if (event.author == name || event.author == 'user') {
        continue;
      }
      final String? branch = event.branch;
      if (branch == null || !branch.contains('.')) {
        continue;
      }
      final List<String> parts = branch.split('.');
      final String leaf = parts.last;
      if (!leaf.startsWith('${event.author}_')) {
        continue;
      }
      final String suffix = leaf.substring(event.author.length + 1);
      if (suffix.isNotEmpty) {
        resolved[suffix] = event.author;
      }
    }
    return resolved;
  }

  (String, String?, List<FunctionCall>, List<Part>) _resolveStepContext({
    required AntigravityStep step,
    required String mainTrajId,
    required InvocationContext context,
    required List<FunctionCall> mainPendingFcs,
    required List<Part> mainPendingThoughts,
    required Map<String, List<FunctionCall>> subPendingFcs,
    required Map<String, List<Part>> subPendingThoughts,
    required Map<String, String> trajToAuthor,
    required Queue<Map<String, Object?>> pendingSubagents,
  }) {
    final String stepTrajId = step.trajectoryId;
    final bool isSubagent =
        (stepTrajId.isNotEmpty &&
            mainTrajId.isNotEmpty &&
            stepTrajId != mainTrajId) ||
        step.parentTrajectoryId.isNotEmpty ||
        step.depth > 0;

    if (!isSubagent) {
      return (name, context.branch, mainPendingFcs, mainPendingThoughts);
    }

    final String trajKey = stepTrajId.isNotEmpty
        ? stepTrajId
        : 'depth_${step.depth}';
    String? subAuthor = trajToAuthor[trajKey];

    if (subAuthor == null || subAuthor == 'subagent') {
      if (step.type == StepType.toolCall && step.toolCalls.isNotEmpty) {
        for (final AntigravityToolCall tc in step.toolCalls) {
          final String? matched = _matchingSubagentByTool(tc.name);
          if (matched != null) {
            for (final Map<String, Object?> item in pendingSubagents) {
              if (item['subagent_type'] == matched ||
                  item['subagent_name'] == matched ||
                  item['name'] == matched) {
                pendingSubagents.remove(item);
                break;
              }
            }
            subAuthor = matched;
            trajToAuthor[trajKey] = subAuthor;
            break;
          }
        }
      }

      if (subAuthor == null && pendingSubagents.isNotEmpty) {
        final Map<String, Object?> args = pendingSubagents.removeFirst();
        final String candidate =
            '${args['subagent_type'] ?? args['subagent_name'] ?? args['name'] ?? 'subagent'}';
        subAuthor =
            _configuredSubagentNames.isEmpty ||
                _configuredSubagentNames.contains(candidate)
            ? candidate
            : 'subagent';
        trajToAuthor[trajKey] = subAuthor;
      } else if (subAuthor == null) {
        subAuthor = _configuredSubagentNames.length == 1
            ? _configuredSubagentNames.first
            : 'subagent';
        trajToAuthor[trajKey] = subAuthor;
      }
    }

    final String shortId = trajKey.length >= 8
        ? trajKey.substring(0, 8)
        : trajKey;
    final String subBranch = context.branch != null && context.branch!.isNotEmpty
        ? '${context.branch}.$name.${subAuthor}_$shortId'
        : '$name.${subAuthor}_$shortId';
    final List<FunctionCall> pFcs = subPendingFcs.putIfAbsent(
      trajKey,
      () => <FunctionCall>[],
    );
    final List<Part> pThoughts = subPendingThoughts.putIfAbsent(
      trajKey,
      () => <Part>[],
    );
    return (subAuthor, subBranch, pFcs, pThoughts);
  }

  Stream<Event> _executeTurn(
    InvocationContext context,
    String prompt,
  ) async* {
    final bool trackSession = mode != 'single_turn';
    final String stateKey = _stateConversationKey;
    final String? storedId = trackSession
        ? context.session.state[stateKey] as String?
        : null;

    final List<FunctionCall> pendingFunctionCalls = <FunctionCall>[];
    final List<Part> pendingThoughts = <Part>[];
    final StreamingMode streamingMode =
        context.runConfig?.streamingMode ?? StreamingMode.none;

    final _ActiveTurnSession active = await _openTurnSession(storedId);
    try {
      if (trackSession) {
        if (config is BaseLocalAgentConfig &&
            storedId != null &&
            active.agent.conversation.history.isEmpty) {
          yield Event(
            invocationId: context.invocationId,
            author: name,
            branch: context.branch,
            actions: EventActions(
              stateDelta: <String, Object?>{stateKey: null},
            ),
          );
          throw StateError(
            "AntigravityAgent '$name' failed to resume conversation "
            "'$storedId': the server returned an empty history, indicating "
            'the saved state was not found '
            '(save_dir=${(config as BaseLocalAgentConfig).saveDir}) and the '
            'server silently started a fresh conversation. Clearing stored '
            'conversation ID from session state.',
          );
        }

        final String? convId = active.agent.conversation.conversationId;
        if (convId != null && convId.isNotEmpty && convId != storedId) {
          context.session.state[stateKey] = convId;
          yield Event(
            invocationId: context.invocationId,
            author: name,
            branch: context.branch,
            actions: EventActions(
              stateDelta: <String, Object?>{stateKey: convId},
            ),
          );
        }
      }

      String mainTrajId = '';
      final Map<String, List<FunctionCall>> subPendingFcs =
          <String, List<FunctionCall>>{};
      final Map<String, List<Part>> subPendingThoughts =
          <String, List<Part>>{};
      final Map<String, String> trajToAuthor =
          _extractSessionSubagentAuthors(context);
      bool hasEmittedEvents = false;

      await for (final AntigravityStep step
          in active.agent.conversation.sendStream(prompt)) {
        if (mainTrajId.isEmpty &&
            step.parentTrajectoryId.isEmpty &&
            step.depth == 0 &&
            step.trajectoryId.isNotEmpty) {
          mainTrajId = step.trajectoryId;
        }

        final (
          String stepAuthor,
          String? stepBranch,
          List<FunctionCall> pFcs,
          List<Part> pThoughts,
        ) = _resolveStepContext(
          step: step,
          mainTrajId: mainTrajId,
          context: context,
          mainPendingFcs: pendingFunctionCalls,
          mainPendingThoughts: pendingThoughts,
          subPendingFcs: subPendingFcs,
          subPendingThoughts: subPendingThoughts,
          trajToAuthor: trajToAuthor,
          pendingSubagents: active.resultBuffer.pendingSubagents,
        );

        for (final Event event in convertStepToEvents(
          step,
          invocationId: context.invocationId,
          author: stepAuthor,
          branch: stepBranch,
          pendingFunctionCalls: pFcs,
          pendingThoughts: pThoughts,
          resultBuffer: active.resultBuffer,
          streamingMode: streamingMode,
        )) {
          hasEmittedEvents = true;
          yield event;
        }
      }

      // Drain remaining tool results for sub-agents.
      for (final MapEntry<String, List<FunctionCall>> entry
          in subPendingFcs.entries) {
        final String trajKey = entry.key;
        final List<FunctionCall> pFcs = entry.value;
        final String subAuthor = trajToAuthor[trajKey] ?? 'subagent';
        final String shortId = trajKey.length >= 8
            ? trajKey.substring(0, 8)
            : trajKey;
        final String subBranch =
            context.branch != null && context.branch!.isNotEmpty
            ? '${context.branch}.$name.${subAuthor}_$shortId'
            : '$name.${subAuthor}_$shortId';
        final Event? subToolResp = drainToolResults(
          invocationId: context.invocationId,
          author: subAuthor,
          branch: subBranch,
          pendingFunctionCalls: pFcs,
          resultBuffer: active.resultBuffer,
        );
        if (subToolResp != null) {
          hasEmittedEvents = true;
          yield subToolResp;
        }
      }

      // Flush remaining thoughts for sub-agents.
      for (final MapEntry<String, List<Part>> entry
          in subPendingThoughts.entries) {
        final String trajKey = entry.key;
        final List<Part> pThoughts = entry.value;
        if (pThoughts.isNotEmpty) {
          final String subAuthor = trajToAuthor[trajKey] ?? 'subagent';
          final String shortId = trajKey.length >= 8
              ? trajKey.substring(0, 8)
              : trajKey;
          final String subBranch =
              context.branch != null && context.branch!.isNotEmpty
              ? '${context.branch}.$name.${subAuthor}_$shortId'
              : '$name.${subAuthor}_$shortId';
          hasEmittedEvents = true;
          yield Event(
            invocationId: context.invocationId,
            author: subAuthor,
            branch: subBranch,
            content: Content(
              role: 'model',
              parts: List<Part>.from(pThoughts),
            ),
          );
          pThoughts.clear();
        }
      }

      final Event? toolResp = drainToolResults(
        invocationId: context.invocationId,
        author: name,
        branch: context.branch,
        pendingFunctionCalls: pendingFunctionCalls,
        resultBuffer: active.resultBuffer,
      );
      if (toolResp != null) {
        hasEmittedEvents = true;
        yield toolResp;
      }

      if (pendingThoughts.isNotEmpty) {
        hasEmittedEvents = true;
        yield Event(
          invocationId: context.invocationId,
          author: name,
          branch: context.branch,
          content: Content(
            role: 'model',
            parts: List<Part>.from(pendingThoughts),
          ),
        );
        pendingThoughts.clear();
      }

      final AntigravityTurnUsage? usage =
          active.agent.conversation.lastTurnUsage;
      if (hasEmittedEvents && usage != null) {
        yield Event(
          invocationId: context.invocationId,
          author: name,
          branch: context.branch,
          usageMetadata: <String, Object?>{
            'prompt_token_count': usage.promptTokenCount,
            'candidates_token_count': usage.candidatesTokenCount,
            'total_token_count': usage.totalTokenCount,
            'thoughts_token_count': usage.thoughtsTokenCount,
          },
        );
      }
    } finally {
      await active.agent.exit();
    }
  }

  @override
  Stream<Event> runAsyncImpl(InvocationContext context) async* {
    final String? prompt = _extractLastUserText(context);
    if (prompt == null) {
      developer.log(
        "AntigravityAgent '$name' received no user text in InvocationContext; yielding nothing.",
        name: 'adk_dart.antigravity_agent',
      );
      return;
    }
    await for (final Event event in _executeTurn(context, prompt)) {
      yield event;
    }
  }

  /// Executes this agent as a workflow node with optional [nodeInput].
  Stream<Event> runNodeImpl(
    InvocationContext context, {
    Object? nodeInput,
  }) async* {
    final String? prompt = nodeInput != null
        ? '$nodeInput'
        : _extractLastUserText(context);
    if (prompt == null || prompt.isEmpty) {
      return;
    }
    await for (final Event event in _executeTurn(context, prompt)) {
      yield event;
    }
  }

  @override
  AntigravityAgent clone({Map<String, Object?>? update}) {
    final Map<String, Object?> u = update ?? const <String, Object?>{};
    final String clonedName = u.containsKey('name')
        ? u['name'] as String
        : name;
    final String clonedDescription = u.containsKey('description')
        ? u['description'] as String
        : description;
    final List<BaseAgent> clonedSubAgents = u.containsKey('subAgents')
        ? (u['subAgents'] as List<BaseAgent>?) ?? <BaseAgent>[]
        : subAgents.map((BaseAgent s) => s.clone()).toList();
    final AgentConfig clonedConfig = u.containsKey('config')
        ? u['config'] as AgentConfig
        : config;
    final String? clonedMode = u.containsKey('mode')
        ? u['mode'] as String?
        : mode;

    final AntigravityAgent cloned = AntigravityAgent(
      name: clonedName,
      description: clonedDescription,
      subAgents: clonedSubAgents,
      beforeAgentCallback: u.containsKey('beforeAgentCallback')
          ? u['beforeAgentCallback']
          : beforeAgentCallback,
      afterAgentCallback: u.containsKey('afterAgentCallback')
          ? u['afterAgentCallback']
          : afterAgentCallback,
      config: clonedConfig,
      mode: clonedMode,
      sdkAgentFactory: _sdkAgentFactory,
    );
    if (u.containsKey('parentAgent')) {
      cloned.parentAgent = u['parentAgent'] as BaseAgent?;
    } else {
      cloned.parentAgent = parentAgent;
    }
    return cloned;
  }
}
