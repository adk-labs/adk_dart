import '../types/content.dart';
import 'llm_request.dart';
import 'llm_response.dart';

abstract class BaseLlm {
  BaseLlm({required this.model});

  String model;

  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  });

  void maybeAppendUserContent(LlmRequest request) {
    if (request.contents.isEmpty) {
      request.contents.add(
        Content.userText(
          'Handle the requests as specified in the system instruction.',
        ),
      );
      return;
    }

    if (request.contents.last.role != 'user') {
      request.contents.add(
        Content.userText(
          'Continue processing previous requests as instructed.',
        ),
      );
    }
  }
}
