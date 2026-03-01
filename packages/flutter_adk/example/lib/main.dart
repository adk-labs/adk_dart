import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _apiKeyPrefKey = 'flutter_adk_example_gemini_api_key';
const String _mcpUrlPrefKey = 'flutter_adk_example_mcp_url';
const String _mcpBearerTokenPrefKey = 'flutter_adk_example_mcp_bearer_token';
const String _loopCompletionPhrase = 'No major issues found.';

class _ExampleTab {
  const _ExampleTab({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

const List<_ExampleTab> _exampleTabs = <_ExampleTab>[
  _ExampleTab(label: 'Basic Chatbot', icon: Icons.chat_bubble_outline),
  _ExampleTab(label: 'Transfer Multi-Agent', icon: Icons.hub_outlined),
  _ExampleTab(label: 'Workflow Combo', icon: Icons.account_tree_outlined),
  _ExampleTab(label: 'Sequential', icon: Icons.linear_scale_outlined),
  _ExampleTab(label: 'Parallel', icon: Icons.call_split_outlined),
  _ExampleTab(label: 'Loop', icon: Icons.loop_outlined),
  _ExampleTab(label: 'Agent Team', icon: Icons.groups_outlined),
  _ExampleTab(label: 'MCP Toolset', icon: Icons.extension_outlined),
  _ExampleTab(label: 'Skills', icon: Icons.psychology_outlined),
];

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
  final TextEditingController _mcpUrlController = TextEditingController();
  final TextEditingController _mcpBearerTokenController =
      TextEditingController();

  bool _obscureApiKey = true;
  bool _obscureMcpBearerToken = true;
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
    _mcpUrlController.dispose();
    _mcpBearerTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedApiKey() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String savedKey = prefs.getString(_apiKeyPrefKey) ?? '';
      final String savedMcpUrl = prefs.getString(_mcpUrlPrefKey) ?? '';
      final String savedMcpBearerToken =
          prefs.getString(_mcpBearerTokenPrefKey) ?? '';
      if (!mounted) {
        return;
      }
      setState(() {
        _apiKeyController.text = savedKey;
        _mcpUrlController.text = savedMcpUrl;
        _mcpBearerTokenController.text = savedMcpBearerToken;
      });
    } on MissingPluginException {
      // Widget tests may run without shared_preferences plugin registration.
    }
  }

  Future<void> _saveApiKey() async {
    final String key = _apiKeyController.text.trim();
    final String mcpUrl = _mcpUrlController.text.trim();
    final String mcpBearerToken = _mcpBearerTokenController.text.trim();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (key.isEmpty) {
        await prefs.remove(_apiKeyPrefKey);
      } else {
        await prefs.setString(_apiKeyPrefKey, key);
      }

      if (mcpUrl.isEmpty) {
        await prefs.remove(_mcpUrlPrefKey);
      } else {
        await prefs.setString(_mcpUrlPrefKey, mcpUrl);
      }

      if (mcpBearerToken.isEmpty) {
        await prefs.remove(_mcpBearerTokenPrefKey);
      } else {
        await prefs.setString(_mcpBearerTokenPrefKey, mcpBearerToken);
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
    ).showSnackBar(const SnackBar(content: Text('설정이 저장되었습니다.')));
  }

