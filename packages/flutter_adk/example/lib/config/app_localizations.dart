import 'package:flutter_adk_example/domain/models/app_language.dart';

const Map<String, Map<AppLanguage, String>>
appI18n = <String, Map<AppLanguage, String>>{
  'app.title': <AppLanguage, String>{
    AppLanguage.en: 'Flutter ADK Examples',
    AppLanguage.ko: 'Flutter ADK 예제',
    AppLanguage.ja: 'Flutter ADK サンプル',
    AppLanguage.zh: 'Flutter ADK 示例',
  },
  'app.settings': <AppLanguage, String>{
    AppLanguage.en: 'Settings',
    AppLanguage.ko: '설정',
    AppLanguage.ja: '設定',
    AppLanguage.zh: '设置',
  },
  'app.language': <AppLanguage, String>{
    AppLanguage.en: 'Language',
    AppLanguage.ko: '언어',
    AppLanguage.ja: '言語',
    AppLanguage.zh: '语言',
  },
  'app.settings_saved': <AppLanguage, String>{
    AppLanguage.en: 'Settings saved.',
    AppLanguage.ko: '설정이 저장되었습니다.',
    AppLanguage.ja: '設定を保存しました。',
    AppLanguage.zh: '设置已保存。',
  },
  'app.no_api_key': <AppLanguage, String>{
    AppLanguage.en:
        'You need to configure an API key to receive model responses.',
    AppLanguage.ko: 'API 키를 설정해야 실제 모델 응답을 받을 수 있습니다.',
    AppLanguage.ja: 'モデル応答を受け取るには API キー設定が必要です。',
    AppLanguage.zh: '需要配置 API Key 才能获取模型响应。',
  },
  'app.set_api_key': <AppLanguage, String>{
    AppLanguage.en: 'Set API Key',
    AppLanguage.ko: 'API 키 설정',
    AppLanguage.ja: 'API キー設定',
    AppLanguage.zh: '设置 API Key',
  },
  'home.search_hint': <AppLanguage, String>{
    AppLanguage.en: 'Search examples',
    AppLanguage.ko: '예제 검색',
    AppLanguage.ja: 'サンプルを検索',
    AppLanguage.zh: '搜索示例',
  },
  'home.no_results': <AppLanguage, String>{
    AppLanguage.en: 'No examples match your filters.',
    AppLanguage.ko: '조건에 맞는 예제가 없습니다.',
    AppLanguage.ja: '条件に一致するサンプルがありません。',
    AppLanguage.zh: '没有符合筛选条件的示例。',
  },
  'category.all': <AppLanguage, String>{
    AppLanguage.en: 'All',
    AppLanguage.ko: '전체',
    AppLanguage.ja: 'すべて',
    AppLanguage.zh: '全部',
  },
  'category.general': <AppLanguage, String>{
    AppLanguage.en: 'General',
    AppLanguage.ko: '일반',
    AppLanguage.ja: '一般',
    AppLanguage.zh: '通用',
  },
  'category.workflow': <AppLanguage, String>{
    AppLanguage.en: 'Workflow',
    AppLanguage.ko: '워크플로우',
    AppLanguage.ja: 'ワークフロー',
    AppLanguage.zh: '工作流',
  },
  'category.team': <AppLanguage, String>{
    AppLanguage.en: 'Team',
    AppLanguage.ko: '팀',
    AppLanguage.ja: 'チーム',
    AppLanguage.zh: '团队',
  },
  'category.integrations': <AppLanguage, String>{
    AppLanguage.en: 'Integrations',
    AppLanguage.ko: '연동',
    AppLanguage.ja: '連携',
    AppLanguage.zh: '集成',
  },
  'chat.example_prompts': <AppLanguage, String>{
    AppLanguage.en: 'Example Questions',
    AppLanguage.ko: '예시 질문',
    AppLanguage.ja: '質問例',
    AppLanguage.zh: '示例问题',
  },
  'difficulty.basic': <AppLanguage, String>{
    AppLanguage.en: 'Basic',
    AppLanguage.ko: '기초',
    AppLanguage.ja: '基礎',
    AppLanguage.zh: '基础',
  },
  'difficulty.advanced': <AppLanguage, String>{
    AppLanguage.en: 'Advanced',
    AppLanguage.ko: '심화',
    AppLanguage.ja: '応用',
    AppLanguage.zh: '进阶',
  },
  'prompt.basic.1': <AppLanguage, String>{
    AppLanguage.en: 'What is the capital of Japan?',
    AppLanguage.ko: '일본의 수도는 어디야?',
    AppLanguage.ja: '日本の首都はどこ？',
    AppLanguage.zh: '日本的首都是哪里？',
  },
  'prompt.basic.2': <AppLanguage, String>{
    AppLanguage.en: 'What is the capital of Canada?',
    AppLanguage.ko: '캐나다의 수도는 어디야?',
    AppLanguage.ja: 'カナダの首都はどこ？',
    AppLanguage.zh: '加拿大的首都是哪里？',
  },
  'prompt.basic.3': <AppLanguage, String>{
    AppLanguage.en: 'List capitals of Japan, Canada, and Australia.',
    AppLanguage.ko: '일본·캐나다·호주의 수도를 한 번에 알려줘.',
    AppLanguage.ja: '日本・カナダ・オーストラリアの首都をまとめて教えて。',
    AppLanguage.zh: '请一次性列出日本、加拿大、澳大利亚的首都。',
  },
  'prompt.transfer.1': <AppLanguage, String>{
    AppLanguage.en: 'I was charged twice this month.',
    AppLanguage.ko: '이번 달에 결제가 두 번 청구됐어요.',
    AppLanguage.ja: '今月、二重請求されました。',
    AppLanguage.zh: '这个月我被重复扣费了。',
  },
  'prompt.transfer.2': <AppLanguage, String>{
    AppLanguage.en: 'I cannot log in after resetting password.',
    AppLanguage.ko: '비밀번호를 바꿨는데 로그인이 안돼요.',
    AppLanguage.ja: 'パスワード変更後にログインできません。',
    AppLanguage.zh: '重置密码后无法登录。',
  },
  'prompt.transfer.3': <AppLanguage, String>{
    AppLanguage.en:
        'I was charged twice and cannot log in. Route this to the right teams.',
    AppLanguage.ko: '중복 결제도 있고 로그인도 안돼요. 적절한 팀으로 라우팅해줘.',
    AppLanguage.ja: '二重請求とログイン不可の両方があります。適切な担当に振り分けて。',
    AppLanguage.zh: '我既被重复扣费又无法登录，请路由到正确团队处理。',
  },
  'prompt.workflow.1': <AppLanguage, String>{
    AppLanguage.en: 'Plan a 3-day Tokyo trip for first-timers.',
    AppLanguage.ko: '도쿄 3일 여행 일정을 짜줘.',
    AppLanguage.ja: '東京3日間の旅行プランを作って。',
    AppLanguage.zh: '帮我规划东京三日游。',
  },
  'prompt.workflow.2': <AppLanguage, String>{
    AppLanguage.en: 'Create a launch plan for a new mobile app feature.',
    AppLanguage.ko: '신규 앱 기능 출시 계획을 만들어줘.',
    AppLanguage.ja: '新機能のローンチ計画を作って。',
    AppLanguage.zh: '制定一个新功能上线计划。',
  },
  'prompt.workflow.3': <AppLanguage, String>{
    AppLanguage.en:
        'Make a 6-week launch plan with milestones, owners, and risks.',
    AppLanguage.ko: '6주 출시 계획을 마일스톤/담당자/리스크까지 포함해 만들어줘.',
    AppLanguage.ja: '6週間のローンチ計画をマイルストーン・担当・リスク付きで作って。',
    AppLanguage.zh: '做一个6周上线计划，包含里程碑、负责人和风险。',
  },
  'prompt.sequential.1': <AppLanguage, String>{
    AppLanguage.en: 'Write a Python function to remove duplicates from a list.',
    AppLanguage.ko: '리스트 중복 제거 파이썬 함수를 작성해줘.',
    AppLanguage.ja: '重複を除去する Python 関数を書いて。',
    AppLanguage.zh: '写一个去重列表的 Python 函数。',
  },
  'prompt.sequential.2': <AppLanguage, String>{
    AppLanguage.en: 'Refactor a factorial function for readability and tests.',
    AppLanguage.ko: '팩토리얼 함수 가독성과 테스트를 개선해줘.',
    AppLanguage.ja: '階乗関数を読みやすくテストしやすく改善して。',
    AppLanguage.zh: '重构阶乘函数并增强可读性与测试性。',
  },
  'prompt.sequential.3': <AppLanguage, String>{
    AppLanguage.en:
        'Design a retry utility with tests, then review and refine it.',
    AppLanguage.ko: '재시도 유틸리티를 테스트 포함으로 만들고 리뷰/개선까지 해줘.',
    AppLanguage.ja: 'リトライユーティリティをテスト付きで作り、レビューして改善して。',
    AppLanguage.zh: '设计一个带测试的重试工具，并完成评审与优化。',
  },
  'prompt.parallel.1': <AppLanguage, String>{
    AppLanguage.en: 'Propose a paid plan strategy for a SaaS product.',
    AppLanguage.ko: 'SaaS 유료 플랜 전략을 제안해줘.',
    AppLanguage.ja: 'SaaS の有料プラン戦略を提案して。',
    AppLanguage.zh: '给出 SaaS 付费方案策略。',
  },
  'prompt.parallel.2': <AppLanguage, String>{
    AppLanguage.en: 'Analyze a new onboarding flow from product/UX/risk views.',
    AppLanguage.ko: '온보딩 플로우를 제품/UX/리스크 관점으로 분석해줘.',
    AppLanguage.ja: 'オンボーディングを製品/UX/リスクで分析して。',
    AppLanguage.zh: '从产品/UX/风险角度分析新手引导流程。',
  },
  'prompt.parallel.3': <AppLanguage, String>{
    AppLanguage.en:
        'Evaluate a pricing change in parallel, then synthesize one recommendation.',
    AppLanguage.ko: '가격 정책 변경을 병렬 관점으로 평가하고 단일 권장안으로 통합해줘.',
    AppLanguage.ja: '価格改定を並列観点で評価し、最終提案を1つに統合して。',
    AppLanguage.zh: '并行评估一次定价变更，并整合成一个最终建议。',
  },
  'prompt.loop.1': <AppLanguage, String>{
    AppLanguage.en: 'Write a short story about a cat in a rainy city.',
    AppLanguage.ko: '비 오는 도시의 고양이 이야기를 써줘.',
    AppLanguage.ja: '雨の街の猫の短い物語を書いて。',
    AppLanguage.zh: '写一个雨城小猫的短故事。',
  },
  'prompt.loop.2': <AppLanguage, String>{
    AppLanguage.en: 'Improve this draft until it is clear and vivid.',
    AppLanguage.ko: '초안을 더 명확하고 생생하게 다듬어줘.',
    AppLanguage.ja: 'この下書きを明確で生き生きと改善して。',
    AppLanguage.zh: '把这份草稿优化得更清晰生动。',
  },
  'prompt.loop.3': <AppLanguage, String>{
    AppLanguage.en:
        'Iteratively refine this draft until it has clear beginning, middle, and end.',
    AppLanguage.ko: '이 초안을 시작-중간-끝이 분명해질 때까지 반복 개선해줘.',
    AppLanguage.ja: 'この下書きを起承転結が明確になるまで反復改善して。',
    AppLanguage.zh: '把这份草稿迭代优化到开头、中段、结尾都清晰。',
  },
  'prompt.team.1': <AppLanguage, String>{
    AppLanguage.en: 'What time is it in Seoul now?',
    AppLanguage.ko: '지금 서울 시간 알려줘.',
    AppLanguage.ja: '今ソウルは何時？',
    AppLanguage.zh: '现在首尔几点？',
  },
  'prompt.team.2': <AppLanguage, String>{
    AppLanguage.en: 'How is the weather in New York today?',
    AppLanguage.ko: '오늘 뉴욕 날씨 어때?',
    AppLanguage.ja: '今日のニューヨークの天気は？',
    AppLanguage.zh: '今天纽约天气怎么样？',
  },
  'prompt.team.3': <AppLanguage, String>{
    AppLanguage.en: 'Greet me, tell Seoul time, and end with a farewell.',
    AppLanguage.ko: '인사하고 서울 현재 시각을 알려준 뒤 작별 인사로 마무리해줘.',
    AppLanguage.ja: 'あいさつして、ソウルの現在時刻を伝え、最後に別れの言葉で締めて。',
    AppLanguage.zh: '先打招呼，再告诉我首尔时间，最后礼貌道别。',
  },
  'prompt.mcp.1': <AppLanguage, String>{
    AppLanguage.en: 'Check MCP connection status first.',
    AppLanguage.ko: '먼저 MCP 연결 상태를 확인해줘.',
    AppLanguage.ja: 'まず MCP 接続状態を確認して。',
    AppLanguage.zh: '先检查 MCP 连接状态。',
  },
  'prompt.mcp.2': <AppLanguage, String>{
    AppLanguage.en: 'Use available MCP tools to summarize capabilities.',
    AppLanguage.ko: '사용 가능한 MCP 도구 기능을 요약해줘.',
    AppLanguage.ja: '利用可能な MCP ツール機能を要約して。',
    AppLanguage.zh: '总结当前可用的 MCP 工具能力。',
  },
  'prompt.mcp.3': <AppLanguage, String>{
    AppLanguage.en:
        'If MCP is configured, list tools and run one practical example.',
    AppLanguage.ko: 'MCP가 설정되어 있으면 도구 목록을 보여주고 예시 작업 하나를 실행해줘.',
    AppLanguage.ja: 'MCP 設定済みならツール一覧を示し、実用的な例を1つ実行して。',
    AppLanguage.zh: '若 MCP 已配置，请列出工具并执行一个实用示例。',
  },
  'prompt.skills.1': <AppLanguage, String>{
    AppLanguage.en: 'Improve the structure of this blog post draft.',
    AppLanguage.ko: '이 블로그 초안 구조를 개선해줘.',
    AppLanguage.ja: 'このブログ下書きの構成を改善して。',
    AppLanguage.zh: '优化这篇博客草稿的结构。',
  },
  'prompt.skills.2': <AppLanguage, String>{
    AppLanguage.en: 'Turn this goal into an actionable 3-step plan.',
    AppLanguage.ko: '이 목표를 실행 가능한 3단계 계획으로 바꿔줘.',
    AppLanguage.ja: 'この目標を実行可能な3段階計画にして。',
    AppLanguage.zh: '把这个目标转成可执行的三步计划。',
  },
  'prompt.skills.3': <AppLanguage, String>{
    AppLanguage.en:
        'Rewrite this announcement and add a phased execution plan.',
    AppLanguage.ko: '이 공지문을 더 명확히 다듬고 단계별 실행 계획도 추가해줘.',
    AppLanguage.ja: 'この告知文を改善し、段階的な実行計画も追加して。',
    AppLanguage.zh: '润色这份公告，并补充分阶段执行计划。',
  },
  'settings.title': <AppLanguage, String>{
    AppLanguage.en: 'API Settings',
    AppLanguage.ko: 'API 설정',
    AppLanguage.ja: 'API 設定',
    AppLanguage.zh: 'API 设置',
  },
  'settings.api_key': <AppLanguage, String>{
    AppLanguage.en: 'Gemini API Key',
    AppLanguage.ko: 'Gemini API Key',
    AppLanguage.ja: 'Gemini API Key',
    AppLanguage.zh: 'Gemini API Key',
  },
  'settings.mcp_url': <AppLanguage, String>{
    AppLanguage.en: 'MCP Streamable HTTP URL',
    AppLanguage.ko: 'MCP Streamable HTTP URL',
    AppLanguage.ja: 'MCP Streamable HTTP URL',
    AppLanguage.zh: 'MCP Streamable HTTP URL',
  },
  'settings.mcp_token': <AppLanguage, String>{
    AppLanguage.en: 'MCP Bearer Token (Optional)',
    AppLanguage.ko: 'MCP Bearer Token (선택)',
    AppLanguage.ja: 'MCP Bearer Token（任意）',
    AppLanguage.zh: 'MCP Bearer Token（可选）',
  },
  'settings.security': <AppLanguage, String>{
    AppLanguage.en:
        'Storing keys in browser storage may expose secrets. Use a server proxy in production.',
    AppLanguage.ko: '웹 브라우저에 키를 저장하는 경우 노출 위험이 있습니다. 프로덕션은 서버 프록시를 권장합니다.',
    AppLanguage.ja: 'ブラウザ保存は鍵漏洩リスクがあります。本番環境ではサーバープロキシを推奨します。',
    AppLanguage.zh: '将密钥保存在浏览器中存在泄露风险，生产环境建议使用服务端代理。',
  },
  'settings.clear': <AppLanguage, String>{
    AppLanguage.en: 'Clear Keys',
    AppLanguage.ko: '키 삭제',
    AppLanguage.ja: 'キー削除',
    AppLanguage.zh: '清除密钥',
  },
  'settings.save': <AppLanguage, String>{
    AppLanguage.en: 'Save',
    AppLanguage.ko: '저장',
    AppLanguage.ja: '保存',
    AppLanguage.zh: '保存',
  },
  'error.api_key_required': <AppLanguage, String>{
    AppLanguage.en: 'Please set Gemini API key first.',
    AppLanguage.ko: 'Gemini API 키를 먼저 설정하세요.',
    AppLanguage.ja: '先に Gemini API キーを設定してください。',
    AppLanguage.zh: '请先设置 Gemini API Key。',
  },
  'error.prefix': <AppLanguage, String>{
    AppLanguage.en: 'An error occurred: ',
    AppLanguage.ko: '오류가 발생했습니다: ',
    AppLanguage.ja: 'エラーが発生しました: ',
    AppLanguage.zh: '发生错误：',
  },
  'error.no_response_text': <AppLanguage, String>{
    AppLanguage.en: 'Could not find response text.',
    AppLanguage.ko: '응답 텍스트를 찾지 못했습니다.',
    AppLanguage.ja: '応答テキストが見つかりませんでした。',
    AppLanguage.zh: '未找到响应文本。',
  },
  'basic.title': <AppLanguage, String>{
    AppLanguage.en: 'Basic Chatbot Example',
    AppLanguage.ko: '기본 챗봇 예제',
    AppLanguage.ja: '基本チャットボット例',
    AppLanguage.zh: '基础聊天机器人示例',
  },
  'basic.summary': <AppLanguage, String>{
    AppLanguage.en: 'Single Agent + FunctionTool example.',
    AppLanguage.ko: '단일 Agent + FunctionTool 기반 예제입니다.',
    AppLanguage.ja: '単一 Agent + FunctionTool の例です。',
    AppLanguage.zh: '单一 Agent + FunctionTool 示例。',
  },
  'basic.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. This is a basic chatbot for capital-city lookup and general Q&A.\nSet API key and send a message.',
    AppLanguage.ko:
        '안녕하세요. 국가 수도, 일반 Q&A를 처리하는 기본 챗봇 예제입니다.\nAPI 키를 설정하고 질문을 보내세요.',
    AppLanguage.ja: 'こんにちは。国の首都検索と一般Q&Aに対応する基本チャットボットです。\nAPI キーを設定して質問してください。',
    AppLanguage.zh: '你好，这是一个处理首都查询和通用问答的基础聊天机器人。\n请先设置 API Key 再提问。',
  },
  'basic.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to start the basic chatbot.',
    AppLanguage.ko: '메시지를 보내 기본 챗봇을 시작하세요.',
    AppLanguage.ja: 'メッセージを送信して基本チャットボットを開始してください。',
    AppLanguage.zh: '发送消息以开始基础聊天机器人。',
  },
  'basic.hint': <AppLanguage, String>{
    AppLanguage.en: 'Ask the basic chatbot...',
    AppLanguage.ko: '기본 챗봇에게 질문하기...',
    AppLanguage.ja: '基本チャットボットに質問...',
    AppLanguage.zh: '向基础聊天机器人提问...',
  },
  'transfer.title': <AppLanguage, String>{
    AppLanguage.en: 'Multi-Agent Coordinator Example',
    AppLanguage.ko: '멀티에이전트 코디네이터 예제',
    AppLanguage.ja: 'マルチエージェント コーディネーター例',
    AppLanguage.zh: '多智能体协调器示例',
  },
  'transfer.summary': <AppLanguage, String>{
    AppLanguage.en:
        'Coordinator/Dispatcher pattern with Billing and Support transfers.',
    AppLanguage.ko:
        'Coordinator/Dispatcher 패턴 (Billing/Support transfer) 예제입니다.',
    AppLanguage.ja: 'Coordinator/Dispatcher パターン（Billing/Support transfer）例です。',
    AppLanguage.zh: 'Coordinator/Dispatcher 模式（Billing/Support transfer）示例。',
  },
  'transfer.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. This multi-agent coordinator routes billing issues to Billing and technical issues to Support.',
    AppLanguage.ko: '안녕하세요. 결제/청구 문의는 Billing, 기술/로그인 문의는 Support로 라우팅합니다.',
    AppLanguage.ja: 'こんにちは。請求関連は Billing、技術/ログイン問題は Support にルーティングします。',
    AppLanguage.zh: '你好，计费问题会路由到 Billing，技术/登录问题会路由到 Support。',
  },
  'transfer.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to test multi-agent routing.',
    AppLanguage.ko: '메시지를 보내 멀티에이전트 라우팅을 확인하세요.',
    AppLanguage.ja: 'メッセージを送ってマルチエージェントのルーティングを確認してください。',
    AppLanguage.zh: '发送消息以验证多智能体路由。',
  },
  'transfer.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. I was charged twice / I cannot login',
    AppLanguage.ko: '예: 결제가 두 번 청구됐어요 / 로그인이 안돼요',
    AppLanguage.ja: '例: 二重請求されました / ログインできません',
    AppLanguage.zh: '例如：被重复扣费了 / 无法登录',
  },
  'workflow.title': <AppLanguage, String>{
    AppLanguage.en: 'Workflow Agents Example',
    AppLanguage.ko: '워크플로우 에이전트 예제',
    AppLanguage.ja: 'ワークフローエージェント例',
    AppLanguage.zh: '工作流智能体示例',
  },
  'workflow.summary': <AppLanguage, String>{
    AppLanguage.en: 'Sequential + Parallel + Loop composition example.',
    AppLanguage.ko: 'Sequential + Parallel + Loop 조합 예제입니다.',
    AppLanguage.ja: 'Sequential + Parallel + Loop の組み合わせ例です。',
    AppLanguage.zh: 'Sequential + Parallel + Loop 组合示例。',
  },
  'workflow.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. Send a question and it runs through Sequential/Parallel/Loop chain.',
    AppLanguage.ko: '안녕하세요. 질문을 보내면 Sequential/Parallel/Loop 체인으로 처리합니다.',
    AppLanguage.ja: 'こんにちは。質問を送ると Sequential/Parallel/Loop チェーンで処理します。',
    AppLanguage.zh: '你好，发送问题后会通过 Sequential/Parallel/Loop 链路处理。',
  },
  'workflow.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to run workflow pipeline.',
    AppLanguage.ko: '메시지를 보내 워크플로우 실행을 확인하세요.',
    AppLanguage.ja: 'メッセージを送ってワークフロー実行を確認してください。',
    AppLanguage.zh: '发送消息以执行工作流。',
  },
  'workflow.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. Plan a 3-day trip in Paris',
    AppLanguage.ko: '예: 파리 2박 3일 일정 추천',
    AppLanguage.ja: '例: パリ2泊3日の旅行プラン',
    AppLanguage.zh: '例如：推荐巴黎三日行程',
  },
  'sequential.title': <AppLanguage, String>{
    AppLanguage.en: 'SequentialAgent Example',
    AppLanguage.ko: 'SequentialAgent 예제',
    AppLanguage.ja: 'SequentialAgent 例',
    AppLanguage.zh: 'SequentialAgent 示例',
  },
  'sequential.summary': <AppLanguage, String>{
    AppLanguage.en: 'Writer -> Reviewer -> Refactorer fixed pipeline.',
    AppLanguage.ko: 'Code Writer -> Reviewer -> Refactorer 순차 실행 예제입니다.',
    AppLanguage.ja: 'Code Writer -> Reviewer -> Refactorer の順次パイプラインです。',
    AppLanguage.zh: 'Code Writer -> Reviewer -> Refactorer 固定顺序流水线示例。',
  },
  'sequential.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. Send a request and it runs write-review-refactor in sequence.',
    AppLanguage.ko: '안녕하세요. 요청을 보내면 작성-리뷰-리팩터링을 순차 실행합니다.',
    AppLanguage.ja: 'こんにちは。リクエストを送ると作成→レビュー→リファクタを順次実行します。',
    AppLanguage.zh: '你好，发送请求后会按“编写-评审-重构”顺序执行。',
  },
  'sequential.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to run sequential workflow.',
    AppLanguage.ko: '메시지를 보내 Sequential 워크플로우를 실행하세요.',
    AppLanguage.ja: 'メッセージを送って Sequential ワークフローを実行してください。',
    AppLanguage.zh: '发送消息以运行 Sequential 工作流。',
  },
  'sequential.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. Write a Python function that reverses a string',
    AppLanguage.ko: '예: 문자열을 뒤집는 파이썬 함수를 작성해줘',
    AppLanguage.ja: '例: 文字列を反転する Python 関数を書いて',
    AppLanguage.zh: '例如：写一个反转字符串的 Python 函数',
  },
  'parallel.title': <AppLanguage, String>{
    AppLanguage.en: 'ParallelAgent Example',
    AppLanguage.ko: 'ParallelAgent 예제',
    AppLanguage.ja: 'ParallelAgent 例',
    AppLanguage.zh: 'ParallelAgent 示例',
  },
  'parallel.summary': <AppLanguage, String>{
    AppLanguage.en: 'Run independent perspectives in parallel and synthesize.',
    AppLanguage.ko: '독립 관점 에이전트를 병렬 실행 후 결과를 통합합니다.',
    AppLanguage.ja: '独立観点エージェントを並列実行して統合します。',
    AppLanguage.zh: '并行执行独立视角后再统一总结。',
  },
  'parallel.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. It generates multiple angles in parallel and returns a synthesis.',
    AppLanguage.ko: '안녕하세요. 질문을 보내면 여러 관점을 동시에 생성해 요약합니다.',
    AppLanguage.ja: 'こんにちは。質問を送ると複数観点を並列生成し、要約します。',
    AppLanguage.zh: '你好，发送问题后会并行生成多个视角并汇总。',
  },
  'parallel.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to run parallel workflow.',
    AppLanguage.ko: '메시지를 보내 Parallel 워크플로우를 실행하세요.',
    AppLanguage.ja: 'メッセージを送って Parallel ワークフローを実行してください。',
    AppLanguage.zh: '发送消息以运行 Parallel 工作流。',
  },
  'parallel.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. Propose a paid plan launch strategy',
    AppLanguage.ko: '예: 신규 유료 플랜 출시 전략을 정리해줘',
    AppLanguage.ja: '例: 新しい有料プランのローンチ戦略を整理して',
    AppLanguage.zh: '例如：整理新付费方案上线策略',
  },
  'loop.title': <AppLanguage, String>{
    AppLanguage.en: 'LoopAgent Example',
    AppLanguage.ko: 'LoopAgent 예제',
    AppLanguage.ja: 'LoopAgent 例',
    AppLanguage.zh: 'LoopAgent 示例',
  },
  'loop.summary': <AppLanguage, String>{
    AppLanguage.en: 'Iterative refinement with Critic/Refiner and exit_loop.',
    AppLanguage.ko: 'Critic + Refiner 반복 개선과 exit_loop 종료 예제입니다.',
    AppLanguage.ja: 'Critic + Refiner の反復改善と exit_loop 終了例です。',
    AppLanguage.zh: 'Critic + Refiner 迭代优化并通过 exit_loop 结束。',
  },
  'loop.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. It writes an initial draft and iteratively refines it.',
    AppLanguage.ko: '안녕하세요. 초안 작성 후 반복 개선하고, 완료 조건이면 루프를 종료합니다.',
    AppLanguage.ja: 'こんにちは。初稿を作成後、反復改善し、完了条件でループを終了します。',
    AppLanguage.zh: '你好，会先生成初稿并迭代优化，满足条件后结束循环。',
  },
  'loop.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to run loop workflow.',
    AppLanguage.ko: '메시지를 보내 Loop 워크플로우를 실행하세요.',
    AppLanguage.ja: 'メッセージを送って Loop ワークフローを実行してください。',
    AppLanguage.zh: '发送消息以运行 Loop 工作流。',
  },
  'loop.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. Write a short story about a cat',
    AppLanguage.ko: '예: 고양이에 대한 짧은 동화를 써줘',
    AppLanguage.ja: '例: 猫についての短い物語を書いて',
    AppLanguage.zh: '例如：写一篇关于猫的短故事',
  },
  'team.title': <AppLanguage, String>{
    AppLanguage.en: 'Agent Team Example',
    AppLanguage.ko: 'Agent Team 예제',
    AppLanguage.ja: 'Agent Team 例',
    AppLanguage.zh: 'Agent Team 示例',
  },
  'team.summary': <AppLanguage, String>{
    AppLanguage.en: 'Coordinator transfers to Greeting/Weather/Farewell.',
    AppLanguage.ko: 'Coordinator가 Greeting/Weather/Farewell로 transfer합니다.',
    AppLanguage.ja: 'Coordinator が Greeting/Weather/Farewell に transfer します。',
    AppLanguage.zh: 'Coordinator 会 transfer 到 Greeting/Weather/Farewell。',
  },
  'team.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. Greeting/weather/time/farewell requests are routed to specialists.',
    AppLanguage.ko: '안녕하세요. 인사/날씨/시간/작별 요청을 각각 전담 에이전트로 라우팅합니다.',
    AppLanguage.ja: 'こんにちは。挨拶/天気/時刻/別れの要求を専門エージェントにルーティングします。',
    AppLanguage.zh: '你好，问候/天气/时间/告别请求会路由到对应专家智能体。',
  },
  'team.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to test agent team routing.',
    AppLanguage.ko: '메시지를 보내 Agent Team 라우팅을 확인하세요.',
    AppLanguage.ja: 'メッセージを送って Agent Team ルーティングを確認してください。',
    AppLanguage.zh: '发送消息以验证 Agent Team 路由。',
  },
  'team.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. What time is it in Seoul? / Weather in New York?',
    AppLanguage.ko: '예: 서울 시간 알려줘 / 뉴욕 날씨 어때?',
    AppLanguage.ja: '例: ソウルの時間は？ / ニューヨークの天気は？',
    AppLanguage.zh: '例如：首尔现在几点？/ 纽约天气如何？',
  },
  'mcp.title': <AppLanguage, String>{
    AppLanguage.en: 'MCP Toolset Example',
    AppLanguage.ko: 'MCP Toolset 예제',
    AppLanguage.ja: 'MCP Toolset 例',
    AppLanguage.zh: 'MCP Toolset 示例',
  },
  'mcp.summary': <AppLanguage, String>{
    AppLanguage.en: 'Remote MCP tools via McpToolset(Streamable HTTP).',
    AppLanguage.ko: 'McpToolset(Streamable HTTP) 기반 원격 MCP 도구 예제입니다.',
    AppLanguage.ja: 'McpToolset（Streamable HTTP）によるリモート MCP ツール例です。',
    AppLanguage.zh: '基于 McpToolset（Streamable HTTP）的远程 MCP 工具示例。',
  },
  'mcp.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. Configure MCP URL in settings first, then send a request.',
    AppLanguage.ko: '안녕하세요. 먼저 설정에서 MCP URL을 입력한 뒤 메시지를 보내세요.',
    AppLanguage.ja: 'こんにちは。先に設定で MCP URL を入力してからメッセージを送ってください。',
    AppLanguage.zh: '你好，请先在设置中填写 MCP URL 再发送请求。',
  },
  'mcp.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to test MCP toolset.',
    AppLanguage.ko: '메시지를 보내 MCP Toolset 동작을 확인하세요.',
    AppLanguage.ja: 'メッセージを送って MCP Toolset の動作を確認してください。',
    AppLanguage.zh: '发送消息以测试 MCP Toolset。',
  },
  'mcp.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. Check MCP connection status',
    AppLanguage.ko: '예: MCP 연결 상태 확인해줘',
    AppLanguage.ja: '例: MCP 接続状態を確認して',
    AppLanguage.zh: '例如：检查 MCP 连接状态',
  },
  'skills.title': <AppLanguage, String>{
    AppLanguage.en: 'SkillToolset Example',
    AppLanguage.ko: 'SkillToolset 예제',
    AppLanguage.ja: 'SkillToolset 例',
    AppLanguage.zh: 'SkillToolset 示例',
  },
  'skills.summary': <AppLanguage, String>{
    AppLanguage.en: 'Inline Skill + SkillToolset orchestration example.',
    AppLanguage.ko: 'inline Skill + SkillToolset 오케스트레이션 예제입니다.',
    AppLanguage.ja: 'inline Skill + SkillToolset オーケストレーション例です。',
    AppLanguage.zh: 'inline Skill + SkillToolset 编排示例。',
  },
  'skills.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. It lists/loads skills and follows skill resources to solve tasks.',
    AppLanguage.ko: '안녕하세요. skill을 list/load하고 resource 지시를 따라 작업을 처리합니다.',
    AppLanguage.ja: 'こんにちは。skill を list/load し、resource 指示に従って処理します。',
    AppLanguage.zh: '你好，会先 list/load skill 并按照 resource 指示完成任务。',
  },
  'skills.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to test skills flow.',
    AppLanguage.ko: '메시지를 보내 Skills 동작을 확인하세요.',
    AppLanguage.ja: 'メッセージを送って Skills の動作を確認してください。',
    AppLanguage.zh: '发送消息以测试 Skills 流程。',
  },
  'skills.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. Improve this blog post structure',
    AppLanguage.ko: '예: 블로그 글 구조를 개선해줘',
    AppLanguage.ja: '例: このブログ記事の構成を改善して',
    AppLanguage.zh: '例如：优化这篇博客的结构',
  },
};

String tr(AppLanguage language, String key) {
  final Map<AppLanguage, String>? values = appI18n[key];
  if (values == null) {
    return key;
  }
  return values[language] ?? values[AppLanguage.en] ?? key;
}
