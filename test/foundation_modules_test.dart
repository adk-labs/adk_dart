import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Foundation modules', () {
    test('dependency container resolves singleton and factory', () {
      final DependencyContainer container = DependencyContainer();
      container.registerSingleton<String>('alpha');
      container.registerFactory<int>(() => 42);

      expect(container.resolve<String>(), 'alpha');
      expect(container.resolve<int>(), 42);
    });

    test('feature flags toggle values', () {
      final FeatureFlags flags = FeatureFlags();
      flags.set('use_new_flow', true);

      expect(flags.isEnabled('use_new_flow'), isTrue);
      expect(flags.isEnabled('unknown', defaultValue: false), isFalse);
    });

    test('rule-based planner produces non-empty plan', () {
      final RuleBasedPlanner planner = RuleBasedPlanner();
      final PlanningResult result = planner.plan(
        PlanningRequest(goal: 'answer user question'),
      );

      expect(result.steps, isNotEmpty);
      expect(result.steps.first.title, 'Understand goal');
    });

    test('prompt optimizer normalizes whitespace', () {
      final PromptOptimizer optimizer = PromptOptimizer();
      final PromptOptimizationResult result = optimizer.optimize(
        '  hello   world  ',
      );

      expect(result.changed, isTrue);
      expect(result.optimizedPrompt, 'hello world');
    });

    test('skill registry stores and retrieves skills', () {
      final SkillRegistry registry = SkillRegistry();
      final Skill skill = Skill(name: 'search', description: 'Search docs');
      registry.register(skill);

      expect(registry.get('search')?.description, 'Search docs');
      expect(registry.list(), hasLength(1));
    });

    test('a2a router delivers message to target agent stream', () async {
      final InMemoryA2ARouter router = InMemoryA2ARouter();
      final Future<A2AMessage> next = router.messagesFor('agent_b').first;

      router.send(
        A2AMessage(
          fromAgent: 'agent_a',
          toAgent: 'agent_b',
          content: 'handoff',
        ),
      );

      final A2AMessage delivered = await next;
      expect(delivered.content, 'handoff');
      await router.close();
    });
  });
}
