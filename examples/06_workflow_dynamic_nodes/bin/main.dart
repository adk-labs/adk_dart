import 'dart:io';
import 'package:adk_dart/adk_dart.dart';

// 1. Define agents that will be called dynamically
final Agent generateHeadline = Agent(
  name: 'generate_headline',
  model: 'gemini-3.7-flash',
  instruction: '''
Write a short, engaging news headline about the given topic.
If feedback is provided, improve the headline to resolve it.
Topic: {input}
Feedback: {feedback?}
''',
);

final Agent evaluateHeadline = Agent(
  name: 'evaluate_headline',
  model: 'gemini-3.7-flash',
  instruction: '''
Grade whether the given headline is related to technology or software engineering.
Respond with a JSON object conforming to the schema:
{
  "grade": "tech-related" | "unrelated",
  "feedback": "If unrelated, explain how to make it tech-focused. Otherwise leave empty."
}
''',
  outputKey: 'evaluation',
);

// 2. Define the orchestrator function node using WorkflowContext.runNode
final FunctionNode orchestrator = node(
  (WorkflowContext context, Object? input) async {
    final String topic = input as String;
    String? feedback;
    int attempt = 1;

    while (true) {
      print('\n[Orchestrator] Attempt #$attempt: Generating headline for "$topic"...');
      
      // Run generate_headline dynamically
      final Object? headline = await context.runNode(
        generateHeadline,
        input: <String, Object?>{
          'input': topic,
          'feedback': ?feedback,
        },
      );
      print('[GenerateAgent] Generated: "$headline"');

      print('[Orchestrator] Evaluating headline...');
      // Run evaluate_headline dynamically, passing the generated headline
      final Object? evaluationRaw = await context.runNode(
        evaluateHeadline,
        input: headline,
      );
      print('[EvaluateAgent] Evaluation: $evaluationRaw');

      // Parse the response safely
      final String evaluationStr = evaluationRaw.toString().toLowerCase();
      if (evaluationStr.contains('tech-related') || evaluationStr.contains('tech')) {
        print('[Orchestrator] Headline approved!');
        return headline;
      } else {
        feedback = 'Make it more related to technology, coding, or AI.';
        print('[Orchestrator] Feedback provided: "$feedback". Retrying...');
        attempt += 1;
        if (attempt > 3) {
          print('[Orchestrator] Max attempts reached. Returning last result.');
          return headline;
        }
      }
    }
  },
  name: 'orchestrator',
  rerunOnResume: true,
);

Future<void> main() async {
  final String? apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Set GEMINI_API_KEY before running this example.');
    return;
  }

  // Define the workflow graph
  final Workflow workflow = Workflow(
    name: 'dynamic_orchestration_workflow',
    nodes: <BaseNode>[
      orchestrator,
    ],
  );

  print('Running dynamic orchestration workflow. Topic: "Artificial Intelligence"');

  final WorkflowResult result = await workflow.runWorkflow(input: 'Artificial Intelligence');

  print('\n--- Workflow Complete ---');
  print('Final approved headline: ${result.outputs['orchestrator']}');
}
