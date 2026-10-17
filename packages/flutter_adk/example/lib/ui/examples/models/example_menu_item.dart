/// Data models representing interactive agent examples and navigation menu items.
library;

import 'package:flutter/material.dart';

import 'package:flutter_adk_example/data/services/agent_service.dart';

/// Categories for filtering example workflows in the catalog.
enum ExampleCategory {
  /// All example categories.
  all,

  /// General single-agent chat examples.
  general,

  /// Multi-step workflow and DAG examples.
  workflow,

  /// Multi-agent team and hand-off examples.
  team,

  /// External integrations such as MCP, tools, and search.
  integrations,
}

/// Extension methods for [ExampleCategory] providing localized label keys.
extension ExampleCategoryX on ExampleCategory {
  /// The localization key for the category name.
  String get labelKey {
    switch (this) {
      case ExampleCategory.all:
        return 'category.all';
      case ExampleCategory.general:
        return 'category.general';
      case ExampleCategory.workflow:
        return 'category.workflow';
      case ExampleCategory.team:
        return 'category.team';
      case ExampleCategory.integrations:
        return 'category.integrations';
    }
  }
}

/// Difficulty classification for suggested user prompts.
enum ExamplePromptDifficulty {
  /// Basic prompt suitable for getting started.
  basic,

  /// Advanced prompt demonstrating complex capabilities.
  advanced,
}

/// Extension methods for [ExamplePromptDifficulty] providing localized label keys.
extension ExamplePromptDifficultyX on ExamplePromptDifficulty {
  /// The localization key for the difficulty label.
  String get labelKey {
    switch (this) {
      case ExamplePromptDifficulty.basic:
        return 'difficulty.basic';
      case ExamplePromptDifficulty.advanced:
        return 'difficulty.advanced';
    }
  }
}

/// A localized suggested prompt item for an example.
class ExamplePromptItem {
  /// Creates a prompt item with [textKey] and [difficulty].
  const ExamplePromptItem({required this.textKey, required this.difficulty});

  /// The localization key for the prompt text.
  final String textKey;

  /// The difficulty tier of the prompt.
  final ExamplePromptDifficulty difficulty;
}

/// View model representing resolved prompt text and display metadata.
class ExamplePromptViewData {
  /// Creates view data for an example prompt.
  const ExamplePromptViewData({
    required this.text,
    required this.difficultyLabel,
    required this.isAdvanced,
  });

  /// The rendered prompt string.
  final String text;

  /// The display label for the difficulty.
  final String difficultyLabel;

  /// Whether this prompt is in the advanced difficulty tier.
  final bool isAdvanced;
}

/// Defines an interactive example entry in the example explorer menu.
class ExampleMenuItem {
  /// Creates an example menu item with metadata and builder callbacks.
  const ExampleMenuItem({
    required this.id,
    required this.icon,
    required this.category,
    required this.titleKey,
    required this.summaryKey,
    required this.initialKey,
    required this.emptyKey,
    required this.hintKey,
    required this.prompts,
    required this.agentBuilder,
  });

  /// The unique identifier of the example.
  final String id;

  /// The visual icon representing the example.
  final IconData icon;

  /// The category to which this example belongs.
  final ExampleCategory category;

  /// The localization key for the title.
  final String titleKey;

  /// The localization key for the summary description.
  final String summaryKey;

  /// The localization key for the initial greeting message.
  final String initialKey;

  /// The localization key for the empty-state message.
  final String emptyKey;

  /// The localization key for the text field hint.
  final String hintKey;

  /// The list of suggested prompt items.
  final List<ExamplePromptItem> prompts;

  /// Factory callback to instantiate the configured agent.
  final AgentBuilder agentBuilder;
}
