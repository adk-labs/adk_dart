import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_adk_example/config/app_localizations.dart';
import 'package:flutter_adk_example/data/repositories/custom_agent_config_repository.dart';
import 'package:flutter_adk_example/data/repositories/settings_repository.dart';
import 'package:flutter_adk_example/data/repositories/user_example_repository.dart';
import 'package:flutter_adk_example/data/services/agent_service.dart';
import 'package:flutter_adk_example/domain/models/app_language.dart';
import 'package:flutter_adk_example/domain/models/custom_agent_config.dart';
import 'package:flutter_adk_example/domain/models/user_example_config.dart';
import 'package:flutter_adk_example/routing/app_router.dart';
import 'package:flutter_adk_example/ui/core/widgets/settings_bottom_sheet.dart';
import 'package:flutter_adk_example/ui/examples/examples_registry.dart';
import 'package:flutter_adk_example/ui/examples/models/example_menu_item.dart';
import 'package:flutter_adk_example/ui/examples/widgets/custom_agent_config_screen.dart';
import 'package:flutter_adk_example/ui/examples/widgets/example_chat_page.dart';
import 'package:flutter_adk_example/ui/examples/widgets/example_detail_screen.dart';
import 'package:flutter_adk_example/ui/examples/widgets/user_example_builder_screen.dart';
import 'package:flutter_adk_example/ui/home/view_models/home_view_model.dart';

class ExamplesHomeScreen extends StatefulWidget {
  const ExamplesHomeScreen({super.key});

  @override
  State<ExamplesHomeScreen> createState() => _ExamplesHomeScreenState();
}

