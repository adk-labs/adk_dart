import 'package:flutter/material.dart';

import 'package:flutter_adk_example/domain/models/app_language.dart';
import 'package:flutter_adk_example/ui/examples/models/example_menu_item.dart';
import 'package:flutter_adk_example/ui/examples/widgets/example_chat_page.dart';

class ExampleDetailScreen extends StatelessWidget {
  const ExampleDetailScreen({
    super.key,
    required this.item,
    required this.title,
    required this.summary,
    required this.initialAssistantMessage,
    required this.emptyStateMessage,
    required this.inputHint,
    required this.examplePromptsTitle,
    required this.examplePrompts,
    required this.apiKey,
    required this.mcpUrl,
    required this.mcpBearerToken,
    required this.language,
    required this.apiKeyMissingMessage,
    required this.genericErrorPrefix,
    required this.responseNotFoundMessage,
  });

  final ExampleMenuItem item;
  final String title;
  final String summary;
  final String initialAssistantMessage;
  final String emptyStateMessage;
  final String inputHint;
  final String examplePromptsTitle;
  final List<ExamplePromptViewData> examplePrompts;
  final String apiKey;
  final String mcpUrl;
  final String mcpBearerToken;
  final AppLanguage language;
  final String apiKeyMissingMessage;
  final String genericErrorPrefix;
  final String responseNotFoundMessage;

  @override
  Widget build(BuildContext context) {
    return ExampleChatPage(
      exampleId: item.id,
      title: title,
      summary: summary,
      initialAssistantMessage: initialAssistantMessage,
      emptyStateMessage: emptyStateMessage,
      inputHint: inputHint,
      examplePromptsTitle: examplePromptsTitle,
      examplePrompts: examplePrompts,
      agentBuilder: item.agentBuilder,
      apiKey: apiKey,
      mcpUrl: mcpUrl,
      mcpBearerToken: mcpBearerToken,
      language: language,
      apiKeyMissingMessage: apiKeyMissingMessage,
      genericErrorPrefix: genericErrorPrefix,
      responseNotFoundMessage: responseNotFoundMessage,
    );
  }
}
