import 'dart:async';

import '../../agents/base_agent.dart';
import '../../agents/llm_agent.dart';
import '../../agents/loop_agent.dart';
import '../../agents/parallel_agent.dart';
import '../../agents/sequential_agent.dart';
import '../../examples/example.dart';
import '../../tools/base_tool.dart';
import '../../tools/example_tool.dart';
import '../../types/content.dart';
import '../protocol.dart';

class AgentCardBuilder {
  AgentCardBuilder({
    required BaseAgent agent,
    String? rpcUrl,
    AgentCapabilities? capabilities,
    this.docUrl,
    this.provider,
    String? agentVersion,
    Map<String, SecurityScheme>? securitySchemes,
  }) : _agent = agent,
       _rpcUrl = rpcUrl ?? 'http://localhost:80/a2a',
       _capabilities = capabilities ?? AgentCapabilities(),
       _agentVersion = agentVersion ?? '0.0.1',
       _securitySchemes = securitySchemes ?? <String, SecurityScheme>{};

  final BaseAgent _agent;
  final String _rpcUrl;
  final AgentCapabilities _capabilities;
  final String? docUrl;
  final AgentProvider? provider;
  final String _agentVersion;
  final Map<String, SecurityScheme> _securitySchemes;

  Future<AgentCard> build() async {
    final List<AgentSkill> primarySkills = await _buildPrimarySkills(_agent);
    final List<AgentSkill> subAgentSkills = await _buildSubAgentSkills(_agent);

    return AgentCard(
      name: _agent.name,
      description: _agent.description.isNotEmpty
          ? _agent.description
          : 'An ADK Agent',
      docUrl: docUrl,
      url: _rpcUrl.replaceFirst(RegExp(r'/+$'), ''),
      version: _agentVersion,
      capabilities: _capabilities,
      skills: <AgentSkill>[...primarySkills, ...subAgentSkills],
      defaultInputModes: <String>['text/plain'],
      defaultOutputModes: <String>['text/plain'],
      supportsAuthenticatedExtendedCard: false,
      provider: provider,
      securitySchemes: _securitySchemes,
    );
  }
}

Future<List<AgentSkill>> _buildPrimarySkills(BaseAgent agent) async {
  if (agent is LlmAgent) {
    return _buildLlmAgentSkills(agent);
  }
  return _buildNonLlmAgentSkills(agent);
}

Future<List<AgentSkill>> _buildLlmAgentSkills(LlmAgent agent) async {
  final List<AgentSkill> skills = <AgentSkill>[];

  final String agentDescription = _buildLlmAgentDescriptionWithInstructions(
    agent,
  );
  final List<Map<String, Object?>> examples = await _extractExamplesFromAgent(
    agent,
  );

  skills.add(
    AgentSkill(
      id: agent.name,
      name: 'model',
      description: agentDescription,
      examples: _extractInputsFromExamples(examples),
      inputModes: _getInputModes(agent),
      outputModes: _getOutputModes(agent),
      tags: <String>['llm'],
    ),
  );

  final List<AgentSkill> toolSkills = await _buildToolSkills(agent);
  skills.addAll(toolSkills);

  if (agent.planner != null) {
    skills.add(_buildPlannerSkill(agent));
  }
  if (agent.codeExecutor != null) {
    skills.add(_buildCodeExecutorSkill(agent));
  }

  return skills;
}

Future<List<AgentSkill>> _buildSubAgentSkills(BaseAgent agent) async {
  final List<AgentSkill> subAgentSkills = <AgentSkill>[];
  for (final BaseAgent subAgent in agent.subAgents) {
    final List<AgentSkill> subSkills = await _buildPrimarySkills(subAgent);
    for (final AgentSkill skill in subSkills) {
      subAgentSkills.add(
        AgentSkill(
          id: '${subAgent.name}_${skill.id}',
          name: '${subAgent.name}: ${skill.name}',
          description: skill.description,
          examples: skill.examples,
          inputModes: skill.inputModes,
          outputModes: skill.outputModes,
          tags: <String>['sub_agent:${subAgent.name}', ...skill.tags],
        ),
      );
    }
  }

  return subAgentSkills;
}

