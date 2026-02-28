import '../agents/callback_context.dart';
import '../agents/readonly_context.dart';
import '../models/llm_request.dart';
import '../types/content.dart';
import 'base_planner.dart';

const String planningTag = '/*PLANNING*/';
const String replanningTag = '/*REPLANNING*/';
const String reasoningTag = '/*REASONING*/';
const String actionTag = '/*ACTION*/';
const String finalAnswerTag = '/*FINAL_ANSWER*/';

class PlanReActPlanner extends BasePlanner {
  @override
  String buildPlanningInstruction(
    ReadonlyContext readonlyContext,
    LlmRequest llmRequest,
  ) {
    return _buildNlPlannerInstruction();
  }

  @override
  List<Part>? processPlanningResponse(
    CallbackContext callbackContext,
    List<Part> responseParts,
  ) {
    if (responseParts.isEmpty) {
      return null;
    }

    final List<Part> preservedParts = <Part>[];
    int firstFunctionCallPartIndex = -1;

    for (int i = 0; i < responseParts.length; i += 1) {
      final Part part = responseParts[i];
      if (part.functionCall != null) {
        final String? functionName = part.functionCall?.name;
        if (functionName == null || functionName.isEmpty) {
          continue;
        }
        preservedParts.add(part.copyWith());
        firstFunctionCallPartIndex = i;
        break;
      }

      _handleNonFunctionCallPart(part, preservedParts);
    }

    if (firstFunctionCallPartIndex >= 0) {
      int index = firstFunctionCallPartIndex + 1;
      while (index < responseParts.length) {
        final Part part = responseParts[index];
        if (part.functionCall != null) {
          preservedParts.add(part.copyWith());
          index += 1;
          continue;
        }
        break;
      }
    }

    return preservedParts;
  }

  ({String before, String after}) _splitByLastPattern(
    String text,
    String separator,
  ) {
    final int index = text.lastIndexOf(separator);
    if (index < 0) {
      return (before: text, after: '');
    }
    final int separatorEnd = index + separator.length;
    return (
      before: text.substring(0, separatorEnd),
      after: text.substring(separatorEnd),
    );
  }

  void _handleNonFunctionCallPart(
    Part responsePart,
    List<Part> preservedParts,
  ) {
    final String responseText = responsePart.text ?? '';

    if (responseText.isNotEmpty && responseText.contains(finalAnswerTag)) {
      final ({String before, String after}) split = _splitByLastPattern(
        responseText,
        finalAnswerTag,
      );
      if (split.before.isNotEmpty) {
        final Part reasoningPart = Part.text(split.before);
        _markAsThought(reasoningPart);
        preservedParts.add(reasoningPart);
      }
      if (split.after.isNotEmpty) {
        preservedParts.add(Part.text(split.after));
      }
      return;
    }

    final Part copy = responsePart.copyWith();
    if (responseText.isNotEmpty &&
        (responseText.startsWith(planningTag) ||
            responseText.startsWith(reasoningTag) ||
            responseText.startsWith(actionTag) ||
            responseText.startsWith(replanningTag))) {
      _markAsThought(copy);
    }
    preservedParts.add(copy);
  }

  void _markAsThought(Part responsePart) {
    if (responsePart.text != null) {
      responsePart.thought = true;
    }
  }

  String _buildNlPlannerInstruction() {
    final String highLevelPreamble =
        '''
When answering the question, try to leverage the available tools to gather the information instead of your memorized knowledge.

Follow this process when answering the question: (1) first come up with a plan in natural language text format; (2) Then use tools to execute the plan and provide reasoning between tool code snippets to make a summary of current state and next step. Tool code snippets and reasoning should be interleaved with each other. (3) In the end, return one final answer.

Follow this format when answering the question: (1) The planning part should be under $planningTag. (2) The tool code snippets should be under $actionTag, and the reasoning parts should be under $reasoningTag. (3) The final answer part should be under $finalAnswerTag.
''';

    final String planningPreamble =
        '''
Below are the requirements for the planning:
The plan is made to answer the user query if following the plan. The plan is coherent and covers all aspects of information from user query, and only involves the tools that are accessible by the agent. The plan contains the decomposed steps as a numbered list where each step should use one or multiple available tools. By reading the plan, you can intuitively know which tools to trigger or what actions to take.
If the initial plan cannot be successfully executed, you should learn from previous execution results and revise your plan. The revised plan should be under $replanningTag. Then use tools to follow the new plan.
''';

    final String reasoningPreamble = '''
Below are the requirements for the reasoning:
The reasoning makes a summary of the current trajectory based on the user query and tool outputs. Based on the tool outputs and plan, the reasoning also comes up with instructions to the next steps, making the trajectory closer to the final answer.
''';

    final String finalAnswerPreamble = '''
Below are the requirements for the final answer:
The final answer should be precise and follow query formatting requirements. Some queries may not be answerable with the available tools and information. In those cases, inform the user why you cannot process their query and ask for more information.
''';

    final String toolCodePreamble = '''
Below are the requirements for the tool code:

**Custom Tools:** The available tools are described in the context and can be directly used.
- Code must be valid self-contained Python snippets with no imports and no references to tools or Python libraries that are not in the context.
- You cannot use any parameters or fields that are not explicitly defined in the APIs in the context.
- The code snippets should be readable, efficient, and directly relevant to the user query and reasoning steps.
- When using the tools, you should use the library name together with the function name, e.g., vertex_search.search().
- If Python libraries are not provided in the context, NEVER write your own code other than the function calls using the provided tools.
''';

    final String userInputPreamble = '''
VERY IMPORTANT instruction that you MUST follow in addition to the above instructions:

You should ask for clarification if you need more information to answer the question.
You should prefer using the information available in the context instead of repeated tool use.
''';

    return <String>[
      highLevelPreamble,
      planningPreamble,
      reasoningPreamble,
      finalAnswerPreamble,
      toolCodePreamble,
      userInputPreamble,
    ].join('\n\n');
  }
}
