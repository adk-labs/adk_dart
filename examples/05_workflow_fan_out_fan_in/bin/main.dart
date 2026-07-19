import 'package:adk_dart/adk_dart.dart';

// Define functions to act as workflow nodes
final FunctionNode makeUppercase = node(
  (WorkflowContext _, Object? input) => (input as String).toUpperCase(),
  name: 'makeUppercase',
);

final FunctionNode countCharacters = node(
  (WorkflowContext _, Object? input) => (input as String).length,
  name: 'countCharacters',
);

final FunctionNode reverseString = node(
  (WorkflowContext _, Object? input) => (input as String).split('').reversed.join(''),
  name: 'reverseString',
);

final JoinNode joinNode = JoinNode(
  name: 'joinForResults',
  dependsOn: const <String>['makeUppercase', 'countCharacters', 'reverseString'],
);

final FunctionNode aggregate = node(
  (WorkflowContext _, Object? input) {
    final Map<String, Object?> results = input as Map<String, Object?>;
    return 'Uppercase: ${results['makeUppercase']}\n'
        'Character Count: ${results['countCharacters']}\n'
        'Reversed: ${results['reverseString']}';
  },
  name: 'aggregate',
);

Future<void> main() async {
  final Workflow workflow = Workflow(
    name: 'fan_out_fan_in_workflow',
    nodes: <BaseNode>[
      makeUppercase,
      countCharacters,
      reverseString,
      joinNode,
      aggregate,
    ],
    edges: <Edge>[
      Edge(fromNode: joinNode, toNode: aggregate),
    ],
  );

  print('Running fan-out fan-in workflow with input: "Hello ADK 2.0 Workflow"');

  final WorkflowResult result = await workflow.runWorkflow(input: 'Hello ADK 2.0 Workflow');

  print('\n--- Execution Outputs ---');
  print('makeUppercase output: ${result.outputs['makeUppercase']}');
  print('countCharacters output: ${result.outputs['countCharacters']}');
  print('reverseString output: ${result.outputs['reverseString']}');
  print('joinNode merged output: ${result.outputs['joinForResults']}');
  print('\nFinal aggregated result:\n${result.outputs['aggregate']}');
}
