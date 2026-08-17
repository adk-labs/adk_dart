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
  'prompt.custom.1': <AppLanguage, String>{
    AppLanguage.en: 'What can you do with your current tool setup?',
    AppLanguage.ko: '지금 구성된 도구로 무엇을 할 수 있어?',
    AppLanguage.ja: '今のツール構成で何ができますか？',
    AppLanguage.zh: '你在当前工具配置下可以做什么？',
  },
  'prompt.custom.2': <AppLanguage, String>{
    AppLanguage.en:
        'Find the capital of Germany and weather in Seoul in one answer.',
    AppLanguage.ko: '독일 수도와 서울 날씨를 한 번에 알려줘.',
    AppLanguage.ja: 'ドイツの首都とソウルの天気を一度に教えて。',
    AppLanguage.zh: '请一次回答德国首都和首尔天气。',
  },
  'prompt.custom.3': <AppLanguage, String>{
    AppLanguage.en:
        'If a needed tool is disabled, explain limitation and suggest next action.',
    AppLanguage.ko: '필요한 도구가 꺼져 있으면 한계를 설명하고 다음 행동을 제안해줘.',
    AppLanguage.ja: '必要なツールが無効なら制約を説明し、次の行動を提案して。',
    AppLanguage.zh: '如果所需工具被禁用，请说明限制并给出下一步建议。',
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
  'prompt.url_context.1': <AppLanguage, String>{
    AppLanguage.en:
        'Summarize https://google.github.io/adk-docs/ in three bullets.',
    AppLanguage.ko: 'https://google.github.io/adk-docs/ 내용을 세 줄로 요약해줘.',
    AppLanguage.ja: 'https://google.github.io/adk-docs/ を3つの箇条書きで要約して。',
    AppLanguage.zh: '用三条要点总结 https://google.github.io/adk-docs/。',
  },
  'prompt.url_context.2': <AppLanguage, String>{
    AppLanguage.en:
        'Read https://github.com/google/adk-python and explain what the project is.',
    AppLanguage.ko: 'https://github.com/google/adk-python 을 읽고 어떤 프로젝트인지 설명해줘.',
    AppLanguage.ja: 'https://github.com/google/adk-python を読み、どんなプロジェクトか説明して。',
    AppLanguage.zh: '阅读 https://github.com/google/adk-python 并说明这个项目是什么。',
  },
  'prompt.url_context.3': <AppLanguage, String>{
    AppLanguage.en:
        'Compare https://google.github.io/adk-docs/ with https://github.com/google/adk-python.',
    AppLanguage.ko:
        'https://google.github.io/adk-docs/ 와 https://github.com/google/adk-python 을 비교해줘.',
    AppLanguage.ja:
        'https://google.github.io/adk-docs/ と https://github.com/google/adk-python を比較して。',
    AppLanguage.zh:
        '比较 https://google.github.io/adk-docs/ 和 https://github.com/google/adk-python。',
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
  'prompt.graph.1': <AppLanguage, String>{
    AppLanguage.en: 'Our Flutter app crashes on launch. How do I debug it?',
    AppLanguage.ko: 'Flutter 앱이 실행하자마자 크래시가 나요. 어떻게 디버깅하죠?',
    AppLanguage.ja: 'Flutter アプリが起動直後にクラッシュします。どうデバッグすれば？',
    AppLanguage.zh: 'Flutter 应用一启动就崩溃，该怎么调试？',
  },
  'prompt.graph.2': <AppLanguage, String>{
    AppLanguage.en: 'Suggest a pricing strategy for our new subscription.',
    AppLanguage.ko: '새 구독 상품의 가격 전략을 제안해줘.',
    AppLanguage.ja: '新しいサブスクの価格戦略を提案して。',
    AppLanguage.zh: '为我们的新订阅产品建议一个价格策略。',
  },
  'prompt.graph.3': <AppLanguage, String>{
    AppLanguage.en:
        'Recommend a weekend reading list about creative thinking.',
    AppLanguage.ko: '창의적 사고에 관한 주말 독서 목록을 추천해줘.',
    AppLanguage.ja: '創造的思考に関する週末の読書リストを勧めて。',
    AppLanguage.zh: '推荐一份关于创造性思维的周末书单。',
  },
  'prompt.google_search.1': <AppLanguage, String>{
    AppLanguage.en: 'What are the latest updates in the Gemini API?',
    AppLanguage.ko: 'Gemini API의 최신 업데이트 내용을 알려줘.',
    AppLanguage.ja: 'Gemini API の最新アップデートを教えて。',
    AppLanguage.zh: '介绍一下 Gemini API 的最新更新。',
  },
  'prompt.google_search.2': <AppLanguage, String>{
    AppLanguage.en: 'Search for this week\'s major AI industry news.',
    AppLanguage.ko: '이번 주 주요 AI 업계 뉴스를 검색해줘.',
    AppLanguage.ja: '今週の主要な AI 業界ニュースを検索して。',
    AppLanguage.zh: '搜索本周主要的 AI 行业新闻。',
  },
  'prompt.google_search.3': <AppLanguage, String>{
    AppLanguage.en:
        'Compare the current stable versions of Flutter and React Native with sources.',
    AppLanguage.ko: 'Flutter와 React Native의 현재 안정 버전을 출처와 함께 비교해줘.',
    AppLanguage.ja: 'Flutter と React Native の現在の安定版を出典付きで比較して。',
    AppLanguage.zh: '比较 Flutter 和 React Native 当前的稳定版本，并附上来源。',
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
  'settings.debug_logs': <AppLanguage, String>{
    AppLanguage.en: 'Debug Logs',
    AppLanguage.ko: '디버그 로그',
    AppLanguage.ja: 'デバッグログ',
    AppLanguage.zh: '调试日志',
  },
  'settings.debug_logs_description': <AppLanguage, String>{
    AppLanguage.en:
        'Print user messages and ADK events to terminal. Share these logs when reporting issues.',
    AppLanguage.ko: '사용자 메시지와 ADK 이벤트를 터미널에 출력합니다. 이슈 제보 시 로그를 공유해 주세요.',
    AppLanguage.ja: 'ユーザーメッセージと ADK イベントをターミナルに出力します。問題報告時にこのログを共有してください。',
    AppLanguage.zh: '将用户消息和 ADK 事件输出到终端。反馈问题时请附上这些日志。',
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
  'custom.configure': <AppLanguage, String>{
    AppLanguage.en: 'Configure',
    AppLanguage.ko: '구성',
    AppLanguage.ja: '設定',
    AppLanguage.zh: '配置',
  },
  'custom.config.title': <AppLanguage, String>{
    AppLanguage.en: 'Custom Agent Configuration',
    AppLanguage.ko: '커스텀 에이전트 설정',
    AppLanguage.ja: 'カスタムエージェント設定',
    AppLanguage.zh: '自定义智能体配置',
  },
  'custom.config.name': <AppLanguage, String>{
    AppLanguage.en: 'Agent name',
    AppLanguage.ko: '에이전트 이름',
    AppLanguage.ja: 'エージェント名',
    AppLanguage.zh: '智能体名称',
  },
  'custom.config.description': <AppLanguage, String>{
    AppLanguage.en: 'Description',
    AppLanguage.ko: '설명',
    AppLanguage.ja: '説明',
    AppLanguage.zh: '描述',
  },
  'custom.config.instruction': <AppLanguage, String>{
    AppLanguage.en: 'Instruction',
    AppLanguage.ko: '지시문',
    AppLanguage.ja: '指示文',
    AppLanguage.zh: '指令',
  },
  'custom.config.tool_capital': <AppLanguage, String>{
    AppLanguage.en: 'Enable capital lookup tool',
    AppLanguage.ko: '수도 조회 도구 사용',
    AppLanguage.ja: '首都検索ツールを有効化',
    AppLanguage.zh: '启用首都查询工具',
  },
  'custom.config.tool_weather': <AppLanguage, String>{
    AppLanguage.en: 'Enable weather tool',
    AppLanguage.ko: '날씨 도구 사용',
    AppLanguage.ja: '天気ツールを有効化',
    AppLanguage.zh: '启用天气工具',
  },
  'custom.config.tool_time': <AppLanguage, String>{
    AppLanguage.en: 'Enable time tool',
    AppLanguage.ko: '시간 도구 사용',
    AppLanguage.ja: '時刻ツールを有効化',
    AppLanguage.zh: '启用时间工具',
  },
  'custom.config.saved': <AppLanguage, String>{
    AppLanguage.en: 'Custom agent configuration saved.',
    AppLanguage.ko: '커스텀 에이전트 설정이 저장되었습니다.',
    AppLanguage.ja: 'カスタムエージェント設定を保存しました。',
    AppLanguage.zh: '已保存自定义智能体配置。',
  },
  'custom.config.cancel': <AppLanguage, String>{
    AppLanguage.en: 'Cancel',
    AppLanguage.ko: '취소',
    AppLanguage.ja: 'キャンセル',
    AppLanguage.zh: '取消',
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
  'local_llm.title': <AppLanguage, String>{
    AppLanguage.en: 'Local LLM (Ollama / LM Studio)',
    AppLanguage.ko: '로컬 LLM (Ollama / LM Studio)',
    AppLanguage.ja: 'ローカル LLM (Ollama / LM Studio)',
    AppLanguage.zh: '本地 LLM (Ollama / LM Studio)',
  },
  'local_llm.summary': <AppLanguage, String>{
    AppLanguage.en: 'Run inference entirely locally via Ollama / LM Studio or local proxy without cloud keys.',
    AppLanguage.ko: '클라우드 API 키 없이 Ollama / LM Studio 등 로컬 LLM 엔드포인트와 연동하는 예제입니다.',
    AppLanguage.ja: 'クラウドAPIキーなしで、Ollama / LM Studio などのローカルLLMと連携する例です。',
    AppLanguage.zh: '无需云端 API Key，直接连接 Ollama / LM Studio 等本地 LLM 端点的示例。',
  },
  'local_llm.initial': <AppLanguage, String>{
    AppLanguage.en: 'Hello! I am running on your local LLM (e.g. Ollama at http://localhost:11434/v1). No API key required.',
    AppLanguage.ko: '안녕하세요! 로컬 LLM(Ollama / LM Studio)으로 구동되는 오프라인 에이전트입니다. 별도의 클라우드 키 없이 동작합니다.',
    AppLanguage.ja: 'こんにちは！ローカルLLM（Ollama / LM Studio）で動作するオフラインエージェントです。',
    AppLanguage.zh: '你好！我是运行在本地 LLM（Ollama / LM Studio）上的离线智能体。',
  },
  'local_llm.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to chat with your local LLM.',
    AppLanguage.ko: '메시지를 보내 로컬 LLM과 대화하세요.',
    AppLanguage.ja: 'メッセージを送信してローカルLLMと対話してください。',
    AppLanguage.zh: '发送消息与本地 LLM 对话。',
  },
  'local_llm.hint': <AppLanguage, String>{
    AppLanguage.en: 'Ask the local LLM...',
    AppLanguage.ko: '로컬 LLM에게 질문하기...',
    AppLanguage.ja: 'ローカルLLMに質問...',
    AppLanguage.zh: '向本地 LLM 提问...',
  },
  'prompt.local_llm.1': <AppLanguage, String>{
    AppLanguage.en: 'Explain quantum computing in one simple sentence.',
    AppLanguage.ko: '양자 컴퓨터를 1문장으로 쉽게 설명해 줘.',
    AppLanguage.ja: '量子コンピュータを1文で分かりやすく説明して。',
    AppLanguage.zh: '用一句话简单解释量子计算。',
  },
  'prompt.local_llm.2': <AppLanguage, String>{
    AppLanguage.en: 'Write a quick Dart hello world example.',
    AppLanguage.ko: '간단한 Dart Hello World 코드를 작성해 줘.',
    AppLanguage.ja: 'シンプルなDartのHello Worldコードを書いて。',
    AppLanguage.zh: '写一个简单的 Dart Hello World 示例。',
  },
  'prompt.local_llm.3': <AppLanguage, String>{
    AppLanguage.en: 'What are the main benefits of running local on-device models?',
    AppLanguage.ko: '로컬 온디바이스 모델 사용의 주요 장점 3가지는?',
    AppLanguage.ja: 'ローカルオンデバイスモデルを使用する主な利点は何ですか？',
    AppLanguage.zh: '使用本地端侧模型的主要优势是什么？',
  },
  'custom.title': <AppLanguage, String>{
    AppLanguage.en: 'Custom Agent Builder',
    AppLanguage.ko: '커스텀 에이전트 빌더',
    AppLanguage.ja: 'カスタムエージェントビルダー',
    AppLanguage.zh: '自定义智能体构建器',
  },
  'custom.summary': <AppLanguage, String>{
    AppLanguage.en:
        'Configure your own agent instruction and tools, then reuse it later.',
    AppLanguage.ko: '지시문/도구를 직접 구성하고, 저장한 에이전트를 다음에도 재사용합니다.',
    AppLanguage.ja: '指示文/ツールを自分で構成し、保存したエージェントを次回も再利用します。',
    AppLanguage.zh: '可自定义指令与工具，并在下次继续复用。',
  },
  'custom.initial': <AppLanguage, String>{
    AppLanguage.en:
        'This is your saved custom agent. Open Configure to change instruction or tool toggles anytime.',
    AppLanguage.ko: '저장된 커스텀 에이전트입니다. 구성 버튼에서 지시문/도구를 언제든 변경할 수 있습니다.',
    AppLanguage.ja: '保存済みのカスタムエージェントです。設定ボタンで指示文/ツールをいつでも変更できます。',
    AppLanguage.zh: '这是你已保存的自定义智能体，可在“配置”中随时修改指令与工具。',
  },
  'custom.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to test your custom agent.',
    AppLanguage.ko: '메시지를 보내 커스텀 에이전트를 테스트하세요.',
    AppLanguage.ja: 'メッセージを送ってカスタムエージェントをテストしてください。',
    AppLanguage.zh: '发送消息测试你的自定义智能体。',
  },
  'custom.hint': <AppLanguage, String>{
    AppLanguage.en: 'Ask your custom agent...',
    AppLanguage.ko: '커스텀 에이전트에게 질문하기...',
    AppLanguage.ja: 'カスタムエージェントに質問...',
    AppLanguage.zh: '向自定义智能体提问...',
  },
  'user_example.saved': <AppLanguage, String>{
    AppLanguage.en: 'User example saved.',
    AppLanguage.ko: '사용자 예제가 저장되었습니다.',
    AppLanguage.ja: 'ユーザー例を保存しました。',
    AppLanguage.zh: '已保存用户示例。',
  },
  'user_example.deleted': <AppLanguage, String>{
    AppLanguage.en: 'User example deleted.',
    AppLanguage.ko: '사용자 예제가 삭제되었습니다.',
    AppLanguage.ja: 'ユーザー例を削除しました。',
    AppLanguage.zh: '已删除用户示例。',
  },
  'user_example.delete_title': <AppLanguage, String>{
    AppLanguage.en: 'Delete user example?',
    AppLanguage.ko: '사용자 예제를 삭제할까요?',
    AppLanguage.ja: 'ユーザー例を削除しますか？',
    AppLanguage.zh: '要删除该用户示例吗？',
  },
  'user_example.delete_message': <AppLanguage, String>{
    AppLanguage.en: 'This action cannot be undone.',
    AppLanguage.ko: '삭제 후에는 되돌릴 수 없습니다.',
    AppLanguage.ja: 'この操作は元に戻せません。',
    AppLanguage.zh: '此操作无法撤销。',
  },
  'user_example.builder.new_title': <AppLanguage, String>{
    AppLanguage.en: 'Create User Example',
    AppLanguage.ko: '사용자 예제 만들기',
    AppLanguage.ja: 'ユーザー例を作成',
    AppLanguage.zh: '创建用户示例',
  },
  'user_example.builder.edit_title': <AppLanguage, String>{
    AppLanguage.en: 'Edit User Example',
    AppLanguage.ko: '사용자 예제 수정',
    AppLanguage.ja: 'ユーザー例を編集',
    AppLanguage.zh: '编辑用户示例',
  },
  'user_example.field.title': <AppLanguage, String>{
    AppLanguage.en: 'Example title',
    AppLanguage.ko: '예제 제목',
    AppLanguage.ja: '例のタイトル',
    AppLanguage.zh: '示例标题',
  },
  'user_example.field.summary': <AppLanguage, String>{
    AppLanguage.en: 'Example summary',
    AppLanguage.ko: '예제 요약',
    AppLanguage.ja: '例の概要',
    AppLanguage.zh: '示例摘要',
  },
  'user_example.field.initial': <AppLanguage, String>{
    AppLanguage.en: 'Initial assistant message',
    AppLanguage.ko: '초기 안내 메시지',
    AppLanguage.ja: '初期アシスタントメッセージ',
    AppLanguage.zh: '初始助手消息',
  },
  'user_example.field.hint': <AppLanguage, String>{
    AppLanguage.en: 'Input hint',
    AppLanguage.ko: '입력 힌트',
    AppLanguage.ja: '入力ヒント',
    AppLanguage.zh: '输入提示',
  },
  'user_example.field.architecture': <AppLanguage, String>{
    AppLanguage.en: 'Agent topology',
    AppLanguage.ko: '에이전트 연결 방식',
    AppLanguage.ja: 'エージェント接続方式',
    AppLanguage.zh: '智能体连接方式',
  },
  'user_example.field.entry_agent': <AppLanguage, String>{
    AppLanguage.en: 'Entry agent',
    AppLanguage.ko: '시작 에이전트',
    AppLanguage.ja: '開始エージェント',
    AppLanguage.zh: '入口智能体',
  },
  'user_example.field.connections': <AppLanguage, String>{
    AppLanguage.en: 'Connections (Graph)',
    AppLanguage.ko: '연결(그래프)',
    AppLanguage.ja: '接続（グラフ）',
    AppLanguage.zh: '连接（图）',
  },
  'user_example.connection.from': <AppLanguage, String>{
    AppLanguage.en: 'From',
    AppLanguage.ko: '출발',
    AppLanguage.ja: '接続元',
    AppLanguage.zh: '起点',
  },
  'user_example.connection.to': <AppLanguage, String>{
    AppLanguage.en: 'To',
    AppLanguage.ko: '도착',
    AppLanguage.ja: '接続先',
    AppLanguage.zh: '终点',
  },
  'user_example.field.connection_condition': <AppLanguage, String>{
    AppLanguage.en: 'Condition (optional)',
    AppLanguage.ko: '조건(선택)',
    AppLanguage.ja: '条件（任意）',
    AppLanguage.zh: '条件（可选）',
  },
  'user_example.connection.default_condition': <AppLanguage, String>{
    AppLanguage.en: 'always',
    AppLanguage.ko: 'always',
    AppLanguage.ja: 'always',
    AppLanguage.zh: 'always',
  },
  'user_example.connection.dsl_help': <AppLanguage, String>{
    AppLanguage.en:
        'DSL: always | intent:<name> | contains:<keyword> (e.g. intent:weather, contains:refund)',
    AppLanguage.ko:
        'DSL: always | intent:<name> | contains:<keyword> (예: intent:weather, contains:refund)',
    AppLanguage.ja:
        'DSL: always | intent:<name> | contains:<keyword>（例: intent:weather, contains:refund）',
    AppLanguage.zh:
        'DSL：always | intent:<name> | contains:<keyword>（例如：intent:weather, contains:refund）',
  },
  'user_example.connection.invalid': <AppLanguage, String>{
    AppLanguage.en:
        'Unrecognized DSL format. Use always / intent:* / contains:*.',
    AppLanguage.ko:
        'DSL 형식이 인식되지 않았습니다. always / intent:* / contains:* 를 사용하세요.',
    AppLanguage.ja: 'DSL 形式を認識できません。always / intent:* / contains:* を使用してください。',
    AppLanguage.zh: '无法识别 DSL 格式，请使用 always / intent:* / contains:*。',
  },
  'user_example.connection.empty': <AppLanguage, String>{
    AppLanguage.en:
        'No explicit connections. Default order/routing will be used.',
    AppLanguage.ko: '명시적 연결이 없습니다. 기본 순서/라우팅을 사용합니다.',
    AppLanguage.ja: '明示的な接続はありません。既定の順序/ルーティングを使用します。',
    AppLanguage.zh: '暂无显式连接，将使用默认顺序/路由。',
  },
  'user_example.field.prompts': <AppLanguage, String>{
    AppLanguage.en: 'Example prompts',
    AppLanguage.ko: '예시 질문',
    AppLanguage.ja: '質問例',
    AppLanguage.zh: '示例提问',
  },
  'user_example.field.prompt1': <AppLanguage, String>{
    AppLanguage.en: 'Prompt 1',
    AppLanguage.ko: '질문 1',
    AppLanguage.ja: '質問 1',
    AppLanguage.zh: '提问 1',
  },
  'user_example.field.prompt2': <AppLanguage, String>{
    AppLanguage.en: 'Prompt 2',
    AppLanguage.ko: '질문 2',
    AppLanguage.ja: '質問 2',
    AppLanguage.zh: '提问 2',
  },
  'user_example.field.prompt3': <AppLanguage, String>{
    AppLanguage.en: 'Prompt 3',
    AppLanguage.ko: '질문 3',
    AppLanguage.ja: '質問 3',
    AppLanguage.zh: '提问 3',
  },
  'user_example.field.agents': <AppLanguage, String>{
    AppLanguage.en: 'Agents',
    AppLanguage.ko: '에이전트 목록',
    AppLanguage.ja: 'エージェント一覧',
    AppLanguage.zh: '智能体列表',
  },
  'user_example.action.new': <AppLanguage, String>{
    AppLanguage.en: 'New Example',
    AppLanguage.ko: '새 예제',
    AppLanguage.ja: '新しい例',
    AppLanguage.zh: '新建示例',
  },
  'user_example.action.add_agent': <AppLanguage, String>{
    AppLanguage.en: 'Add agent',
    AppLanguage.ko: '에이전트 추가',
    AppLanguage.ja: 'エージェント追加',
    AppLanguage.zh: '添加智能体',
  },
  'user_example.action.add_connection': <AppLanguage, String>{
    AppLanguage.en: 'Add connection',
    AppLanguage.ko: '연결 추가',
    AppLanguage.ja: '接続追加',
    AppLanguage.zh: '添加连接',
  },
  'user_example.action.edit_agent': <AppLanguage, String>{
    AppLanguage.en: 'Edit agent',
    AppLanguage.ko: '에이전트 수정',
    AppLanguage.ja: 'エージェント編集',
    AppLanguage.zh: '编辑智能体',
  },
  'user_example.action.remove_agent': <AppLanguage, String>{
    AppLanguage.en: 'Remove agent',
    AppLanguage.ko: '에이전트 삭제',
    AppLanguage.ja: 'エージェント削除',
    AppLanguage.zh: '删除智能体',
  },
  'user_example.action.remove_connection': <AppLanguage, String>{
    AppLanguage.en: 'Remove connection',
    AppLanguage.ko: '연결 삭제',
    AppLanguage.ja: '接続削除',
    AppLanguage.zh: '删除连接',
  },
  'user_example.action.edit': <AppLanguage, String>{
    AppLanguage.en: 'Edit',
    AppLanguage.ko: '수정',
    AppLanguage.ja: '編集',
    AppLanguage.zh: '编辑',
  },
  'user_example.action.delete': <AppLanguage, String>{
    AppLanguage.en: 'Delete',
    AppLanguage.ko: '삭제',
    AppLanguage.ja: '削除',
    AppLanguage.zh: '删除',
  },
  'user_example.validation.min_agents': <AppLanguage, String>{
    AppLanguage.en:
        'Current topology requires more agents. Add at least the minimum number of agents.',
    AppLanguage.ko: '현재 연결 방식에는 더 많은 에이전트가 필요합니다. 최소 개수 이상 추가해 주세요.',
    AppLanguage.ja: '現在の接続方式には、より多くのエージェントが必要です。最小数以上を追加してください。',
    AppLanguage.zh: '当前连接方式需要更多智能体，请至少添加到最小数量。',
  },
  'user_example.tool.capital': <AppLanguage, String>{
    AppLanguage.en: 'Capital',
    AppLanguage.ko: '수도',
    AppLanguage.ja: '首都',
    AppLanguage.zh: '首都',
  },
  'user_example.tool.weather': <AppLanguage, String>{
    AppLanguage.en: 'Weather',
    AppLanguage.ko: '날씨',
    AppLanguage.ja: '天気',
    AppLanguage.zh: '天气',
  },
  'user_example.tool.time': <AppLanguage, String>{
    AppLanguage.en: 'Time',
    AppLanguage.ko: '시간',
    AppLanguage.ja: '時刻',
    AppLanguage.zh: '时间',
  },
  'user_example.tool.none': <AppLanguage, String>{
    AppLanguage.en: 'No tools',
    AppLanguage.ko: '도구 없음',
    AppLanguage.ja: 'ツールなし',
    AppLanguage.zh: '无工具',
  },
  'user_example.agent.no_description': <AppLanguage, String>{
    AppLanguage.en: 'No description',
    AppLanguage.ko: '설명 없음',
    AppLanguage.ja: '説明なし',
    AppLanguage.zh: '无描述',
  },
  'user_example.arch.single': <AppLanguage, String>{
    AppLanguage.en: 'Single Agent',
    AppLanguage.ko: '단일 에이전트',
    AppLanguage.ja: '単一エージェント',
    AppLanguage.zh: '单智能体',
  },
  'user_example.arch.team': <AppLanguage, String>{
    AppLanguage.en: 'Agent Team',
    AppLanguage.ko: '에이전트 팀',
    AppLanguage.ja: 'エージェントチーム',
    AppLanguage.zh: '智能体团队',
  },
  'user_example.arch.sequential': <AppLanguage, String>{
    AppLanguage.en: 'Sequential Workflow',
    AppLanguage.ko: 'Sequential 워크플로우',
    AppLanguage.ja: 'Sequential ワークフロー',
    AppLanguage.zh: 'Sequential 工作流',
  },
  'user_example.arch.parallel': <AppLanguage, String>{
    AppLanguage.en: 'Parallel Workflow',
    AppLanguage.ko: 'Parallel 워크플로우',
    AppLanguage.ja: 'Parallel ワークフロー',
    AppLanguage.zh: 'Parallel 工作流',
  },
  'user_example.arch.loop': <AppLanguage, String>{
    AppLanguage.en: 'Loop Workflow',
    AppLanguage.ko: 'Loop 워크플로우',
    AppLanguage.ja: 'Loop ワークフロー',
    AppLanguage.zh: 'Loop 工作流',
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
  'graph.title': <AppLanguage, String>{
    AppLanguage.en: 'Graph Workflow Example',
    AppLanguage.ko: 'Graph Workflow 예제',
    AppLanguage.ja: 'Graph Workflow 例',
    AppLanguage.zh: 'Graph Workflow 示例',
  },
  'graph.summary': <AppLanguage, String>{
    AppLanguage.en:
        'ADK 2.0 graph Workflow with a triage node and routed edges.',
    AppLanguage.ko: 'Triage 노드와 routed edge를 사용하는 ADK 2.0 graph Workflow 예제입니다.',
    AppLanguage.ja: 'Triage ノードと routed edge を使う ADK 2.0 graph Workflow の例です。',
    AppLanguage.zh: '使用 triage 节点与 routed edge 的 ADK 2.0 graph Workflow 示例。',
  },
  'graph.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. A triage node routes each request to a tech, business, or general specialist node.',
    AppLanguage.ko: '안녕하세요. Triage 노드가 요청을 기술/비즈니스/일반 전문 노드로 라우팅합니다.',
    AppLanguage.ja: 'こんにちは。Triage ノードが要求を技術/ビジネス/一般ノードへルーティングします。',
    AppLanguage.zh: '你好，triage 节点会把请求路由到技术/商业/通用专家节点。',
  },
  'graph.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to see graph-based routing in action.',
    AppLanguage.ko: '메시지를 보내 graph 기반 라우팅을 확인하세요.',
    AppLanguage.ja: 'メッセージを送って graph ベースのルーティングを確認してください。',
    AppLanguage.zh: '发送消息以体验基于 graph 的路由。',
  },
  'graph.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. How do I fix this API error?',
    AppLanguage.ko: '예: 이 API 에러를 어떻게 고치죠?',
    AppLanguage.ja: '例: この API エラーの直し方は？',
    AppLanguage.zh: '例如：这个 API 报错怎么修？',
  },
  'google_search.title': <AppLanguage, String>{
    AppLanguage.en: 'Google Search Example',
    AppLanguage.ko: 'Google Search 예제',
    AppLanguage.ja: 'Google Search 例',
    AppLanguage.zh: 'Google Search 示例',
  },
  'google_search.summary': <AppLanguage, String>{
    AppLanguage.en: 'Gemini built-in Google Search grounding example.',
    AppLanguage.ko: 'Gemini built-in Google Search grounding 예제입니다.',
    AppLanguage.ja: 'Gemini 組み込み Google Search grounding の例です。',
    AppLanguage.zh: 'Gemini 内置 Google Search grounding 示例。',
  },
  'google_search.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. Ask about recent or factual topics and I will ground answers with Google Search.',
    AppLanguage.ko: '안녕하세요. 최신/사실 확인 질문을 하면 Google Search로 근거를 찾아 답합니다.',
    AppLanguage.ja: 'こんにちは。最新情報や事実確認の質問には Google Search で根拠を探して答えます。',
    AppLanguage.zh: '你好，问我最新或需要核实的问题，我会用 Google Search 提供有依据的回答。',
  },
  'google_search.empty': <AppLanguage, String>{
    AppLanguage.en: 'Ask a question to test Google Search grounding.',
    AppLanguage.ko: '질문을 보내 Google Search grounding을 확인하세요.',
    AppLanguage.ja: '質問を送って Google Search grounding を確認してください。',
    AppLanguage.zh: '发送问题以测试 Google Search grounding。',
  },
  'google_search.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. Latest Gemini API updates?',
    AppLanguage.ko: '예: Gemini API 최신 업데이트는?',
    AppLanguage.ja: '例: Gemini API の最新アップデートは？',
    AppLanguage.zh: '例如：Gemini API 有哪些最新更新？',
  },
  'url_context.title': <AppLanguage, String>{
    AppLanguage.en: 'URL Context Example',
    AppLanguage.ko: 'URL Context 예제',
    AppLanguage.ja: 'URL Context 例',
    AppLanguage.zh: 'URL Context 示例',
  },
  'url_context.summary': <AppLanguage, String>{
    AppLanguage.en: 'Gemini built-in URL context retrieval example.',
    AppLanguage.ko: 'Gemini built-in URL context retrieval 예제입니다.',
    AppLanguage.ja: 'Gemini 組み込み URL context retrieval の例です。',
    AppLanguage.zh: 'Gemini 内置 URL context retrieval 示例。',
  },
  'url_context.initial': <AppLanguage, String>{
    AppLanguage.en:
        'Hello. Send one or more URLs and I will use URL context to read them.',
    AppLanguage.ko: '안녕하세요. URL을 보내면 URL context로 내용을 읽어 처리합니다.',
    AppLanguage.ja: 'こんにちは。URL を送ると URL context で内容を読み取ります。',
    AppLanguage.zh: '你好，发送 URL 后我会用 URL context 读取内容。',
  },
  'url_context.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a URL to test model-side URL context retrieval.',
    AppLanguage.ko: 'URL을 보내 model-side URL context retrieval을 확인하세요.',
    AppLanguage.ja: 'URL を送って model-side URL context retrieval を確認してください。',
    AppLanguage.zh: '发送 URL 以测试 model-side URL context retrieval。',
  },
  'url_context.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. Summarize https://google.github.io/adk-docs/',
    AppLanguage.ko: '예: https://google.github.io/adk-docs/ 요약해줘',
    AppLanguage.ja: '例: https://google.github.io/adk-docs/ を要約して',
    AppLanguage.zh: '例如：总结 https://google.github.io/adk-docs/',
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
  'hitl.title': <AppLanguage, String>{
    AppLanguage.en: 'Human In The Loop (Choice)',
    AppLanguage.ko: '휴먼 인 더 루프 (선택/승인)',
    AppLanguage.ja: 'Human In The Loop (選択/承認)',
    AppLanguage.zh: '人机协同 (选择/确认)',
  },
  'hitl.summary': <AppLanguage, String>{
    AppLanguage.en: 'Interactive decision making with GetUserChoiceTool.',
    AppLanguage.ko: 'GetUserChoiceTool을 활용한 대화형 사용자 선택/확인 예제입니다.',
    AppLanguage.ja: 'GetUserChoiceTool を活用したインタラクティブなユーザー選択・確認例です。',
    AppLanguage.zh: '基于 GetUserChoiceTool 的交互式用户选择与确认示例。',
  },
  'hitl.initial': <AppLanguage, String>{
    AppLanguage.en: 'Hello! Ask me for travel advice or recommendations, and I will present options for you to choose.',
    AppLanguage.ko: '안녕하세요! 여행 계획이나 추천을 요청하시면 옵션을 제시하고 직접 선택하실 수 있도록 도와드립니다.',
    AppLanguage.ja: 'こんにちは！旅行の相談やおすすめを尋ねてください。選択肢を提示して直接選べるよう案内します。',
    AppLanguage.zh: '你好！向我咨询旅行计划或推荐，我会提供选项供您选择。',
  },
  'hitl.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a message to start human-in-the-loop interaction.',
    AppLanguage.ko: '메시지를 보내 Human-In-The-Loop 대화형 선택을 확인하세요.',
    AppLanguage.ja: 'メッセージを送信して Human-In-The-Loop インタラクティブ選択を確認してください。',
    AppLanguage.zh: '发送消息以体验人机协同交互式选择。',
  },
  'hitl.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. Recommend weekend getaway spots in Europe or Asia',
    AppLanguage.ko: '예: 주말에 갈만한 국내/해외 힐링 여행지 추천해줘',
    AppLanguage.ja: '例: 週末に行けるおすすめの旅行先を提案して',
    AppLanguage.zh: '例如：推荐适合周末度假的旅游目的地',
  },
  'prompt.hitl.1': <AppLanguage, String>{
    AppLanguage.en: 'Recommend 3 scenic vacation destinations and let me choose one.',
    AppLanguage.ko: '경치 좋은 휴양지 3곳을 추천해주고 내가 고를 수 있게 해줘.',
    AppLanguage.ja: '景色の良いリゾート地を3つ推薦して、選ばせてください。',
    AppLanguage.zh: '推荐3个风景优美的度假胜地，并让我选择一个。',
  },
  'prompt.hitl.2': <AppLanguage, String>{
    AppLanguage.en: 'Plan a romantic dinner date in Seoul with style options.',
    AppLanguage.ko: '서울에서 데이트하기 좋은 저녁 코스를 분위기별 옵션으로 제안해줘.',
    AppLanguage.ja: 'ソウルで雰囲気の良いディナーデートコースを選択肢付きで提案して。',
    AppLanguage.zh: '推荐首尔适合浪漫约会的晚餐路线并提供风格选项。',
  },
  'prompt.hitl.3': <AppLanguage, String>{
    AppLanguage.en: 'Give me 3 tech conference topics and ask me which one to deep dive into.',
    AppLanguage.ko: '최근 주목받는 AI 기술 테마 3가지를 제시하고 어떤 것을 깊게 다룰지 물어봐줘.',
    AppLanguage.ja: '注目されているAI技術テーマを3つ提示し、どれを深掘りするか尋ねて。',
    AppLanguage.zh: '列出3个热门的AI技术主题，并询问我想深入了解哪一个。',
  },
  'self_healing.title': <AppLanguage, String>{
    AppLanguage.en: 'Self-Healing (Reflect & Retry)',
    AppLanguage.ko: '자가 치유 에이전트 (반추 및 재시도)',
    AppLanguage.ja: '自己修復エージェント (Reflect & Retry)',
    AppLanguage.zh: '自愈 Agent (反思与重试)',
  },
  'self_healing.summary': <AppLanguage, String>{
    AppLanguage.en: 'Automatic reflection and tool error recovery with ReflectAndRetryToolPlugin.',
    AppLanguage.ko: 'ReflectAndRetryToolPlugin을 통한 도구 에러 자동 반추 및 복구 예제입니다.',
    AppLanguage.ja: 'ReflectAndRetryToolPlugin によるツールエラーの自動内省と回復例です。',
    AppLanguage.zh: '基于 ReflectAndRetryToolPlugin 的工具错误自动反思与自愈恢复示例。',
  },
  'self_healing.initial': <AppLanguage, String>{
    AppLanguage.en: 'Hello! I can perform mathematical and data operations with automatic self-healing retry on errors.',
    AppLanguage.ko: '안녕하세요! 계산 및 데이터 처리 중 오류가 발생해도 플러그인이 스스로 반추하여 파라미터를 수정 후 재시도합니다.',
    AppLanguage.ja: 'こんにちは！ツール実行中にエラーが発生しても自動で内省・修正して再試行します。',
    AppLanguage.zh: '你好！在工具执行出错时，插件会自动反思并修正参数进行自愈重试。',
  },
  'self_healing.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a calculation request to see self-healing in action.',
    AppLanguage.ko: '계산 또는 데이터 요청을 보내 자가 치유 동작을 확인하세요.',
    AppLanguage.ja: '計算リクエストを送信して自己修復の動作を確認してください。',
    AppLanguage.zh: '发送计算请求以查看自愈重试效果。',
  },
  'self_healing.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. Calculate 100 divided by (5 - 5), then fix denominator to 2',
    AppLanguage.ko: '예: 100을 25로 나눈 값과 곱한 값을 안전하게 계산해줘',
    AppLanguage.ja: '例: 100 を 25 で割った値を安全に計算して',
    AppLanguage.zh: '例如：安全地计算 100 除以 25 的结果',
  },
  'prompt.self_healing.1': <AppLanguage, String>{
    AppLanguage.en: 'Divide 250 by 5 safely using the calculate tool.',
    AppLanguage.ko: 'calculate_safely 도구를 사용해 250을 5로 나눠줘.',
    AppLanguage.ja: 'calculate_safely ツールを使って 250 を 5 で割って。',
    AppLanguage.zh: '使用 calculate_safely 工具将 250 除以 5。',
  },
  'prompt.self_healing.2': <AppLanguage, String>{
    AppLanguage.en: 'Multiply 42 and 18 safely.',
    AppLanguage.ko: '42와 18의 곱셈을 calculate_safely 도구로 계산해줘.',
    AppLanguage.ja: '42 と 18 の掛け算を calculate_safely ツールで計算して。',
    AppLanguage.zh: '使用 calculate_safely 工具计算 42 乘以 18。',
  },
  'prompt.self_healing.3': <AppLanguage, String>{
    AppLanguage.en: 'Attempt dividing 100 by 0, notice the error feedback, and fix it to divide by 4.',
    AppLanguage.ko: '100을 0으로 나누려 시도했을 때 에러 피드백을 보고 분모를 4로 자동 수정해 계산해줘.',
    AppLanguage.ja: '100 を 0 で割る試みでエラーが出たら、自動で分母を 4 に修正して計算して。',
    AppLanguage.zh: '尝试将 100 除以 0，捕获错误反馈后自动修正为除以 4 并完成计算。',
  },
  'structured_output.title': <AppLanguage, String>{
    AppLanguage.en: 'Structured Output (JSON Schema)',
    AppLanguage.ko: '구조화된 출력 (JSON Schema)',
    AppLanguage.ja: '構造化出力 (JSON Schema)',
    AppLanguage.zh: '结构化输出 (JSON Schema)',
  },
  'structured_output.summary': <AppLanguage, String>{
    AppLanguage.en: 'Guaranteed typed JSON responses via model outputSchema.',
    AppLanguage.ko: 'outputSchema를 통해 모델이 엄격한 형식의 JSON 객체로 응답하는 예제입니다.',
    AppLanguage.ja: 'outputSchema により型定義された厳格な JSON で応答する例です。',
    AppLanguage.zh: '通过 outputSchema 确保模型按严格的 JSON 结构返回数据。',
  },
  'structured_output.initial': <AppLanguage, String>{
    AppLanguage.en: 'Hello! Ask for any recipe and I will return guaranteed typed JSON data with ingredients and steps.',
    AppLanguage.ko: '안녕하세요! 원하는 요리를 말씀해주시면 outputSchema에 정의된 엄격한 JSON 형식으로 레시피를 생성해 드립니다.',
    AppLanguage.ja: 'こんにちは！料理名を教えていただければ、厳格な JSON スキーマに従ってレシピを生成します。',
    AppLanguage.zh: '你好！告诉我你想做的菜品，我会按照严格的 JSON Schema 生成食谱数据。',
  },
  'structured_output.empty': <AppLanguage, String>{
    AppLanguage.en: 'Send a food name to see structured JSON output.',
    AppLanguage.ko: '요리 이름을 보내 구조화된 JSON 레시피를 확인하세요.',
    AppLanguage.ja: '料理名を送信して構造化 JSON レシピを確認してください。',
    AppLanguage.zh: '发送菜品名称以查看结构化 JSON 食谱。',
  },
  'structured_output.hint': <AppLanguage, String>{
    AppLanguage.en: 'e.g. Italian creamy carbonara pasta',
    AppLanguage.ko: '예: 이탈리아 정통 까르보나라 파스타',
    AppLanguage.ja: '例: 本格カルボナーラパスタ',
    AppLanguage.zh: '例如：正宗意式卡邦尼意面',
  },
  'prompt.structured_output.1': <AppLanguage, String>{
    AppLanguage.en: 'Generate a recipe for classic Kimchi Fried Rice.',
    AppLanguage.ko: '정통 김치볶음밥 레시피를 JSON으로 생성해줘.',
    AppLanguage.ja: 'クラシックなキムチチャーハンのレシピを JSON で作成して。',
    AppLanguage.zh: '生成一份经典的泡菜炒饭食谱 JSON。',
  },
  'prompt.structured_output.2': <AppLanguage, String>{
    AppLanguage.en: 'Create a 15-minute quick healthy breakfast recipe.',
    AppLanguage.ko: '15분 안에 만들 수 있는 건강한 아침 식사 레시피를 만들어줘.',
    AppLanguage.ja: '15分で作れるヘルシーな朝食レシピを作成して。',
    AppLanguage.zh: '创建一份可在15分钟内完成的健康早餐食谱。',
  },
  'prompt.structured_output.3': <AppLanguage, String>{
    AppLanguage.en: 'Provide a French beef bourguignon recipe with full ingredient measurements.',
    AppLanguage.ko: '프랑스식 비프 부르기뇽 레시피를 재료 정량과 함께 JSON으로 출력해줘.',
    AppLanguage.ja: 'フランス風ビーフブルギニョンのレシピを分量付きの JSON で出力して。',
    AppLanguage.zh: '提供带完整食材用量的法式红酒炖牛肉食谱 JSON。',
  },
};

String tr(AppLanguage language, String key) {
  final Map<AppLanguage, String>? values = appI18n[key];
  if (values == null) {
    return key;
  }
  return values[language] ?? values[AppLanguage.en] ?? key;
}