class _ExamplesHomeScreenState extends State<ExamplesHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _mcpUrlController = TextEditingController();
  final TextEditingController _mcpBearerTokenController =
      TextEditingController();

  late final HomeViewModel _viewModel;
  late final List<ExampleMenuItem> _menuItems;
  final SharedPreferencesCustomAgentConfigRepository _customConfigRepository =
      SharedPreferencesCustomAgentConfigRepository();
  final SharedPreferencesUserExampleRepository _userExampleRepository =
      SharedPreferencesUserExampleRepository();

  CustomAgentConfig _customAgentConfig = CustomAgentConfig.defaults();
  List<UserExampleConfig> _userExamples = <UserExampleConfig>[];
  ExampleCategory _selectedCategory = ExampleCategory.all;

  bool get _hasApiKey => _viewModel.hasApiKey;
  String _t(String key) => tr(_viewModel.selectedLanguage, key);

  List<_HomeEntry> get _filteredEntries {
    final String query = _searchController.text.trim().toLowerCase();
    final List<_HomeEntry> entries = <_HomeEntry>[];

    for (final ExampleMenuItem item in _menuItems) {
      final bool categoryMatches =
          _selectedCategory == ExampleCategory.all ||
          item.category == _selectedCategory;
      if (!categoryMatches) {
        continue;
      }
      if (query.isNotEmpty) {
        final String title = _t(item.titleKey).toLowerCase();
        final String summary = _t(item.summaryKey).toLowerCase();
        if (!title.contains(query) && !summary.contains(query)) {
          continue;
        }
      }
      entries.add(_HomeEntry.builtIn(item));
    }

    for (final UserExampleConfig example in _userExamples) {
      final bool categoryMatches =
          _selectedCategory == ExampleCategory.all ||
          _categoryForArchitecture(example.architecture) == _selectedCategory;
      if (!categoryMatches) {
        continue;
      }
      if (query.isNotEmpty) {
        final String title = example.title.toLowerCase();
        final String summary = example.summary.toLowerCase();
        if (!title.contains(query) && !summary.contains(query)) {
          continue;
        }
      }
      entries.add(_HomeEntry.user(example));
    }

    return entries;
  }

  @override
  void initState() {
    super.initState();
    _menuItems = buildExampleMenuItems();
    _searchController.addListener(() {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    _viewModel = HomeViewModel(
      settingsRepository: SharedPreferencesSettingsRepository(),
    );
    _viewModel.addListener(_onViewModelChanged);
    unawaited(_initializeViewModel());
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _searchController.dispose();
    _apiKeyController.dispose();
    _mcpUrlController.dispose();
    _mcpBearerTokenController.dispose();
    super.dispose();
  }

  Future<void> _initializeViewModel() async {
    await _viewModel.initialize(
      fallbackLanguage: appLanguageFromCode(
        WidgetsBinding.instance.platformDispatcher.locale.languageCode,
      ),
    );
    final CustomAgentConfig loadedCustom = await _customConfigRepository.load();
    final List<UserExampleConfig> loadedExamples = await _userExampleRepository
        .loadAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _customAgentConfig = loadedCustom;
      _userExamples = loadedExamples;
    });
    _syncControllersFromSettings();
  }

  void _onViewModelChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _syncControllersFromSettings() {
    _apiKeyController.text = _viewModel.apiKey;
    _mcpUrlController.text = _viewModel.mcpUrl;
    _mcpBearerTokenController.text = _viewModel.mcpBearerToken;
  }

  Future<void> _saveSettings({
    bool showSnackBar = true,
    bool? debugLogsEnabled,
  }) async {
    await _viewModel.saveSettings(
      apiKey: _apiKeyController.text.trim(),
      mcpUrl: _mcpUrlController.text.trim(),
      mcpBearerToken: _mcpBearerTokenController.text.trim(),
      debugLogsEnabled: debugLogsEnabled ?? _viewModel.debugLogsEnabled,
    );

    if (!mounted) {
      return;
    }
    if (showSnackBar) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t('app.settings_saved'))));
    }
  }

  Future<void> _clearSettings() async {
    _apiKeyController.clear();
    _mcpUrlController.clear();
    _mcpBearerTokenController.clear();
    await _saveSettings(debugLogsEnabled: true);
  }

  Future<void> _openSettingsSheet() async {
    _syncControllersFromSettings();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SettingsBottomSheet(
          title: _t('settings.title'),
          apiKeyLabel: _t('settings.api_key'),
          mcpUrlLabel: _t('settings.mcp_url'),
          mcpTokenLabel: _t('settings.mcp_token'),
          debugLogsLabel: _t('settings.debug_logs'),
          debugLogsDescription: _t('settings.debug_logs_description'),
          initialDebugLogsEnabled: _viewModel.debugLogsEnabled,
          securityNotice: _t('settings.security'),
          clearLabel: _t('settings.clear'),
          saveLabel: _t('settings.save'),
          apiKeyController: _apiKeyController,
          mcpUrlController: _mcpUrlController,
          mcpBearerTokenController: _mcpBearerTokenController,
          onClear: _clearSettings,
          onSave: (bool debugLogsEnabled) =>
              _saveSettings(debugLogsEnabled: debugLogsEnabled),
        );
      },
    );
  }

  Future<void> _openExample(ExampleMenuItem item) async {
    final AgentBuilder? agentBuilderOverride = item.id == 'custom_agent'
        ? ({
            required String apiKey,
            required AppLanguage language,
            required String mcpUrl,
            required String mcpBearerToken,
          }) {
            return AgentService.buildCustom(
              apiKey: apiKey,
              language: language,
              config: _customAgentConfig,
              mcpUrl: mcpUrl,
              mcpBearerToken: mcpBearerToken,
            );
          }
        : null;

    await AppRouter.push(
      context,
      ExampleDetailScreen(
        item: item,
        agentBuilderOverride: agentBuilderOverride,
        title: _t(item.titleKey),
        summary: _t(item.summaryKey),
        initialAssistantMessage: _t(item.initialKey),
        emptyStateMessage: _t(item.emptyKey),
        inputHint: _t(item.hintKey),
        examplePromptsTitle: _t('chat.example_prompts'),
        examplePrompts: item.prompts
            .map(
              (ExamplePromptItem prompt) => ExamplePromptViewData(
                text: _t(prompt.textKey),
                difficultyLabel: _t(prompt.difficulty.labelKey),
                isAdvanced:
                    prompt.difficulty == ExamplePromptDifficulty.advanced,
              ),
            )
            .toList(growable: false),
        apiKey: _apiKeyController.text.trim(),
        mcpUrl: _mcpUrlController.text.trim(),
        mcpBearerToken: _mcpBearerTokenController.text.trim(),
        enableDebugLogs: _viewModel.debugLogsEnabled,
        language: _viewModel.selectedLanguage,
        apiKeyMissingMessage: _t('error.api_key_required'),
        genericErrorPrefix: _t('error.prefix'),
        responseNotFoundMessage: _t('error.no_response_text'),
      ),
    );
  }

  Future<void> _openUserExample(UserExampleConfig example) async {
    final List<ExamplePromptViewData> prompts = example.prompts
        .asMap()
        .entries
        .map((MapEntry<int, String> entry) {
          final bool isAdvanced = entry.key >= 2;
          return ExamplePromptViewData(
            text: entry.value,
            difficultyLabel: _t(
              isAdvanced ? 'difficulty.advanced' : 'difficulty.basic',
            ),
            isAdvanced: isAdvanced,
          );
        })
        .toList(growable: false);
    await AppRouter.push(
      context,
      ExampleChatPage(
        exampleId: example.id,
        title: example.title,
        summary: example.summary,
        initialAssistantMessage: example.initialAssistantMessage,
        emptyStateMessage: _t('custom.empty'),
        inputHint: example.inputHint,
        examplePromptsTitle: _t('chat.example_prompts'),
        examplePrompts: prompts,
        agentBuilder:
            ({
              required String apiKey,
              required AppLanguage language,
              required String mcpUrl,
              required String mcpBearerToken,
            }) {
              return AgentService.buildUserDefinedExample(
                apiKey: apiKey,
                language: language,
                config: example,
                mcpUrl: mcpUrl,
                mcpBearerToken: mcpBearerToken,
              );
            },
        apiKey: _apiKeyController.text.trim(),
        mcpUrl: _mcpUrlController.text.trim(),
        mcpBearerToken: _mcpBearerTokenController.text.trim(),
        enableDebugLogs: _viewModel.debugLogsEnabled,
        language: _viewModel.selectedLanguage,
        apiKeyMissingMessage: _t('error.api_key_required'),
        genericErrorPrefix: _t('error.prefix'),
        responseNotFoundMessage: _t('error.no_response_text'),
      ),
    );
  }

  Future<void> _openCustomAgentConfig() async {
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
              initialConfig: _customAgentConfig,
            ),
          ),
        );
    if (next == null) {
      return;
    }
    _customAgentConfig = next;
    await _customConfigRepository.save(next);
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_t('custom.config.saved'))));
  }

  Future<void> _createUserExample() async {
    final UserExampleConfig? created = await Navigator.of(context)
        .push<UserExampleConfig>(
          MaterialPageRoute<UserExampleConfig>(
            builder: (_) =>
                UserExampleBuilderScreen(language: _viewModel.selectedLanguage),
          ),
        );
    if (created == null || !mounted) {
      return;
    }
    final List<UserExampleConfig> next = <UserExampleConfig>[
      created,
      ..._userExamples.where((UserExampleConfig item) => item.id != created.id),
    ];
    await _userExampleRepository.saveAll(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _userExamples = next;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_t('user_example.saved'))));
  }

  Future<void> _editUserExample(UserExampleConfig example) async {
    final UserExampleConfig? edited = await Navigator.of(context)
        .push<UserExampleConfig>(
          MaterialPageRoute<UserExampleConfig>(
            builder: (_) => UserExampleBuilderScreen(
              language: _viewModel.selectedLanguage,
              initialConfig: example,
            ),
          ),
        );
    if (edited == null || !mounted) {
      return;
    }
    final List<UserExampleConfig> next =
        _userExamples
            .map(
              (UserExampleConfig item) => item.id == edited.id ? edited : item,
            )
            .toList(growable: false)
          ..sort(
            (UserExampleConfig a, UserExampleConfig b) =>
                b.updatedAtMs.compareTo(a.updatedAtMs),
          );
    await _userExampleRepository.saveAll(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _userExamples = next;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_t('user_example.saved'))));
  }

  Future<void> _deleteUserExample(UserExampleConfig example) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_t('user_example.delete_title')),
          content: Text(_t('user_example.delete_message')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_t('custom.config.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_t('user_example.action.delete')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final List<UserExampleConfig> next = _userExamples
        .where((UserExampleConfig item) => item.id != example.id)
        .toList(growable: false);
    await _userExampleRepository.saveAll(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _userExamples = next;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_t('user_example.deleted'))));
  }

  @override
  Widget build(BuildContext context) {
    final List<_HomeEntry> entries = _filteredEntries;

    return Scaffold(
      appBar: AppBar(
        title: Text(_t('app.title')),
        actions: <Widget>[
          PopupMenuButton<AppLanguage>(
            tooltip: _t('app.language'),
            icon: const Icon(Icons.translate),
            onSelected: (AppLanguage language) async {
              if (_viewModel.selectedLanguage == language) {
                return;
              }
              await _viewModel.setLanguage(language);
            },
            itemBuilder: (BuildContext context) {
              return AppLanguage.values.map((AppLanguage language) {
                return PopupMenuItem<AppLanguage>(
                  value: language,
                  child: Row(
                    children: <Widget>[
                      if (_viewModel.selectedLanguage == language)
                        const Icon(Icons.check, size: 16)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text(language.nativeLabel),
                    ],
                  ),
                );
              }).toList();
            },
          ),
          Icon(
            _hasApiKey ? Icons.verified : Icons.warning_amber_rounded,
            color: _hasApiKey ? Colors.green : Colors.orange,
          ),
          IconButton(
            tooltip: _t('app.settings'),
            onPressed: _openSettingsSheet,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createUserExample,
        icon: const Icon(Icons.add),
        label: Text(_t('user_example.action.new')),
      ),
      body: Column(
        children: <Widget>[
          if (!_hasApiKey)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_t('app.no_api_key'))),
                  TextButton(
                    onPressed: _openSettingsSheet,
                    child: Text(_t('app.set_api_key')),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _t('home.search_hint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => _searchController.clear(),
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ExampleCategory.values
                    .map((ExampleCategory category) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_t(category.labelKey)),
                          selected: _selectedCategory == category,
                          onSelected: (bool selected) {
                            if (!selected) {
                              return;
                            }
                            setState(() {
                              _selectedCategory = category;
                            });
                          },
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      _t('home.no_results'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final _HomeEntry entry = entries[index];
                      if (entry.builtIn != null) {
                        return _buildBuiltInCard(entry.builtIn!);
                      }
                      return _buildUserCard(entry.user!);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBuiltInCard(ExampleMenuItem item) {
    return Card(
      child: ListTile(
        isThreeLine: true,
        leading: CircleAvatar(child: Icon(item.icon, size: 20)),
        title: Text(
          _t(item.titleKey),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(_t(item.summaryKey)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(_t(item.category.labelKey)),
                  ),
                  if (item.id == 'custom_agent')
                    ActionChip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: const Icon(Icons.tune, size: 16),
                      label: Text(_t('custom.configure')),
                      onPressed: _openCustomAgentConfig,
                    ),
                ],
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openExample(item),
      ),
    );
  }

  Widget _buildUserCard(UserExampleConfig example) {
    final IconData icon;
    switch (example.architecture) {
      case UserExampleArchitecture.single:
        icon = Icons.smart_toy_outlined;
        break;
      case UserExampleArchitecture.team:
        icon = Icons.groups_outlined;
        break;
      case UserExampleArchitecture.sequential:
        icon = Icons.linear_scale_outlined;
        break;
      case UserExampleArchitecture.parallel:
        icon = Icons.call_split_outlined;
        break;
      case UserExampleArchitecture.loop:
        icon = Icons.loop_outlined;
        break;
    }
    return Card(
      child: ListTile(
        isThreeLine: true,
        leading: CircleAvatar(child: Icon(icon, size: 20)),
        title: Text(
          example.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(example.summary),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                      _t(
                        _categoryForArchitecture(example.architecture).labelKey,
                      ),
                    ),
                  ),
                  Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(_t(example.architecture.labelKey)),
                  ),
                  ActionChip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    avatar: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(_t('user_example.action.edit')),
                    onPressed: () => _editUserExample(example),
                  ),
                  ActionChip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    avatar: const Icon(Icons.delete_outline, size: 16),
                    label: Text(_t('user_example.action.delete')),
                    onPressed: () => _deleteUserExample(example),
                  ),
                ],
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openUserExample(example),
      ),
    );
  }

  ExampleCategory _categoryForArchitecture(UserExampleArchitecture arch) {
    switch (arch) {
      case UserExampleArchitecture.single:
        return ExampleCategory.general;
      case UserExampleArchitecture.team:
        return ExampleCategory.team;
      case UserExampleArchitecture.sequential:
      case UserExampleArchitecture.parallel:
      case UserExampleArchitecture.loop:
        return ExampleCategory.workflow;
    }
  }
}

class _HomeEntry {
  const _HomeEntry._({this.builtIn, this.user});

  factory _HomeEntry.builtIn(ExampleMenuItem item) {
    return _HomeEntry._(builtIn: item);
  }

  factory _HomeEntry.user(UserExampleConfig config) {
    return _HomeEntry._(user: config);
  }

  final ExampleMenuItem? builtIn;
  final UserExampleConfig? user;
}
