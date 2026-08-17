import 'package:adk_dart/adk_core.dart' as adk;
import 'package:flutter_adk/flutter_adk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdkWorkflowController Tests', () {
    test('manages workflow step statuses, progress, and manual resets', () async {
      final agent = adk.LlmAgent(name: 'wf_agent', instruction: 'test');
      final steps = [
        const AdkWorkflowStep(id: 's1', label: 'Step 1'),
        const AdkWorkflowStep(id: 's2', label: 'Step 2'),
      ];

      final ctrl = AdkWorkflowController(
        workflowAgent: agent,
        initialSteps: steps,
      );

      expect(ctrl.steps.length, equals(2));
      expect(ctrl.progress, equals(0.0));
      expect(ctrl.isCompleted, isFalse);

      ctrl.setStepStatus('s1', AdkStepStatus.completed, output: 'Done 1');
      expect(ctrl.progress, equals(0.5));
      expect(ctrl.steps.first.output, equals('Done 1'));

      ctrl.setStepStatus('s2', AdkStepStatus.completed, output: 'Done 2');
      expect(ctrl.progress, equals(1.0));
      expect(ctrl.isCompleted, isTrue);

      ctrl.reset();
      expect(ctrl.progress, equals(0.0));
      expect(ctrl.steps.first.status, equals(AdkStepStatus.pending));
    });
  });

  group('AdkVoiceController Tests', () {
    test('manages voice listening, speaking, amplitude and transcripts', () async {
      final ctrl = AdkVoiceController();

      expect(ctrl.state.status, equals(AdkVoiceStatus.idle));
      expect(ctrl.isListening, isFalse);

      await ctrl.startListening();
      expect(ctrl.isListening, isTrue);

      ctrl.updateAmplitude(0.75);
      expect(ctrl.decibels, equals(0.75));

      ctrl.updateUserTranscript('Hello agent');
      expect(ctrl.userTranscript, equals('Hello agent'));

      ctrl.toggleMute();
      expect(ctrl.isMuted, isTrue);

      await ctrl.stopListening();
      expect(ctrl.state.status, equals(AdkVoiceStatus.processing));

      ctrl.startSpeaking(text: 'Hello user');
      expect(ctrl.isSpeaking, isTrue);
      expect(ctrl.agentTranscript, equals('Hello user'));

      ctrl.interrupt();
      expect(ctrl.state.status, equals(AdkVoiceStatus.idle));
    });
  });

  group('AdkSessionController Tests', () {
    test('creates, switches, renames, and filters sessions with storage sync', () async {
      final storage = AdkMemoryStorage();
      final ctrl = AdkSessionController(storage: storage);

      await ctrl.loadAllSessions();
      expect(ctrl.sessions, isEmpty);

      final s1 = await ctrl.createNewSession(title: 'Chat 1');
      final s2 = await ctrl.createNewSession(title: 'Travel Planning');

      expect(ctrl.sessions.length, equals(2));
      expect(ctrl.activeSessionId, equals(s2.id));

      ctrl.switchSession(s1.id);
      expect(ctrl.activeSessionId, equals(s1.id));

      await ctrl.updateSessionTitle(s1.id, 'Renamed Chat');
      expect(ctrl.activeSession?.title, equals('Renamed Chat'));

      ctrl.setSearchQuery('Travel');
      expect(ctrl.filteredSessions.length, equals(1));
      expect(ctrl.filteredSessions.first.title, equals('Travel Planning'));

      await ctrl.deleteSession(s2.id);
      expect(ctrl.sessions.length, equals(1));

      await ctrl.clearAllSessions();
      expect(ctrl.sessions, isEmpty);
    });
  });

  group('AdkSmartFormController Tests', () {
    test('updates fields, validates required values, and triggers submission', () async {
      Map<String, String>? submittedData;

      final ctrl = AdkSmartFormController(
        initialFields: const [
          AdkFormField(key: 'username', label: 'Username', isRequired: true),
          AdkFormField(key: 'age', label: 'Age', isRequired: false),
        ],
        onSubmitted: (data) => submittedData = data,
      );

      expect(ctrl.isReady, isFalse);
      expect(ctrl.progress, equals(0.0));

      final missing = ctrl.validate();
      expect(missing, contains('username'));

      ctrl.populateFromMap({'username': 'dev_user', 'age': '28'});
      expect(ctrl.isReady, isTrue);
      expect(ctrl.progress, equals(1.0));

      final success = await ctrl.submit();
      expect(success, isTrue);
      expect(submittedData?['username'], equals('dev_user'));
      expect(submittedData?['age'], equals('28'));
    });
  });

  group('AdkAgentLoggerController Tests', () {
    test('buffers logs, filters by category/search, and exports JSON', () {
      final ctrl = AdkAgentLoggerController(maxLogEntries: 10);

      ctrl.addLog(
        AdkAgentLogEntry(
          id: '1',
          timestamp: DateTime.now(),
          agentName: 'researcher',
          category: AdkLogCategory.toolCall,
          title: 'Search Google',
          payload: {'query': 'Flutter ADK'},
        ),
      );

      ctrl.addLog(
        AdkAgentLogEntry(
          id: '2',
          timestamp: DateTime.now(),
          agentName: 'writer',
          category: AdkLogCategory.modelResponse,
          title: 'Article summary',
          payload: {'text': 'Here is the summary'},
        ),
      );

      expect(ctrl.logs.length, equals(2));

      ctrl.setCategory(AdkLogCategory.toolCall);
      expect(ctrl.filteredLogs.length, equals(1));
      expect(ctrl.filteredLogs.first.title, equals('Search Google'));

      ctrl.setCategory(AdkLogCategory.all);
      ctrl.setSearchQuery('summary');
      expect(ctrl.filteredLogs.length, equals(1));
      expect(ctrl.filteredLogs.first.agentName, equals('writer'));

      final String jsonStr = ctrl.exportJson(pretty: true);
      expect(jsonStr, contains('Search Google'));
      expect(jsonStr, contains('Article summary'));

      ctrl.clearLogs();
      expect(ctrl.logs, isEmpty);
    });
  });
}
