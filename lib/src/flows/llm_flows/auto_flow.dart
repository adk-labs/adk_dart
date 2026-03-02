import 'agent_transfer.dart';
import 'single_flow.dart';

/// Default flow that adds automatic agent-transfer request processing.
class AutoFlow extends SingleFlow {
  /// Creates an auto flow with transfer preprocessing enabled.
  AutoFlow() : super() {
    requestProcessors.add(AgentTransferLlmRequestProcessor());
  }
}