Future<List<AgentSkill>> _buildToolSkills(LlmAgent agent) async {
  final List<AgentSkill> toolSkills = <AgentSkill>[];
  final List<BaseTool> tools = await agent.canonicalTools();

  for (final BaseTool tool in tools) {
    if (tool is ExampleTool) {
      continue;
    }

    final String toolName = tool.name.isNotEmpty
        ? tool.name
        : tool.runtimeType.toString();
    final String description = tool.description.isNotEmpty
        ? tool.description
        : 'Tool: $toolName';

    toolSkills.add(
      AgentSkill(
        id: '${agent.name}-$toolName',
        name: toolName,
        description: description,
        tags: <String>['llm', 'tools'],
      ),
    );
  }

  return toolSkills;
}

AgentSkill _buildPlannerSkill(LlmAgent agent) {
  return AgentSkill(
    id: '${agent.name}-planner',
    name: 'planning',
    description: 'Can think about the tasks to do and make plans',
    tags: <String>['llm', 'planning'],
  );
}

AgentSkill _buildCodeExecutorSkill(LlmAgent agent) {
  return AgentSkill(
    id: '${agent.name}-code-executor',
    name: 'code-execution',
    description: 'Can execute code',
    tags: <String>['llm', 'code_execution'],
  );
}

Future<List<AgentSkill>> _buildNonLlmAgentSkills(BaseAgent agent) async {
  final String agentDescription = _buildAgentDescription(agent);
  final List<Map<String, Object?>> examples = await _extractExamplesFromAgent(
    agent,
  );

  final String agentType = _getAgentType(agent);
  final String agentName = _getAgentSkillName(agent);

  final List<AgentSkill> skills = <AgentSkill>[
    AgentSkill(
      id: agent.name,
      name: agentName,
      description: agentDescription,
      examples: _extractInputsFromExamples(examples),
      inputModes: _getInputModes(agent),
      outputModes: _getOutputModes(agent),
      tags: <String>[agentType],
    ),
  ];

  if (agent.subAgents.isNotEmpty) {
    final AgentSkill? orchestrationSkill = _buildOrchestrationSkill(
      agent,
      agentType,
    );
    if (orchestrationSkill != null) {
      skills.add(orchestrationSkill);
    }
  }

  return skills;
}

AgentSkill? _buildOrchestrationSkill(BaseAgent agent, String agentType) {
  if (agent.subAgents.isEmpty) {
    return null;
  }

  final List<String> descriptions = agent.subAgents
      .map(
        (BaseAgent subAgent) =>
            '${subAgent.name}: ${subAgent.description.isNotEmpty ? subAgent.description : 'No description'}',
      )
      .toList();

  return AgentSkill(
    id: '${agent.name}-sub-agents',
    name: 'sub-agents',
    description: 'Orchestrates: ${descriptions.join('; ')}',
    tags: <String>[agentType, 'orchestration'],
  );
}

String _getAgentType(BaseAgent agent) {
  if (agent is LlmAgent) {
    return 'llm';
  }
  if (agent is SequentialAgent) {
    return 'sequential_workflow';
  }
  if (agent is ParallelAgent) {
    return 'parallel_workflow';
  }
  if (agent is LoopAgent) {
    return 'loop_workflow';
  }
  return 'custom_agent';
}

String _getAgentSkillName(BaseAgent agent) {
  if (agent is LlmAgent) {
    return 'model';
  }
  if (agent is SequentialAgent ||
      agent is ParallelAgent ||
      agent is LoopAgent) {
    return 'workflow';
  }
  return 'custom';
}

String _buildAgentDescription(BaseAgent agent) {
  final List<String> parts = <String>[];
  if (agent.description.isNotEmpty) {
    parts.add(agent.description);
  }

  if (agent is! LlmAgent) {
    final String? workflowDescription = _getWorkflowDescription(agent);
    if (workflowDescription != null) {
      parts.add(workflowDescription);
    }
  }

  if (parts.isEmpty) {
    return _getDefaultDescription(agent);
  }
  return parts.join(' ');
}

String _buildLlmAgentDescriptionWithInstructions(LlmAgent agent) {
  final List<String> parts = <String>[];

  if (agent.description.isNotEmpty) {
    parts.add(agent.description);
  }
  if (agent.instruction is String && (agent.instruction as String).isNotEmpty) {
    parts.add(_replacePronouns(agent.instruction as String));
  }
  if (agent.globalInstruction is String &&
      (agent.globalInstruction as String).isNotEmpty) {
    parts.add(_replacePronouns(agent.globalInstruction as String));
  }

  if (parts.isEmpty) {
    return _getDefaultDescription(agent);
  }
  return parts.join(' ');
}

