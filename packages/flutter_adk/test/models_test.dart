import 'package:flutter/material.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdkChatMessage Model Tests', () {
    test('instantiates and computes role helpers', () {
      final userMsg = AdkChatMessage(
        id: '1',
        text: 'hello',
        role: AdkMessageRole.user,
      );
      expect(userMsg.isUser, isTrue);
      expect(userMsg.isModel, isFalse);
      expect(userMsg.isSystem, isFalse);
      expect(userMsg.isTool, isFalse);

      final modelMsg = AdkChatMessage(
        id: '2',
        text: 'response',
        role: AdkMessageRole.model,
        thought: 'thinking...',
      );
      expect(modelMsg.isModel, isTrue);
      expect(modelMsg.thought, equals('thinking...'));

      final sysMsg = AdkChatMessage(
        id: '3',
        text: 'system note',
        role: AdkMessageRole.system,
      );
      expect(sysMsg.isSystem, isTrue);

      final toolMsg = AdkChatMessage(
        id: '4',
        text: 'result',
        role: AdkMessageRole.tool,
        toolName: 'calc',
        toolArgs: {'x': 1},
        toolResult: 42,
      );
      expect(toolMsg.isTool, isTrue);
      expect(toolMsg.toolName, equals('calc'));
      expect(toolMsg.toolArguments, equals({'x': 1}));
      expect(toolMsg.toolResult, equals(42));
    });

    test('copyWith works correctly', () {
      final now = DateTime.now();
      final msg = AdkChatMessage(
        id: '1',
        text: 'original',
        role: AdkMessageRole.user,
      );

      final updated = msg.copyWith(
        id: '2',
        text: 'updated',
        role: AdkMessageRole.model,
        timestamp: now,
        isStreaming: true,
        isError: false,
        author: 'agent_1',
        thought: 'thought_1',
        toolName: 'tool_1',
        toolArgs: {'a': 1},
        toolResult: 'res',
        metadata: {'k': 'v'},
      );

      expect(updated.id, equals('2'));
      expect(updated.text, equals('updated'));
      expect(updated.role, equals(AdkMessageRole.model));
      expect(updated.timestamp, equals(now));
      expect(updated.isStreaming, isTrue);
      expect(updated.author, equals('agent_1'));
      expect(updated.thought, equals('thought_1'));
      expect(updated.toolName, equals('tool_1'));
      expect(updated.toolArgs, equals({'a': 1}));
      expect(updated.toolResult, equals('res'));
      expect(updated.metadata, equals({'k': 'v'}));
    });
  });

  group('AdkToolCallInfo Model Tests', () {
    test('instantiates and calculates duration', () {
      final start = DateTime(2026, 1, 1, 12, 0, 0);
      final end = DateTime(2026, 1, 1, 12, 0, 1, 500);

      final tool = AdkToolCallInfo(
        callId: 'call_1',
        toolName: 'web_search',
        arguments: const {'q': 'flutter'},
        result: const {'hits': 5},
        status: AdkToolStatus.success,
        startTime: start,
        endTime: end,
      );

      expect(tool.callId, equals('call_1'));
      expect(tool.toolName, equals('web_search'));
      expect(tool.durationMs, equals(1500));

      final updated = tool.copyWith(
        status: AdkToolStatus.error,
        errorMessage: 'failed',
      );
      expect(updated.status, equals(AdkToolStatus.error));
      expect(updated.errorMessage, equals('failed'));
    });
  });

  group('AdkWorkflowStep Model Tests', () {
    test('instantiates and calculates duration', () {
      final start = DateTime(2026, 1, 1, 10, 0, 0);
      final end = DateTime(2026, 1, 1, 10, 0, 2);

      final step = AdkWorkflowStep(
        id: 'node_1',
        label: 'Fetch Data',
        description: 'Fetches raw data',
        status: AdkStepStatus.running,
        startTime: start,
        endTime: end,
      );

      expect(step.id, equals('node_1'));
      expect(step.label, equals('Fetch Data'));
      expect(step.description, equals('Fetches raw data'));
      expect(step.durationMs, equals(2000));

      final updated = step.copyWith(
        status: AdkStepStatus.completed,
        output: {'status': 'ok'},
      );
      expect(updated.status, equals(AdkStepStatus.completed));
      expect(updated.output, equals({'status': 'ok'}));
    });
  });

  group('AdkSessionInfo Model Tests', () {
    test('instantiates and copyWith', () {
      final now = DateTime.now();
      final session = AdkSessionInfo(
        id: 'session_1',
        title: 'Project Planning',
        createdAt: now,
        updatedAt: now,
        lastMessagePreview: 'Let us start',
        messageCount: 10,
        metadata: const {'tag': 'planning'},
      );

      expect(session.id, equals('session_1'));
      expect(session.title, equals('Project Planning'));
      expect(session.messageCount, equals(10));

      final updated = session.copyWith(
        title: 'Updated Planning',
        messageCount: 11,
      );
      expect(updated.title, equals('Updated Planning'));
      expect(updated.messageCount, equals(11));
    });
  });

  group('AdkPromptSuggestion Model Tests', () {
    test('displayLabel falls back to text when label is null', () {
      const s1 = AdkPromptSuggestion(text: 'Full prompt text');
      expect(s1.displayLabel, equals('Full prompt text'));

      const s2 = AdkPromptSuggestion(
        text: 'Full prompt text',
        label: 'Short Label',
        icon: Icons.star,
        category: 'code',
      );
      expect(s2.displayLabel, equals('Short Label'));
      expect(s2.icon, equals(Icons.star));
      expect(s2.category, equals('code'));
    });
  });

  group('AdkTokenUsage Model Tests', () {
    test('formats token count correctly', () {
      const usage1 = AdkTokenUsage(
        promptTokens: 400,
        completionTokens: 200,
        totalTokens: 600,
        latencyMs: 120,
      );
      expect(usage1.formattedTotal, equals('600'));
      expect(usage1.latencyMs, equals(120));

      const usage2 = AdkTokenUsage(
        promptTokens: 1500,
        completionTokens: 1000,
        totalTokens: 2500,
      );
      expect(usage2.formattedTotal, equals('2.5k'));

      final updated = usage2.copyWith(totalTokens: 3000);
      expect(updated.totalTokens, equals(3000));
    });
  });

  group('AdkVoiceState Model Tests', () {
    test('isActive checks state correctly', () {
      const idle = AdkVoiceState(status: AdkVoiceStatus.idle);
      expect(idle.isActive, isFalse);

      const listening = AdkVoiceState(
        status: AdkVoiceStatus.listening,
        decibels: 0.5,
      );
      expect(listening.isActive, isTrue);

      const processing = AdkVoiceState(status: AdkVoiceStatus.processing);
      expect(processing.isActive, isTrue);

      const speaking = AdkVoiceState(status: AdkVoiceStatus.speaking);
      expect(speaking.isActive, isTrue);

      const error = AdkVoiceState(
        status: AdkVoiceStatus.error,
        errorMessage: 'Microphone permission denied',
      );
      expect(error.isActive, isFalse);
      expect(error.errorMessage, equals('Microphone permission denied'));

      final updated = idle.copyWith(status: AdkVoiceStatus.listening, isMuted: true);
      expect(updated.status, equals(AdkVoiceStatus.listening));
      expect(updated.isMuted, isTrue);
    });
  });
}
