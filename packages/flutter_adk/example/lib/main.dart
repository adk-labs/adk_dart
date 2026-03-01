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
      title: 'Flutter ADK Chatbot',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ChatbotPage(),
    );
  }
}

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = <_ChatMessage>[
    _ChatMessage.assistant(
      '안녕하세요. 국가 수도, 일반 Q&A를 처리하는 Flutter ADK 챗봇 예제입니다.\n'
      '우측 상단 설정에서 Gemini API 키를 저장한 뒤 메시지를 보내세요.',
    ),
  ];

  InMemoryRunner? _runner;
  String? _runnerApiKey;
  bool _isSending = false;
  bool _obscureApiKey = true;

  static const String _userId = 'example_user';
  String _sessionId = 'session_init';

  bool get _hasApiKey => _apiKeyController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadSavedApiKey();
  }

  @override
  void dispose() {
    unawaited(_runner?.close());
    _messageController.dispose();
    _apiKeyController.dispose();
    _scrollController.dispose();
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

    if (_runnerApiKey != key) {
      await _resetRunner();
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

  Future<void> _resetRunner() async {
    final InMemoryRunner? runner = _runner;
    _runner = null;
    _runnerApiKey = null;
    if (runner != null) {
      await runner.close();
    }
  }

  Future<void> _ensureRunner() async {
    final String apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      throw StateError('Gemini API 키를 먼저 설정하세요.');
    }
    if (_runner != null && _runnerApiKey == apiKey) {
      return;
    }

    await _resetRunner();

    final Agent agent = Agent(
      name: 'capital_chatbot',
      model: Gemini(
        model: 'gemini-2.5-flash',
        environment: <String, String>{'GEMINI_API_KEY': apiKey},
      ),
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

    final InMemoryRunner runner = InMemoryRunner(
      agent: agent,
      appName: 'flutter_adk_chatbot_example',
    );
    final String sessionId = 'session_${DateTime.now().microsecondsSinceEpoch}';
    await runner.sessionService.createSession(
      appName: runner.appName,
      userId: _userId,
      sessionId: sessionId,
    );

    _runner = runner;
    _runnerApiKey = apiKey;
    _sessionId = sessionId;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter ADK Chatbot'),
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
          Expanded(
            child: _messages.length == 1
                ? const Center(
                    child: Text(
                      '메시지를 보내 챗봇을 시작하세요.',
                      style: TextStyle(fontSize: 16),
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
                      decoration: const InputDecoration(
                        hintText: '질문을 입력하세요...',
                        border: OutlineInputBorder(),
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
      ),
    );
  }
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