  Future<void> _clearApiKey() async {
    _apiKeyController.clear();
    _mcpUrlController.clear();
    _mcpBearerTokenController.clear();
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: _mcpUrlController,
                    decoration: const InputDecoration(
                      labelText: 'MCP Streamable HTTP URL',
                      hintText: 'https://your-mcp-server.example.com/mcp',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _mcpBearerTokenController,
                    obscureText: _obscureMcpBearerToken,
                    decoration: InputDecoration(
                      labelText: 'MCP Bearer Token (Optional)',
                      hintText: 'eyJ...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureMcpBearerToken
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setModalState(() {
                            _obscureMcpBearerToken = !_obscureMcpBearerToken;
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
    final String mcpUrl = _mcpUrlController.text.trim();
    final String mcpBearerToken = _mcpBearerTokenController.text.trim();

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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List<Widget>.generate(_exampleTabs.length, (
                  int index,
                ) {
                  final _ExampleTab tab = _exampleTabs[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == _exampleTabs.length - 1 ? 0 : 8,
                    ),
                    child: ChoiceChip(
                      avatar: Icon(tab.icon, size: 18),
                      label: Text(tab.label),
                      selected: _selectedExampleIndex == index,
                      onSelected: (bool selected) {
                        if (!selected) {
                          return;
                        }
                        setState(() {
                          _selectedExampleIndex = index;
                        });
                      },
                    ),
                  );
                }),
              ),
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
                _ChatExampleView(
                  key: const ValueKey<String>('sequential_example'),
                  exampleId: 'sequential',
                  exampleTitle: 'SequentialAgent Example',
                  summary:
                      'Code Writer -> Reviewer -> Refactorer를 순서대로 실행하는 '
                      '고정 파이프라인 예제입니다.',
                  initialAssistantMessage:
                      '안녕하세요. SequentialAgent 예제입니다.\n'
                      '요청을 보내면 작성-리뷰-리팩터링을 순차 실행합니다.',
                  emptyStateMessage: '메시지를 보내 Sequential 워크플로우를 실행하세요.',
                  inputHint: '예: 문자열을 뒤집는 파이썬 함수를 작성해줘',
                  apiKey: apiKey,
                  createAgent: _buildSequentialCodePipeline,
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('parallel_example'),
                  exampleId: 'parallel',
                  exampleTitle: 'ParallelAgent Example',
                  summary:
                      '독립 관점 에이전트를 병렬 실행한 뒤, 마지막 에이전트가 '
                      '결과를 합성하는 예제입니다.',
                  initialAssistantMessage:
                      '안녕하세요. ParallelAgent 예제입니다.\n'
                      '질문을 보내면 여러 관점을 동시에 생성해 요약합니다.',
                  emptyStateMessage: '메시지를 보내 Parallel 워크플로우를 실행하세요.',
                  inputHint: '예: 신규 유료 플랜 출시 전략을 정리해줘',
                  apiKey: apiKey,
                  createAgent: _buildParallelResearchPipeline,
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('loop_example'),
                  exampleId: 'loop',
                  exampleTitle: 'LoopAgent Example',
                  summary:
                      'Critic + Refiner를 반복 실행하며 조건 충족 시 '
                      '툴 호출로 루프를 종료하는 예제입니다.',
                  initialAssistantMessage:
                      '안녕하세요. LoopAgent 예제입니다.\n'
                      '초안 작성 후 반복 개선하고, 완료 조건이면 루프를 종료합니다.',
                  emptyStateMessage: '메시지를 보내 Loop 워크플로우를 실행하세요.',
                  inputHint: '예: 고양이에 대한 짧은 동화를 써줘',
                  apiKey: apiKey,
                  createAgent: _buildLoopRefinementPipeline,
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('agent_team_example'),
                  exampleId: 'agent_team',
                  exampleTitle: 'Agent Team Example',
                  summary:
                      'Coordinator가 Greeting/Weather/Farewell 전문 에이전트로 '
                      'transfer하는 팀 예제입니다.',
                  initialAssistantMessage:
                      '안녕하세요. Agent Team 예제입니다.\n'
                      '인사/날씨/시간/작별 요청을 각각 전담 에이전트로 라우팅합니다.',
                  emptyStateMessage: '메시지를 보내 Agent Team 라우팅을 확인하세요.',
                  inputHint: '예: 서울 시간 알려줘 / 뉴욕 날씨 어때?',
                  apiKey: apiKey,
                  createAgent: _buildAgentTeamWeather,
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('mcp_toolset_example'),
                  exampleId: 'mcp_toolset',
                  exampleTitle: 'MCP Toolset Example',
                  summary:
                      'McpToolset(Streamable HTTP) 기반 예제입니다.\n'
                      '설정에서 MCP URL/토큰을 입력하면 원격 MCP tools를 로드해 사용합니다.',
                  initialAssistantMessage:
                      '안녕하세요. MCP Toolset 예제입니다.\n'
                      '먼저 설정에서 MCP Streamable HTTP URL을 입력하세요.\n'
                      '그 다음 MCP 서버가 제공하는 tool을 자동으로 사용합니다.',
                  emptyStateMessage: '메시지를 보내 MCP Toolset 동작을 확인하세요.',
                  inputHint: '예: MCP 서버 tool로 파일 목록 보여줘',
                  apiKey: apiKey,
                  createAgent: (String key) => _buildMcpToolsetAgent(
                    key,
                    mcpUrl: mcpUrl,
                    mcpBearerToken: mcpBearerToken,
                  ),
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('skills_example'),
                  exampleId: 'skills',
                  exampleTitle: 'SkillToolset Example',
                  summary:
                      'inline Skill + SkillToolset 기반 예제입니다.\n'
                      '리스트/로드/리소스 조회 도구를 통해 스킬 지시를 단계적으로 사용합니다.',
                  initialAssistantMessage:
                      '안녕하세요. Skills 예제입니다.\n'
                      '요청에 맞는 skill을 list/load해서 지시를 따르도록 설계되었습니다.',
                  emptyStateMessage: '메시지를 보내 Skills 동작을 확인하세요.',
                  inputHint: '예: 블로그 글 구조를 개선해줘',
                  apiKey: apiKey,
                  createAgent: _buildSkillsAgent,
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

BaseAgent _buildSequentialCodePipeline(String apiKey) {
  final Agent codeWriter = Agent(
    name: 'CodeWriterAgent',
    model: _createGeminiModel(apiKey),
    description: '요청을 기반으로 초기 코드를 작성합니다.',
    instruction: '''
You are a code writer.
- Read the latest user request and produce an initial solution.
- Output concise code and brief explanation.
''',
    outputKey: 'generated_code',
  );

  final Agent codeReviewer = Agent(
    name: 'CodeReviewerAgent',
    model: _createGeminiModel(apiKey),
    description: '초기 코드를 리뷰하고 개선 포인트를 제시합니다.',
    instruction: '''
You are a code reviewer.
- Review this draft:
{generated_code}
- Focus on correctness, readability, edge cases, and maintainability.
- Output a short bullet list in Korean.
''',
    outputKey: 'review_comments',
  );

  final Agent codeRefactorer = Agent(
    name: 'CodeRefactorerAgent',
    model: _createGeminiModel(apiKey),
    description: '리뷰 의견을 반영해 최종 답변을 제공합니다.',
    instruction: '''
You are a refactoring agent.
- Original draft:
{generated_code}
- Review comments:
{review_comments}
- Produce an improved final answer in Korean.
''',
  );

  return SequentialAgent(
    name: 'SequentialCodePipeline',
    description: 'Writer -> Reviewer -> Refactorer 순차 실행 예제',
    subAgents: <BaseAgent>[codeWriter, codeReviewer, codeRefactorer],
  );
}

BaseAgent _buildParallelResearchPipeline(String apiKey) {
  final Agent productAngle = Agent(
    name: 'ProductResearcher',
    model: _createGeminiModel(apiKey),
    description: '제품/비즈니스 관점에서 분석합니다.',
    instruction: '''
Analyze the latest user request from a product and business perspective.
- Keep it concise in 3 bullets.
''',
    outputKey: 'parallel_product_result',
  );

  final Agent userAngle = Agent(
    name: 'UXResearcher',
    model: _createGeminiModel(apiKey),
    description: '사용자 경험 관점에서 분석합니다.',
    instruction: '''
Analyze the latest user request from a UX perspective.
- Keep it concise in 3 bullets.
''',
    outputKey: 'parallel_ux_result',
  );

  final Agent riskAngle = Agent(
    name: 'RiskResearcher',
    model: _createGeminiModel(apiKey),
    description: '리스크/운영 관점에서 분석합니다.',
    instruction: '''
Analyze the latest user request from a risk and operations perspective.
- Keep it concise in 3 bullets.
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
    instruction: '''
Synthesize the following in Korean:
- Product: {parallel_product_result}
- UX: {parallel_ux_result}
- Risk: {parallel_risk_result}

Output:
1) 핵심 요약
2) 실행 권장안
3) 주의할 리스크
''',
  );

  return SequentialAgent(
    name: 'ParallelResearchPipeline',
    description: 'Parallel 실행 후 결과 통합',
    subAgents: <BaseAgent>[parallel, synthesizer],
  );
}

Map<String, Object?> _exitLoopTool({ToolContext? toolContext}) {
  if (toolContext != null) {
    toolContext.actions.escalate = true;
    toolContext.actions.skipSummarization = true;
  }
  return <String, Object?>{'status': 'loop_exit_requested'};
}

BaseAgent _buildLoopRefinementPipeline(String apiKey) {
  final Agent initialWriter = Agent(
    name: 'InitialWriterAgent',
    model: _createGeminiModel(apiKey),
    description: '초기 초안을 작성합니다.',
    instruction: '''
Write a short first draft in Korean based on the latest user request.
- Keep it to 2~4 sentences.
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
$_loopCompletionPhrase

Criteria:
- 명확한 흐름(시작/중간/끝)
- 구체적인 묘사 1개 이상
- 어색한 문장 최소화

If not met, provide concise improvement feedback in Korean.
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

If critique is exactly "$_loopCompletionPhrase", call exit_loop and output nothing.
Otherwise, apply feedback and output an improved Korean draft.
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
    instruction: '''
Return the final refined output in Korean:
{loop_current_document}
''',
  );

  return SequentialAgent(
    name: 'LoopRefinementPipeline',
    description: '초안 작성 후 루프 기반 반복 개선',
    subAgents: <BaseAgent>[initialWriter, loop, finalAnswer],
  );
}

Agent _buildAgentTeamWeather(String apiKey) {
  final Agent greetingAgent = Agent(
    name: 'GreetingAgent',
    model: _createGeminiModel(apiKey),
    description: '간단한 인사 요청을 처리합니다.',
    instruction: '''
You are a greeting specialist.
- For greetings, call say_hello.
- Keep response short and friendly in Korean.
''',
    tools: <Object>[
      FunctionTool(
        name: 'say_hello',
        description: 'Returns a greeting message.',
        func: ({String? name}) =>
            name == null || name.trim().isEmpty ? '안녕하세요!' : '안녕하세요, $name님!',
      ),
    ],
  );

  final Agent weatherAgent = Agent(
    name: 'WeatherTimeAgent',
    model: _createGeminiModel(apiKey),
    description: '날씨 또는 현재 시간 관련 요청을 처리합니다.',
    instruction: '''
You are a weather/time specialist.
- For weather questions, call get_weather.
- For current time questions, call get_current_time.
- If city is unsupported, explain politely in Korean.
''',
    tools: <Object>[
      FunctionTool(
        name: 'get_weather',
        description: 'Returns weather report for a city.',
        func: ({required String city}) => _lookupTeamWeather(city),
      ),
      FunctionTool(
        name: 'get_current_time',
        description: 'Returns current local time for a city.',
        func: ({required String city}) => _lookupTeamCurrentTime(city),
      ),
    ],
  );

  final Agent farewellAgent = Agent(
    name: 'FarewellAgent',
    model: _createGeminiModel(apiKey),
    description: '작별 인사 요청을 처리합니다.',
    instruction: '''
You are a farewell specialist.
- For goodbye messages, call say_goodbye.
- Keep response short in Korean.
''',
    tools: <Object>[
      FunctionTool(
        name: 'say_goodbye',
        description: 'Returns a goodbye message.',
        func: () => '좋은 하루 보내세요. 다음에 또 만나요!',
      ),
    ],
  );

  return Agent(
    name: 'WeatherTeamCoordinator',
    model: _createGeminiModel(apiKey),
    description: '요청을 적절한 전문 에이전트로 라우팅하는 코디네이터',
    instruction: '''
You are a coordinator for an agent team.
- Route greetings to GreetingAgent using transfer_to_agent.
- Route weather/time requests to WeatherTimeAgent using transfer_to_agent.
- Route farewells to FarewellAgent using transfer_to_agent.
- If intent is unclear, ask one short clarifying question in Korean.
''',
    subAgents: <BaseAgent>[greetingAgent, weatherAgent, farewellAgent],
  );
}

Agent _buildMcpToolsetAgent(
  String apiKey, {
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
            ? 'MCP endpoint configured.'
            : 'MCP URL is empty. Open settings and configure MCP Streamable HTTP URL.',
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
    instruction: '''
You are an assistant that can use MCP tools.
- First, call mcp_connection_status to verify whether MCP is configured.
- If configured, use available MCP tools to solve the request.
- If MCP is not configured or MCP calls fail, explain what setting is missing.
- Keep responses concise and practical in Korean.
''',
    tools: tools,
  );
}

Agent _buildSkillsAgent(String apiKey) {
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
    instruction: '''
You are a skill-enabled assistant.
- For writing/editing tasks, use writing-refiner skill.
- For planning/roadmap tasks, use planning-advisor skill.
- Always list/load relevant skills before applying them.
- Use load_skill_resource when instructions refer to references/assets.
- Respond in Korean.
''',
    tools: <Object>[
      SkillToolset(skills: <Skill>[writingRefinerSkill, planningAdvisorSkill]),
    ],
  );
}

Map<String, Object?> _lookupTeamWeather(String city) {
  final String normalized = city.trim().toLowerCase();
  const Map<String, String> reports = <String, String>{
    'new york': '뉴욕은 맑고 25°C입니다.',
    'london': '런던은 흐리고 15°C입니다.',
    'seoul': '서울은 구름 많고 22°C입니다.',
    'tokyo': '도쿄는 약한 비와 18°C입니다.',
  };
  final String? report = reports[normalized];
  if (report == null) {
    return <String, Object?>{
      'status': 'error',
      'error_message': '지원하지 않는 도시입니다: $city',
    };
  }
  return <String, Object?>{'status': 'success', 'report': report};
}

Map<String, Object?> _lookupTeamCurrentTime(String city) {
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
      'error_message': '시간대를 모르는 도시입니다: $city',
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
    'report': '$city 현재 시각은 $date $hh:$mm ($zone) 입니다.',
  };
}

String _formatUtcOffset(int offsetHours) {
  final String sign = offsetHours >= 0 ? '+' : '-';
  final int absHours = offsetHours.abs();
  final String hh = absHours.toString().padLeft(2, '0');
  return 'UTC$sign$hh:00';
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
