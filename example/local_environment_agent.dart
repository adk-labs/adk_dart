import 'dart:io';

import 'package:adk_dart/adk_dart.dart';

final Agent rootAgent = Agent(
  model: 'gemini-2.5-pro',
  name: 'local_environment_agent',
  description: 'A simple agent that demonstrates local environment usage.',
  instruction: '''
You are a helpful assistant that can use the local environment for
command execution and file I/O. Follow the environment rules and the
user's instructions.
''',
  tools: <Object>[
    EnvironmentToolset(
      environment: LocalEnvironment(workingDirectory: Directory.current),
    ),
  ],
);

void main() {
  print('Configured ${rootAgent.name} for ${Directory.current.path}');
}
