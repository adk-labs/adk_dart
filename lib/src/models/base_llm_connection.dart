import '../types/content.dart';
import 'llm_response.dart';

/// Binary payload sent over realtime model transports.
class RealtimeBlob {
  /// Creates a realtime blob with [mimeType] and binary [data].
  RealtimeBlob({required this.mimeType, required this.data});

  /// MIME type describing [data].
  final String mimeType;

  /// Raw binary payload.
  final List<int> data;
}

/// Bidirectional connection contract for realtime model sessions.
abstract class BaseLlmConnection {
  /// Sends prior conversation [history] to initialize the session.
  Future<void> sendHistory(List<Content> history);

  /// Sends one content message to the model connection.
  Future<void> sendContent(Content content);

  /// Sends realtime binary [blob] content to the model connection.
  Future<void> sendRealtime(RealtimeBlob blob);

  /// Receives responses emitted by the model connection.
  Stream<LlmResponse> receive();

  /// Closes the underlying model connection.
  Future<void> close();
}
