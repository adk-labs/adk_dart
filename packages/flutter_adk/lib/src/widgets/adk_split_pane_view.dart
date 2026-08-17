import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';

import '../controllers/adk_chat_controller.dart';
import '../models/adk_chat_message.dart';
import '../theme/adk_theme.dart';
import 'adk_agent_logger_view.dart';
import 'adk_chat_view.dart';
import 'adk_tool_inspector_view.dart';

/// A multi-pane split layout widget tailored for Web, Desktop, and Tablet AI development and monitoring.
class AdkSplitPaneView extends StatefulWidget {
  /// Creates an [AdkSplitPaneView].
  const AdkSplitPaneView({
    super.key,
    this.agent,
    this.runner,
    this.controller,
    this.theme,
    this.splitRatio = 0.55,
    this.breakpoint = 768.0,
    this.dividerColor,
    this.dividerWidth = 1.0,
    this.showToolInspector = true,
    this.showLogger = true,
    this.customRightTabs = const <Tab>[],
    this.customRightViews = const <Widget>[],
    this.leftPaneBuilder,
    this.rightPaneBuilder,
  }) : assert(
          customRightTabs.length == customRightViews.length,
          'customRightTabs and customRightViews must have equal length.',
        );

  /// Agent to run.
  final adk.BaseAgent? agent;

  /// Runner to execute.
  final adk.Runner? runner;

  /// Optional preconfigured controller.
  final AdkChatController? controller;

  /// Optional theme styling configuration.
  final AdkChatThemeData? theme;

  /// Width ratio occupied by the left chat pane (0.1 to 0.9).
  final double splitRatio;

  /// Screen width threshold below which the layout collapses into a single-pane view.
  final double breakpoint;

  /// Color of the dividing line between panes.
  final Color? dividerColor;

  /// Width of the dividing line.
  final double dividerWidth;

  /// Whether to include the tool inspector tab in the right pane.
  final bool showToolInspector;

  /// Whether to include the live logger tab in the right pane.
  final bool showLogger;

  /// Custom tabs to append to the right inspector pane.
  final List<Tab> customRightTabs;

  /// Custom tab view widgets corresponding to [customRightTabs].
  final List<Widget> customRightViews;

  /// Optional builder to override the left pane entirely.
  final Widget Function(BuildContext context, AdkChatController controller)? leftPaneBuilder;

  /// Optional builder to override the right inspector pane entirely.
  final Widget Function(BuildContext context, AdkChatController controller)? rightPaneBuilder;

  @override
  State<AdkSplitPaneView> createState() => _AdkSplitPaneViewState();
}

class _AdkSplitPaneViewState extends State<AdkSplitPaneView>
    with SingleTickerProviderStateMixin {
  late final AdkChatController _controller;
  late final bool _ownsController;
  late TabController _tabController;
  final List<AdkAgentLogEntry> _logs = <AdkAgentLogEntry>[];

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = AdkChatController(
        agent: widget.agent,
        runner: widget.runner,
      );
      _ownsController = true;
    }

    _controller.addListener(_onChatUpdate);
    final int totalTabs = (widget.showLogger ? 1 : 0) +
        (widget.showToolInspector ? 1 : 0) +
        widget.customRightTabs.length;

    _tabController = TabController(
      length: totalTabs > 0 ? totalTabs : 1,
      vsync: this,
    );
  }

  void _onChatUpdate() {
    if (!mounted) return;
    setState(() {
      for (final AdkChatMessage msg in _controller.messages) {
        final String logId = 'log_${msg.id}';
        final int existingIndex = _logs.indexWhere((AdkAgentLogEntry l) => l.id == logId);
        final AdkAgentLogEntry entry = AdkAgentLogEntry(
          id: logId,
          timestamp: msg.timestamp,
          agentName: msg.author.isNotEmpty ? msg.author : 'agent',
          category: _mapRoleToCategory(msg.role),
          title: msg.isTool
              ? 'Tool: ${msg.toolName}'
              : (msg.isUser ? 'User Prompt' : 'Model Response'),
          payload: msg.isTool ? msg.toolArgs : <String, dynamic>{'text': msg.text},
          isError: msg.isError,
        );

        if (existingIndex >= 0) {
          _logs[existingIndex] = entry;
        } else {
          _logs.add(entry);
        }
      }
    });
  }

  AdkLogCategory _mapRoleToCategory(AdkMessageRole role) {
    switch (role) {
      case .user:
        return .userInput;
      case .model:
        return .modelResponse;
      case .tool:
        return .toolCall;
      case .system:
        return .error;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChatUpdate);
    if (_ownsController) {
      _controller.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData flutterTheme = Theme.of(context);
    final AdkChatThemeData adkTheme = widget.theme ?? AdkTheme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth >= widget.breakpoint;

        final Widget leftPane = widget.leftPaneBuilder != null
            ? widget.leftPaneBuilder!(context, _controller)
            : AdkChatView(
                controller: _controller,
                theme: adkTheme,
                showAppBar: false,
              );

        if (!isWide) {
          return leftPane;
        }

        final Widget rightPane = widget.rightPaneBuilder != null
            ? widget.rightPaneBuilder!(context, _controller)
            : _buildDefaultRightPane(flutterTheme, adkTheme);

        final double leftWidth = constraints.maxWidth * widget.splitRatio;
        final double rightWidth = constraints.maxWidth - leftWidth - widget.dividerWidth;

        return Row(
          children: <Widget>[
            SizedBox(width: leftWidth, child: leftPane),
            VerticalDivider(
              width: widget.dividerWidth,
              thickness: widget.dividerWidth,
              color: widget.dividerColor ?? flutterTheme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            SizedBox(width: rightWidth, child: rightPane),
          ],
        );
      },
    );
  }

  Widget _buildDefaultRightPane(ThemeData theme, AdkChatThemeData adkTheme) {
    final List<Tab> tabs = <Tab>[
      if (widget.showLogger)
        const Tab(icon: Icon(Icons.history_outlined, size: 18), text: 'Logger'),
      if (widget.showToolInspector)
        const Tab(icon: Icon(Icons.build_circle_outlined, size: 18), text: 'Tools'),
      ...widget.customRightTabs,
    ];

    final List<Widget> views = <Widget>[
      if (widget.showLogger)
        AdkAgentLoggerView(
          logs: _logs,
          showHeader: false,
          onClearLogs: () => setState(() => _logs.clear()),
        ),
      if (widget.showToolInspector)
        AdkToolInspectorView(
          tools: (widget.agent is adk.LlmAgent)
              ? (widget.agent! as adk.LlmAgent).tools
              : const <Object>[],
        ),
      ...widget.customRightViews,
    ];

    if (tabs.isEmpty) {
      return const Center(child: Text('Inspector Pane'));
    }

    return Column(
      children: <Widget>[
        TabBar(
          controller: _tabController,
          tabs: tabs,
          isScrollable: tabs.length > 3,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: views,
          ),
        ),
      ],
    );
  }
}
