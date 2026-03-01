import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_adk/flutter_adk.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _apiKeyPrefKey = 'flutter_adk_example_gemini_api_key';
const String _mcpUrlPrefKey = 'flutter_adk_example_mcp_url';
const String _mcpBearerTokenPrefKey = 'flutter_adk_example_mcp_bearer_token';
const String _languagePrefKey = 'flutter_adk_example_language';
const String _loopCompletionPhrase = 'No major issues found.';

enum _AppLanguage { en, ko, ja, zh }

extension _AppLanguageX on _AppLanguage {
  String get code {
    switch (this) {
      case _AppLanguage.en:
        return 'en';
      case _AppLanguage.ko:
        return 'ko';
      case _AppLanguage.ja:
        return 'ja';
      case _AppLanguage.zh:
        return 'zh';
    }
  }

  String get nativeLabel {
    switch (this) {
      case _AppLanguage.en:
        return 'English';
      case _AppLanguage.ko:
        return '한국어';
      case _AppLanguage.ja:
        return '日本語';
      case _AppLanguage.zh:
        return '中文';
    }
  }
}

_AppLanguage _appLanguageFromCode(String? code) {
  switch (code) {
    case 'ko':
      return _AppLanguage.ko;
    case 'ja':
      return _AppLanguage.ja;
    case 'zh':
      return _AppLanguage.zh;
    case 'en':
    default:
      return _AppLanguage.en;
  }
}

String _responseLanguageInstruction(_AppLanguage language) {
  switch (language) {
    case _AppLanguage.en:
      return 'Respond in English.';
    case _AppLanguage.ko:
      return 'Respond in Korean.';
    case _AppLanguage.ja:
      return 'Respond in Japanese.';
    case _AppLanguage.zh:
      return 'Respond in Simplified Chinese.';
  }
}

class _ExampleTab {
  const _ExampleTab({required this.labelKey, required this.icon});

  final String labelKey;
  final IconData icon;
}

const List<_ExampleTab> _exampleTabs = <_ExampleTab>[
  _ExampleTab(labelKey: 'tab.basic', icon: Icons.chat_bubble_outline),
  _ExampleTab(labelKey: 'tab.transfer', icon: Icons.hub_outlined),
  _ExampleTab(labelKey: 'tab.workflow', icon: Icons.account_tree_outlined),
  _ExampleTab(labelKey: 'tab.sequential', icon: Icons.linear_scale_outlined),
  _ExampleTab(labelKey: 'tab.parallel', icon: Icons.call_split_outlined),
  _ExampleTab(labelKey: 'tab.loop', icon: Icons.loop_outlined),
  _ExampleTab(labelKey: 'tab.team', icon: Icons.groups_outlined),
  _ExampleTab(labelKey: 'tab.mcp', icon: Icons.extension_outlined),
  _ExampleTab(labelKey: 'tab.skills', icon: Icons.psychology_outlined),
];

