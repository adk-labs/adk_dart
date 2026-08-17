import 'package:flutter/material.dart';

import 'package:flutter_adk_example/data/services/agent_service.dart';
import 'package:flutter_adk_example/ui/examples/models/example_menu_item.dart';

List<ExampleMenuItem> buildExampleMenuItems() {
  return <ExampleMenuItem>[
    ExampleMenuItem(
      id: 'basic',
      icon: Icons.chat_bubble_outline,
      category: ExampleCategory.general,
      titleKey: 'basic.title',
      summaryKey: 'basic.summary',
      initialKey: 'basic.initial',
      emptyKey: 'basic.empty',
      hintKey: 'basic.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.basic.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.basic.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.basic.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildBasic,
    ),
    ExampleMenuItem(
      id: 'local_llm',
      icon: Icons.memory_outlined,
      category: ExampleCategory.general,
      titleKey: 'local_llm.title',
      summaryKey: 'local_llm.summary',
      initialKey: 'local_llm.initial',
      emptyKey: 'local_llm.empty',
      hintKey: 'local_llm.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.local_llm.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.local_llm.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.local_llm.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildLocalLlm,
    ),
    ExampleMenuItem(
      id: 'custom_agent',
      icon: Icons.tune_outlined,
      category: ExampleCategory.general,
      titleKey: 'custom.title',
      summaryKey: 'custom.summary',
      initialKey: 'custom.initial',
      emptyKey: 'custom.empty',
      hintKey: 'custom.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.custom.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.custom.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.custom.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      // 실제 커스텀 구성은 HomeScreen에서 agentBuilderOverride로 주입된다.
      agentBuilder: AgentService.buildBasic,
    ),
    ExampleMenuItem(
      id: 'multi_agent',
      icon: Icons.hub_outlined,
      category: ExampleCategory.general,
      titleKey: 'transfer.title',
      summaryKey: 'transfer.summary',
      initialKey: 'transfer.initial',
      emptyKey: 'transfer.empty',
      hintKey: 'transfer.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.transfer.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.transfer.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.transfer.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildTransfer,
    ),
    ExampleMenuItem(
      id: 'workflow',
      icon: Icons.account_tree_outlined,
      category: ExampleCategory.workflow,
      titleKey: 'workflow.title',
      summaryKey: 'workflow.summary',
      initialKey: 'workflow.initial',
      emptyKey: 'workflow.empty',
      hintKey: 'workflow.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.workflow.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.workflow.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.workflow.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildWorkflow,
    ),
    ExampleMenuItem(
      id: 'graph_workflow',
      icon: Icons.schema_outlined,
      category: ExampleCategory.workflow,
      titleKey: 'graph.title',
      summaryKey: 'graph.summary',
      initialKey: 'graph.initial',
      emptyKey: 'graph.empty',
      hintKey: 'graph.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.graph.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.graph.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.graph.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildGraphWorkflow,
    ),
    ExampleMenuItem(
      id: 'sequential',
      icon: Icons.linear_scale_outlined,
      category: ExampleCategory.workflow,
      titleKey: 'sequential.title',
      summaryKey: 'sequential.summary',
      initialKey: 'sequential.initial',
      emptyKey: 'sequential.empty',
      hintKey: 'sequential.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.sequential.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.sequential.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.sequential.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildSequential,
    ),
    ExampleMenuItem(
      id: 'parallel',
      icon: Icons.call_split_outlined,
      category: ExampleCategory.workflow,
      titleKey: 'parallel.title',
      summaryKey: 'parallel.summary',
      initialKey: 'parallel.initial',
      emptyKey: 'parallel.empty',
      hintKey: 'parallel.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.parallel.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.parallel.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.parallel.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildParallel,
    ),
    ExampleMenuItem(
      id: 'loop',
      icon: Icons.loop_outlined,
      category: ExampleCategory.workflow,
      titleKey: 'loop.title',
      summaryKey: 'loop.summary',
      initialKey: 'loop.initial',
      emptyKey: 'loop.empty',
      hintKey: 'loop.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.loop.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.loop.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.loop.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildLoop,
    ),
    ExampleMenuItem(
      id: 'agent_team',
      icon: Icons.groups_outlined,
      category: ExampleCategory.team,
      titleKey: 'team.title',
      summaryKey: 'team.summary',
      initialKey: 'team.initial',
      emptyKey: 'team.empty',
      hintKey: 'team.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.team.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.team.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.team.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildTeam,
    ),
    ExampleMenuItem(
      id: 'mcp_toolset',
      icon: Icons.extension_outlined,
      category: ExampleCategory.integrations,
      titleKey: 'mcp.title',
      summaryKey: 'mcp.summary',
      initialKey: 'mcp.initial',
      emptyKey: 'mcp.empty',
      hintKey: 'mcp.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.mcp.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.mcp.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.mcp.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildMcp,
    ),
    ExampleMenuItem(
      id: 'google_search',
      icon: Icons.travel_explore_outlined,
      category: ExampleCategory.integrations,
      titleKey: 'google_search.title',
      summaryKey: 'google_search.summary',
      initialKey: 'google_search.initial',
      emptyKey: 'google_search.empty',
      hintKey: 'google_search.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.google_search.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.google_search.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.google_search.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildGoogleSearch,
    ),
    ExampleMenuItem(
      id: 'url_context',
      icon: Icons.link_outlined,
      category: ExampleCategory.integrations,
      titleKey: 'url_context.title',
      summaryKey: 'url_context.summary',
      initialKey: 'url_context.initial',
      emptyKey: 'url_context.empty',
      hintKey: 'url_context.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.url_context.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.url_context.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.url_context.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildUrlContext,
    ),
    ExampleMenuItem(
      id: 'skills',
      icon: Icons.psychology_outlined,
      category: ExampleCategory.integrations,
      titleKey: 'skills.title',
      summaryKey: 'skills.summary',
      initialKey: 'skills.initial',
      emptyKey: 'skills.empty',
      hintKey: 'skills.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.skills.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.skills.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.skills.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildSkills,
    ),
    ExampleMenuItem(
      id: 'hitl',
      icon: Icons.touch_app_outlined,
      category: ExampleCategory.general,
      titleKey: 'hitl.title',
      summaryKey: 'hitl.summary',
      initialKey: 'hitl.initial',
      emptyKey: 'hitl.empty',
      hintKey: 'hitl.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.hitl.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.hitl.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.hitl.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildHumanInTheLoop,
    ),
    ExampleMenuItem(
      id: 'self_healing',
      icon: Icons.healing_outlined,
      category: ExampleCategory.integrations,
      titleKey: 'self_healing.title',
      summaryKey: 'self_healing.summary',
      initialKey: 'self_healing.initial',
      emptyKey: 'self_healing.empty',
      hintKey: 'self_healing.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.self_healing.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.self_healing.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.self_healing.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildSelfHealing,
    ),
    ExampleMenuItem(
      id: 'structured_output',
      icon: Icons.data_object_outlined,
      category: ExampleCategory.general,
      titleKey: 'structured_output.title',
      summaryKey: 'structured_output.summary',
      initialKey: 'structured_output.initial',
      emptyKey: 'structured_output.empty',
      hintKey: 'structured_output.hint',
      prompts: const <ExamplePromptItem>[
        ExamplePromptItem(
          textKey: 'prompt.structured_output.1',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.structured_output.2',
          difficulty: ExamplePromptDifficulty.basic,
        ),
        ExamplePromptItem(
          textKey: 'prompt.structured_output.3',
          difficulty: ExamplePromptDifficulty.advanced,
        ),
      ],
      agentBuilder: AgentService.buildStructuredOutput,
    ),
  ];
}
