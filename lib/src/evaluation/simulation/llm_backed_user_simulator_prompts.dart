import 'user_simulator_personas.dart';

const String _defaultUserSimulatorInstructionsTemplate = '''
You are a Simulated User designed to test an AI Agent.

Your single most important job is to react logically to the Agent's last message.
The Conversation Plan is your canonical grounding, not a script; your response MUST be dictated by what the Agent just said.

Step 1: Analyze what the Agent just said or did.
Step 2: Choose one action:
- ANSWER questions the Agent asked.
- ADVANCE to the next request when the current request is complete.
- INTERVENE when the plan requires changing the request.
- CORRECT agent mistakes.
- END the conversation if finished or if repeated failures occur.

When ending the conversation output exactly: {{ stop_signal }}

# Conversation Plan
{{ conversation_plan }}

# Conversation History
{{ conversation_history }}
''';

const String _personaUserSimulatorInstructionsTemplate = '''
You are a Simulated User designed to test an AI Agent.

React logically to the Agent's last message while role-playing the persona below.
The Conversation Plan is canonical grounding, not a script.

# Persona Description
{{ persona.description }}

# Persona Behaviors
{{ persona.behaviors }}

# Conversation Plan
{{ conversation_plan }}

# Conversation History
{{ conversation_history }}
''';

bool isValidUserSimulatorTemplate(
  String templateStr, {
  required List<String> requiredParams,
}) {
  final int opening = RegExp(r'{{').allMatches(templateStr).length;
  final int closing = RegExp(r'}}').allMatches(templateStr).length;
  if (opening != closing) {
    return false;
  }

  final Set<String> placeholders = RegExp(r'{{\s*([a-zA-Z0-9_.]+)\s*}}')
      .allMatches(templateStr)
      .map((Match match) {
        return match.group(1) ?? '';
      })
      .where((String name) => name.isNotEmpty)
      .toSet();

  for (final String required in requiredParams) {
    if (!placeholders.contains(required)) {
      return false;
    }
  }
  return true;
}

String _getUserSimulatorInstructionsTemplate({
  String? customInstructions,
  UserPersona? userPersona,
}) {
  if (customInstructions == null && userPersona == null) {
    return _defaultUserSimulatorInstructionsTemplate;
  }
  if (customInstructions == null && userPersona != null) {
    return _personaUserSimulatorInstructionsTemplate;
  }
  if (customInstructions != null && userPersona == null) {
    return customInstructions;
  }

  if (!isValidUserSimulatorTemplate(
    customInstructions!,
    requiredParams: <String>[
      'stop_signal',
      'conversation_plan',
      'conversation_history',
      'persona',
    ],
  )) {
    throw ArgumentError(
      'Custom instructions using personas must include: '
      '{{ stop_signal }}, {{ conversation_plan }}, '
      '{{ conversation_history }}, {{ persona }}',
    );
  }
  return customInstructions;
}

String getLlmBackedUserSimulatorPrompt({
  required String conversationPlan,
  required String conversationHistory,
  required String stopSignal,
  String? customInstructions,
  UserPersona? userPersona,
}) {
  final String template = _getUserSimulatorInstructionsTemplate(
    customInstructions: customInstructions,
    userPersona: userPersona,
  );

  final Map<String, String> values = <String, String>{
    'stop_signal': stopSignal,
    'conversation_plan': conversationPlan,
    'conversation_history': conversationHistory,
  };
  if (userPersona != null) {
    values['persona'] = _renderPersona(userPersona);
    values['persona.description'] = userPersona.description;
    values['persona.behaviors'] = _renderPersonaBehaviors(userPersona);
  }

  return _renderTemplate(template, values);
}

String _renderPersona(UserPersona persona) {
  final StringBuffer buffer = StringBuffer();
  buffer.writeln('id: ${persona.id}');
  buffer.writeln('description: ${persona.description}');
  buffer.writeln('behaviors:');
  for (final UserBehavior behavior in persona.behaviors) {
    buffer.writeln('- name: ${behavior.name}');
    buffer.writeln('  description: ${behavior.description}');
    final String instructions = behavior.getBehaviorInstructionsStr();
    if (instructions.isNotEmpty) {
      buffer.writeln('  instructions:');
      buffer.writeln(instructions);
    }
  }
  return buffer.toString().trim();
}

String _renderPersonaBehaviors(UserPersona persona) {
  if (persona.behaviors.isEmpty) {
    return '';
  }
  final StringBuffer buffer = StringBuffer();
  for (final UserBehavior behavior in persona.behaviors) {
    if (buffer.isNotEmpty) {
      buffer.writeln();
    }
    buffer.writeln('## ${behavior.name}');
    buffer.writeln(behavior.description);
    final String instructions = behavior.getBehaviorInstructionsStr();
    if (instructions.isNotEmpty) {
      buffer.writeln('Instructions:');
      buffer.writeln(instructions);
    }
  }
  return buffer.toString().trim();
}

String _renderTemplate(String template, Map<String, String> values) {
  String rendered = template;
  values.forEach((String key, String value) {
    final RegExp matcher = RegExp('{{\\s*${RegExp.escape(key)}\\s*}}');
    rendered = rendered.replaceAll(matcher, value);
  });
  return rendered;
}