const Map<String, Map<_AppLanguage, String>>
_i18n = <String, Map<_AppLanguage, String>>{
  'app.title': <_AppLanguage, String>{
    _AppLanguage.en: 'Flutter ADK Examples',
    _AppLanguage.ko: 'Flutter ADK 예제',
    _AppLanguage.ja: 'Flutter ADK サンプル',
    _AppLanguage.zh: 'Flutter ADK 示例',
  },
  'app.settings': <_AppLanguage, String>{
    _AppLanguage.en: 'Settings',
    _AppLanguage.ko: '설정',
    _AppLanguage.ja: '設定',
    _AppLanguage.zh: '设置',
  },
  'app.language': <_AppLanguage, String>{
    _AppLanguage.en: 'Language',
    _AppLanguage.ko: '언어',
    _AppLanguage.ja: '言語',
    _AppLanguage.zh: '语言',
  },
  'app.settings_saved': <_AppLanguage, String>{
    _AppLanguage.en: 'Settings saved.',
    _AppLanguage.ko: '설정이 저장되었습니다.',
    _AppLanguage.ja: '設定を保存しました。',
    _AppLanguage.zh: '设置已保存。',
  },
  'app.no_api_key': <_AppLanguage, String>{
    _AppLanguage.en:
        'You need to configure an API key to receive model responses.',
    _AppLanguage.ko: 'API 키를 설정해야 실제 모델 응답을 받을 수 있습니다.',
    _AppLanguage.ja: 'モデル応答を受け取るには API キー設定が必要です。',
    _AppLanguage.zh: '需要配置 API Key 才能获取模型响应。',
  },
  'app.set_api_key': <_AppLanguage, String>{
    _AppLanguage.en: 'Set API Key',
    _AppLanguage.ko: 'API 키 설정',
    _AppLanguage.ja: 'API キー設定',
    _AppLanguage.zh: '设置 API Key',
  },
  'settings.title': <_AppLanguage, String>{
    _AppLanguage.en: 'API Settings',
    _AppLanguage.ko: 'API 설정',
    _AppLanguage.ja: 'API 設定',
    _AppLanguage.zh: 'API 设置',
  },
  'settings.api_key': <_AppLanguage, String>{
    _AppLanguage.en: 'Gemini API Key',
    _AppLanguage.ko: 'Gemini API Key',
    _AppLanguage.ja: 'Gemini API Key',
    _AppLanguage.zh: 'Gemini API Key',
  },
  'settings.mcp_url': <_AppLanguage, String>{
    _AppLanguage.en: 'MCP Streamable HTTP URL',
    _AppLanguage.ko: 'MCP Streamable HTTP URL',
    _AppLanguage.ja: 'MCP Streamable HTTP URL',
    _AppLanguage.zh: 'MCP Streamable HTTP URL',
  },
  'settings.mcp_token': <_AppLanguage, String>{
    _AppLanguage.en: 'MCP Bearer Token (Optional)',
    _AppLanguage.ko: 'MCP Bearer Token (선택)',
    _AppLanguage.ja: 'MCP Bearer Token（任意）',
    _AppLanguage.zh: 'MCP Bearer Token（可选）',
  },
  'settings.security': <_AppLanguage, String>{
    _AppLanguage.en:
        'Storing keys in browser storage may expose secrets. Use a server proxy in production.',
    _AppLanguage.ko: '웹 브라우저에 키를 저장하는 경우 노출 위험이 있습니다. 프로덕션은 서버 프록시를 권장합니다.',
    _AppLanguage.ja: 'ブラウザ保存は鍵漏洩リスクがあります。本番環境ではサーバープロキシを推奨します。',
    _AppLanguage.zh: '将密钥保存在浏览器中存在泄露风险，生产环境建议使用服务端代理。',
  },
  'settings.clear': <_AppLanguage, String>{
    _AppLanguage.en: 'Clear Keys',
    _AppLanguage.ko: '키 삭제',
    _AppLanguage.ja: 'キー削除',
    _AppLanguage.zh: '清除密钥',
  },
  'settings.save': <_AppLanguage, String>{
    _AppLanguage.en: 'Save',
    _AppLanguage.ko: '저장',
    _AppLanguage.ja: '保存',
    _AppLanguage.zh: '保存',
  },
  'error.api_key_required': <_AppLanguage, String>{
    _AppLanguage.en: 'Please set Gemini API key first.',
    _AppLanguage.ko: 'Gemini API 키를 먼저 설정하세요.',
    _AppLanguage.ja: '先に Gemini API キーを設定してください。',
    _AppLanguage.zh: '请先设置 Gemini API Key。',
  },
  'error.prefix': <_AppLanguage, String>{
    _AppLanguage.en: 'An error occurred: ',
    _AppLanguage.ko: '오류가 발생했습니다: ',
    _AppLanguage.ja: 'エラーが発生しました: ',
    _AppLanguage.zh: '发生错误：',
  },
  'error.no_response_text': <_AppLanguage, String>{
    _AppLanguage.en: 'Could not find response text.',
    _AppLanguage.ko: '응답 텍스트를 찾지 못했습니다.',
    _AppLanguage.ja: '応答テキストが見つかりませんでした。',
    _AppLanguage.zh: '未找到响应文本。',
  },
  'tab.basic': <_AppLanguage, String>{
    _AppLanguage.en: 'Basic Chatbot',
    _AppLanguage.ko: '기본 챗봇',
    _AppLanguage.ja: '基本チャットボット',
    _AppLanguage.zh: '基础聊天机器人',
  },
  'tab.transfer': <_AppLanguage, String>{
    _AppLanguage.en: 'Transfer Multi-Agent',
    _AppLanguage.ko: '전달 멀티에이전트',
    _AppLanguage.ja: 'Transfer マルチエージェント',
    _AppLanguage.zh: 'Transfer 多智能体',
  },
  'tab.workflow': <_AppLanguage, String>{
    _AppLanguage.en: 'Workflow Combo',
    _AppLanguage.ko: '워크플로우 조합',
    _AppLanguage.ja: 'Workflow 組み合わせ',
    _AppLanguage.zh: '工作流组合',
  },
  'tab.sequential': <_AppLanguage, String>{
    _AppLanguage.en: 'Sequential',
    _AppLanguage.ko: '순차',
    _AppLanguage.ja: '順次',
    _AppLanguage.zh: '顺序',
  },
  'tab.parallel': <_AppLanguage, String>{
    _AppLanguage.en: 'Parallel',
    _AppLanguage.ko: '병렬',
    _AppLanguage.ja: '並列',
    _AppLanguage.zh: '并行',
  },
  'tab.loop': <_AppLanguage, String>{
    _AppLanguage.en: 'Loop',
    _AppLanguage.ko: '루프',
    _AppLanguage.ja: 'ループ',
    _AppLanguage.zh: '循环',
  },
  'tab.team': <_AppLanguage, String>{
    _AppLanguage.en: 'Agent Team',
    _AppLanguage.ko: '에이전트 팀',
    _AppLanguage.ja: 'エージェントチーム',
    _AppLanguage.zh: '智能体团队',
  },
  'tab.mcp': <_AppLanguage, String>{
    _AppLanguage.en: 'MCP Toolset',
    _AppLanguage.ko: 'MCP 툴셋',
    _AppLanguage.ja: 'MCP ツールセット',
    _AppLanguage.zh: 'MCP 工具集',
  },
  'tab.skills': <_AppLanguage, String>{
    _AppLanguage.en: 'Skills',
    _AppLanguage.ko: '스킬',
    _AppLanguage.ja: 'スキル',
    _AppLanguage.zh: '技能',
  },
  'basic.title': <_AppLanguage, String>{
    _AppLanguage.en: 'Basic Chatbot Example',
    _AppLanguage.ko: '기본 챗봇 예제',
    _AppLanguage.ja: '基本チャットボット例',
    _AppLanguage.zh: '基础聊天机器人示例',
  },
  'basic.summary': <_AppLanguage, String>{
    _AppLanguage.en: 'Single Agent + FunctionTool example.',
    _AppLanguage.ko: '단일 Agent + FunctionTool 기반 예제입니다.',
    _AppLanguage.ja: '単一 Agent + FunctionTool の例です。',
    _AppLanguage.zh: '单一 Agent + FunctionTool 示例。',
  },
  'basic.initial': <_AppLanguage, String>{
    _AppLanguage.en:
        'Hello. This is a basic chatbot for capital-city lookup and general Q&A.\nSet API key and send a message.',
    _AppLanguage.ko:
        '안녕하세요. 국가 수도, 일반 Q&A를 처리하는 기본 챗봇 예제입니다.\nAPI 키를 설정하고 질문을 보내세요.',
    _AppLanguage.ja:
        'こんにちは。国の首都検索と一般Q&Aに対応する基本チャットボットです。\nAPI キーを設定して質問してください。',
    _AppLanguage.zh: '你好，这是一个处理首都查询和通用问答的基础聊天机器人。\n请先设置 API Key 再提问。',
  },
  'basic.empty': <_AppLanguage, String>{
    _AppLanguage.en: 'Send a message to start the basic chatbot.',
    _AppLanguage.ko: '메시지를 보내 기본 챗봇을 시작하세요.',
    _AppLanguage.ja: 'メッセージを送信して基本チャットボットを開始してください。',
    _AppLanguage.zh: '发送消息以开始基础聊天机器人。',
  },
  'basic.hint': <_AppLanguage, String>{
    _AppLanguage.en: 'Ask the basic chatbot...',
    _AppLanguage.ko: '기본 챗봇에게 질문하기...',
    _AppLanguage.ja: '基本チャットボットに質問...',
    _AppLanguage.zh: '向基础聊天机器人提问...',
  },
  'transfer.title': <_AppLanguage, String>{
    _AppLanguage.en: 'Multi-Agent Coordinator Example',
    _AppLanguage.ko: '멀티에이전트 코디네이터 예제',
    _AppLanguage.ja: 'マルチエージェント コーディネーター例',
    _AppLanguage.zh: '多智能体协调器示例',
  },
  'transfer.summary': <_AppLanguage, String>{
    _AppLanguage.en:
        'Coordinator/Dispatcher pattern with Billing and Support transfers.',
    _AppLanguage.ko:
        'Coordinator/Dispatcher 패턴 (Billing/Support transfer) 예제입니다.',
    _AppLanguage.ja:
        'Coordinator/Dispatcher パターン（Billing/Support transfer）例です。',
    _AppLanguage.zh: 'Coordinator/Dispatcher 模式（Billing/Support transfer）示例。',
  },
  'transfer.initial': <_AppLanguage, String>{
    _AppLanguage.en:
        'Hello. This multi-agent coordinator routes billing issues to Billing and technical issues to Support.',
    _AppLanguage.ko: '안녕하세요. 결제/청구 문의는 Billing, 기술/로그인 문의는 Support로 라우팅합니다.',
    _AppLanguage.ja: 'こんにちは。請求関連は Billing、技術/ログイン問題は Support にルーティングします。',
    _AppLanguage.zh: '你好，计费问题会路由到 Billing，技术/登录问题会路由到 Support。',
  },
  'transfer.empty': <_AppLanguage, String>{
    _AppLanguage.en: 'Send a message to test multi-agent routing.',
    _AppLanguage.ko: '메시지를 보내 멀티에이전트 라우팅을 확인하세요.',
    _AppLanguage.ja: 'メッセージを送ってマルチエージェントのルーティングを確認してください。',
    _AppLanguage.zh: '发送消息以验证多智能体路由。',
  },
  'transfer.hint': <_AppLanguage, String>{
    _AppLanguage.en: 'e.g. I was charged twice / I cannot login',
    _AppLanguage.ko: '예: 결제가 두 번 청구됐어요 / 로그인이 안돼요',
    _AppLanguage.ja: '例: 二重請求されました / ログインできません',
    _AppLanguage.zh: '例如：被重复扣费了 / 无法登录',
  },
  'workflow.title': <_AppLanguage, String>{
    _AppLanguage.en: 'Workflow Agents Example',
    _AppLanguage.ko: '워크플로우 에이전트 예제',
    _AppLanguage.ja: 'ワークフローエージェント例',
    _AppLanguage.zh: '工作流智能体示例',
  },
  'workflow.summary': <_AppLanguage, String>{
    _AppLanguage.en: 'Sequential + Parallel + Loop composition example.',
    _AppLanguage.ko: 'Sequential + Parallel + Loop 조합 예제입니다.',
    _AppLanguage.ja: 'Sequential + Parallel + Loop の組み合わせ例です。',
    _AppLanguage.zh: 'Sequential + Parallel + Loop 组合示例。',
  },
  'workflow.initial': <_AppLanguage, String>{
    _AppLanguage.en:
        'Hello. Send a question and it runs through Sequential/Parallel/Loop chain.',
    _AppLanguage.ko: '안녕하세요. 질문을 보내면 Sequential/Parallel/Loop 체인으로 처리합니다.',
    _AppLanguage.ja: 'こんにちは。質問を送ると Sequential/Parallel/Loop チェーンで処理します。',
    _AppLanguage.zh: '你好，发送问题后会通过 Sequential/Parallel/Loop 链路处理。',
  },
  'workflow.empty': <_AppLanguage, String>{
    _AppLanguage.en: 'Send a message to run workflow pipeline.',
    _AppLanguage.ko: '메시지를 보내 워크플로우 실행을 확인하세요.',
    _AppLanguage.ja: 'メッセージを送ってワークフロー実行を確認してください。',
    _AppLanguage.zh: '发送消息以执行工作流。',
  },
  'workflow.hint': <_AppLanguage, String>{
    _AppLanguage.en: 'e.g. Plan a 3-day trip in Paris',
    _AppLanguage.ko: '예: 파리 2박 3일 일정 추천',
    _AppLanguage.ja: '例: パリ2泊3日の旅行プラン',
    _AppLanguage.zh: '例如：推荐巴黎三日行程',
  },
  'sequential.title': <_AppLanguage, String>{
    _AppLanguage.en: 'SequentialAgent Example',
    _AppLanguage.ko: 'SequentialAgent 예제',
    _AppLanguage.ja: 'SequentialAgent 例',
    _AppLanguage.zh: 'SequentialAgent 示例',
  },
  'sequential.summary': <_AppLanguage, String>{
    _AppLanguage.en: 'Writer -> Reviewer -> Refactorer fixed pipeline.',
    _AppLanguage.ko: 'Code Writer -> Reviewer -> Refactorer 순차 실행 예제입니다.',
    _AppLanguage.ja: 'Code Writer -> Reviewer -> Refactorer の順次パイプラインです。',
    _AppLanguage.zh: 'Code Writer -> Reviewer -> Refactorer 固定顺序流水线示例。',
  },
  'sequential.initial': <_AppLanguage, String>{
    _AppLanguage.en:
        'Hello. Send a request and it runs write-review-refactor in sequence.',
    _AppLanguage.ko: '안녕하세요. 요청을 보내면 작성-리뷰-리팩터링을 순차 실행합니다.',
    _AppLanguage.ja: 'こんにちは。リクエストを送ると作成→レビュー→リファクタを順次実行します。',
    _AppLanguage.zh: '你好，发送请求后会按“编写-评审-重构”顺序执行。',
  },
  'sequential.empty': <_AppLanguage, String>{
    _AppLanguage.en: 'Send a message to run sequential workflow.',
    _AppLanguage.ko: '메시지를 보내 Sequential 워크플로우를 실행하세요.',
    _AppLanguage.ja: 'メッセージを送って Sequential ワークフローを実行してください。',
    _AppLanguage.zh: '发送消息以运行 Sequential 工作流。',
  },
  'sequential.hint': <_AppLanguage, String>{
    _AppLanguage.en: 'e.g. Write a Python function that reverses a string',
    _AppLanguage.ko: '예: 문자열을 뒤집는 파이썬 함수를 작성해줘',
    _AppLanguage.ja: '例: 文字列を反転する Python 関数を書いて',
    _AppLanguage.zh: '例如：写一个反转字符串的 Python 函数',
  },
  'parallel.title': <_AppLanguage, String>{
    _AppLanguage.en: 'ParallelAgent Example',
    _AppLanguage.ko: 'ParallelAgent 예제',
    _AppLanguage.ja: 'ParallelAgent 例',
    _AppLanguage.zh: 'ParallelAgent 示例',
  },
  'parallel.summary': <_AppLanguage, String>{
    _AppLanguage.en: 'Run independent perspectives in parallel and synthesize.',
    _AppLanguage.ko: '독립 관점 에이전트를 병렬 실행 후 결과를 통합합니다.',
    _AppLanguage.ja: '独立観点エージェントを並列実行して統合します。',
    _AppLanguage.zh: '并行执行独立视角后再统一总结。',
  },
  'parallel.initial': <_AppLanguage, String>{
    _AppLanguage.en:
        'Hello. It generates multiple angles in parallel and returns a synthesis.',
    _AppLanguage.ko: '안녕하세요. 질문을 보내면 여러 관점을 동시에 생성해 요약합니다.',
    _AppLanguage.ja: 'こんにちは。質問を送ると複数観点を並列生成し、要約します。',
    _AppLanguage.zh: '你好，发送问题后会并行生成多个视角并汇总。',
  },
  'parallel.empty': <_AppLanguage, String>{
    _AppLanguage.en: 'Send a message to run parallel workflow.',
    _AppLanguage.ko: '메시지를 보내 Parallel 워크플로우를 실행하세요.',
    _AppLanguage.ja: 'メッセージを送って Parallel ワークフローを実行してください。',
    _AppLanguage.zh: '发送消息以运行 Parallel 工作流。',
  },
  'parallel.hint': <_AppLanguage, String>{
    _AppLanguage.en: 'e.g. Propose a paid plan launch strategy',
    _AppLanguage.ko: '예: 신규 유료 플랜 출시 전략을 정리해줘',
    _AppLanguage.ja: '例: 新しい有料プランのローンチ戦略を整理して',
    _AppLanguage.zh: '例如：整理新付费方案上线策略',
  },
  'loop.title': <_AppLanguage, String>{
    _AppLanguage.en: 'LoopAgent Example',
    _AppLanguage.ko: 'LoopAgent 예제',
    _AppLanguage.ja: 'LoopAgent 例',
    _AppLanguage.zh: 'LoopAgent 示例',
  },
  'loop.summary': <_AppLanguage, String>{
    _AppLanguage.en: 'Iterative refinement with Critic/Refiner and exit_loop.',
    _AppLanguage.ko: 'Critic + Refiner 반복 개선과 exit_loop 종료 예제입니다.',
    _AppLanguage.ja: 'Critic + Refiner の反復改善と exit_loop 終了例です。',
    _AppLanguage.zh: 'Critic + Refiner 迭代优化并通过 exit_loop 结束。',
  },
  'loop.initial': <_AppLanguage, String>{
    _AppLanguage.en:
        'Hello. It writes an initial draft and iteratively refines it.',
    _AppLanguage.ko: '안녕하세요. 초안 작성 후 반복 개선하고, 완료 조건이면 루프를 종료합니다.',
    _AppLanguage.ja: 'こんにちは。初稿を作成後、反復改善し、完了条件でループを終了します。',
    _AppLanguage.zh: '你好，会先生成初稿并迭代优化，满足条件后结束循环。',
  },
  'loop.empty': <_AppLanguage, String>{
    _AppLanguage.en: 'Send a message to run loop workflow.',
    _AppLanguage.ko: '메시지를 보내 Loop 워크플로우를 실행하세요.',
    _AppLanguage.ja: 'メッセージを送って Loop ワークフローを実行してください。',
    _AppLanguage.zh: '发送消息以运行 Loop 工作流。',
  },
  'loop.hint': <_AppLanguage, String>{
    _AppLanguage.en: 'e.g. Write a short story about a cat',
    _AppLanguage.ko: '예: 고양이에 대한 짧은 동화를 써줘',
    _AppLanguage.ja: '例: 猫についての短い物語を書いて',
    _AppLanguage.zh: '例如：写一篇关于猫的短故事',
  },
  'team.title': <_AppLanguage, String>{
    _AppLanguage.en: 'Agent Team Example',
    _AppLanguage.ko: 'Agent Team 예제',
    _AppLanguage.ja: 'Agent Team 例',
    _AppLanguage.zh: 'Agent Team 示例',
  },
  'team.summary': <_AppLanguage, String>{
    _AppLanguage.en: 'Coordinator transfers to Greeting/Weather/Farewell.',
    _AppLanguage.ko: 'Coordinator가 Greeting/Weather/Farewell로 transfer합니다.',
    _AppLanguage.ja: 'Coordinator が Greeting/Weather/Farewell に transfer します。',
    _AppLanguage.zh: 'Coordinator 会 transfer 到 Greeting/Weather/Farewell。',
  },
  'team.initial': <_AppLanguage, String>{
    _AppLanguage.en:
        'Hello. Greeting/weather/time/farewell requests are routed to specialists.',
    _AppLanguage.ko: '안녕하세요. 인사/날씨/시간/작별 요청을 각각 전담 에이전트로 라우팅합니다.',
    _AppLanguage.ja: 'こんにちは。挨拶/天気/時刻/別れの要求を専門エージェントにルーティングします。',
    _AppLanguage.zh: '你好，问候/天气/时间/告别请求会路由到对应专家智能体。',
  },
  'team.empty': <_AppLanguage, String>{
    _AppLanguage.en: 'Send a message to test agent team routing.',
    _AppLanguage.ko: '메시지를 보내 Agent Team 라우팅을 확인하세요.',
    _AppLanguage.ja: 'メッセージを送って Agent Team ルーティングを確認してください。',
    _AppLanguage.zh: '发送消息以验证 Agent Team 路由。',
  },
  'team.hint': <_AppLanguage, String>{
    _AppLanguage.en: 'e.g. What time is it in Seoul? / Weather in New York?',
    _AppLanguage.ko: '예: 서울 시간 알려줘 / 뉴욕 날씨 어때?',
    _AppLanguage.ja: '例: ソウルの時間は？ / ニューヨークの天気は？',
    _AppLanguage.zh: '例如：首尔现在几点？/ 纽约天气如何？',
  },
  'mcp.title': <_AppLanguage, String>{
    _AppLanguage.en: 'MCP Toolset Example',
    _AppLanguage.ko: 'MCP Toolset 예제',
    _AppLanguage.ja: 'MCP Toolset 例',
    _AppLanguage.zh: 'MCP Toolset 示例',
  },
  'mcp.summary': <_AppLanguage, String>{
    _AppLanguage.en: 'Remote MCP tools via McpToolset(Streamable HTTP).',
    _AppLanguage.ko: 'McpToolset(Streamable HTTP) 기반 원격 MCP 도구 예제입니다.',
    _AppLanguage.ja: 'McpToolset（Streamable HTTP）によるリモート MCP ツール例です。',
    _AppLanguage.zh: '基于 McpToolset（Streamable HTTP）的远程 MCP 工具示例。',
  },
  'mcp.initial': <_AppLanguage, String>{
    _AppLanguage.en:
        'Hello. Configure MCP URL in settings first, then send a request.',
    _AppLanguage.ko: '안녕하세요. 먼저 설정에서 MCP URL을 입력한 뒤 메시지를 보내세요.',
    _AppLanguage.ja: 'こんにちは。先に設定で MCP URL を入力してからメッセージを送ってください。',
    _AppLanguage.zh: '你好，请先在设置中填写 MCP URL 再发送请求。',
  },
  'mcp.empty': <_AppLanguage, String>{
    _AppLanguage.en: 'Send a message to test MCP toolset.',
    _AppLanguage.ko: '메시지를 보내 MCP Toolset 동작을 확인하세요.',
    _AppLanguage.ja: 'メッセージを送って MCP Toolset の動作を確認してください。',
    _AppLanguage.zh: '发送消息以测试 MCP Toolset。',
  },
  'mcp.hint': <_AppLanguage, String>{
    _AppLanguage.en: 'e.g. Check MCP connection status',
    _AppLanguage.ko: '예: MCP 연결 상태 확인해줘',
    _AppLanguage.ja: '例: MCP 接続状態を確認して',
    _AppLanguage.zh: '例如：检查 MCP 连接状态',
  },
  'skills.title': <_AppLanguage, String>{
    _AppLanguage.en: 'SkillToolset Example',
    _AppLanguage.ko: 'SkillToolset 예제',
    _AppLanguage.ja: 'SkillToolset 例',
    _AppLanguage.zh: 'SkillToolset 示例',
  },
  'skills.summary': <_AppLanguage, String>{
    _AppLanguage.en: 'Inline Skill + SkillToolset orchestration example.',
    _AppLanguage.ko: 'inline Skill + SkillToolset 오케스트레이션 예제입니다.',
    _AppLanguage.ja: 'inline Skill + SkillToolset オーケストレーション例です。',
    _AppLanguage.zh: 'inline Skill + SkillToolset 编排示例。',
  },
  'skills.initial': <_AppLanguage, String>{
    _AppLanguage.en:
        'Hello. It lists/loads skills and follows skill resources to solve tasks.',
    _AppLanguage.ko: '안녕하세요. skill을 list/load하고 resource 지시를 따라 작업을 처리합니다.',
    _AppLanguage.ja: 'こんにちは。skill を list/load し、resource 指示に従って処理します。',
    _AppLanguage.zh: '你好，会先 list/load skill 并按照 resource 指示完成任务。',
  },
  'skills.empty': <_AppLanguage, String>{
    _AppLanguage.en: 'Send a message to test skills flow.',
    _AppLanguage.ko: '메시지를 보내 Skills 동작을 확인하세요.',
    _AppLanguage.ja: 'メッセージを送って Skills の動作を確認してください。',
    _AppLanguage.zh: '发送消息以测试 Skills 流程。',
  },
  'skills.hint': <_AppLanguage, String>{
    _AppLanguage.en: 'e.g. Improve this blog post structure',
    _AppLanguage.ko: '예: 블로그 글 구조를 개선해줘',
    _AppLanguage.ja: '例: このブログ記事の構成を改善して',
    _AppLanguage.zh: '例如：优化这篇博客的结构',
  },
};

