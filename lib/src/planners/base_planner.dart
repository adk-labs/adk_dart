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

abstract class BasePlanner {
  PlanningResult plan(PlanningRequest request);
}
