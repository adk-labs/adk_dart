import 'package:flutter_adk/flutter_adk.dart';

import 'package:flutter_adk_example/config/app_constants.dart';
import 'package:flutter_adk_example/domain/models/app_language.dart';
import 'package:flutter_adk_example/domain/models/custom_agent_config.dart';
import 'package:flutter_adk_example/domain/models/user_example_connection_dsl.dart';
import 'package:flutter_adk_example/domain/models/user_example_config.dart';

typedef AgentBuilder =
    BaseAgent Function({
      required String apiKey,
      required AppLanguage language,
      required String mcpUrl,
      required String mcpBearerToken,
    });

class AgentService {
  static BaseAgent buildBasic({
    required String apiKey,
    required AppLanguage language,
    required String mcpUrl,
    required String mcpBearerToken,
  }) {
    return Agent(
      name: 'capital_chatbot',
      model: _createGeminiModel(apiKey),
      description: 'Capital-city and general helper chatbot.',
      instruction:
          '''
You are a helpful chatbot.
- If user asks for a country's capital city, use get_capital_city tool first.
- If tool returns known=false, explain that you do not know that country yet.
- For general questions, answer directly.
- Keep answers concise and friendly.
${responseLanguageInstruction(language)}
''',
      tools: <Object>[
        FunctionTool(
          name: 'get_capital_city',
          description: 'Returns the capital city for a given country name.',
          func: ({required String country}) => _lookupCapitalCity(country),
        ),
      ],
    );
  }

  static BaseAgent buildCustom({
    required String apiKey,
    required AppLanguage language,
    required CustomAgentConfig config,
    required String mcpUrl,
    required String mcpBearerToken,
  }) {
    return _buildConfigAgent(
      apiKey: apiKey,
      language: language,
      config: config,
      fallbackName: 'CustomAgent',
      fallbackDescription: 'User-configured custom agent.',
    );
  }

  static BaseAgent buildUserDefinedExample({
    required String apiKey,
    required AppLanguage language,
    required UserExampleConfig config,
    required String mcpUrl,
    required String mcpBearerToken,
  }) {
    final List<CustomAgentConfig> nodeConfigs = config.agents.isEmpty
        ? <CustomAgentConfig>[CustomAgentConfig.defaults()]
        : config.agents;
    final List<int> orderedIndexes = _orderedNodeIndexes(
      config: config,
      totalNodes: nodeConfigs.length,
    );
    final List<Agent> nodes = nodeConfigs
        .asMap()
        .entries
        .map((entry) {
          final int index = entry.key;
          final CustomAgentConfig node = entry.value;
          return _buildConfigAgent(
            apiKey: apiKey,
            language: language,
            config: node,
            fallbackName: 'NodeAgent${index + 1}',
            fallbackDescription: 'User-defined node agent ${index + 1}.',
          );
        })
        .toList(growable: false);

    switch (config.architecture) {
      case UserExampleArchitecture.single:
        return nodes[orderedIndexes.first];
      case UserExampleArchitecture.team:
        return _buildUserTeamCoordinator(
          apiKey: apiKey,
          language: language,
          config: config,
          nodes: nodes,
          orderedIndexes: orderedIndexes,
        );
      case UserExampleArchitecture.sequential:
        return SequentialAgent(
          name: _normalizeName(config.title, fallback: 'UserSequentialFlow'),
          description: config.summary,
          subAgents: orderedIndexes
              .map((int index) => nodes[index])
              .toList(growable: false),
        );
      case UserExampleArchitecture.parallel:
        return _buildUserParallelPipeline(
          apiKey: apiKey,
          language: language,
          config: config,
          nodeConfigs: nodeConfigs,
          orderedIndexes: orderedIndexes,
        );
      case UserExampleArchitecture.loop:
        return _buildUserLoopPipeline(
          apiKey: apiKey,
          language: language,
          config: config,
          nodeConfigs: nodeConfigs,
          orderedIndexes: orderedIndexes,
        );
    }
  }

  static Agent _buildConfigAgent({
    required String apiKey,
    required AppLanguage language,
    required CustomAgentConfig config,
    required String fallbackName,
    required String fallbackDescription,
    String? outputKey,
  }) {
    final List<Object> tools = _buildCommonTools(
      config: config,
      language: language,
    );
    final String toolGuide = tools.isEmpty
        ? '- No tools are enabled. Answer with general reasoning only.'
        : '- Use enabled tools when relevant and provide concise, factual answers.';
    return Agent(
      name: _normalizeName(config.name, fallback: fallbackName),
      model: _createGeminiModel(apiKey),
      description: config.description.trim().isEmpty
          ? fallbackDescription
          : config.description.trim(),
      instruction:
          '''
${config.instruction}
$toolGuide
${responseLanguageInstruction(language)}
''',
      tools: tools,
      outputKey: outputKey,
    );
  }