String _tr(_AppLanguage language, String key) {
  final Map<_AppLanguage, String>? values = _i18n[key];
  if (values == null) {
    return key;
  }
  return values[language] ?? values[_AppLanguage.en] ?? key;
}

class _AppSettings {
  const _AppSettings({
    required this.apiKey,
    required this.mcpUrl,
    required this.mcpBearerToken,
    required this.language,
  });

  final String apiKey;
  final String mcpUrl;
  final String mcpBearerToken;
  final _AppLanguage language;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  _AppSettings copyWith({
    String? apiKey,
    String? mcpUrl,
    String? mcpBearerToken,
    _AppLanguage? language,
  }) {
    return _AppSettings(
      apiKey: apiKey ?? this.apiKey,
      mcpUrl: mcpUrl ?? this.mcpUrl,
      mcpBearerToken: mcpBearerToken ?? this.mcpBearerToken,
      language: language ?? this.language,
    );
  }
}

abstract interface class _SettingsRepository {
  Future<_AppSettings> load({required _AppLanguage fallbackLanguage});

  Future<void> save(_AppSettings settings);
}

class _SharedPreferencesSettingsRepository implements _SettingsRepository {
  @override
  Future<_AppSettings> load({required _AppLanguage fallbackLanguage}) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return _AppSettings(
        apiKey: prefs.getString(_apiKeyPrefKey) ?? '',
        mcpUrl: prefs.getString(_mcpUrlPrefKey) ?? '',
        mcpBearerToken: prefs.getString(_mcpBearerTokenPrefKey) ?? '',
        language: _appLanguageFromCode(
          prefs.getString(_languagePrefKey) ?? fallbackLanguage.code,
        ),
      );
    } on MissingPluginException {
      return _AppSettings(
        apiKey: '',
        mcpUrl: '',
        mcpBearerToken: '',
        language: fallbackLanguage,
      );
    }
  }

  @override
  Future<void> save(_AppSettings settings) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String apiKey = settings.apiKey.trim();
      final String mcpUrl = settings.mcpUrl.trim();
      final String mcpBearerToken = settings.mcpBearerToken.trim();
      if (apiKey.isEmpty) {
        await prefs.remove(_apiKeyPrefKey);
      } else {
        await prefs.setString(_apiKeyPrefKey, apiKey);
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
      await prefs.setString(_languagePrefKey, settings.language.code);
    } on MissingPluginException {
      // Keep running with in-memory state when plugin is unavailable.
    }
  }
}

