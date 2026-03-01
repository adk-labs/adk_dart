import 'package:flutter/material.dart';

import 'package:flutter_adk_example/config/app_localizations.dart';
import 'package:flutter_adk_example/domain/models/app_language.dart';
import 'package:flutter_adk_example/domain/models/custom_agent_config.dart';
import 'package:flutter_adk_example/domain/models/user_example_connection_dsl.dart';
import 'package:flutter_adk_example/domain/models/user_example_config.dart';
import 'package:flutter_adk_example/ui/examples/widgets/custom_agent_config_screen.dart';

class UserExampleBuilderScreen extends StatefulWidget {
  const UserExampleBuilderScreen({
    super.key,
    required this.language,
    this.initialConfig,
  });

  final AppLanguage language;
  final UserExampleConfig? initialConfig;

  @override
  State<UserExampleBuilderScreen> createState() =>
      _UserExampleBuilderScreenState();
}

class _UserExampleBuilderScreenState extends State<UserExampleBuilderScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _summaryController;
  late final TextEditingController _initialMessageController;
  late final TextEditingController _hintController;
  late final TextEditingController _prompt1Controller;
  late final TextEditingController _prompt2Controller;
  late final TextEditingController _prompt3Controller;

  late UserExampleArchitecture _architecture;
  late List<CustomAgentConfig> _agents;
  late int _entryAgentIndex;
  late List<UserExampleConnection> _connections;

  String _t(String key) => tr(widget.language, key);

  bool get _isEditing => widget.initialConfig != null;

  @override
  void initState() {
    super.initState();
    final UserExampleConfig config =
        widget.initialConfig ?? UserExampleConfig.defaults();
    final List<String> prompts = List<String>.from(config.prompts);
    while (prompts.length < 3) {
      prompts.add('');
    }
    _titleController = TextEditingController(text: config.title);
    _summaryController = TextEditingController(text: config.summary);
    _initialMessageController = TextEditingController(
      text: config.initialAssistantMessage,
    );
    _hintController = TextEditingController(text: config.inputHint);
    _prompt1Controller = TextEditingController(text: prompts[0]);
    _prompt2Controller = TextEditingController(text: prompts[1]);
    _prompt3Controller = TextEditingController(text: prompts[2]);
    _architecture = config.architecture;
    _agents = List<CustomAgentConfig>.from(config.agents);
    if (_agents.isEmpty) {
      _agents = <CustomAgentConfig>[CustomAgentConfig.defaults()];
    }
    _entryAgentIndex = config.entryAgentIndex;
    _connections = List<UserExampleConnection>.from(config.connections);
    _normalizeGraphState();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _initialMessageController.dispose();
    _hintController.dispose();
    _prompt1Controller.dispose();
    _prompt2Controller.dispose();
    _prompt3Controller.dispose();
    super.dispose();
  }

  int _minAgents(UserExampleArchitecture architecture) {
    switch (architecture) {
      case UserExampleArchitecture.single:
        return 1;
      case UserExampleArchitecture.team:
      case UserExampleArchitecture.sequential:
      case UserExampleArchitecture.parallel:
        return 2;
      case UserExampleArchitecture.loop:
        return 1;
    }
  }

  Future<void> _editAgent(int index) async {
    final CustomAgentConfig current = _agents[index];
    final CustomAgentConfig? next = await Navigator.of(context)
        .push<CustomAgentConfig>(
          MaterialPageRoute<CustomAgentConfig>(
            builder: (_) => CustomAgentConfigScreen(
              title: _t('custom.config.title'),
              nameLabel: _t('custom.config.name'),
              descriptionLabel: _t('custom.config.description'),
              instructionLabel: _t('custom.config.instruction'),
              capitalToolLabel: _t('custom.config.tool_capital'),
              weatherToolLabel: _t('custom.config.tool_weather'),
              timeToolLabel: _t('custom.config.tool_time'),
              cancelLabel: _t('custom.config.cancel'),
              saveLabel: _t('settings.save'),
              initialConfig: current,
            ),
          ),
        );
    if (next == null || !mounted) {
      return;
    }
    setState(() {
      _agents[index] = next;
    });
  }

  void _addAgent() {
    if (_agents.length >= 4) {
      return;
    }
    setState(() {
      _agents = List<CustomAgentConfig>.from(_agents)
        ..add(
          CustomAgentConfig.defaults().copyWith(
            name: 'Agent ${_agents.length + 1}',
          ),
        );
      _normalizeGraphState();
    });
  }

  void _removeAgent(int index) {
    if (_agents.length <= _minAgents(_architecture)) {
      return;
    }
    setState(() {
      _agents = List<CustomAgentConfig>.from(_agents)..removeAt(index);
      _entryAgentIndex = _remapAfterRemoval(_entryAgentIndex, index);
      if (_entryAgentIndex < 0) {
        _entryAgentIndex = 0;
      }
      _connections = _connections
          .map((UserExampleConnection item) {
            final int from = _remapAfterRemoval(item.fromIndex, index);
            final int to = _remapAfterRemoval(item.toIndex, index);
            if (from < 0 || to < 0 || from == to) {
              return null;
            }
            return item.copyWith(fromIndex: from, toIndex: to);
          })
          .whereType<UserExampleConnection>()
          .toList(growable: false);
      _normalizeGraphState();
    });
  }

  int _remapAfterRemoval(int value, int removedIndex) {
    if (value == removedIndex) {
      return -1;
    }
    if (value > removedIndex) {
      return value - 1;
    }
    return value;
  }

  void _normalizeGraphState() {
    if (_agents.isEmpty) {
      _entryAgentIndex = 0;
      _connections = <UserExampleConnection>[];
      return;
    }
    if (_entryAgentIndex < 0 || _entryAgentIndex >= _agents.length) {
      _entryAgentIndex = 0;
    }
    _connections = _connections
        .where(
          (UserExampleConnection item) =>
              item.fromIndex >= 0 &&
              item.fromIndex < _agents.length &&
              item.toIndex >= 0 &&
              item.toIndex < _agents.length &&
              item.fromIndex != item.toIndex,
        )
        .toList(growable: false);
  }

  String _agentLabel(int index) {
    if (index < 0 || index >= _agents.length) {
      return 'Agent';
    }
    final String name = _agents[index].name.trim();
    if (name.isNotEmpty) {
      return name;
    }
    return 'Agent ${index + 1}';
  }

  Future<void> _addConnection() async {
    if (_agents.length < 2) {
      return;
    }
    int from = _entryAgentIndex;
    int to = _entryAgentIndex == 0 ? 1 : 0;
    final TextEditingController conditionController = TextEditingController(
      text: _t('user_example.connection.default_condition'),
    );
    final UserExampleConnection? created =
        await showDialog<UserExampleConnection>(
          context: context,
          builder: (BuildContext context) {
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                return AlertDialog(
                  title: Text(_t('user_example.action.add_connection')),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      DropdownButtonFormField<int>(
                        initialValue: from,
                        decoration: InputDecoration(
                          labelText: _t('user_example.connection.from'),
                        ),
                        items: List<DropdownMenuItem<int>>.generate(
                          _agents.length,
                          (int index) => DropdownMenuItem<int>(
                            value: index,
                            child: Text(_agentLabel(index)),
                          ),
                        ),
                        onChanged: (int? value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            from = value;
                            if (to == from) {
                              to = (from + 1) % _agents.length;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: to,
                        decoration: InputDecoration(
                          labelText: _t('user_example.connection.to'),
                        ),
                        items: List<DropdownMenuItem<int>>.generate(
                          _agents.length,
                          (int index) => DropdownMenuItem<int>(
                            value: index,
                            enabled: index != from,
                            child: Text(_agentLabel(index)),
                          ),
                        ),
                        onChanged: (int? value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            to = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: conditionController,
                        minLines: 1,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: _t(
                            'user_example.field.connection_condition',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children:
                            <String>[
                                  'always',
                                  'intent:weather',
                                  'intent:time',
                                  'intent:greeting',
                                  'contains:refund',
                                ]
                                .map((String expr) {
                                  return ActionChip(
                                    label: Text(expr),
                                    onPressed: () {
                                      conditionController.text = expr;
                                    },
                                  );
                                })
                                .toList(growable: false),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _t('user_example.connection.dsl_help'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(_t('custom.config.cancel')),
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop(
                          UserExampleConnection(
                            fromIndex: from,
                            toIndex: to,
                            condition: conditionController.text.trim(),
                          ),
                        );
                      },
                      child: Text(_t('settings.save')),
                    ),
                  ],
                );
              },
            );
          },
        );
    conditionController.dispose();
    if (created == null || !mounted) {
      return;
    }
    setState(() {
      final bool exists = _connections.any(
        (UserExampleConnection item) =>
            item.fromIndex == created.fromIndex &&
            item.toIndex == created.toIndex &&
            item.condition == created.condition,
      );
      if (!exists) {
        _connections = <UserExampleConnection>[..._connections, created];
      }
    });
  }

  void _save() {
    final int minAgents = _minAgents(_architecture);
    if (_agents.length < minAgents) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('user_example.validation.min_agents'))),
      );
      return;
    }

    final UserExampleConfig seed =
        widget.initialConfig ?? UserExampleConfig.defaults();
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<String> prompts = <String>[
      _prompt1Controller.text.trim(),
      _prompt2Controller.text.trim(),
      _prompt3Controller.text.trim(),
    ].where((String item) => item.isNotEmpty).toList(growable: false);

    final UserExampleConfig next = seed.copyWith(
      title: _titleController.text.trim().isEmpty
          ? seed.title
          : _titleController.text.trim(),
      summary: _summaryController.text.trim().isEmpty
          ? seed.summary
          : _summaryController.text.trim(),
      initialAssistantMessage: _initialMessageController.text.trim().isEmpty
          ? seed.initialAssistantMessage
          : _initialMessageController.text.trim(),
      inputHint: _hintController.text.trim().isEmpty
          ? seed.inputHint
          : _hintController.text.trim(),
      architecture: _architecture,
      agents: List<CustomAgentConfig>.from(_agents),
      entryAgentIndex: _entryAgentIndex,
      connections: _architecture == UserExampleArchitecture.single
          ? const <UserExampleConnection>[]
          : List<UserExampleConnection>.from(_connections),
      prompts: prompts.isEmpty ? seed.prompts : prompts,
      createdAtMs: seed.createdAtMs,
      updatedAtMs: now,
    );

    Navigator.of(context).pop(next);
  }

  @override
  Widget build(BuildContext context) {
    final int minAgents = _minAgents(_architecture);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? _t('user_example.builder.edit_title')
              : _t('user_example.builder.new_title'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: _t('user_example.field.title'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summaryController,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _t('user_example.field.summary'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserExampleArchitecture>(
              initialValue: _architecture,
              decoration: InputDecoration(
                labelText: _t('user_example.field.architecture'),
                border: const OutlineInputBorder(),
              ),
              items: UserExampleArchitecture.values
                  .map((UserExampleArchitecture arch) {
                    return DropdownMenuItem<UserExampleArchitecture>(
                      value: arch,
                      child: Text(_t(arch.labelKey)),
                    );
                  })
                  .toList(growable: false),
              onChanged: (UserExampleArchitecture? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _architecture = value;
                  final int required = _minAgents(value);
                  final List<CustomAgentConfig> next =
                      List<CustomAgentConfig>.from(_agents);
                  while (next.length < required) {
                    next.add(
                      CustomAgentConfig.defaults().copyWith(
                        name: 'Agent ${next.length + 1}',
                      ),
                    );
                  }
                  _agents = next;
                  _normalizeGraphState();
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _initialMessageController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: _t('user_example.field.initial'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hintController,
              decoration: InputDecoration(
                labelText: _t('user_example.field.hint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _t('user_example.field.prompts'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _prompt1Controller,
              decoration: InputDecoration(
                labelText: _t('user_example.field.prompt1'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _prompt2Controller,
              decoration: InputDecoration(
                labelText: _t('user_example.field.prompt2'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _prompt3Controller,
              decoration: InputDecoration(
                labelText: _t('user_example.field.prompt3'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _t('user_example.field.agents'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _agents.length >= 4 ? null : _addAgent,
                  icon: const Icon(Icons.add),
                  label: Text(_t('user_example.action.add_agent')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_agents.length < minAgents)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _t('user_example.validation.min_agents'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            ..._agents.asMap().entries.map((
              MapEntry<int, CustomAgentConfig> e,
            ) {
              final int index = e.key;
              final CustomAgentConfig agent = e.value;
              final List<String> enabledTools = <String>[
                if (agent.enableCapitalTool) _t('user_example.tool.capital'),
                if (agent.enableWeatherTool) _t('user_example.tool.weather'),
                if (agent.enableTimeTool) _t('user_example.tool.time'),
              ];
              return Card(
                child: ListTile(
                  title: Text(
                    agent.name.trim().isEmpty
                        ? 'Agent ${index + 1}'
                        : agent.name.trim(),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: 4),
                      Text(
                        agent.description.trim().isEmpty
                            ? _t('user_example.agent.no_description')
                            : agent.description.trim(),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: enabledTools.isEmpty
                            ? <Widget>[
                                Chip(
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  label: Text(_t('user_example.tool.none')),
                                ),
                              ]
                            : enabledTools
                                  .map(
                                    (String tool) => Chip(
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      label: Text(tool),
                                    ),
                                  )
                                  .toList(growable: false),
                      ),
                    ],
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: <Widget>[
                      IconButton(
                        tooltip: _t('user_example.action.edit_agent'),
                        onPressed: () => _editAgent(index),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: _t('user_example.field.entry_agent'),
                        onPressed: () {
                          setState(() {
                            _entryAgentIndex = index;
                          });
                        },
                        icon: Icon(
                          _entryAgentIndex == index
                              ? Icons.flag
                              : Icons.outlined_flag,
                        ),
                      ),
                      IconButton(
                        tooltip: _t('user_example.action.remove_agent'),
                        onPressed: _agents.length <= minAgents
                            ? null
                            : () => _removeAgent(index),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _t('user_example.field.connections'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: _agents.length < 2 ? null : _addConnection,
                  icon: const Icon(Icons.add_link),
                  label: Text(_t('user_example.action.add_connection')),
                ),
              ],
            ),
            if (_agents.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  '${_t('user_example.field.entry_agent')}: ${_agentLabel(_entryAgentIndex)}',
                ),
              ),
            if (_connections.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _t('user_example.connection.empty'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ..._connections.asMap().entries.map((
              MapEntry<int, UserExampleConnection> entry,
            ) {
              final int index = entry.key;
              final UserExampleConnection connection = entry.value;
              final String condition = connection.condition.trim().isEmpty
                  ? _t('user_example.connection.default_condition')
                  : connection.condition.trim();
              final UserExampleConnectionDsl parsed =
                  UserExampleConnectionDsl.parse(condition);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.arrow_right_alt),
                  title: Text(
                    '${_agentLabel(connection.fromIndex)} -> ${_agentLabel(connection.toIndex)}',
                  ),
                  subtitle: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(condition),
                      if (!parsed.isValid)
                        Text(
                          _t('user_example.connection.invalid'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: _t('user_example.action.remove_connection'),
                    onPressed: () {
                      setState(() {
                        _connections = List<UserExampleConnection>.from(
                          _connections,
                        )..removeAt(index);
                      });
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(_t('custom.config.cancel')),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _save,
                  child: Text(_t('settings.save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
