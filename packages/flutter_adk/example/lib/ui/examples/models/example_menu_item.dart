import 'package:flutter/material.dart';

import 'package:flutter_adk_example/data/services/agent_service.dart';

enum ExampleCategory { all, general, workflow, team, integrations }

extension ExampleCategoryX on ExampleCategory {
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

enum ExamplePromptDifficulty { basic, advanced }

extension ExamplePromptDifficultyX on ExamplePromptDifficulty {
  String get labelKey {
    switch (this) {
      case ExamplePromptDifficulty.basic:
        return 'difficulty.basic';
      case ExamplePromptDifficulty.advanced:
        return 'difficulty.advanced';
    }
  }
}

class ExamplePromptItem {
  const ExamplePromptItem({required this.textKey, required this.difficulty});

  final String textKey;
  final ExamplePromptDifficulty difficulty;
}

class ExamplePromptViewData {
  const ExamplePromptViewData({
    required this.text,
    required this.difficultyLabel,
    required this.isAdvanced,
  });

  final String text;
  final String difficultyLabel;
  final bool isAdvanced;
}

class ExampleMenuItem {
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

  final String id;
  final IconData icon;
  final ExampleCategory category;
  final String titleKey;
  final String summaryKey;
  final String initialKey;
  final String emptyKey;
  final String hintKey;
  final List<ExamplePromptItem> prompts;
  final AgentBuilder agentBuilder;
}