class _AppShellViewModel extends ChangeNotifier {
  _AppShellViewModel({required _SettingsRepository settingsRepository})
    : _settingsRepository = settingsRepository;

  final _SettingsRepository _settingsRepository;

  _AppSettings _settings = const _AppSettings(
    apiKey: '',
    mcpUrl: '',
    mcpBearerToken: '',
    language: _AppLanguage.en,
  );
  int _selectedExampleIndex = 0;

  _AppSettings get settings => _settings;
  int get selectedExampleIndex => _selectedExampleIndex;
  _AppLanguage get selectedLanguage => _settings.language;
  String get apiKey => _settings.apiKey;
  String get mcpUrl => _settings.mcpUrl;
  String get mcpBearerToken => _settings.mcpBearerToken;
  bool get hasApiKey => _settings.hasApiKey;

  Future<void> initialize({required _AppLanguage fallbackLanguage}) async {
    _settings = await _settingsRepository.load(
      fallbackLanguage: fallbackLanguage,
    );
    notifyListeners();
  }

  void setSelectedExample(int index) {
    if (_selectedExampleIndex == index) {
      return;
    }
    _selectedExampleIndex = index;
    notifyListeners();
  }

  Future<void> setLanguage(_AppLanguage language) async {
    if (_settings.language == language) {
      return;
    }
    _settings = _settings.copyWith(language: language);
    notifyListeners();
    await _settingsRepository.save(_settings);
  }

