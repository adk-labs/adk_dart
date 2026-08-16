import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../examples/models/example_menu_item.dart';

/// Preview for a standard agent response bubble with markdown formatting.
@Preview(
  name: 'Agent Response Bubble',
  group: 'ADK Chat UI',
)
Widget agentResponseBubblePreview() {
  return MaterialApp(
    theme: ThemeData.light(useMaterial3: true),
    darkTheme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.smart_toy, size: 16, color: Colors.blue),
                      SizedBox(width: 6),
                      Text(
                        'Weather Agent',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    'The current weather in Seoul is **24°C** and clear skies.',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Preview for a user message bubble.
@Preview(
  name: 'User Message Bubble',
  group: 'ADK Chat UI',
)
Widget userMessageBubblePreview() {
  return MaterialApp(
    theme: ThemeData.light(useMaterial3: true),
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                'What is the weather in Seoul right now?',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Preview for suggested prompt action chips.
@Preview(
  name: 'Prompt Action Chips',
  group: 'ADK Chat UI',
)
Widget promptActionChipsPreview() {
  const List<ExamplePromptViewData> prompts = <ExamplePromptViewData>[
    ExamplePromptViewData(
      text: 'Tell me the weather in Tokyo',
      difficultyLabel: 'Basic',
      isAdvanced: false,
    ),
    ExamplePromptViewData(
      text: 'Run 50-step financial forecast',
      difficultyLabel: 'Advanced',
      isAdvanced: true,
    ),
  ];

  return MaterialApp(
    theme: ThemeData.light(useMaterial3: true),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: prompts.map((ExamplePromptViewData prompt) {
            return ActionChip(
              avatar: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: prompt.isAdvanced ? Colors.deepPurple.shade100 : Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  prompt.difficultyLabel,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
              label: Text(prompt.text),
              onPressed: () {},
            );
          }).toList(),
        ),
      ),
    ),
  );
}

/// Preview for the live agent drafting banner.
@Preview(
  name: 'Agent Drafting Banner',
  group: 'ADK Chat UI',
)
Widget agentDraftingBannerPreview() {
  return MaterialApp(
    theme: ThemeData.light(useMaterial3: true),
    home: const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFF1F5F9),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Weather Agent is drafting a response...',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                LinearProgressIndicator(minHeight: 3),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
