import 'base_planner.dart';

class RuleBasedPlanner extends BasePlanner {
  @override
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
