import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Agent clone parity', () {
    test('clones LlmAgent and applies updated name', () {
      final LlmAgent original = LlmAgent(
        name: 'llm_agent',
        description: 'An LLM agent',
        instruction: 'You are a helpful assistant.',
      );

      final LlmAgent cloned = original.clone(
        update: <String, Object?>{'name': 'cloned_llm_agent'},
      );

      expect(cloned.name, 'cloned_llm_agent');
      expect(cloned.description, 'An LLM agent');
      expect(cloned.instruction, 'You are a helpful assistant.');
      expect(cloned.parentAgent, isNull);
      expect(cloned.subAgents, isEmpty);
      expect(cloned, isA<LlmAgent>());

      expect(original.name, 'llm_agent');
      expect(original.instruction, 'You are a helpful assistant.');
    });

    test('deep-clones subAgents and re-links parent', () {
      final LlmAgent subAgent1 = LlmAgent(
        name: 'sub_agent1',
        description: 'First sub-agent',
      );
      final LlmAgent subAgent2 = LlmAgent(
        name: 'sub_agent2',
        description: 'Second sub-agent',
      );

      final SequentialAgent original = SequentialAgent(
        name: 'parent_agent',
        description: 'Parent agent with sub-agents',
        subAgents: <BaseAgent>[subAgent1, subAgent2],
      );

      final SequentialAgent cloned = original.clone(
        update: <String, Object?>{'name': 'cloned_parent'},
      );

      expect(cloned.name, 'cloned_parent');
      expect(cloned.description, 'Parent agent with sub-agents');
      expect(cloned.parentAgent, isNull);
      expect(cloned.subAgents, hasLength(2));
      expect(cloned.subAgents[0].name, 'sub_agent1');
      expect(cloned.subAgents[1].name, 'sub_agent2');
      expect(cloned.subAgents[0].parentAgent, same(cloned));
      expect(cloned.subAgents[1].parentAgent, same(cloned));
      expect(identical(cloned.subAgents[0], original.subAgents[0]), isFalse);
      expect(identical(cloned.subAgents[1], original.subAgents[1]), isFalse);

      expect(original.name, 'parent_agent');
      expect(original.subAgents, hasLength(2));
      expect(original.subAgents[0].parentAgent, same(original));
      expect(original.subAgents[1].parentAgent, same(original));
    });

    test('recursively clones nested workflow agents', () {
      final LlmAgent leafAgent1 = LlmAgent(
        name: 'leaf1',
        description: 'First leaf agent',
      );
      final LlmAgent leafAgent2 = LlmAgent(
        name: 'leaf2',
        description: 'Second leaf agent',
      );

      final SequentialAgent middleAgent1 = SequentialAgent(
        name: 'middle1',
        description: 'First middle agent',
        subAgents: <BaseAgent>[leafAgent1],
      );
      final ParallelAgent middleAgent2 = ParallelAgent(
        name: 'middle2',
        description: 'Second middle agent',
        subAgents: <BaseAgent>[leafAgent2],
      );

      final LoopAgent rootAgent = LoopAgent(
        name: 'root_agent',
        description: 'Root agent with three levels',
        maxIterations: 5,
        subAgents: <BaseAgent>[middleAgent1, middleAgent2],
      );

      final LoopAgent clonedRoot = rootAgent.clone(
        update: <String, Object?>{'name': 'cloned_root'},
      );

      expect(clonedRoot.name, 'cloned_root');
      expect(clonedRoot.description, 'Root agent with three levels');
      expect(clonedRoot.maxIterations, 5);
      expect(clonedRoot.parentAgent, isNull);
      expect(clonedRoot.subAgents, hasLength(2));
      expect(clonedRoot, isA<LoopAgent>());

      final BaseAgent clonedMiddle1 = clonedRoot.subAgents[0];
      final BaseAgent clonedMiddle2 = clonedRoot.subAgents[1];
      expect(clonedMiddle1.name, 'middle1');
      expect(clonedMiddle1.parentAgent, same(clonedRoot));
      expect(clonedMiddle1.subAgents, hasLength(1));
      expect(clonedMiddle1, isA<SequentialAgent>());

      expect(clonedMiddle2.name, 'middle2');
      expect(clonedMiddle2.parentAgent, same(clonedRoot));
      expect(clonedMiddle2.subAgents, hasLength(1));
      expect(clonedMiddle2, isA<ParallelAgent>());

      final BaseAgent clonedLeaf1 = clonedMiddle1.subAgents[0];
      final BaseAgent clonedLeaf2 = clonedMiddle2.subAgents[0];
      expect(clonedLeaf1.name, 'leaf1');
      expect(clonedLeaf1.parentAgent, same(clonedMiddle1));
      expect(clonedLeaf1.subAgents, isEmpty);
      expect(clonedLeaf1, isA<LlmAgent>());

      expect(clonedLeaf2.name, 'leaf2');
      expect(clonedLeaf2.parentAgent, same(clonedMiddle2));
      expect(clonedLeaf2.subAgents, isEmpty);
      expect(clonedLeaf2, isA<LlmAgent>());

      expect(identical(clonedRoot, rootAgent), isFalse);
      expect(identical(clonedMiddle1, middleAgent1), isFalse);
      expect(identical(clonedMiddle2, middleAgent2), isFalse);
      expect(identical(clonedLeaf1, leafAgent1), isFalse);
      expect(identical(clonedLeaf2, leafAgent2), isFalse);
    });

    test('supports multiple independent clones', () {
      final LlmAgent original = LlmAgent(
        name: 'original_agent',
        description: 'Agent for multiple cloning',
      );

      final LlmAgent clone1 = original.clone(
        update: <String, Object?>{'name': 'clone1'},
      );
      final LlmAgent clone2 = original.clone(
        update: <String, Object?>{'name': 'clone2'},
      );

      expect(clone1.name, 'clone1');
      expect(clone2.name, 'clone2');
      expect(identical(clone1, clone2), isFalse);
    });

    test('preserves complex LlmAgent configuration', () {
      final LlmAgent original = LlmAgent(
        name: 'complex_agent',
        description: 'A complex agent with many settings',
        instruction: 'You are a specialized assistant.',
        globalInstruction: 'Always be helpful and accurate.',
        disallowTransferToParent: true,
        disallowTransferToPeers: true,
        includeContents: 'none',
      );

      final LlmAgent cloned = original.clone(
        update: <String, Object?>{'name': 'complex_clone'},
      );

      expect(cloned.name, 'complex_clone');
      expect(cloned.description, 'A complex agent with many settings');
      expect(cloned.instruction, 'You are a specialized assistant.');
      expect(cloned.globalInstruction, 'Always be helpful and accurate.');
      expect(cloned.disallowTransferToParent, isTrue);
      expect(cloned.disallowTransferToPeers, isTrue);
      expect(cloned.includeContents, 'none');
      expect(cloned.parentAgent, isNull);
      expect(cloned.subAgents, isEmpty);
    });

    test('clones without updates', () {
      final LlmAgent original = LlmAgent(
        name: 'test_agent',
        description: 'Test agent',
      );

      final LlmAgent cloned = original.clone();

      expect(cloned.name, 'test_agent');
      expect(cloned.description, 'Test agent');
    });

    test('applies multiple updates', () {
      final LlmAgent original = LlmAgent(
        name: 'original_agent',
        description: 'Original description',
        instruction: 'Original instruction',
      );

      final LlmAgent cloned = original.clone(
        update: <String, Object?>{
          'name': 'updated_agent',
          'description': 'Updated description',
          'instruction': 'Updated instruction',
        },
      );

      expect(cloned.name, 'updated_agent');
      expect(cloned.description, 'Updated description');
      expect(cloned.instruction, 'Updated instruction');
    });

    test('rejects clone update for nonexistent fields', () {
      final LlmAgent original = LlmAgent(
        name: 'test_agent',
        description: 'Test agent',
      );

      expect(
        () =>
            original.clone(update: <String, Object?>{'invalidField': 'value'}),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message.toString(),
            'message',
            contains('Cannot update nonexistent fields'),
          ),
        ),
      );
    });

    test('rejects clone update for parentAgent field', () {
      final LlmAgent original = LlmAgent(
        name: 'test_agent',
        description: 'Test agent',
      );

      expect(
        () =>
            original.clone(update: <String, Object?>{'parentAgent': original}),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message.toString(),
            'message',
            contains('Cannot update `parentAgent` field in clone'),
          ),
        ),
      );
    });

    test('shallow-copies list fields that are not updated', () {
      final AgentLifecycleCallback callback = (CallbackContext context) {
        return null;
      };
      final Object tool = Object();

      final LlmAgent original = LlmAgent(
        name: 'list_clone',
        description: 'list behavior',
        beforeAgentCallback: <AgentLifecycleCallback>[callback],
        tools: <Object>[tool],
      );

      final LlmAgent cloned = original.clone();

      expect(identical(cloned.tools, original.tools), isFalse);
      expect(identical(cloned.tools.first, original.tools.first), isTrue);

      final List<Object?> originalBefore =
          original.beforeAgentCallback! as List<Object?>;
      final List<Object?> clonedBefore =
          cloned.beforeAgentCallback! as List<Object?>;
      expect(identical(clonedBefore, originalBefore), isFalse);
      expect(identical(clonedBefore.first, originalBefore.first), isTrue);
    });

    test('does not copy list fields provided in update', () {
      final Object replacementTool = Object();
      final List<Object> replacementTools = <Object>[replacementTool];

      final LlmAgent original = LlmAgent(
        name: 'list_update',
        description: 'list update behavior',
        tools: <Object>[Object()],
      );

      final LlmAgent cloned = original.clone(
        update: <String, Object?>{'tools': replacementTools},
      );

      expect(identical(cloned.tools, replacementTools), isTrue);
      expect(identical(cloned.tools.first, replacementTool), isTrue);
    });

    test('re-links parent for subAgents supplied in update', () {
      final LlmAgent existingChild = LlmAgent(
        name: 'existing_child',
        description: 'Existing child',
      );
      final SequentialAgent existingParent = SequentialAgent(
        name: 'existing_parent',
        subAgents: <BaseAgent>[existingChild],
      );
      expect(existingChild.parentAgent, same(existingParent));

      final SequentialAgent original = SequentialAgent(name: 'original');
      final List<BaseAgent> updatedSubAgents = <BaseAgent>[existingChild];
      final SequentialAgent cloned = original.clone(
        update: <String, Object?>{
          'name': 'cloned_with_updated_subagents',
          'subAgents': updatedSubAgents,
        },
      );

      expect(identical(cloned.subAgents, updatedSubAgents), isTrue);
      expect(cloned.subAgents.single.parentAgent, same(cloned));
      expect(existingChild.parentAgent, same(cloned));
    });
  });
}
