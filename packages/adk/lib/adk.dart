/// Unified entrypoint for ADK in Dart: provides core runtime SDK and CLI tooling.
///
/// ```dart
/// import 'package:adk/adk.dart';
///
/// Future<void> main(List<String> args) async {
///   final agent = LlmAgent(
///     name: 'assistant',
///     model: 'gemini-2.5-flash',
///     instruction: 'Answer user questions concisely.',
///   );
///   final runner = InMemoryRunner(agent: agent);
///   await runner.close();
/// }
/// ```
library;

export 'package:adk_dart/adk_dart.dart' hide adkPackageVersion;
export 'cli.dart';
