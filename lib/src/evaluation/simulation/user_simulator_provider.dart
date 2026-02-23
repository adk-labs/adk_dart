import '../eval_case.dart';
import '../eval_config.dart';
import 'llm_backed_user_simulator.dart';
import 'static_user_simulator.dart';
import 'user_simulator.dart';

class UserSimulatorProvider {
  UserSimulatorProvider({BaseUserSimulatorConfig? userSimulatorConfig})
    : _userSimulatorConfig = userSimulatorConfig ?? BaseUserSimulatorConfig();

  final BaseUserSimulatorConfig _userSimulatorConfig;

  UserSimulator provide(EvalCase evalCase) {
    if (evalCase.conversation == null) {
      if (evalCase.conversationScenario == null) {
        throw ArgumentError(
          'Neither static invocations nor conversation scenario provided in '
          'EvalCase. Provide exactly one.',
        );
      }
      return LlmBackedUserSimulator(
        config: _userSimulatorConfig,
        conversationScenario: evalCase.conversationScenario!,
      );
    }

    if (evalCase.conversationScenario != null) {
      throw ArgumentError(
        'Both static invocations and conversation scenario provided in '
        'EvalCase. Provide exactly one.',
      );
    }

    return StaticUserSimulator(staticConversation: evalCase.conversation!);
  }
}