  Future<void> saveSettings({
    required String apiKey,
    required String mcpUrl,
    required String mcpBearerToken,
  }) async {
    _settings = _settings.copyWith(
      apiKey: apiKey,
      mcpUrl: mcpUrl,
      mcpBearerToken: mcpBearerToken,
    );
    notifyListeners();
    await _settingsRepository.save(_settings);
  }
}

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

  late final _AppShellViewModel _viewModel;

  bool _obscureApiKey = true;
  bool _obscureMcpBearerToken = true;
  bool get _hasApiKey => _viewModel.hasApiKey;
  String _t(String key) => _tr(_viewModel.selectedLanguage, key);

  @override
  void initState() {
    super.initState();
    _viewModel = _AppShellViewModel(
      settingsRepository: _SharedPreferencesSettingsRepository(),
    );
    _viewModel.addListener(_onViewModelChanged);
    unawaited(_initializeViewModel());
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _apiKeyController.dispose();
    _mcpUrlController.dispose();
    _mcpBearerTokenController.dispose();
    super.dispose();
  }

  Future<void> _initializeViewModel() async {
    await _viewModel.initialize(
      fallbackLanguage: _appLanguageFromCode(
        WidgetsBinding.instance.platformDispatcher.locale.languageCode,
      ),
    );
    _syncControllersFromSettings();
  }

  void _onViewModelChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _syncControllersFromSettings() {
    _apiKeyController.text = _viewModel.apiKey;
    _mcpUrlController.text = _viewModel.mcpUrl;
    _mcpBearerTokenController.text = _viewModel.mcpBearerToken;
  }

  Future<void> _saveApiKey({bool showSnackBar = true}) async {
    await _viewModel.saveSettings(
      apiKey: _apiKeyController.text.trim(),
      mcpUrl: _mcpUrlController.text.trim(),
      mcpBearerToken: _mcpBearerTokenController.text.trim(),
    );

    if (!mounted) {
      return;
    }
    setState(() {});
    if (showSnackBar) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t('app.settings_saved'))));
    }
  }

  Future<void> _clearApiKey() async {
    _apiKeyController.clear();
    _mcpUrlController.clear();
    _mcpBearerTokenController.clear();
    await _saveApiKey();
  }

  Future<void> _openSettingsSheet() async {
    _syncControllersFromSettings();
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
                  Text(
                    _t('settings.title'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: _t('settings.api_key'),
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
                    decoration: InputDecoration(
                      labelText: _t('settings.mcp_url'),
                      hintText: 'https://your-mcp-server.example.com/mcp',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _mcpBearerTokenController,
                    obscureText: _obscureMcpBearerToken,
                    decoration: InputDecoration(
                      labelText: _t('settings.mcp_token'),
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
                  Text(
                    _t('settings.security'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      OutlinedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _clearApiKey();
                        },
                        child: Text(_t('settings.clear')),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _saveApiKey();
                        },
                        child: Text(_t('settings.save')),
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
        title: Text(_t('app.title')),
        actions: <Widget>[
          PopupMenuButton<_AppLanguage>(
            tooltip: _t('app.language'),
            icon: const Icon(Icons.translate),
            onSelected: (_AppLanguage language) async {
              if (_viewModel.selectedLanguage == language) {
                return;
              }
              await _viewModel.setLanguage(language);
            },
            itemBuilder: (BuildContext context) {
              return _AppLanguage.values.map((final _AppLanguage language) {
                return PopupMenuItem<_AppLanguage>(
                  value: language,
                  child: Row(
                    children: <Widget>[
                      if (_viewModel.selectedLanguage == language)
                        const Icon(Icons.check, size: 16)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text(language.nativeLabel),
                    ],
                  ),
                );
              }).toList();
            },
          ),
          Icon(
            _hasApiKey ? Icons.verified : Icons.warning_amber_rounded,
            color: _hasApiKey ? Colors.green : Colors.orange,
          ),
          IconButton(
            tooltip: _t('app.settings'),
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
                  Expanded(child: Text(_t('app.no_api_key'))),
                  TextButton(
                    onPressed: _openSettingsSheet,
                    child: Text(_t('app.set_api_key')),
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
                      label: Text(_t(tab.labelKey)),
                      selected: _viewModel.selectedExampleIndex == index,
                      onSelected: (bool selected) {
                        if (!selected) {
                          return;
                        }
                        _viewModel.setSelectedExample(index);
                      },
                    ),
                  );
                }),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _viewModel.selectedExampleIndex,
              children: <Widget>[
                _ChatExampleView(
                  key: const ValueKey<String>('basic_example'),
                  exampleId: 'basic',
                  language: _viewModel.selectedLanguage,
                  exampleTitle: _t('basic.title'),
                  summary: _t('basic.summary'),
                  initialAssistantMessage: _t('basic.initial'),
                  emptyStateMessage: _t('basic.empty'),
                  inputHint: _t('basic.hint'),
                  apiKey: apiKey,
                  createAgent: _buildBasicAgent,
                  apiKeyMissingMessage: _t('error.api_key_required'),
                  genericErrorPrefix: _t('error.prefix'),
                  responseNotFoundMessage: _t('error.no_response_text'),
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('multi_agent_example'),
                  exampleId: 'multi_agent',
                  language: _viewModel.selectedLanguage,
                  exampleTitle: _t('transfer.title'),
                  summary: _t('transfer.summary'),
                  initialAssistantMessage: _t('transfer.initial'),
                  emptyStateMessage: _t('transfer.empty'),
                  inputHint: _t('transfer.hint'),
                  apiKey: apiKey,
                  createAgent: _buildMultiAgentCoordinator,
                  apiKeyMissingMessage: _t('error.api_key_required'),
                  genericErrorPrefix: _t('error.prefix'),
                  responseNotFoundMessage: _t('error.no_response_text'),
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('workflow_example'),
                  exampleId: 'workflow',
                  language: _viewModel.selectedLanguage,
                  exampleTitle: _t('workflow.title'),
                  summary: _t('workflow.summary'),
                  initialAssistantMessage: _t('workflow.initial'),
                  emptyStateMessage: _t('workflow.empty'),
                  inputHint: _t('workflow.hint'),
                  apiKey: apiKey,
                  createAgent: _buildWorkflowOrchestrator,
                  apiKeyMissingMessage: _t('error.api_key_required'),
                  genericErrorPrefix: _t('error.prefix'),
                  responseNotFoundMessage: _t('error.no_response_text'),
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('sequential_example'),
                  exampleId: 'sequential',
                  language: _viewModel.selectedLanguage,
                  exampleTitle: _t('sequential.title'),
                  summary: _t('sequential.summary'),
                  initialAssistantMessage: _t('sequential.initial'),
                  emptyStateMessage: _t('sequential.empty'),
                  inputHint: _t('sequential.hint'),
                  apiKey: apiKey,
                  createAgent: _buildSequentialCodePipeline,
                  apiKeyMissingMessage: _t('error.api_key_required'),
                  genericErrorPrefix: _t('error.prefix'),
                  responseNotFoundMessage: _t('error.no_response_text'),
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('parallel_example'),
                  exampleId: 'parallel',
                  language: _viewModel.selectedLanguage,
                  exampleTitle: _t('parallel.title'),
                  summary: _t('parallel.summary'),
                  initialAssistantMessage: _t('parallel.initial'),
                  emptyStateMessage: _t('parallel.empty'),
                  inputHint: _t('parallel.hint'),
                  apiKey: apiKey,
                  createAgent: _buildParallelResearchPipeline,
                  apiKeyMissingMessage: _t('error.api_key_required'),
                  genericErrorPrefix: _t('error.prefix'),
                  responseNotFoundMessage: _t('error.no_response_text'),
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('loop_example'),
                  exampleId: 'loop',
                  language: _viewModel.selectedLanguage,
                  exampleTitle: _t('loop.title'),
                  summary: _t('loop.summary'),
                  initialAssistantMessage: _t('loop.initial'),
                  emptyStateMessage: _t('loop.empty'),
                  inputHint: _t('loop.hint'),
                  apiKey: apiKey,
                  createAgent: _buildLoopRefinementPipeline,
                  apiKeyMissingMessage: _t('error.api_key_required'),
                  genericErrorPrefix: _t('error.prefix'),
                  responseNotFoundMessage: _t('error.no_response_text'),
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('agent_team_example'),
                  exampleId: 'agent_team',
                  language: _viewModel.selectedLanguage,
                  exampleTitle: _t('team.title'),
                  summary: _t('team.summary'),
                  initialAssistantMessage: _t('team.initial'),
                  emptyStateMessage: _t('team.empty'),
                  inputHint: _t('team.hint'),
                  apiKey: apiKey,
                  createAgent: _buildAgentTeamWeather,
                  apiKeyMissingMessage: _t('error.api_key_required'),
                  genericErrorPrefix: _t('error.prefix'),
                  responseNotFoundMessage: _t('error.no_response_text'),
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('mcp_toolset_example'),
                  exampleId: 'mcp_toolset',
                  language: _viewModel.selectedLanguage,
                  exampleTitle: _t('mcp.title'),
                  summary: _t('mcp.summary'),
                  initialAssistantMessage: _t('mcp.initial'),
                  emptyStateMessage: _t('mcp.empty'),
                  inputHint: _t('mcp.hint'),
                  apiKey: apiKey,
                  createAgent: (String key, _AppLanguage language) =>
                      _buildMcpToolsetAgent(
                        key,
                        language: language,
                        mcpUrl: mcpUrl,
                        mcpBearerToken: mcpBearerToken,
                      ),
                  apiKeyMissingMessage: _t('error.api_key_required'),
                  genericErrorPrefix: _t('error.prefix'),
                  responseNotFoundMessage: _t('error.no_response_text'),
                ),
                _ChatExampleView(
                  key: const ValueKey<String>('skills_example'),
                  exampleId: 'skills',
                  language: _viewModel.selectedLanguage,
                  exampleTitle: _t('skills.title'),
                  summary: _t('skills.summary'),
                  initialAssistantMessage: _t('skills.initial'),
                  emptyStateMessage: _t('skills.empty'),
                  inputHint: _t('skills.hint'),
                  apiKey: apiKey,
                  createAgent: _buildSkillsAgent,
                  apiKeyMissingMessage: _t('error.api_key_required'),
                  genericErrorPrefix: _t('error.prefix'),
                  responseNotFoundMessage: _t('error.no_response_text'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef _AgentFactory =
    BaseAgent Function(String apiKey, _AppLanguage language);

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
    required this.language,
    required this.createAgent,
    required this.apiKeyMissingMessage,
    required this.genericErrorPrefix,
    required this.responseNotFoundMessage,
  });

  final String exampleId;
  final String exampleTitle;
  final String summary;
  final String initialAssistantMessage;
  final String emptyStateMessage;
  final String inputHint;
  final String apiKey;
  final _AppLanguage language;
  final _AgentFactory createAgent;
  final String apiKeyMissingMessage;
  final String genericErrorPrefix;
  final String responseNotFoundMessage;

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
    if ((oldWidget.apiKey != widget.apiKey && _runnerApiKey != widget.apiKey) ||
        oldWidget.language != widget.language) {
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
      throw StateError(widget.apiKeyMissingMessage);
    }
    if (_runner != null && _runnerApiKey == apiKey) {
      return;
    }

    await _resetRunner();

    final BaseAgent agent = widget.createAgent(apiKey, widget.language);
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
        _messages.add(
          _ChatMessage.assistant('${widget.genericErrorPrefix}$error'),
        );
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
    return widget.responseNotFoundMessage;
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

Agent _buildBasicAgent(String apiKey, _AppLanguage language) {
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
${_responseLanguageInstruction(language)}
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

Agent _buildMultiAgentCoordinator(String apiKey, _AppLanguage language) {
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
${_responseLanguageInstruction(language)}
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
${_responseLanguageInstruction(language)}
''',
  );

  return Agent(
    name: 'HelpDeskCoordinator',
    model: _createGeminiModel(apiKey),
    description: 'Main help desk router.',
    instruction:
        '''
You are a help desk coordinator.
- Route payment or billing requests to Billing using transfer_to_agent.
- Route login/app/account technical requests to Support using transfer_to_agent.
- If unclear, ask one short clarification question before transfer.
- After routing, the selected specialist should provide the final answer.
${_responseLanguageInstruction(language)}
''',
    subAgents: <BaseAgent>[billingAgent, supportAgent],
  );
}

BaseAgent _buildWorkflowOrchestrator(String apiKey, _AppLanguage language) {
  final Agent summarize = Agent(
    name: 'SummarizeInput',
    model: _createGeminiModel(apiKey),
    instruction:
        '''
Read the latest user message and write a short summary.
- Keep it under 2 sentences.
- Save concise output for downstream steps.
${_responseLanguageInstruction(language)}
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
${_responseLanguageInstruction(language)}
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
${_responseLanguageInstruction(language)}
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
${_responseLanguageInstruction(language)}
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
${_responseLanguageInstruction(language)}
''',
  );

  return SequentialAgent(
    name: 'WorkflowOrchestrator',
    subAgents: <BaseAgent>[summarize, parallel, loop, finalAnswer],
  );
}

BaseAgent _buildSequentialCodePipeline(String apiKey, _AppLanguage language) {
  final Agent codeWriter = Agent(
    name: 'CodeWriterAgent',
    model: _createGeminiModel(apiKey),
    description: '요청을 기반으로 초기 코드를 작성합니다.',
    instruction:
        '''
You are a code writer.
- Read the latest user request and produce an initial solution.
- Output concise code and brief explanation.
${_responseLanguageInstruction(language)}
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
${_responseLanguageInstruction(language)}
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
${_responseLanguageInstruction(language)}
''',
  );

  return SequentialAgent(
    name: 'SequentialCodePipeline',
    description: 'Writer -> Reviewer -> Refactorer 순차 실행 예제',
    subAgents: <BaseAgent>[codeWriter, codeReviewer, codeRefactorer],
  );
}

BaseAgent _buildParallelResearchPipeline(String apiKey, _AppLanguage language) {
  final Agent productAngle = Agent(
    name: 'ProductResearcher',
    model: _createGeminiModel(apiKey),
    description: '제품/비즈니스 관점에서 분석합니다.',
    instruction:
        '''
Analyze the latest user request from a product and business perspective.
- Keep it concise in 3 bullets.
${_responseLanguageInstruction(language)}
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
${_responseLanguageInstruction(language)}
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
${_responseLanguageInstruction(language)}
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
${_responseLanguageInstruction(language)}
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

BaseAgent _buildLoopRefinementPipeline(String apiKey, _AppLanguage language) {
  final Agent initialWriter = Agent(
    name: 'InitialWriterAgent',
    model: _createGeminiModel(apiKey),
    description: '초기 초안을 작성합니다.',
    instruction:
        '''
Write a short first draft based on the latest user request.
- Keep it to 2~4 sentences.
${_responseLanguageInstruction(language)}
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

If not met, provide concise improvement feedback.
${_responseLanguageInstruction(language)}
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
Otherwise, apply feedback and output an improved draft.
${_responseLanguageInstruction(language)}
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
${_responseLanguageInstruction(language)}
''',
  );

  return SequentialAgent(
    name: 'LoopRefinementPipeline',
    description: '초안 작성 후 루프 기반 반복 개선',
    subAgents: <BaseAgent>[initialWriter, loop, finalAnswer],
  );
}

Agent _buildAgentTeamWeather(String apiKey, _AppLanguage language) {
  final Agent greetingAgent = Agent(
    name: 'GreetingAgent',
    model: _createGeminiModel(apiKey),
    description: '간단한 인사 요청을 처리합니다.',
    instruction:
        '''
You are a greeting specialist.
- For greetings, call say_hello.
- Keep response short and friendly.
${_responseLanguageInstruction(language)}
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
- For weather questions, call get_weather.
- For current time questions, call get_current_time.
- If city is unsupported, explain politely.
${_responseLanguageInstruction(language)}
''',
    tools: <Object>[
      FunctionTool(
        name: 'get_weather',
        description: 'Returns weather report for a city.',
        func: ({required String city}) => _lookupTeamWeather(city, language),
      ),
      FunctionTool(
        name: 'get_current_time',
        description: 'Returns current local time for a city.',
        func: ({required String city}) =>
            _lookupTeamCurrentTime(city, language),
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
${_responseLanguageInstruction(language)}
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
- Route greetings to GreetingAgent using transfer_to_agent.
- Route weather/time requests to WeatherTimeAgent using transfer_to_agent.
- Route farewells to FarewellAgent using transfer_to_agent.
- If intent is unclear, ask one short clarifying question.
${_responseLanguageInstruction(language)}
''',
    subAgents: <BaseAgent>[greetingAgent, weatherAgent, farewellAgent],
  );
}

Agent _buildMcpToolsetAgent(
  String apiKey, {
  required _AppLanguage language,
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
${_responseLanguageInstruction(language)}
''',
    tools: tools,
  );
}

Agent _buildSkillsAgent(String apiKey, _AppLanguage language) {
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
${_responseLanguageInstruction(language)}
''',
    tools: <Object>[
      SkillToolset(skills: <Skill>[writingRefinerSkill, planningAdvisorSkill]),
    ],
  );
}

String _localizedGreeting(_AppLanguage language) {
  switch (language) {
    case _AppLanguage.en:
      return 'Hello!';
    case _AppLanguage.ko:
      return '안녕하세요!';
    case _AppLanguage.ja:
      return 'こんにちは！';
    case _AppLanguage.zh:
      return '你好！';
  }
}

String _localizedGreetingWithName(_AppLanguage language, String name) {
  switch (language) {
    case _AppLanguage.en:
      return 'Hello, $name!';
    case _AppLanguage.ko:
      return '안녕하세요, $name님!';
    case _AppLanguage.ja:
      return 'こんにちは、$nameさん！';
    case _AppLanguage.zh:
      return '你好，$name！';
  }
}

String _localizedFarewell(_AppLanguage language) {
  switch (language) {
    case _AppLanguage.en:
      return 'Have a great day. See you next time!';
    case _AppLanguage.ko:
      return '좋은 하루 보내세요. 다음에 또 만나요!';
    case _AppLanguage.ja:
      return '良い一日を。またお会いしましょう！';
    case _AppLanguage.zh:
      return '祝你今天愉快，下次见！';
  }
}

String _localizedMcpConfigured(_AppLanguage language) {
  switch (language) {
    case _AppLanguage.en:
      return 'MCP endpoint configured.';
    case _AppLanguage.ko:
      return 'MCP 엔드포인트가 설정되었습니다.';
    case _AppLanguage.ja:
      return 'MCP エンドポイントが設定されています。';
    case _AppLanguage.zh:
      return 'MCP 端点已配置。';
  }
}

String _localizedMcpNotConfigured(_AppLanguage language) {
  switch (language) {
    case _AppLanguage.en:
      return 'MCP URL is empty. Open settings and configure MCP Streamable HTTP URL.';
    case _AppLanguage.ko:
      return 'MCP URL이 비어 있습니다. 설정에서 MCP Streamable HTTP URL을 입력하세요.';
    case _AppLanguage.ja:
      return 'MCP URL が空です。設定で MCP Streamable HTTP URL を入力してください。';
    case _AppLanguage.zh:
      return 'MCP URL 为空。请在设置中配置 MCP Streamable HTTP URL。';
  }
}

String _localizedUnsupportedCity(_AppLanguage language, String city) {
  switch (language) {
    case _AppLanguage.en:
      return 'Unsupported city: $city';
    case _AppLanguage.ko:
      return '지원하지 않는 도시입니다: $city';
    case _AppLanguage.ja:
      return '未対応の都市です: $city';
    case _AppLanguage.zh:
      return '不支持该城市：$city';
  }
}

String _localizedUnknownTimezone(_AppLanguage language, String city) {
  switch (language) {
    case _AppLanguage.en:
      return 'Unknown timezone for city: $city';
    case _AppLanguage.ko:
      return '시간대를 모르는 도시입니다: $city';
    case _AppLanguage.ja:
      return 'この都市のタイムゾーンが不明です: $city';
    case _AppLanguage.zh:
      return '未知时区城市：$city';
  }
}

String _localizedTimeReport(
  _AppLanguage language, {
  required String city,
  required String date,
  required String hh,
  required String mm,
  required String zone,
}) {
  switch (language) {
    case _AppLanguage.en:
      return 'Current time in $city is $date $hh:$mm ($zone).';
    case _AppLanguage.ko:
      return '$city 현재 시각은 $date $hh:$mm ($zone) 입니다.';
    case _AppLanguage.ja:
      return '$city の現在時刻は $date $hh:$mm ($zone) です。';
    case _AppLanguage.zh:
      return '$city 当前时间是 $date $hh:$mm（$zone）。';
  }
}

Map<String, Object?> _lookupTeamWeather(String city, _AppLanguage language) {
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

Map<String, Object?> _lookupTeamCurrentTime(
  String city,
  _AppLanguage language,
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
