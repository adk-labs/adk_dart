/// Provider that selects user simulator implementations.
library;

import '../eval_case.dart';
import '../eval_config.dart';
import 'llm_backed_user_simulator.dart';
import 'static_user_simulator.dart';
import 'user_simulator.dart';

/// Selects the appropriate simulator implementation for an eval case.
class UserSimulatorProvider {
  /// Creates a simulator provider with optional shared config.
  UserSimulatorProvider({BaseUserSimulatorConfig? userSimulatorConfig})
    : _userSimulatorConfig = userSimulatorConfig ?? BaseUserSimulatorConfig();

  final BaseUserSimulatorConfig _userSimulatorConfig;

  /// Builds a simulator for [evalCase].
  ///
  /// Static conversations use [StaticUserSimulator]. Scenario-based
  /// simulations use [LlmBackedUserSimulator].
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
