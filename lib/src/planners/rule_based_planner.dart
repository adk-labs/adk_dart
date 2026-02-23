/// Legacy utility planner retained for compatibility with early adk_dart APIs.
///
/// For Python parity planners, use `BuiltInPlanner` or `PlanReActPlanner`.
class PlanningRequest {
  PlanningRequest({required this.goal, List<String>? context})
    : context = context ?? <String>[];

  final String goal;
  final List<String> context;
}

class PlanningStep {
  PlanningStep({required this.title, this.reason});

  final String title;
  final String? reason;
}

class PlanningResult {
  PlanningResult({List<PlanningStep>? steps})
    : steps = steps ?? <PlanningStep>[];

  final List<PlanningStep> steps;
}

class RuleBasedPlanner {
  PlanningResult plan(PlanningRequest request) {
    final List<PlanningStep> steps = <PlanningStep>[
      PlanningStep(title: 'Understand goal', reason: request.goal),
      PlanningStep(
        title: 'Collect required context',
        reason: 'Gather data needed before execution.',
      ),
      PlanningStep(
        title: 'Execute and verify',
        reason: 'Run tasks and validate outputs.',
      ),
    ];

    if (request.context.isNotEmpty) {
      steps.insert(
        1,
        PlanningStep(
          title: 'Process provided context',
          reason: request.context.join('; '),
        ),
      );
    }

    return PlanningResult(steps: steps);
  }
}