  static List<Object> _buildCommonTools({
    required CustomAgentConfig config,
    required AppLanguage language,
  }) {
    final List<Object> tools = <Object>[];
    if (config.enableCapitalTool) {
      tools.add(
        FunctionTool(
          name: 'get_capital_city',
          description: 'Returns the capital city for a given country name.',
          func: ({required String country}) => _lookupCapitalCity(country),
        ),
      );
    }
    if (config.enableWeatherTool) {
      tools.add(
        FunctionTool(
          name: 'get_weather',
          description: 'Returns weather report for a city.',
          func: ({String? city, String? location}) {
            final String? resolved = _resolveCityArg(
              city: city,
              location: location,
            );
            if (resolved == null) {
              return <String, Object?>{
                'status': 'error',
                'error_message': _localizedMissingCity(language),
              };
            }
            return _lookupTeamWeather(resolved, language);
          },
        ),
      );
    }
    if (config.enableTimeTool) {
      tools.add(
        FunctionTool(
          name: 'get_current_time',
          description: 'Returns current local time for a city.',
          func: ({String? city, String? location}) {
            final String? resolved = _resolveCityArg(
              city: city,
              location: location,
            );
            if (resolved == null) {
              return <String, Object?>{
                'status': 'error',
                'error_message': _localizedMissingCity(language),
              };
            }
            return _lookupTeamCurrentTime(resolved, language);
          },
        ),
      );
    }
    return tools;
  }

  static BaseAgent _buildUserTeamCoordinator({
    required String apiKey,
    required AppLanguage language,
    required UserExampleConfig config,
    required List<Agent> nodes,
    required List<int> orderedIndexes,
  }) {
    final int entryIndex = orderedIndexes.first;
    final StringBuffer specialties = StringBuffer();
    for (int i = 0; i < nodes.length; i++) {
      final Agent node = nodes[i];
      final String entryMarker = i == entryIndex ? ' (entry)' : '';
      specialties.writeln(
        '- [A$i] ${node.name}$entryMarker: ${node.description}',
      );
    }

    final List<UserExampleConnection> entryEdges = config.connections
        .where(
          (UserExampleConnection item) =>
              item.fromIndex == entryIndex &&
              item.toIndex >= 0 &&
              item.toIndex < nodes.length &&
              item.toIndex != entryIndex,
        )
        .toList(growable: false);
    final StringBuffer routingRules = StringBuffer();
    if (entryEdges.isEmpty) {
      routingRules.writeln('- No explicit entry routing rules.');
    } else {
      for (final UserExampleConnection edge in entryEdges) {
        final UserExampleConnectionDsl parsed = UserExampleConnectionDsl.parse(
          edge.condition,
        );
        final String condition = _dslRuleToCoordinatorPhrase(parsed);
        routingRules.writeln(
          '- $condition => transfer_to_agent ${nodes[edge.toIndex].name}',
        );
      }
    }

    final String entryAgentName = nodes[entryIndex].name;
    return Agent(
      name: _normalizeName(config.title, fallback: 'UserTeamCoordinator'),
      model: _createGeminiModel(apiKey),
      description: config.summary,
      instruction:
          '''
You are a team coordinator for user-defined agents.
Available specialists:
${specialties.toString()}

Entry agent: $entryAgentName
Entry routing rules:
${routingRules.toString()}

DSL semantics:
- always: unconditional route
- intent:<name>: route when primary intent matches name
- contains:<keyword>: route when user message includes keyword (case-insensitive)

Rules:
- Prefer one transfer_to_agent call per user turn.
- Apply entry routing rules first when possible.
- If no explicit rule matches, route to $entryAgentName or the best matching specialist.
- Prefer exactly one transfer_to_agent per turn.
- If intent is ambiguous, ask one short clarifying question.
- Do not solve the request yourself after routing.
${responseLanguageInstruction(language)}
''',
      subAgents: nodes,
    );
  }

  static BaseAgent _buildUserParallelPipeline({
    required String apiKey,
    required AppLanguage language,
    required UserExampleConfig config,
    required List<CustomAgentConfig> nodeConfigs,
    required List<int> orderedIndexes,
  }) {
    final StringBuffer inputs = StringBuffer();
    final List<Agent> parallelNodes = <Agent>[];
    for (int i = 0; i < orderedIndexes.length; i++) {
      final int index = orderedIndexes[i];
      final CustomAgentConfig nodeConfig = nodeConfigs[index];
      final Agent node = _buildConfigAgent(
        apiKey: apiKey,
        language: language,
        config: nodeConfig,
        fallbackName: 'ParallelNode${i + 1}',
        fallbackDescription: 'User parallel node ${i + 1}.',
        outputKey: 'user_parallel_${i + 1}_result',
      );
      parallelNodes.add(node);
      inputs.writeln(
        '- Node ${i + 1} (${node.name}) output: {user_parallel_${i + 1}_result}',
      );
    }
    final ParallelAgent parallel = ParallelAgent(
      name: _normalizeName('${config.title}Parallel', fallback: 'UserParallel'),
      description: 'User-defined parallel nodes',
      subAgents: parallelNodes,
    );
    final Agent synth = Agent(
      name: _normalizeName('${config.title}Synth', fallback: 'UserSynthesizer'),
      model: _createGeminiModel(apiKey),
      description: 'Synthesize parallel outputs from user-defined nodes.',
      instruction:
          '''
Synthesize results from parallel nodes:
${inputs.toString()}

Provide one coherent final answer grounded only on those node outputs.
${responseLanguageInstruction(language)}
''',
    );
    return SequentialAgent(
      name: _normalizeName(config.title, fallback: 'UserParallelPipeline'),
      description: config.summary,
      subAgents: <BaseAgent>[parallel, synth],
    );
  }

