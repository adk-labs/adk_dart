/// Execution mode constants for ADK agents.
library;

/// Defines how an agent interacts with session history and control flow.
enum AgentMode {
  /// Standard multi-turn conversational mode.
  chat('chat'),

  /// Delegated task mode with isolated execution context.
  task('task'),

  /// Single-turn workflow node mode that only sees current-turn node events.
  singleTurn('single_turn');

  /// Creates an agent execution mode with its wire [value].
  const AgentMode(this.value);

  /// Wire string representation of this mode.
  final String value;
}

/// Agent modes that represent delegated task execution rather than chat.
const Set<String> delegatedTaskModes = <String>{'task', 'single_turn'};
