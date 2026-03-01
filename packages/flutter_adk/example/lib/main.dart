import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _apiKeyPrefKey = 'flutter_adk_example_gemini_api_key';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter ADK Examples',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ExamplesHomePage(),
    );
  }
}

class ExamplesHomePage extends StatefulWidget {
  const ExamplesHomePage({super.key});

  @override
  State<ExamplesHomePage> createState() => _ExamplesHomePageState();
}

class _ExamplesHomePageState extends State<ExamplesHomePage> {
  final TextEditingController _apiKeyController = TextEditingController();

  bool _obscureApiKey = true;
  int _selectedExampleIndex = 0;

  bool get _hasApiKey => _apiKeyController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadSavedApiKey();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedApiKey() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String savedKey = prefs.getString(_apiKeyPrefKey) ?? '';
      if (!mounted) {
        return;
      }
      setState(() {
        _apiKeyController.text = savedKey;
      });
    } on MissingPluginException {
      // Widget tests may run without shared_preferences plugin registration.
    }
  }

  Future<void> _saveApiKey() async {
    final String key = _apiKeyController.text.trim();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (key.isEmpty) {
        await prefs.remove(_apiKeyPrefKey);
      } else {
        await prefs.setString(_apiKeyPrefKey, key);
      }
    } on MissingPluginException {
      // Keep in-memory value even when persistence plugin is unavailable.
    }

    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('API 키 설정이 저장되었습니다.')));
  }

  Future<void> _clearApiKey() async {
    _apiKeyController.clear();
    await _saveApiKey();
  }

  Future<void> _openSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'API 설정',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: 'Gemini API Key',
                      hintText: 'AIza...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureApiKey
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setModalState(() {
                            _obscureApiKey = !_obscureApiKey;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '웹 브라우저에 키를 저장하는 경우 노출 위험이 있습니다. '
                    '프로덕션은 서버 프록시를 권장합니다.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      OutlinedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _clearApiKey();
                        },
                        child: const Text('키 삭제'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _saveApiKey();
                        },
                        child: const Text('저장'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String apiKey = _apiKeyController.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter ADK Examples'),
        actions: <Widget>[
          Icon(
            _hasApiKey ? Icons.verified : Icons.warning_amber_rounded,
            color: _hasApiKey ? Colors.green : Colors.orange,
          ),
          IconButton(
            tooltip: 'API 설정',
            onPressed: _openSettingsSheet,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (!_hasApiKey)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('API 키를 설정해야 실제 모델 응답을 받을 수 있습니다.'),
                  ),
                  TextButton(
                    onPressed: _openSettingsSheet,
                    child: const Text('Set API Key'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.chat_bubble_outline),
                  label: Text('Basic Chatbot'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.hub_outlined),
                  label: Text('Multi-Agent'),
                ),
                ButtonSegment<int>(
                  value: 2,
                  icon: Icon(Icons.account_tree_outlined),
                  label: Text('Workflow'),
                ),
              ],
              selected: <int>{_selectedExampleIndex},
              onSelectionChanged: (Set<int> selected) {
                setState(() {
                  _selectedExampleIndex = selected.first;
                });
              },
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedExampleIndex,
              children: <Widget>[
                _ChatExampleView(
                  key: const ValueKey<String>('basic_example'),
                  exampleId: 'basic',
                  exampleTitle: 'Basic Chatbot Example',
                  summary: '단일 Agent + Tool(FunctionTool) 기반 예제입니다.',
                  initialAssistantMessage:
                      '안녕하세요. 국가 수도, 일반 Q&A를 처리하는 기본 챗봇 예제입니다.\n'
                      'API 키를 설정하고 질문을 보내세요.',
                  emptyStateMessage: '메시지를 보내 기본 챗봇을 시작하세요.',
                  inputHint: '기본 챗봇에게 질문하기...',
                  apiKey: apiKey,
                  createAgent: _buildBasicAgent,
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('multi_agent_example'),
                  exampleId: 'multi_agent',
                  exampleTitle: 'Multi-Agent Coordinator Example',
                  summary:
                      '공식 문서 MAS의 Coordinator/Dispatcher 패턴\n'
                      '(Coordinator + Billing/Support sub-agent transfer) 예제입니다.',
                  initialAssistantMessage:
                      '안녕하세요. 저는 멀티에이전트 코디네이터 예제입니다.\n'
                      '결제/청구 문의는 Billing, 기술/로그인 문의는 Support로 라우팅합니다.',
                  emptyStateMessage: '메시지를 보내 멀티에이전트 라우팅을 확인하세요.',
                  inputHint: '예: 결제가 두 번 청구됐어요 / 로그인이 안돼요',
                  apiKey: apiKey,
                  createAgent: _buildMultiAgentCoordinator,
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('workflow_example'),
                  exampleId: 'workflow',
                  exampleTitle: 'Workflow Agents Example',
                  summary:
                      'Sequential + Parallel + Loop 조합 예제입니다.\n'
                      '입력 요약, 병렬 관점 생성, 루프 정리 후 최종 답변합니다.',
                  initialAssistantMessage:
                      '안녕하세요. 워크플로우 에이전트 예제입니다.\n'
                      '질문을 보내면 Sequential/Parallel/Loop 체인으로 처리합니다.',
                  emptyStateMessage: '메시지를 보내 워크플로우 실행을 확인하세요.',
                  inputHint: '예: 파리 2박 3일 일정 추천',
                  apiKey: apiKey,
                  createAgent: _buildWorkflowOrchestrator,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef _AgentFactory = BaseAgent Function(String apiKey);

class _ChatExampleView extends StatefulWidget {
  const _ChatExampleView({
    super.key,
    required this.exampleId,
    required this.exampleTitle,
    required this.summary,
    required this.initialAssistantMessage,
    required this.emptyStateMessage,
    required this.inputHint,
    required this.apiKey,
    required this.createAgent,
  });

  final String exampleId;
  final String exampleTitle;
  final String summary;
  final String initialAssistantMessage;
  final String emptyStateMessage;
  final String inputHint;
  final String apiKey;
  final _AgentFactory createAgent;

  @override
  State<_ChatExampleView> createState() => _ChatExampleViewState();
}

class _ChatExampleViewState extends State<_ChatExampleView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final List<_ChatMessage> _messages;

  InMemoryRunner? _runner;
  String? _runnerApiKey;
  bool _isSending = false;

  static const String _userId = 'example_user';
  String _sessionId = 'session_init';

  @override
  void initState() {
    super.initState();
    _messages = <_ChatMessage>[
      _ChatMessage.assistant(widget.initialAssistantMessage),
    ];
  }

  @override
  void didUpdateWidget(covariant _ChatExampleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiKey != widget.apiKey && _runnerApiKey != widget.apiKey) {
      unawaited(_resetRunner());
    }
  }

  @override
  void dispose() {
    unawaited(_runner?.close());
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resetRunner() async {
    final InMemoryRunner? runner = _runner;
    _runner = null;
    _runnerApiKey = null;
    if (runner != null) {
      await runner.close();
    }
  }

  Future<void> _ensureRunner() async {
    final String apiKey = widget.apiKey.trim();
    if (apiKey.isEmpty) {
      throw StateError('Gemini API 키를 먼저 설정하세요.');
    }
    if (_runner != null && _runnerApiKey == apiKey) {
      return;
    }

    await _resetRunner();

    final BaseAgent agent = widget.createAgent(apiKey);
    final InMemoryRunner runner = InMemoryRunner(
      agent: agent,
      appName: 'flutter_adk_${widget.exampleId}_example',
    );
    final String sessionId =
        '${widget.exampleId}_session_${DateTime.now().microsecondsSinceEpoch}';
    await runner.sessionService.createSession(
      appName: runner.appName,
      userId: _userId,
      sessionId: sessionId,
    );

    _runner = runner;
    _runnerApiKey = apiKey;
    _sessionId = sessionId;
  }

  Future<void> _sendMessage() async {
    if (_isSending) {
      return;
    }

    final String text = _messageController.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _messages.add(_ChatMessage.user(text));
      _messageController.clear();
      _isSending = true;
    });
    _scrollToBottom();

    try {
      await _ensureRunner();
      final InMemoryRunner runner = _runner!;
      final List<Event> events = await runner
          .runAsync(
            userId: _userId,
            sessionId: _sessionId,
            newMessage: Content.userText(text),
          )
          .toList();

      final String reply = _extractReply(events);
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(_ChatMessage.assistant(reply));
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(_ChatMessage.assistant('오류가 발생했습니다: $error'));
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
      _scrollToBottom();
    }
  }

  String _extractReply(List<Event> events) {
    for (int i = events.length - 1; i >= 0; i -= 1) {
      final Event event = events[i];
      if (!event.isFinalResponse()) {
        continue;
      }
      final Content? content = event.content;
      if (content == null) {
        continue;
      }
      final List<String> parts = <String>[];
      for (final Part part in content.parts) {
        final String? text = part.text?.trim();
        if (text != null && text.isNotEmpty) {
          parts.add(text);
        }
      }
      if (parts.isNotEmpty) {
        return parts.join('\n');
      }
    }
    return '응답 텍스트를 찾지 못했습니다.';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.exampleTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(widget.summary),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: _messages.length == 1
              ? Center(
                  child: Text(
                    widget.emptyStateMessage,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  itemCount: _messages.length,
                  itemBuilder: (BuildContext context, int index) {
                    final _ChatMessage message = _messages[index];
                    return Align(
                      alignment: message.isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 520),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: message.isUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(message.text),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: !_isSending,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: widget.inputHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FilledButton(
                    onPressed: _isSending ? null : _sendMessage,
                    child: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Gemini _createGeminiModel(String apiKey) {
  return Gemini(
    model: 'gemini-2.5-flash',
    environment: <String, String>{'GEMINI_API_KEY': apiKey},
  );
}

Agent _buildBasicAgent(String apiKey) {
  return Agent(
    name: 'capital_chatbot',
    model: _createGeminiModel(apiKey),
    description: 'Capital-city and general helper chatbot.',
    instruction: '''
You are a helpful chatbot.
- If user asks for a country's capital city, use get_capital_city tool first.
- If tool returns known=false, explain that you do not know that country yet.
- For general questions, answer directly.
- Keep answers concise and friendly.
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

Agent _buildMultiAgentCoordinator(String apiKey) {
  final Agent billingAgent = Agent(
    name: 'Billing',
    model: _createGeminiModel(apiKey),
    description: 'Handles billing inquiries and payment issues.',
    instruction: '''
You are the Billing specialist.
- Handle invoices, charges, payments, refunds, and subscription billing.
- If required details are missing, ask concise follow-up questions.
- If the issue is not billing-related, clearly say this team handles billing only.
''',
  );

  final Agent supportAgent = Agent(
    name: 'Support',
    model: _createGeminiModel(apiKey),
    description: 'Handles technical support and account access issues.',
    instruction: '''
You are the Support specialist.
- Handle login failures, app errors, account access, and technical troubleshooting.
- Give practical, step-by-step guidance.
- If the issue is purely billing-related, say this team handles technical issues only.
''',
  );

  return Agent(
    name: 'HelpDeskCoordinator',
    model: _createGeminiModel(apiKey),
    description: 'Main help desk router.',
    instruction: '''
You are a help desk coordinator.
- Route payment or billing requests to Billing using transfer_to_agent.
- Route login/app/account technical requests to Support using transfer_to_agent.
- If unclear, ask one short clarification question before transfer.
- After routing, the selected specialist should provide the final answer.
''',
    subAgents: <BaseAgent>[billingAgent, supportAgent],
  );
}

BaseAgent _buildWorkflowOrchestrator(String apiKey) {
  final Agent summarize = Agent(
    name: 'SummarizeInput',
    model: _createGeminiModel(apiKey),
    instruction: '''
Read the latest user message and write a short summary.
- Keep it under 2 sentences.
- Save concise output for downstream steps.
''',
    outputKey: 'task_summary',
  );

  final Agent angleProduct = Agent(
    name: 'ProductAngle',
    model: _createGeminiModel(apiKey),
    instruction: '''
Based on {task_summary}, provide product/feature perspective recommendations.
- Keep it concise.
''',
    outputKey: 'angle_product',
  );

  final Agent angleUser = Agent(
    name: 'UserAngle',
    model: _createGeminiModel(apiKey),
    instruction: '''
Based on {task_summary}, provide user-experience perspective recommendations.
- Keep it concise.
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
    instruction: '''
Combine {angle_product} and {angle_user} into a cleaner draft answer.
- Keep actionable bullets.
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
    instruction: '''
Return the final response to user using:
- summary: {task_summary}
- draft: {draft_answer}
Output a clear, concise final answer in Korean.
''',
  );

  return SequentialAgent(
    name: 'WorkflowOrchestrator',
    subAgents: <BaseAgent>[summarize, parallel, loop, finalAnswer],
  );
}

Map<String, Object?> _lookupCapitalCity(String country) {
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

class _ChatMessage {
  _ChatMessage({required this.isUser, required this.text});

  factory _ChatMessage.user(String text) {
    return _ChatMessage(isUser: true, text: text);
  }

  factory _ChatMessage.assistant(String text) {
    return _ChatMessage(isUser: false, text: text);
  }

  final bool isUser;
  final String text;
}