String _replacePronouns(String text) {
  final Map<String, String> pronounMap = <String, String>{
    'you are': 'I am',
    'you were': 'I was',
    'you\'re': 'I am',
    'you\'ve': 'I have',
    'yours': 'mine',
    'your': 'my',
    'you': 'I',
  };

  final List<String> keys = pronounMap.keys.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));

  String result = text;
  for (final String key in keys) {
    result = result.replaceAllMapped(
      RegExp('\\b${RegExp.escape(key)}\\b', caseSensitive: false),
      (_) => pronounMap[key]!,
    );
  }
  return result;
}

String? _getWorkflowDescription(BaseAgent agent) {
  if (agent.subAgents.isEmpty) {
    return null;
  }
  if (agent is SequentialAgent) {
    return _buildSequentialDescription(agent);
  }
  if (agent is ParallelAgent) {
    return _buildParallelDescription(agent);
  }
  if (agent is LoopAgent) {
    return _buildLoopDescription(agent);
  }
  return null;
}

String _buildSequentialDescription(SequentialAgent agent) {
  final List<String> descriptions = <String>[];
  for (int i = 0; i < agent.subAgents.length; i += 1) {
    final BaseAgent subAgent = agent.subAgents[i];
    final String subDescription = subAgent.description.isNotEmpty
        ? subAgent.description
        : 'execute the ${subAgent.name} agent';

    if (i == 0) {
      descriptions.add('First, this agent will $subDescription');
    } else if (i == agent.subAgents.length - 1) {
      descriptions.add('Finally, this agent will $subDescription');
    } else {
      descriptions.add('Then, this agent will $subDescription');
    }
  }
  return '${descriptions.join(' ')}.';
}

String _buildParallelDescription(ParallelAgent agent) {
  final List<String> descriptions = <String>[];
  for (int i = 0; i < agent.subAgents.length; i += 1) {
    final BaseAgent subAgent = agent.subAgents[i];
    final String subDescription = subAgent.description.isNotEmpty
        ? subAgent.description
        : 'execute the ${subAgent.name} agent';

    if (i == 0) {
      descriptions.add('This agent will $subDescription');
    } else if (i == agent.subAgents.length - 1) {
      descriptions.add('and $subDescription');
    } else {
      descriptions.add(', $subDescription');
    }
  }
  return '${descriptions.join(' ')} simultaneously.';
}

String _buildLoopDescription(LoopAgent agent) {
  final List<String> descriptions = <String>[];
  for (int i = 0; i < agent.subAgents.length; i += 1) {
    final BaseAgent subAgent = agent.subAgents[i];
    final String subDescription = subAgent.description.isNotEmpty
        ? subAgent.description
        : 'execute the ${subAgent.name} agent';

    if (i == 0) {
      descriptions.add('This agent will $subDescription');
    } else if (i == agent.subAgents.length - 1) {
      descriptions.add('and $subDescription');
    } else {
      descriptions.add(', $subDescription');
    }
  }

  final Object maxIterations = agent.maxIterations ?? 'unlimited';
  return '${descriptions.join(' ')} in a loop (max $maxIterations iterations).';
}

String _getDefaultDescription(BaseAgent agent) {
  if (agent is LlmAgent) {
    return 'An LLM-based agent';
  }
  if (agent is SequentialAgent) {
    return 'A sequential workflow agent';
  }
  if (agent is ParallelAgent) {
    return 'A parallel workflow agent';
  }
  if (agent is LoopAgent) {
    return 'A loop workflow agent';
  }
  return 'A custom agent';
}

List<String> _extractInputsFromExamples(List<Map<String, Object?>> examples) {
  final List<String> extracted = <String>[];

  for (final Map<String, Object?> example in examples) {
    final Object? input = example['input'];
    if (input is String && input.isNotEmpty) {
      extracted.add(input);
      continue;
    }

    if (input is Map) {
      final Object? parts = input['parts'];
      if (parts is List) {
        final List<String> texts = <String>[];
        for (final Object? part in parts) {
          if (part is Map && part['text'] != null) {
            texts.add('${part['text']}');
          }
        }
        if (texts.isNotEmpty) {
          extracted.add(texts.join('\n'));
          continue;
        }
      }
      if (input['text'] != null) {
        extracted.add('${input['text']}');
      }
    }
  }

  return extracted;
}

