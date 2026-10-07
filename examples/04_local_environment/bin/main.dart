import 'dart:io';
import 'package:adk_dart/adk_dart.dart';

final Agent rootAgent = Agent(
  model: 'gemini-3.7-flash',
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

void main() async {
  print('Configured ${rootAgent.name} for ${Directory.current.path}');

  final ExecuteBashTool bashTool = ExecuteBashTool(
    policy: BashToolPolicy(
      allowedCommandPrefixes: <String>['git status', 'dart --version'],
    ),
  );
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'env_demo',
    userId: 'user_1',
  );
  final InvocationContext context = InvocationContext(
    sessionService: sessionService,
    invocationId: 'inv_bash_1',
    agent: rootAgent,
    session: session,
  );

  final Object? blockedResult = await bashTool.run(
    args: <String, dynamic>{'command': 'git statusx'},
    toolContext: Context(context),
  );
  print('Tokenized prefix check for "git statusx": $blockedResult');

  final ExecuteBashTool emptyPolicyTool = ExecuteBashTool(
    policy: BashToolPolicy(allowedCommandPrefixes: const <String>[]),
  );
  print('Empty policy tool description:\n${emptyPolicyTool.description}');
}
