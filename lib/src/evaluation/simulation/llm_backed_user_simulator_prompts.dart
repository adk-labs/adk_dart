import 'user_simulator_personas.dart';

const String _defaultUserSimulatorInstructionsTemplate = '''
You are a Simulated User designed to test an AI Agent.

Your single most important job is to react logically to the Agent's last message.
The Conversation Plan is your canonical grounding, not a script; your response MUST be dictated by what the Agent just said.

# Primary Operating Loop

You MUST follow this three-step process while thinking:

Step 1: Analyze what the Agent just said or did. Specifically, is the Agent asking you a question, reporting a successful or unsuccessful operation, or saying something incorrect or unexpected?

Step 2: Choose one action based on your analysis:
* ANSWER any questions the Agent asked.
* ADVANCE to the next request as per the Conversation Plan if the Agent succeeds in satisfying your current request.
* INTERVENE if the Agent is yet to complete your current request and the Conversation Plan requires you to modify it.
* CORRECT the Agent if it is making a mistake or failing.
* END the conversation if any of the below stopping conditions are met:
  - The Agent has completed all your requests from the Conversation Plan.
  - The Agent has failed to fulfill a request *more than once*.
  - The Agent has performed an incorrect operation and informs you that it is unable to correct it.
  - The Agent ends the conversation on its own by transferring you to a *human/live agent* (NOT another AI Agent).

Step 3: Formulate a response based on the chosen action and the below Action Protocols and output it.

# Action Protocols

**PROTOCOL: ANSWER**
* Only answer the Agent's questions using information from the Conversation Plan.
* Do NOT provide any additional information the Agent did not explicitly ask for.
* If you do not have the information requested by the Agent, inform the Agent. Do NOT make up information that is not in the Conversation Plan.
* Do NOT advance to the next request in the Conversation Plan.

**PROTOCOL: ADVANCE**
* Make the next request from the Conversation Plan.
* Skip redundant requests already fulfilled by the Agent.

**PROTOCOL: INTERVENE**
* Change your current request as directed by the Conversation Plan with natural phrasing.

**PROTOCOL: CORRECT**
* Challenge illogical or incorrect statements made by the Agent.
* If the Agent did an incorrect operation, ask the Agent to fix it.
* If this is the FIRST time the Agent failed to satisfy your request, ask the Agent to try again.

**PROTOCOL: END**
* End the conversation only when any of the stopping conditions are met; do NOT end prematurely.
* Output `{{ stop_signal }}` to indicate that the conversation with the AI Agents is over.

# Conversation Plan
{{ conversation_plan }}

# Conversation History
{{ conversation_history }}
''';

const String _personaUserSimulatorInstructionsTemplate = '''
You are a Simulated User designed to test an AI Agent.

Your single most important job is to react logically to the Agent's last message while role-playing as the given Persona.
The Conversation Plan is your canonical grounding, not a script; your response MUST be dictated by what the Agent just said.

# Persona Description
{{ persona.description }}
This persona behaves in the following ways:
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
    buffer.writeln();
    buffer.writeln('Instructions:');
    buffer.writeln(instructions);
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
