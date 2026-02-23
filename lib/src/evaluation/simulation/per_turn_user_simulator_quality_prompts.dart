import 'user_simulator_personas.dart';

const String _latestTurnUserSimulatorEvaluatorPromptTemplate = '''
You are evaluating whether a Generated User Response is consistent with:
- Conversation Plan
- Conversation History

The conversation ends only when the response includes {{ stop_signal }}.
Return strict JSON:
{
  "criteria": [{"name":"CRITERIA_NAME","reasoning":"...","passes":true}],
  "is_valid": true
}

# Conversation Plan
{{ conversation_plan }}

# Conversation History
{{ conversation_history }}

# Generated User Response
{{ generated_user_response }}
''';

const String _latestTurnUserSimulatorWithPersonaEvaluatorPromptTemplate = '''
You are evaluating whether a Generated User Response is consistent with:
- Conversation Plan
- Conversation History
- Persona behaviors

The conversation ends only when the response includes {{ stop_signal }}.
Use persona criteria below.

{{ persona.criteria }}

Return strict JSON:
{
  "criteria": [{"name":"CRITERIA_NAME","reasoning":"...","passes":true}],
  "is_valid": true
}

# Conversation Plan
{{ conversation_plan }}

# Conversation History
{{ conversation_history }}

# Persona Description
{{ persona.description }}

# Generated User Response
{{ generated_user_response }}
''';

String getPerTurnUserSimulatorQualityPrompt({
  required String conversationPlan,
  required String conversationHistory,
  required String generatedUserResponse,
  required String stopSignal,
  UserPersona? userPersona,
}) {
  final String template = userPersona == null
      ? _latestTurnUserSimulatorEvaluatorPromptTemplate
      : _latestTurnUserSimulatorWithPersonaEvaluatorPromptTemplate;

  final Map<String, String> values = <String, String>{
    'conversation_plan': conversationPlan,
    'conversation_history': conversationHistory,
    'generated_user_response': generatedUserResponse,
    'stop_signal': stopSignal,
  };
  if (userPersona != null) {
    values['persona.description'] = userPersona.description;
    values['persona.criteria'] = _renderPersonaCriteria(userPersona);
    values['persona'] = _renderPersona(userPersona);
  }
  return _renderTemplate(template, values);
}

String _renderPersonaCriteria(UserPersona persona) {
  if (persona.behaviors.isEmpty) {
    return '';
  }
  final StringBuffer buffer = StringBuffer();
  for (final UserBehavior behavior in persona.behaviors) {
    if (buffer.isNotEmpty) {
      buffer.writeln();
    }
    buffer.writeln('## Criteria: ${behavior.name}');
    buffer.writeln(behavior.description);
    final String violations = behavior.getViolationRubricsStr();
    if (violations.isNotEmpty) {
      buffer.writeln('Mark as FAIL on:');
      buffer.writeln(violations);
    }
  }
  return buffer.toString().trim();
}

String _renderPersona(UserPersona persona) {
  return '''
id: ${persona.id}
description: ${persona.description}
'''
      .trim();
}

String _renderTemplate(String template, Map<String, String> values) {
  String rendered = template;
  values.forEach((String key, String value) {
    final RegExp matcher = RegExp('{{\\s*${RegExp.escape(key)}\\s*}}');
    rendered = rendered.replaceAll(matcher, value);
  });
  return rendered;
}
