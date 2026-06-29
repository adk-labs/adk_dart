import 'package:adk_dart/adk_dart.dart';

/// Example showcasing the usage of [GoogleSearchTool] in an [Agent].
final Agent googleSearchExampleAgent = Agent(
  name: 'google_search_example',
  model: 'gemini-3.1-flash-lite',
  instruction:
      'You are a helpful assistant. Use the google_search tool to answer factual or time-sensitive questions.',
  tools: <Object>[googleSearch],
);
