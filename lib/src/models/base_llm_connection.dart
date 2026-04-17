/// Realtime model connection interfaces and payload models.
library;

import '../types/content.dart';
import 'llm_response.dart';

/// Recoverable failure raised by live connections when reconnection is possible.
class RecoverableLiveConnectionException implements Exception {
  /// Creates a recoverable live connection exception.
  RecoverableLiveConnectionException(this.cause, {this.code});

  /// Underlying failure object from the transport layer.
  final Object cause;

  /// Optional backend-specific status or close code.
  final int? code;

  @override
  String toString() {
    if (code == null) {
      return 'RecoverableLiveConnectionException: $cause';
    }
    return 'RecoverableLiveConnectionException(code: $code, cause: $cause)';
  }
}

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