  static BaseAgent _buildUserLoopPipeline({
    required String apiKey,
    required AppLanguage language,
    required UserExampleConfig config,
    required List<CustomAgentConfig> nodeConfigs,
    required List<int> orderedIndexes,
  }) {
    final List<Agent> loopNodes = <Agent>[];
    for (int i = 0; i < orderedIndexes.length; i++) {
      final int index = orderedIndexes[i];
      final CustomAgentConfig nodeConfig = nodeConfigs[index];
      loopNodes.add(
        _buildConfigAgent(
          apiKey: apiKey,
          language: language,
          config: nodeConfig,
          fallbackName: 'LoopNode${i + 1}',
          fallbackDescription: 'User loop node ${i + 1}.',
          outputKey: 'user_loop_${i + 1}_result',
        ),
      );
    }

    final LoopAgent loop = LoopAgent(
      name: _normalizeName('${config.title}Loop', fallback: 'UserLoop'),
      description: 'User-defined iterative loop',
      maxIterations: 3,
      subAgents: loopNodes,
    );
    final StringBuffer outputs = StringBuffer();
    for (int i = 0; i < loopNodes.length; i++) {
      outputs.writeln(
        '- Node ${i + 1} (${loopNodes[i].name}) latest output: {user_loop_${i + 1}_result}',
      );
    }
    final Agent finalizer = Agent(
      name: _normalizeName('${config.title}Final', fallback: 'UserLoopFinal'),
      model: _createGeminiModel(apiKey),
      description: 'Finalize loop outputs into one response.',
      instruction:
          '''
Finalize this loop run:
${outputs.toString()}

Return one concise final response.
${responseLanguageInstruction(language)}
''',
    );
    return SequentialAgent(
      name: _normalizeName(config.title, fallback: 'UserLoopPipeline'),
      description: config.summary,
      subAgents: <BaseAgent>[loop, finalizer],
    );
  }

