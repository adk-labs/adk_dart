import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_adk_example/config/app_localizations.dart';
import 'package:flutter_adk_example/data/repositories/settings_repository.dart';
import 'package:flutter_adk_example/domain/models/app_language.dart';
import 'package:flutter_adk_example/routing/app_router.dart';
import 'package:flutter_adk_example/ui/core/widgets/settings_bottom_sheet.dart';
import 'package:flutter_adk_example/ui/examples/examples_registry.dart';
import 'package:flutter_adk_example/ui/examples/models/example_menu_item.dart';
import 'package:flutter_adk_example/ui/examples/widgets/example_detail_screen.dart';
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
  ExampleCategory _selectedCategory = ExampleCategory.all;

  bool get _hasApiKey => _viewModel.hasApiKey;
  String _t(String key) => tr(_viewModel.selectedLanguage, key);

  List<ExampleMenuItem> get _filteredItems {
    final String query = _searchController.text.trim().toLowerCase();
    return _menuItems.where((ExampleMenuItem item) {
      final bool categoryMatches =
          _selectedCategory == ExampleCategory.all ||
          item.category == _selectedCategory;
      if (!categoryMatches) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final String title = _t(item.titleKey).toLowerCase();
      final String summary = _t(item.summaryKey).toLowerCase();
      return title.contains(query) || summary.contains(query);
    }).toList();
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

  Future<void> _saveSettings({bool showSnackBar = true}) async {
    await _viewModel.saveSettings(
      apiKey: _apiKeyController.text.trim(),
      mcpUrl: _mcpUrlController.text.trim(),
      mcpBearerToken: _mcpBearerTokenController.text.trim(),
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
    await _saveSettings();
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
          securityNotice: _t('settings.security'),
          clearLabel: _t('settings.clear'),
          saveLabel: _t('settings.save'),
          apiKeyController: _apiKeyController,
          mcpUrlController: _mcpUrlController,
          mcpBearerTokenController: _mcpBearerTokenController,
          onClear: _clearSettings,
          onSave: _saveSettings,
        );
      },
    );
  }

  Future<void> _openExample(ExampleMenuItem item) async {
    await AppRouter.push(
      context,
      ExampleDetailScreen(
        item: item,
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
            .toList(),
        apiKey: _apiKeyController.text.trim(),
        mcpUrl: _mcpUrlController.text.trim(),
        mcpBearerToken: _mcpBearerTokenController.text.trim(),
        language: _viewModel.selectedLanguage,
        apiKeyMissingMessage: _t('error.api_key_required'),
        genericErrorPrefix: _t('error.prefix'),
        responseNotFoundMessage: _t('error.no_response_text'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<ExampleMenuItem> filteredItems = _filteredItems;

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
                children: ExampleCategory.values.map((
                  ExampleCategory category,
                ) {
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
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: filteredItems.isEmpty
                ? Center(
                    child: Text(
                      _t('home.no_results'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    itemCount: filteredItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final ExampleMenuItem item = filteredItems[index];
                      return Card(
                        child: ListTile(
                          isThreeLine: true,
                          leading: CircleAvatar(
                            child: Icon(item.icon, size: 20),
                          ),
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
                                Chip(
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  label: Text(_t(item.category.labelKey)),
                                ),
                              ],
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openExample(item),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