Future<List<Map<String, Object?>>> _extractExamplesFromAgent(
  BaseAgent agent,
) async {
  if (agent is! LlmAgent) {
    return <Map<String, Object?>>[];
  }

  try {
    final List tools = await agent.canonicalTools();
    for (final Object tool in tools) {
      if (tool is ExampleTool) {
        return _convertExampleToolExamples(tool);
      }
    }
  } catch (_) {
    // Continue to instruction parsing fallback.
  }

  if (agent.instruction is String && (agent.instruction as String).isNotEmpty) {
    return _extractExamplesFromInstruction(agent.instruction as String);
  }

  return <Map<String, Object?>>[];
}

List<Map<String, Object?>> _convertExampleToolExamples(ExampleTool tool) {
  final Object examples = tool.examples;
  if (examples is List<Example>) {
    return examples.map((Example example) {
      return <String, Object?>{
        'input': _contentToSimpleMap(example.input),
        'output': example.output
            .map(_contentToSimpleMap)
            .toList(growable: false),
      };
    }).toList();
  }

  if (examples is List) {
    final List<Map<String, Object?>> converted = <Map<String, Object?>>[];
    for (final Object item in examples) {
      if (item is Map) {
        converted.add(
          item.map(
            (Object? key, Object? value) =>
                MapEntry<String, Object?>('$key', value),
          ),
        );
      }
    }
    return converted;
  }

  return <Map<String, Object?>>[];
}

Map<String, Object?> _contentToSimpleMap(Content content) {
  return <String, Object?>{
    if (content.role != null) 'role': content.role,
    'parts': content.parts
        .map((Part part) {
          final Map<String, Object?> mapped = <String, Object?>{};
          if (part.text != null) {
            mapped['text'] = part.text;
          }
          if (part.functionCall != null) {
            mapped['function_call'] = <String, Object?>{
              if (part.functionCall!.id != null) 'id': part.functionCall!.id,
              'name': part.functionCall!.name,
              'args': Map<String, dynamic>.from(part.functionCall!.args),
            };
          }
          if (part.functionResponse != null) {
            mapped['function_response'] = <String, Object?>{
              if (part.functionResponse!.id != null)
                'id': part.functionResponse!.id,
              'name': part.functionResponse!.name,
              'response': Map<String, dynamic>.from(
                part.functionResponse!.response,
              ),
            };
          }
          return mapped;
        })
        .toList(growable: false),
  };
}

List<Map<String, Object?>> _extractExamplesFromInstruction(String instruction) {
  final List<Map<String, Object?>> examples = <Map<String, Object?>>[];

  final List<RegExp> patterns = <RegExp>[
    RegExp('Example Query:\\s*["\\\']([^"\\\']+)["\\\']', caseSensitive: false),
    RegExp(
      'Example Response:\\s*["\\\']([^"\\\']+)["\\\']',
      caseSensitive: false,
    ),
    RegExp('Example:\\s*["\\\']([^"\\\']+)["\\\']', caseSensitive: false),
  ];

  final List<String> matches = <String>[];
  for (final RegExp pattern in patterns) {
    final Iterable<RegExpMatch> found = pattern.allMatches(instruction);
    for (final RegExpMatch match in found) {
      final String? value = match.group(1);
      if (value != null && value.isNotEmpty) {
        matches.add(value);
      }
    }
  }

  for (int i = 0; i + 1 < matches.length; i += 2) {
    examples.add(<String, Object?>{
      'input': <String, Object?>{'text': matches[i]},
      'output': <Map<String, Object?>>[
        <String, Object?>{'text': matches[i + 1]},
      ],
    });
  }

  return examples;
}

List<String>? _getInputModes(BaseAgent agent) {
  if (agent is! LlmAgent) {
    return null;
  }
  return null;
}

List<String>? _getOutputModes(BaseAgent agent) {
  if (agent is! LlmAgent) {
    return null;
  }
  return null;
}
