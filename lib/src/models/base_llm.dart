import '../types/content.dart';
import 'llm_request.dart';
import 'llm_response.dart';

/// Base interface for model adapters used by the runner.
abstract class BaseLlm {
  /// Creates an LLM adapter bound to [model].
  BaseLlm({required this.model});

  /// The model identifier sent to the backend.
  String model;

  /// Generates model responses for [request].
  ///
  /// When [stream] is true, implementations may emit partial responses.
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  });

  /// Appends a fallback user turn when [request] has no trailing user content.
  void maybeAppendUserContent(LlmRequest request) {
    if (request.contents.isEmpty) {
      request.contents.add(
        Content.userText(
          'Handle the requests as specified in the System Instruction.',
        ),
      );
      return;
    }

    if (request.contents.last.role != 'user') {
      request.contents.add(
        Content.userText(
          'Continue processing previous requests as instructed. Exit or provide a summary if no more outputs are needed.',
        ),
      );
    }
  }
}
