import 'agent_transfer.dart';
import 'single_flow.dart';

class AutoFlow extends SingleFlow {
  AutoFlow() : super() {
    requestProcessors.add(AgentTransferLlmRequestProcessor());
  }
}
