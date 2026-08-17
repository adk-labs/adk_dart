import 'dart:io';

import 'package:adk_dart/adk_dart.dart';

Future<void> main() async {
  final String? apiKey = Platform.environment['GEMINI_API_KEY'] ??
      Platform.environment['GOOGLE_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Please set GEMINI_API_KEY or GOOGLE_API_KEY environment variable.');
    exit(1);
  }

  // Define an agent with a strict JSON outputSchema
  final Agent agent = Agent(
    name: 'recipe_chef',
    model: Gemini(
      model: 'gemini-3.7-flash',
      environment: <String, String>{'GEMINI_API_KEY': apiKey},
    ),
    outputSchema: const <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'recipe_name': <String, dynamic>{
          'type': 'string',
          'description': 'Name of the recipe',
        },
        'cooking_time_minutes': <String, dynamic>{
          'type': 'integer',
          'description': 'Estimated cooking time in minutes',
        },
        'difficulty': <String, dynamic>{
          'type': 'string',
          'enum': <String>['Easy', 'Medium', 'Hard'],
        },
        'ingredients': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{'type': 'string'},
          'description': 'List of ingredients',
        },
        'instructions': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{'type': 'string'},
          'description': 'Step-by-step instructions',
        },
      },
      'required': <String>[
        'recipe_name',
        'cooking_time_minutes',
        'difficulty',
        'ingredients',
        'instructions',
      ],
    },
    instruction: '''
You are a master chef. Generate delicious recipes formatted strictly as JSON adhering to the provided schema.
''',
  );

  final InMemoryRunner runner = InMemoryRunner(agent: agent);
  final Session session = await runner.sessionService.createSession(
    appName: runner.appName,
    userId: 'user_1',
    sessionId: 'session_recipe',
  );

  print('Generating structured recipe JSON...');
  await for (final Event event in runner.runAsync(
    userId: 'user_1',
    sessionId: session.id,
    newMessage: Content.userText('A quick 15-minute healthy pasta dish'),
  )) {
    final String text = event.content?.parts
            .where((Part p) => p.text != null)
            .map((Part p) => p.text!)
            .join(' ') ??
        '';
    if (text.isNotEmpty) {
      print('[${event.author}] $text');
    }
  }
}
