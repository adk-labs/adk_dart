import '../../agents/invocation_context.dart';
import '../../events/event.dart';

class TranscriptionManager {
  Future<Event> handleInputTranscription(
    InvocationContext invocationContext,
    Object transcription,
  ) async {
    return _createAndSaveTranscriptionEvent(
      invocationContext: invocationContext,
      transcription: transcription,
      author: 'user',
      isInput: true,
    );
  }

  Future<Event> handleOutputTranscription(
    InvocationContext invocationContext,
    Object transcription,
  ) async {
    return _createAndSaveTranscriptionEvent(
      invocationContext: invocationContext,
      transcription: transcription,
      author: invocationContext.agent.name,
      isInput: false,
    );
  }

  Future<Event> _createAndSaveTranscriptionEvent({
    required InvocationContext invocationContext,
    required Object transcription,
    required String author,
    required bool isInput,
  }) async {
    return Event(
      id: Event.newId(),
      invocationId: invocationContext.invocationId,
      author: author,
      inputTranscription: isInput ? transcription : null,
      outputTranscription: isInput ? null : transcription,
      timestamp: DateTime.now().millisecondsSinceEpoch / 1000,
    );
  }

  Map<String, int> getTranscriptionStats(InvocationContext invocationContext) {
    int inputCount = 0;
    int outputCount = 0;

    for (final Event event in invocationContext.session.events) {
      if (event.inputTranscription != null) {
        inputCount += 1;
      }
      if (event.outputTranscription != null) {
        outputCount += 1;
      }
    }

    return <String, int>{
      'input_transcriptions': inputCount,
      'output_transcriptions': outputCount,
      'total_transcriptions': inputCount + outputCount,
    };
  }
}
