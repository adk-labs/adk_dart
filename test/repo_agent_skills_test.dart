import 'dart:io';

import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Repository .agents/skills validation & snippet verification', () {
    const List<String> expectedSkills = <String>[
      'adk-dart-setup',
      'adk-dart-agent-builder',
      'flutter-adk-ui-builder',
      'adk-dart-debug',
      'adk-dart-architecture',
    ];

    test('validates all skill directories in .agents/skills and .claude/skills', () {
      for (final String skillName in expectedSkills) {
        final String skillPath = '.agents/skills/$skillName';
        final List<String> problems = validateSkillDir(skillPath);
        expect(
          problems,
          isEmpty,
          reason: 'Skill $skillName had validation problems: $problems',
        );

        final Skill skill = loadSkillFromDir(skillPath);
        expect(skill.name, skillName);
        expect(skill.description, isNotEmpty);
        expect(skill.instructions, isNotEmpty);
      }

      // Verify .claude/skills symlink resolves all skills too
      for (final String skillName in expectedSkills) {
        final File claudeSkillMd = File('.claude/skills/$skillName/SKILL.md');
        expect(claudeSkillMd.existsSync(), isTrue);
      }

      // Verify AGENTS.md lists all expected skills
      final String agentsMd = File('AGENTS.md').readAsStringSync();
      for (final String skillName in expectedSkills) {
        expect(agentsMd, contains(skillName));
      }
    });

    test('verifies adk-dart-agent-builder workflow, toolset, and eval signatures', () async {
      final FunctionNode fetchA = FunctionNode(
        name: 'fetch_a',
        function: (WorkflowContext ctx, Object? nodeInput) async =>
            <String, Object?>{'a': 10},
      );
      final FunctionNode fetchB = FunctionNode(
        name: 'fetch_b',
        function: (WorkflowContext ctx, Object? nodeInput) async =>
            <String, Object?>{'b': 20},
      );
      final JoinNode join = JoinNode(name: 'join_ab');
      final FunctionNode combine = FunctionNode(
        name: 'combine',
        function: (WorkflowContext ctx, Object? nodeInput) async {
          final Map<String, Object?> inputs =
              (nodeInput as Map?)?.cast<String, Object?>() ??
              <String, Object?>{};
          return <String, Object?>{'sum': 30, 'inputs': inputs};
        },
      );

      final Workflow workflow = Workflow.build(
        name: 'parallel_pipeline',
        nodes: <BaseNode>[fetchA, fetchB, join, combine],
        buildEdges: (EdgesBuilder g) {
          g
              .fromStart()
              .thenGroup(<Object>[fetchA, fetchB])
              .joinTo(join)
              .then(combine);
        },
      );

      final WorkflowResult result = await workflow.runWorkflow(input: 'start');
      expect(result.nodeStates['combine']?.status, NodeStatus.completed);
      expect((result.outputs['combine'] as Map<String, Object?>)['sum'], 30);

      // Verify WorkflowTool and NodeTool wrappers
      final WorkflowTool wfTool = WorkflowTool(workflow: workflow);
      final NodeTool nodeTool = NodeTool(node: fetchA);
      expect(wfTool.name, 'parallel_pipeline');
      expect(nodeTool.name, 'fetch_a');

      // Verify StdioConnectionParams uses `arguments:`
      final StdioConnectionParams stdioParams = StdioConnectionParams(
        command: 'npx',
        arguments: <String>['-y', '@modelcontextprotocol/server-filesystem'],
      );
      expect(stdioParams.arguments, isNotEmpty);

      // Verify SkillToolset and ToolSearchToolset constructors
      final SkillToolset skillToolset = SkillToolset(
        skills: <Skill>[
          loadSkillFromDir('.agents/skills/adk-dart-agent-builder'),
        ],
        discoveryMode: SkillDiscoveryMode.lazy,
        lifecycleConfig: SkillLifecycleConfig(enabled: true),
      );
      expect(skillToolset, isNotNull);

      final ToolSearchToolset toolSearch = ToolSearchToolset(
        tools: <Object>[nodeTool],
        config: const ToolSearchConfig(maxResults: 5),
      );
      expect(toolSearch, isNotNull);

      // Verify EventsCompactionConfig rule (tokenThreshold + eventRetentionSize together)
      final EventsCompactionConfig compactionConfig = EventsCompactionConfig(
        compactionInterval: 10,
        overlapSize: 2,
        tokenThreshold: 64000,
        eventRetentionSize: 10,
      );
      expect(compactionConfig.tokenThreshold, 64000);

      // Verify Multi-Run Evaluation Aggregator signature
      final List<MultiRunCaseResult> multiRunResults =
          EvalCaseResultMultiRunAggregator.aggregate(
        <EvalCaseResult>[],
        multiRunConfig: MultiRunConfig(
          numRuns: 3,
          crossRunCriteria: <MultiRunCriterion>[
            PassKMultiRunCriterion(method: 'pass_at_k', k: 2, threshold: 0.8),
            PassKMultiRunCriterion(method: 'pass_hat_k', k: 2, threshold: 0.5),
          ],
        ),
      );
      expect(multiRunResults, isEmpty);
    });
  });
}
