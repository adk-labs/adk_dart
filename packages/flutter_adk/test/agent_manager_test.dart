import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdkAgentManagerController Tests', () {
    test('registers, toggles, updates instruction, and records telemetry', () {
      final ctrl = AdkAgentManagerController();
      final agent1 = adk.LlmAgent(name: 'researcher', instruction: 'Collect info');
      final agent2 = adk.LlmAgent(name: 'coder', instruction: 'Write code');

      ctrl.registerAgent(
        agent1,
        id: 'agent_res',
        description: 'Research specialist',
        tags: const ['research', 'web'],
      );

      ctrl.registerAgent(
        agent2,
        id: 'agent_coder',
        description: 'Code generator',
        tags: const ['coding', 'dart'],
      );

      expect(ctrl.agents.length, equals(2));
      expect(ctrl.activeAgentId, equals('agent_res'));
      expect(ctrl.allTags, containsAll(['research', 'web', 'coding', 'dart']));

      // Toggle enabled
      ctrl.toggleAgent('agent_res', false);
      expect(ctrl.enabledAgents.length, equals(1));
      expect(ctrl.getAgent('agent_res')?.isEnabled, isFalse);
      expect(ctrl.getAgent('agent_res')?.status, equals(AdkAgentStatus.disabled));

      ctrl.toggleAgent('agent_res', true);
      expect(ctrl.getAgent('agent_res')?.status, equals(AdkAgentStatus.idle));

      // Record invocation metrics
      ctrl.recordInvocation('agent_res', tokens: 150, latencyMs: 320.0);
      ctrl.recordInvocation('agent_res', tokens: 250, latencyMs: 480.0);

      final updatedMeta = ctrl.getAgent('agent_res')!;
      expect(updatedMeta.metrics.totalInvocations, equals(2));
      expect(updatedMeta.metrics.totalTokens, equals(400));
      expect(updatedMeta.metrics.avgLatencyMs, equals(400.0));

      // Filter search
      ctrl.setSearchQuery('Code');
      expect(ctrl.filteredAgents.length, equals(1));
      expect(ctrl.filteredAgents.first.id, equals('agent_coder'));

      ctrl.setSearchQuery('');
      ctrl.setTagFilter('research');
      expect(ctrl.filteredAgents.length, equals(1));
      expect(ctrl.filteredAgents.first.id, equals('agent_res'));

      // Unregister
      ctrl.unregisterAgent('agent_coder');
      expect(ctrl.agents.length, equals(1));

      ctrl.clearAll();
      expect(ctrl.agents, isEmpty);
    });
  });

  group('AdkAgentManagementView Widget Tests', () {
    testWidgets('renders agent fleet summary, cards, search, and inspector dialog', (WidgetTester tester) async {
      final ctrl = AdkAgentManagerController();
      final agent1 = adk.LlmAgent(name: 'SupportBot', instruction: 'Help customers');

      ctrl.registerAgent(
        agent1,
        id: 'bot_support',
        description: 'Handles tickets',
        tags: const ['support'],
      );

      AdkAgentMetadata? selectedAgent;

      await tester.pumpWidget(
        MaterialApp(
          home: AdkAgentManagementView(
            controller: ctrl,
            onAgentSelected: (agent) => selectedAgent = agent,
          ),
        ),
      );

      expect(find.text('AI Agent Fleet Manager'), findsOneWidget);
      expect(find.text('SupportBot'), findsOneWidget);
      expect(find.text('Handles tickets'), findsOneWidget);
      expect(find.text('1 / 1 active'), findsOneWidget);

      // Tap Select button
      await tester.tap(find.text('Active'));
      await tester.pump();
      expect(selectedAgent?.id, equals('bot_support'));

      // Tap Inspect button
      await tester.tap(find.text('Inspect'));
      await tester.pumpAndSettle();

      expect(find.text('System Instruction / Prompt'), findsOneWidget);
      expect(find.text('Help customers'), findsOneWidget);

      // Close bottom sheet
      await tester.tap(find.byType(ListView).last);
      await tester.pumpAndSettle();
    });
  });
}
