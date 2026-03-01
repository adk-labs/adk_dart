import 'package:flutter/material.dart';

import 'package:flutter_adk_example/data/services/agent_service.dart';
import 'package:flutter_adk_example/domain/models/app_language.dart';
import 'package:flutter_adk_example/ui/core/widgets/chat_example_view.dart';
import 'package:flutter_adk_example/ui/examples/models/example_menu_item.dart';

class ExampleChatPage extends StatelessWidget {
  const ExampleChatPage({
    super.key,
    required this.exampleId,
    required this.title,
    required this.summary,
    required this.initialAssistantMessage,
    required this.emptyStateMessage,
    required this.inputHint,
    required this.examplePromptsTitle,
    required this.examplePrompts,
    required this.agentBuilder,
    required this.apiKey,
    required this.mcpUrl,
    required this.mcpBearerToken,
    required this.enableDebugLogs,
    required this.language,
    required this.apiKeyMissingMessage,
    required this.genericErrorPrefix,
    required this.responseNotFoundMessage,
  });

  final String exampleId;
  final String title;
  final String summary;
  final String initialAssistantMessage;
  final String emptyStateMessage;
  final String inputHint;
  final String examplePromptsTitle;
  final List<ExamplePromptViewData> examplePrompts;
  final AgentBuilder agentBuilder;
  final String apiKey;
  final String mcpUrl;
  final String mcpBearerToken;
  final bool enableDebugLogs;
  final AppLanguage language;
  final String apiKeyMissingMessage;
  final String genericErrorPrefix;
  final String responseNotFoundMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ChatExampleView(
        key: ValueKey<String>('${exampleId}_example'),
        exampleId: exampleId,
        exampleTitle: title,
        summary: summary,
        initialAssistantMessage: initialAssistantMessage,
        emptyStateMessage: emptyStateMessage,
        inputHint: inputHint,
        examplePromptsTitle: examplePromptsTitle,
        examplePrompts: examplePrompts,
        apiKey: apiKey,
        mcpUrl: mcpUrl,
        mcpBearerToken: mcpBearerToken,
        enableDebugLogs: enableDebugLogs,
        language: language,
        createAgent: agentBuilder,
        apiKeyMissingMessage: apiKeyMissingMessage,
        genericErrorPrefix: genericErrorPrefix,
        responseNotFoundMessage: responseNotFoundMessage,
      ),
    );
  }
}
