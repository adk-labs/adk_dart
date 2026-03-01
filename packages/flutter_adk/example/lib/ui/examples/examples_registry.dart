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
  ];
}
