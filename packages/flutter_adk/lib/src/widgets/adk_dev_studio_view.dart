import 'dart:convert';
import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';

import '../controllers/adk_chat_controller.dart';
import '../models/adk_chat_message.dart';
import 'adk_agent_logger_view.dart';
import 'adk_chat_view.dart';

/// A developer studio widget replicating the capabilities of `adk web` directly inside Flutter.
///
/// Provides a unified dashboard with:
/// 1. Interactive Agent Chat Playground
/// 2. Live Agent I/O & Telemetry Logger
/// 3. Agent & Sub-Agent Graph Inspector
/// 4. Session & State Variables Inspector
class AdkDevStudioView extends StatefulWidget {
  /// Creates an [AdkDevStudioView].
  const AdkDevStudioView({
    super.key,
    this.agent,
    this.runner,
    this.controller,
    this.title = 'ADK Dev Studio',
    this.initialTabIndex = 0,
    this.initialState = const <String, dynamic>{},
    this.suggestions = const <String>[
      'Hello, what can you do?',
      'List all your available tools',
      'Explain your workflow',
    ],
  }) : assert(
          agent != null || runner != null || controller != null,
          'AdkDevStudioView requires an agent, runner, or controller.',
        );

  /// Agent to inspect and run.
  final adk.BaseAgent? agent;

  /// Runner to execute.
  final adk.Runner? runner;

  /// Optional pre-existing chat controller.
  final AdkChatController? controller;

  /// Title displayed in the studio app bar.
  final String title;

  /// Initial active tab index (0: Chat, 1: Logger, 2: Agent Graph, 3: State).
  final int initialTabIndex;

  /// Initial session state to display in the State Inspector.
  final Map<String, dynamic> initialState;

  /// Quick prompt suggestions for the chat playground.
  final List<String> suggestions;

  @override
  State<AdkDevStudioView> createState() => _AdkDevStudioViewState();
}

class _AdkDevStudioViewState extends State<AdkDevStudioView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final AdkChatController _chatController;
  late final bool _ownsController;

  final List<AdkAgentLogEntry> _logs = <AdkAgentLogEntry>[];
  late Map<String, dynamic> _sessionState;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );

    _sessionState = Map<String, dynamic>.from(widget.initialState);

    if (widget.controller != null) {
      _chatController = widget.controller!;
      _ownsController = false;
    } else {
      _chatController = AdkChatController(
        agent: widget.agent,
        runner: widget.runner,
      );
      _ownsController = true;
    }

    _chatController.addListener(_onChatUpdate);
  }

  void _onChatUpdate() {
    if (!mounted) return;

    // Capture latest events into the logger
    final messages = _chatController.messages;
    if (messages.isNotEmpty) {
      final latest = messages.last;
      final existingIndex = _logs.indexWhere((l) => l.id == latest.id);

      final entry = AdkAgentLogEntry(
        id: latest.id,
        timestamp: latest.timestamp,
        agentName: widget.agent?.name ?? 'agent',
        category: _mapMessageRoleToCategory(latest.role),
        title: latest.text.isNotEmpty
            ? latest.text
            : (latest.toolName != null ? 'Tool: ${latest.toolName}' : 'Event'),
        subtitle: latest.toolArgs != null
            ? 'Args: ${jsonEncode(latest.toolArgs)}'
            : (latest.errorMessage ?? latest.text),
        payload: latest.toolResult ?? latest.toolArgs ?? <String, dynamic>{
          'text': latest.text,
          'role': latest.role.name,
        },
        isError: latest.errorMessage != null,
      );

      setState(() {
        if (existingIndex >= 0) {
          _logs[existingIndex] = entry;
        } else {
          _logs.add(entry);
        }
      });
    }
  }

  AdkLogCategory _mapMessageRoleToCategory(AdkMessageRole role) {
    switch (role) {
      case AdkMessageRole.user:
        return AdkLogCategory.userInput;
      case AdkMessageRole.model:
        return AdkLogCategory.modelResponse;
      case AdkMessageRole.tool:
        return AdkLogCategory.toolCall;
      case AdkMessageRole.system:
        return AdkLogCategory.error;
    }
  }

  @override
  void dispose() {
    _chatController.removeListener(_onChatUpdate);
    if (_ownsController) {
      _chatController.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            Icon(Icons.developer_board, size: 22.0, color: theme.colorScheme.primary),
            const SizedBox(width: 8.0),
            Text(widget.title),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const <Widget>[
            Tab(icon: Icon(Icons.chat_outlined), text: 'Playground'),
            Tab(icon: Icon(Icons.terminal_rounded), text: 'Live Logger'),
            Tab(icon: Icon(Icons.account_tree_outlined), text: 'Agent Graph'),
            Tab(icon: Icon(Icons.data_object), text: 'State & Session'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          // Tab 1: Chat Playground
          AdkChatView(
            controller: _chatController,
            suggestions: widget.suggestions,
            title: widget.agent?.name ?? 'Assistant',
          ),

          // Tab 2: Live Logger
          AdkAgentLoggerView(
            logs: _logs,
            onClearLogs: () => setState(() => _logs.clear()),
            showHeader: false,
          ),

          // Tab 3: Agent Graph
          _buildAgentGraphView(theme),

          // Tab 4: State Inspector
          _buildStateInspectorView(theme),
        ],
      ),
    );
  }

  Widget _buildAgentGraphView(ThemeData theme) {
    final agent = widget.agent;
    if (agent == null) {
      return Center(
        child: Text(
          'Agent metadata not available.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.smart_toy_outlined,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            agent.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Class: ${agent.runtimeType}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (agent.description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12.0),
                    Text(
                      'Description:',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      agent.description,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if (agent is adk.LlmAgent) ...<Widget>[
                    const SizedBox(height: 12.0),
                    Row(
                      children: <Widget>[
                        Text(
                          'Model: ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 2.0,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6.0),
                          ),
                          child: Text(
                            agent.model.toString(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (agent.subAgents.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16.0),
            Text(
              'Sub-Agents (${agent.subAgents.length}):',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8.0),
            ...agent.subAgents.map((sub) => Card(
                  margin: const EdgeInsets.only(bottom: 8.0),
                  child: ListTile(
                    leading: const Icon(Icons.subdirectory_arrow_right),
                    title: Text(
                      sub.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      sub.description.isNotEmpty
                          ? sub.description
                          : 'Type: ${sub.runtimeType}',
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildStateInspectorView(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'Session State Variables',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh State',
                onPressed: () => setState(() {}),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          if (_sessionState.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(
                  'No state variables stored in this session.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            ..._sessionState.entries.map((entry) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8.0),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6.0,
                              vertical: 2.0,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: Text(
                              entry.key,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      SelectableText(
                        jsonEncode(entry.value),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