  static String _normalizeName(String raw, {required String fallback}) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return fallback;
    }
    final String compact = trimmed.replaceAll(RegExp(r'\s+'), '_');
    return compact.length > 64 ? compact.substring(0, 64) : compact;
  }

  static String _dslRuleToCoordinatorPhrase(UserExampleConnectionDsl parsed) {
    switch (parsed.type) {
      case UserExampleConnectionDslType.always:
        return 'always';
      case UserExampleConnectionDslType.intent:
        return 'intent:${parsed.value}';
      case UserExampleConnectionDslType.contains:
        return 'contains:${parsed.value}';
      case UserExampleConnectionDslType.unknown:
        if (parsed.raw.trim().isEmpty) {
          return 'always';
        }
        return 'hint("${parsed.raw.trim()}")';
    }
  }

  static List<int> _orderedNodeIndexes({
    required UserExampleConfig config,
    required int totalNodes,
  }) {
    if (totalNodes <= 0) {
      return <int>[0];
    }
    final int entry =
        config.entryAgentIndex < 0 || config.entryAgentIndex >= totalNodes
        ? 0
        : config.entryAgentIndex;
    final Map<int, List<UserExampleConnection>> edges =
        <int, List<UserExampleConnection>>{};
    for (final UserExampleConnection edge in config.connections) {
      if (edge.fromIndex < 0 ||
          edge.fromIndex >= totalNodes ||
          edge.toIndex < 0 ||
          edge.toIndex >= totalNodes ||
          edge.fromIndex == edge.toIndex) {
        continue;
      }
      edges
          .putIfAbsent(edge.fromIndex, () => <UserExampleConnection>[])
          .add(edge);
    }
    final List<int> order = <int>[entry];
    final Set<int> visited = <int>{entry};
    int current = entry;
    while (true) {
      final List<UserExampleConnection> nextEdges =
          edges[current] ?? const <UserExampleConnection>[];
      UserExampleConnection? candidate;
      for (final UserExampleConnection edge in nextEdges) {
        if (!visited.contains(edge.toIndex)) {
          candidate = edge;
          break;
        }
      }
      if (candidate == null) {
        break;
      }
      current = candidate.toIndex;
      visited.add(current);
      order.add(current);
      if (order.length >= totalNodes) {
        break;
      }
    }
    for (int i = 0; i < totalNodes; i++) {
      if (!visited.contains(i)) {
        order.add(i);
      }
    }
    return order;
  }

  static BaseAgent buildTransfer({
    required String apiKey,
    required AppLanguage language,
    required String mcpUrl,
    required String mcpBearerToken,
  }) {
    final Agent billingAgent = Agent(
      name: 'Billing',
      model: _createGeminiModel(apiKey),
      description: 'Handles billing inquiries and payment issues.',
      instruction:
          '''
You are the Billing specialist.
- Handle invoices, charges, payments, refunds, and subscription billing.
- If required details are missing, ask concise follow-up questions.
- If the issue is not billing-related, clearly say this team handles billing only.
${responseLanguageInstruction(language)}
''',
    );

    final Agent supportAgent = Agent(
      name: 'Support',
      model: _createGeminiModel(apiKey),
      description: 'Handles technical support and account access issues.',
      instruction:
          '''
You are the Support specialist.
- Handle login failures, app errors, account access, and technical troubleshooting.
- Give practical, step-by-step guidance.
- If the issue is purely billing-related, say this team handles technical issues only.
${responseLanguageInstruction(language)}
''',
    );

    return Agent(
      name: 'HelpDeskCoordinator',
      model: _createGeminiModel(apiKey),
      description: 'Main help desk router.',
      instruction:
          '''
You are a help desk coordinator.
- For EVERY user turn, call classify_helpdesk_intent first using the latest user message.
- If route is Support, immediately call transfer_to_agent to Support.
- If route is Billing, immediately call transfer_to_agent to Billing.
- If route is Ambiguous, ask exactly one short clarification question to choose Support(login/app/account) or Billing(payment/refund).
- If user gives a short follow-up like "로그인이요", "결제요", "login", "billing", route immediately without asking again.
- If route is Unknown, ask one short clarification question.
- Do not solve the issue yourself after routing. The selected specialist should provide the final answer.
${responseLanguageInstruction(language)}
''',
      tools: <Object>[
        FunctionTool(
          name: 'classify_helpdesk_intent',
          description:
              'Classifies a user message into Support, Billing, Ambiguous, or Unknown.',
          func: ({required String userMessage}) =>
              _classifyHelpdeskIntent(userMessage: userMessage),
        ),
      ],
      subAgents: <BaseAgent>[billingAgent, supportAgent],
    );
  }

  static BaseAgent buildWorkflow({
    required String apiKey,
    required AppLanguage language,
    required String mcpUrl,
    required String mcpBearerToken,
  }) {
    final Agent summarize = Agent(
      name: 'SummarizeInput',
      model: _createGeminiModel(apiKey),
      instruction:
          '''
Read the latest user message and write a short summary.
- Keep it under 2 sentences.
- Save concise output for downstream steps.
${responseLanguageInstruction(language)}
''',
      outputKey: 'task_summary',
    );

    final Agent angleProduct = Agent(
      name: 'ProductAngle',
      model: _createGeminiModel(apiKey),
      instruction:
          '''
Based on {task_summary}, provide product/feature perspective recommendations.
- Keep it concise.
${responseLanguageInstruction(language)}
''',
      outputKey: 'angle_product',
    );

    final Agent angleUser = Agent(
      name: 'UserAngle',
      model: _createGeminiModel(apiKey),
      instruction:
          '''
Based on {task_summary}, provide user-experience perspective recommendations.
- Keep it concise.
${responseLanguageInstruction(language)}
''',
      outputKey: 'angle_user',
    );

    final ParallelAgent parallel = ParallelAgent(
      name: 'ParallelAngles',
      subAgents: <BaseAgent>[angleProduct, angleUser],
    );

    final Agent refineOnce = Agent(
      name: 'RefineDraft',
      model: _createGeminiModel(apiKey),
      instruction:
          '''
Combine {angle_product} and {angle_user} into a cleaner draft answer.
- Keep actionable bullets.
${responseLanguageInstruction(language)}
''',
      outputKey: 'draft_answer',
    );

    final LoopAgent loop = LoopAgent(
      name: 'SingleLoopRefinement',
      maxIterations: 1,
      subAgents: <BaseAgent>[refineOnce],
    );

    final Agent finalAnswer = Agent(
      name: 'FinalAnswer',
      model: _createGeminiModel(apiKey),
      instruction:
          '''
Return the final response to user using:
- summary: {task_summary}
- draft: {draft_answer}
Output a clear, concise final answer.
${responseLanguageInstruction(language)}
''',
    );

    return SequentialAgent(
      name: 'WorkflowOrchestrator',
      subAgents: <BaseAgent>[summarize, parallel, loop, finalAnswer],
    );
  }

  static BaseAgent buildSequential({
    required String apiKey,
    required AppLanguage language,
    required String mcpUrl,
    required String mcpBearerToken,
  }) {
    final Agent codeWriter = Agent(
      name: 'CodeWriterAgent',
      model: _createGeminiModel(apiKey),
      description: '요청을 기반으로 초기 코드를 작성합니다.',
      instruction:
          '''
You are a code writer.
- Read the latest user request and produce an initial solution.
- Output concise code and brief explanation.
${responseLanguageInstruction(language)}
''',
      outputKey: 'generated_code',
    );

    final Agent codeReviewer = Agent(
      name: 'CodeReviewerAgent',
      model: _createGeminiModel(apiKey),
      description: '초기 코드를 리뷰하고 개선 포인트를 제시합니다.',
      instruction:
          '''
You are a code reviewer.
- Review this draft:
{generated_code}
- Focus on correctness, readability, edge cases, and maintainability.
- Output a short bullet list.
${responseLanguageInstruction(language)}
''',
      outputKey: 'review_comments',
    );

    final Agent codeRefactorer = Agent(
      name: 'CodeRefactorerAgent',
      model: _createGeminiModel(apiKey),
      description: '리뷰 의견을 반영해 최종 답변을 제공합니다.',
      instruction:
          '''
You are a refactoring agent.
- Original draft:
{generated_code}
- Review comments:
{review_comments}
- Produce an improved final answer.
${responseLanguageInstruction(language)}
''',
    );

    return SequentialAgent(
      name: 'SequentialCodePipeline',
      description: 'Writer -> Reviewer -> Refactorer 순차 실행 예제',
      subAgents: <BaseAgent>[codeWriter, codeReviewer, codeRefactorer],
    );
  }

  static BaseAgent buildParallel({
    required String apiKey,
    required AppLanguage language,
    required String mcpUrl,
    required String mcpBearerToken,
  }) {
    final Agent productAngle = Agent(
      name: 'ProductResearcher',
      model: _createGeminiModel(apiKey),
      description: '제품/비즈니스 관점에서 분석합니다.',
      instruction:
          '''
Analyze the latest user request from a product and business perspective.
- Keep it concise in 3 bullets.
${responseLanguageInstruction(language)}
''',
      outputKey: 'parallel_product_result',
    );

    final Agent userAngle = Agent(
      name: 'UXResearcher',
      model: _createGeminiModel(apiKey),
      description: '사용자 경험 관점에서 분석합니다.',
      instruction:
          '''
Analyze the latest user request from a UX perspective.
- Keep it concise in 3 bullets.
${responseLanguageInstruction(language)}
''',
      outputKey: 'parallel_ux_result',
    );

    final Agent riskAngle = Agent(
      name: 'RiskResearcher',
      model: _createGeminiModel(apiKey),
      description: '리스크/운영 관점에서 분석합니다.',
      instruction:
          '''
Analyze the latest user request from a risk and operations perspective.
- Keep it concise in 3 bullets.
${responseLanguageInstruction(language)}
''',
      outputKey: 'parallel_risk_result',
    );

    final ParallelAgent parallel = ParallelAgent(
      name: 'ParallelResearch',
      description: '독립 분석 에이전트를 병렬로 실행합니다.',
      subAgents: <BaseAgent>[productAngle, userAngle, riskAngle],
    );

    final Agent synthesizer = Agent(
      name: 'ParallelSynthesis',
      model: _createGeminiModel(apiKey),
      description: '병렬 결과를 통합해 최종 답변을 작성합니다.',
      instruction:
          '''
Synthesize the following:
- Product: {parallel_product_result}
- UX: {parallel_ux_result}
- Risk: {parallel_risk_result}

Output:
1) 핵심 요약
2) 실행 권장안
3) 주의할 리스크
${responseLanguageInstruction(language)}
''',
    );

    return SequentialAgent(
      name: 'ParallelResearchPipeline',
      description: 'Parallel 실행 후 결과 통합',
      subAgents: <BaseAgent>[parallel, synthesizer],
    );
  }

  static Map<String, Object?> _exitLoopTool({ToolContext? toolContext}) {
    if (toolContext != null) {
      toolContext.actions.escalate = true;
      toolContext.actions.skipSummarization = true;
    }
    return <String, Object?>{'status': 'loop_exit_requested'};
  }

  static BaseAgent buildLoop({
    required String apiKey,
    required AppLanguage language,
    required String mcpUrl,
    required String mcpBearerToken,
  }) {
    final Agent initialWriter = Agent(
      name: 'InitialWriterAgent',
      model: _createGeminiModel(apiKey),
      description: '초기 초안을 작성합니다.',
      instruction:
          '''
Write a short first draft based on the latest user request.
- Keep it to 2~4 sentences.
${responseLanguageInstruction(language)}
''',
      outputKey: 'loop_current_document',
    );

    final Agent critic = Agent(
      name: 'CriticAgent',
      model: _createGeminiModel(apiKey),
      description: '초안을 평가하고 개선점을 제시합니다.',
      instruction:
          '''
Review the document:
{loop_current_document}

If all criteria are met, answer exactly:
$loopCompletionPhrase

Criteria:
- 명확한 흐름(시작/중간/끝)
- 구체적인 묘사 1개 이상
- 어색한 문장 최소화

If not met, provide concise improvement feedback.
${responseLanguageInstruction(language)}
''',
      outputKey: 'loop_criticism',
    );

    final Agent refiner = Agent(
      name: 'RefinerAgent',
      model: _createGeminiModel(apiKey),
      description: '평가를 반영해 문서를 개선하거나 루프를 종료합니다.',
      instruction:
          '''
Current document:
{loop_current_document}

Critique:
{loop_criticism}

If critique is exactly "$loopCompletionPhrase", call exit_loop and output nothing.
Otherwise, apply feedback and output an improved draft.
${responseLanguageInstruction(language)}
''',
      tools: <Object>[
        FunctionTool(
          name: 'exit_loop',
          description: 'Call only when refinement loop should stop.',
          func: ({ToolContext? toolContext}) =>
              _exitLoopTool(toolContext: toolContext),
        ),
      ],
      outputKey: 'loop_current_document',
    );

    final LoopAgent loop = LoopAgent(
      name: 'RefinementLoop',
      description: 'Critic + Refiner 반복 개선 루프',
      maxIterations: 5,
      subAgents: <BaseAgent>[critic, refiner],
    );

    final Agent finalAnswer = Agent(
      name: 'LoopFinalAnswer',
      model: _createGeminiModel(apiKey),
      description: '루프 결과를 사용자에게 최종 반환합니다.',
      instruction:
          '''
Return the final refined output in Korean:
{loop_current_document}
${responseLanguageInstruction(language)}
''',
    );

    return SequentialAgent(
      name: 'LoopRefinementPipeline',
      description: '초안 작성 후 루프 기반 반복 개선',
      subAgents: <BaseAgent>[initialWriter, loop, finalAnswer],
    );
  }

  static BaseAgent buildTeam({
    required String apiKey,
    required AppLanguage language,
    required String mcpUrl,
    required String mcpBearerToken,
  }) {
    final Agent greetingAgent = Agent(
      name: 'GreetingAgent',
      model: _createGeminiModel(apiKey),
      description: '간단한 인사 요청을 처리합니다.',
      instruction:
          '''
You are a greeting specialist.
- For greetings, call say_hello.
- Keep response short and friendly.
- Do not call transfer_to_agent.
${responseLanguageInstruction(language)}
''',
      tools: <Object>[
        FunctionTool(
          name: 'say_hello',
          description: 'Returns a greeting message.',
          func: ({String? name}) => name == null || name.trim().isEmpty
              ? _localizedGreeting(language)
              : _localizedGreetingWithName(language, name),
        ),
      ],
    );

    final Agent weatherAgent = Agent(
      name: 'WeatherTimeAgent',
      model: _createGeminiModel(apiKey),
      description: '날씨 또는 현재 시간 관련 요청을 처리합니다.',
      instruction:
          '''
You are a weather/time specialist.
- For weather questions, call get_weather with city (or location) argument.
- For current time questions, call get_current_time with city (or location) argument.
- If the user also asks for greeting/farewell, include short greeting/farewell directly in one final answer.
- Prefer a single final response; avoid handing off unless absolutely required.
- If city is unsupported, explain politely.
- Do not call transfer_to_agent.
${responseLanguageInstruction(language)}
''',
      tools: <Object>[
        FunctionTool(
          name: 'get_weather',
          description: 'Returns weather report for a city.',
          func: ({String? city, String? location}) {
            final String? resolved = _resolveCityArg(
              city: city,
              location: location,
            );
            if (resolved == null) {
              return <String, Object?>{
                'status': 'error',
                'error_message': _localizedMissingCity(language),
              };
            }
            return _lookupTeamWeather(resolved, language);
          },
        ),
        FunctionTool(
          name: 'get_current_time',
          description: 'Returns current local time for a city.',
          func: ({String? city, String? location}) {
            final String? resolved = _resolveCityArg(
              city: city,
              location: location,
            );
            if (resolved == null) {
              return <String, Object?>{
                'status': 'error',
                'error_message': _localizedMissingCity(language),
              };
            }
            return _lookupTeamCurrentTime(resolved, language);
          },
        ),
      ],
    );

    final Agent farewellAgent = Agent(
      name: 'FarewellAgent',
      model: _createGeminiModel(apiKey),
      description: '작별 인사 요청을 처리합니다.',
      instruction:
          '''
You are a farewell specialist.
- For goodbye messages, call say_goodbye.
- Keep response short.
- Do not call transfer_to_agent.
${responseLanguageInstruction(language)}
''',
      tools: <Object>[
        FunctionTool(
          name: 'say_goodbye',
          description: 'Returns a goodbye message.',
          func: () => _localizedFarewell(language),
        ),
      ],
    );

    return Agent(
      name: 'WeatherTeamCoordinator',
      model: _createGeminiModel(apiKey),
      description: '요청을 적절한 전문 에이전트로 라우팅하는 코디네이터',
      instruction:
          '''
You are a coordinator for an agent team.
- Route greeting-only requests to GreetingAgent using transfer_to_agent.
- Route weather/time requests to WeatherTimeAgent using transfer_to_agent.
- Route farewell-only requests to FarewellAgent using transfer_to_agent.
- For mixed requests (e.g. greeting + time/weather + farewell), route once to WeatherTimeAgent and let it compose one final response.
- Prefer exactly one transfer_to_agent call per user turn.
- If intent is unclear, ask one short clarifying question.
${responseLanguageInstruction(language)}
''',
      subAgents: <BaseAgent>[greetingAgent, weatherAgent, farewellAgent],
    );
  }

  static BaseAgent buildMcp({
    required String apiKey,
    required AppLanguage language,
    required String mcpUrl,
    required String mcpBearerToken,
  }) {
    final String normalizedUrl = mcpUrl.trim();
    final String normalizedToken = mcpBearerToken.trim();
    final bool hasMcpUrl = normalizedUrl.isNotEmpty;

    final List<Object> tools = <Object>[
      FunctionTool(
        name: 'mcp_connection_status',
        description:
            'Returns whether MCP endpoint is configured for this example app.',
        func: () => <String, Object?>{
          'configured': hasMcpUrl,
          'url': hasMcpUrl ? normalizedUrl : null,
          'message': hasMcpUrl
              ? _localizedMcpConfigured(language)
              : _localizedMcpNotConfigured(language),
        },
      ),
    ];

    if (hasMcpUrl) {
      final Map<String, String> headers = <String, String>{};
      if (normalizedToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $normalizedToken';
      }
      tools.add(
        McpToolset(
          connectionParams: StreamableHTTPConnectionParams(
            url: normalizedUrl,
            headers: headers,
          ),
        ),
      );
    }

    return Agent(
      name: 'McpToolsetAssistant',
      model: _createGeminiModel(apiKey),
      description: 'Uses MCP tools from a Streamable HTTP MCP server.',
      instruction:
          '''
You are an assistant that can use MCP tools.
- First, call mcp_connection_status to verify whether MCP is configured.
- If configured, use available MCP tools to solve the request.
- If MCP is not configured or MCP calls fail, explain what setting is missing.
- Keep responses concise and practical.
${responseLanguageInstruction(language)}
''',
      tools: tools,
    );
  }

  static BaseAgent buildSkills({
    required String apiKey,
    required AppLanguage language,
    required String mcpUrl,
    required String mcpBearerToken,
  }) {
    final Skill writingRefinerSkill = Skill(
      frontmatter: Frontmatter(
        name: 'writing-refiner',
        description: '문서/블로그/공지문 초안을 더 읽기 좋게 개선하는 스킬',
      ),
      instructions: '''
목표:
- 사용자가 준 텍스트를 명확하고 읽기 쉽게 개선한다.

절차:
1) 먼저 `references/checklist.md`를 읽어 품질 체크 기준을 확인한다.
2) 필요하면 `assets/structure_template.md`를 참고해 구조를 재정렬한다.
3) 최종 결과는 한국어로 제공하고, 핵심 개선 포인트 3개 이내로 요약한다.
4) 사용자 요청 언어를 우선한다.
''',
      resources: Resources(
        references: <String, String>{
          'checklist.md': '''
- 핵심 메시지가 첫 문단에 명확히 있는가
- 문단 길이가 과도하지 않은가
- 중복/군더더기 문장이 제거되었는가
- 실행 가능한 다음 행동(CTA)이 있는가
''',
        },
        assets: <String, String>{
          'structure_template.md': '''
# 제목
## 배경
## 핵심 내용
## 실행 항목
## 마무리
''',
        },
      ),
    );

    final Skill planningAdvisorSkill = Skill(
      frontmatter: Frontmatter(
        name: 'planning-advisor',
        description: '목표를 실행 가능한 계획으로 쪼개는 스킬',
      ),
      instructions: '''
목표:
- 추상적인 요청을 실행 가능한 액션 플랜으로 변환한다.

절차:
1) `references/planning_rules.md`를 읽고 우선순위 원칙을 따른다.
2) 결과를 1) 즉시 실행 2) 단기 3) 중기 3단계로 나눠 제시한다.
3) 각 항목에 완료 기준을 포함한다.
4) 사용자 요청 언어를 우선한다.
''',
      resources: Resources(
        references: <String, String>{
          'planning_rules.md': '''
- 큰 작업을 작은 단위로 분해한다.
- 사용자 비용/리스크가 큰 항목은 먼저 검증한다.
- 완료 기준은 관찰 가능한 결과로 표현한다.
''',
        },
      ),
    );

    return Agent(
      name: 'SkillEnabledAssistant',
      model: _createGeminiModel(apiKey),
      description: 'Uses SkillToolset with inline skills.',
      instruction:
          '''
You are a skill-enabled assistant.
- For writing/editing tasks, use writing-refiner skill.
- For planning/roadmap tasks, use planning-advisor skill.
- Always list/load relevant skills before applying them.
- Use load_skill_resource when instructions refer to references/assets.
${responseLanguageInstruction(language)}
''',
      tools: <Object>[
        SkillToolset(
          skills: <Skill>[writingRefinerSkill, planningAdvisorSkill],
        ),
      ],
    );
  }

  static Gemini _createGeminiModel(String apiKey) {
    return Gemini(
      model: 'gemini-3-flash-preview',
      environment: <String, String>{'GEMINI_API_KEY': apiKey},
    );
  }

  static String _localizedGreeting(AppLanguage language) {
    switch (language) {
      case AppLanguage.en:
        return 'Hello!';
      case AppLanguage.ko:
        return '안녕하세요!';
      case AppLanguage.ja:
        return 'こんにちは！';
      case AppLanguage.zh:
        return '你好！';
    }
  }

  static String _localizedGreetingWithName(AppLanguage language, String name) {
    switch (language) {
      case AppLanguage.en:
        return 'Hello, $name!';
      case AppLanguage.ko:
        return '안녕하세요, $name님!';
      case AppLanguage.ja:
        return 'こんにちは、$nameさん！';
      case AppLanguage.zh:
        return '你好，$name！';
    }
  }

  static String _localizedFarewell(AppLanguage language) {
    switch (language) {
      case AppLanguage.en:
        return 'Have a great day. See you next time!';
      case AppLanguage.ko:
        return '좋은 하루 보내세요. 다음에 또 만나요!';
      case AppLanguage.ja:
        return '良い一日を。またお会いしましょう！';
      case AppLanguage.zh:
        return '祝你今天愉快，下次见！';
    }
  }

  static String _localizedMcpConfigured(AppLanguage language) {
    switch (language) {
      case AppLanguage.en:
        return 'MCP endpoint configured.';
      case AppLanguage.ko:
        return 'MCP 엔드포인트가 설정되었습니다.';
      case AppLanguage.ja:
        return 'MCP エンドポイントが設定されています。';
      case AppLanguage.zh:
        return 'MCP 端点已配置。';
    }
  }

  static String _localizedMcpNotConfigured(AppLanguage language) {
    switch (language) {
      case AppLanguage.en:
        return 'MCP URL is empty. Open settings and configure MCP Streamable HTTP URL.';
      case AppLanguage.ko:
        return 'MCP URL이 비어 있습니다. 설정에서 MCP Streamable HTTP URL을 입력하세요.';
      case AppLanguage.ja:
        return 'MCP URL が空です。設定で MCP Streamable HTTP URL を入力してください。';
      case AppLanguage.zh:
        return 'MCP URL 为空。请在设置中配置 MCP Streamable HTTP URL。';
    }
  }

  static String _localizedUnsupportedCity(AppLanguage language, String city) {
    switch (language) {
      case AppLanguage.en:
        return 'Unsupported city: $city';
      case AppLanguage.ko:
        return '지원하지 않는 도시입니다: $city';
      case AppLanguage.ja:
        return '未対応の都市です: $city';
      case AppLanguage.zh:
        return '不支持该城市：$city';
    }
  }

  static String _localizedUnknownTimezone(AppLanguage language, String city) {
    switch (language) {
      case AppLanguage.en:
        return 'Unknown timezone for city: $city';
      case AppLanguage.ko:
        return '시간대를 모르는 도시입니다: $city';
      case AppLanguage.ja:
        return 'この都市のタイムゾーンが不明です: $city';
      case AppLanguage.zh:
        return '未知时区城市：$city';
    }
  }

  static String _localizedMissingCity(AppLanguage language) {
    switch (language) {
      case AppLanguage.en:
        return 'Please provide a city name.';
      case AppLanguage.ko:
        return '도시 이름을 입력해 주세요.';
      case AppLanguage.ja:
        return '都市名を入力してください。';
      case AppLanguage.zh:
        return '请输入城市名称。';
    }
  }

  static String? _resolveCityArg({String? city, String? location}) {
    final String? cityTrimmed = city?.trim();
    if (cityTrimmed != null && cityTrimmed.isNotEmpty) {
      return cityTrimmed;
    }
    final String? locationTrimmed = location?.trim();
    if (locationTrimmed != null && locationTrimmed.isNotEmpty) {
      return locationTrimmed;
    }
    return null;
  }

  static Map<String, Object?> _classifyHelpdeskIntent({
    required String userMessage,
  }) {
    final String normalized = userMessage.trim().toLowerCase();

    final bool hasSupportIntent = _containsAny(normalized, <String>[
      'login',
      'sign in',
      'signin',
      'password',
      'account',
      'app error',
      'technical',
      'support',
      '로그인',
      '비밀번호',
      '계정',
      '접속',
      '오류',
      '기술지원',
      'ログイン',
      'パスワード',
      'アカウント',
      '不具合',
      'エラー',
      '技术支持',
      '技術支援',
      '登录',
      '登入',
      '密码',
      '密碼',
      '账号',
      '帳號',
      '账户',
      '帳戶',
    ]);

    final bool hasBillingIntent = _containsAny(normalized, <String>[
      'billing',
      'payment',
      'charge',
      'refund',
      'invoice',
      'subscription',
      '결제',
      '중복결제',
      '중복 결제',
      '환불',
      '청구',
      '요금',
      '구독',
      '請求',
      '支払い',
      '決済',
      '返金',
      '課金',
      'サブスク',
      '二重決済',
      '支付',
      '付款',
      '扣费',
      '扣費',
      '账单',
      '帳單',
      '退款',
      '订阅',
      '訂閱',
      '重复扣款',
      '重複扣款',
    ]);

    final String route = switch ((hasSupportIntent, hasBillingIntent)) {
      (true, false) => 'Support',
      (false, true) => 'Billing',
      (true, true) => 'Ambiguous',
      (false, false) => 'Unknown',
    };

    return <String, Object?>{
      'route': route,
      'has_support_intent': hasSupportIntent,
      'has_billing_intent': hasBillingIntent,
    };
  }

  static bool _containsAny(String text, List<String> keywords) {
    for (final String keyword in keywords) {
      if (text.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  static String _localizedTimeReport(
    AppLanguage language, {
    required String city,
    required String date,
    required String hh,
    required String mm,
    required String zone,
  }) {
    switch (language) {
      case AppLanguage.en:
        return 'Current time in $city is $date $hh:$mm ($zone).';
      case AppLanguage.ko:
        return '$city 현재 시각은 $date $hh:$mm ($zone) 입니다.';
      case AppLanguage.ja:
        return '$city の現在時刻は $date $hh:$mm ($zone) です。';
      case AppLanguage.zh:
        return '$city 当前时间是 $date $hh:$mm（$zone）。';
    }
  }

  static Map<String, Object?> _lookupTeamWeather(
    String city,
    AppLanguage language,
  ) {
    final String normalized = city.trim().toLowerCase();
    const Map<String, String> reports = <String, String>{
      'new york': 'New York is sunny with 25°C.',
      'london': 'London is cloudy with 15°C.',
      'seoul': 'Seoul is mostly cloudy with 22°C.',
      'tokyo': 'Tokyo has light rain with 18°C.',
    };
    final String? report = reports[normalized];
    if (report == null) {
      return <String, Object?>{
        'status': 'error',
        'error_message': _localizedUnsupportedCity(language, city),
      };
    }
    return <String, Object?>{
      'status': 'success',
      'report': report,
      'city': city,
      'language_hint': language.code,
    };
  }

  static Map<String, Object?> _lookupTeamCurrentTime(
    String city,
    AppLanguage language,
  ) {
    final String normalized = city.trim().toLowerCase();
    const Map<String, int> utcOffsets = <String, int>{
      'new york': -5,
      'london': 0,
      'seoul': 9,
      'tokyo': 9,
    };
    final int? offset = utcOffsets[normalized];
    if (offset == null) {
      return <String, Object?>{
        'status': 'error',
        'error_message': _localizedUnknownTimezone(language, city),
      };
    }

    final DateTime now = DateTime.now().toUtc().add(Duration(hours: offset));
    final String hh = now.hour.toString().padLeft(2, '0');
    final String mm = now.minute.toString().padLeft(2, '0');
    final String date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final String zone = _formatUtcOffset(offset);

    return <String, Object?>{
      'status': 'success',
      'report': _localizedTimeReport(
        language,
        city: city,
        date: date,
        hh: hh,
        mm: mm,
        zone: zone,
      ),
    };
  }

  static String _formatUtcOffset(int offsetHours) {
    final String sign = offsetHours >= 0 ? '+' : '-';
    final int absHours = offsetHours.abs();
    final String hh = absHours.toString().padLeft(2, '0');
    return 'UTC$sign$hh:00';
  }

  static Map<String, Object?> _lookupCapitalCity(String country) {
    const Map<String, String> capitals = <String, String>{
      'france': 'Paris',
      'japan': 'Tokyo',
      'canada': 'Ottawa',
      'korea': 'Seoul',
      'south korea': 'Seoul',
      'united states': 'Washington, D.C.',
      'usa': 'Washington, D.C.',
      'germany': 'Berlin',
      'italy': 'Rome',
    };

    final String normalized = country.trim().toLowerCase();
    final String? capital = capitals[normalized];
    return <String, Object?>{
      'country': country,
      'known': capital != null,
      'capital': capital,
    };
  }
}
