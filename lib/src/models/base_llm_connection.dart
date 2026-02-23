import '../types/content.dart';
import 'llm_response.dart';

class RealtimeBlob {
  RealtimeBlob({required this.mimeType, required this.data});

  final String mimeType;
  final List<int> data;
}

abstract class BaseLlmConnection {
  Future<void> sendHistory(List<Content> history);

  Future<void> sendContent(Content content);

  Future<void> sendRealtime(RealtimeBlob blob);

  Stream<LlmResponse> receive();

  Future<void> close();
}
