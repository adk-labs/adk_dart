import 'dart:io';

import 'package:adk_dart/adk_dart.dart';

Future<void> main() async {
  print('=== ADK Skills & Output Artifacts Demo ===');

  // 1. Discover and load local skills from ../skills (or examples/skills)
  final Directory localSkills = Directory('${Directory.current.path}/../skills');
  final Directory skillsRoot = localSkills.existsSync()
      ? localSkills
      : Directory('${Directory.current.path}/examples/skills');
  final Map<String, Frontmatter> discovered = listSkillsInDir(skillsRoot.path);
  print('Discovered skills: ${discovered.keys.join(', ')}');

  final List<Skill> skills = <Skill>[
    for (final String name in discovered.keys)
      loadSkillFromDir('${skillsRoot.path}/$name'),
  ];

  // 2. Configure SkillToolset with saveOutputArtifacts enabled
  final SkillToolset skillToolset = SkillToolset(
    skills: skills,
    saveOutputArtifacts: true,
  );
  print(
    'Configured SkillToolset with saveOutputArtifacts=${skillToolset.saveOutputArtifacts}',
  );

  // 3. Demonstrate safe artifact injection and binary placeholder formatting
  final InMemorySessionService sessionService = InMemorySessionService();
  final InMemoryArtifactService artifactService = InMemoryArtifactService();
  final Session session = await sessionService.createSession(
    appName: 'skills_demo_app',
    userId: 'wizard_user',
    sessionId: 'session_skills_01',
    state: <String, Object?>{'mage_name': 'Merlin'},
  );

  await artifactService.saveArtifact(
    appName: 'skills_demo_app',
    userId: 'wizard_user',
    sessionId: session.id,
    filename: 'spellbook.bin',
    artifact: Part.fromInlineData(
      mimeType: 'application/x-grimoire',
      data: <int>[0xDE, 0xAD, 0xBE, 0xEF],
    ),
  );

  final Agent agent = Agent(
    name: 'wizard_agent',
    model: 'gemini-3.7-flash',
    instruction:
        r'Wizard {mage_name} (shell ${IGNORED_ENV}), inspect {artifact.spellbook.bin}',
    tools: <Object>[skillToolset],
  );

  final InvocationContext context = InvocationContext(
    sessionService: sessionService,
    artifactService: artifactService,
    invocationId: 'inv_skills_1',
    agent: agent,
    session: session,
  );

  final String renderedInstruction = await injectSessionState(
    agent.instruction as String,
    ReadonlyContext(context),
  );
  print('\nRendered instruction:\n$renderedInstruction');
}
