import 'user_simulator_personas.dart';

final UserBehavior _advanceDetailOriented = UserBehavior(
  name: 'Advance in the Agent succeeds',
  description:
      'The Generated User Response should stick to the Conversation Plan. '
      'When starting a new request, the Generated User Response should provide '
      'all the information required to accomplish a high-level goal.',
  behaviorInstructions: <String>[
    'If the Agent succeeds, make the next request from the Conversation Plan.',
    'Skip redundant requests already fulfilled by the Agent.',
    'When making a new request, state both the high-level goal you want to '
        'achieve next AND any additional details you need to achieve that goal.',
  ],
  violationRubrics: <String>[
    'The Generated User Response repeats a high-level goal that was already '
        'completed in previous turns.',
    'The Generated User Response provides details for a high-level goal that '
        'was already completed.',
    'The Generated User Response response agrees to change the topic or '
        'perform a task not listed in the Conversation Plan.',
    'The Generated User Response invents a new goal not present in the '
        'Conversation Plan.',
    'The Generated User Response invents details (e.g., a made-up phone '
        'number or address) not provided in the Conversation Plan.',
    'The Generated User Response only provides the high-level goal and the '
        'Agent has to ask for additional details.',
    'The Generated User Response tries to accomplish more than one high-level '
        'task in a single turn.',
  ],
);

final UserBehavior _advanceGoalOriented = UserBehavior(
  name: 'Advance if the Agent succeeds',
  description:
      'The Generated User Response should stick to the Conversation Plan as '
      'much as possible. It may deviate in response to Agent requests. The '
      'User Simulator starts with high-level goals, expecting the Agent to ask '
      'for specific details.',
  behaviorInstructions: <String>[
    'If the Agent succeeds, make the next request from the Conversation Plan.',
    'Skip redundant requests already fulfilled by the Agent.',
    'When making a request, state only the high-level goal you want to '
        'achieve next.',
    'Do NOT provide any additional information related to the high-level '
        'goal. The Agent must ask for it.',
  ],
  violationRubrics: <String>[
    'The Generated User Response repeats a high-level goal that was already '
        'completed in previous turns.',
    'The Generated User Response provides details for a high-level goal that '
        'was already completed.',
    'The Generated User Response invents a new goal not present in the '
        "Conversation Plan or in the Agent's messages.",
    'The Generated User Response invents details (e.g., a made-up phone '
        'number or address) not provided in the Conversation Plan or in the '
        "Agent's messages.",
    'The Generated User Response provides specific details for a high-level '
        'goal (email content, recipient address, phone numbers) BEFORE the '
        'Agent has explicitly asked for them.',
    'The Generated User Response tries to accomplish more than one high-level '
        'task in a single turn.',
  ],
);

final UserBehavior _answerRelevantOnly = UserBehavior(
  name: 'Answer only relevant questions',
  description:
      "The User Simulator should not answer questions that are not relevant to "
      'the high-level goals in the Conversation Plan (e.g., "How is your day '
      'going?"). If all questions the Agent asked are not relevant, the User '
      'Simulator should enforce the Conversation Plan (e.g., "Please stick to '
      'writing the email.").',
  behaviorInstructions: <String>[
    "Only answer the Agent's questions using information from the "
        'Conversation Plan.',
    'Do NOT provide any additional information the Agent did not explicitly '
        'ask for.',
    'If you do not have the information requested by the Agent, inform the '
        'Agent. Do NOT make up information that is not in the Conversation '
        'Plan.',
    'Do NOT answer questions that are not relevant to the high level goals '
        'in the Conversation Plan.',
  ],
  violationRubrics: <String>[
    'The Agent asked a question that is not relevant to the high-level goal '
        'and the Generated User Response responds to it.',
  ],
);

final UserBehavior _answerAll = UserBehavior(
  name: 'Answer all questions',
  description:
      "The User Simulator should address EVERY question that the Agent asked, "
      'e.g., if the Agent asks "How is your day going?", the User Simulator '
      'should respond.',
  behaviorInstructions: <String>[
    "Only answer the Agent's questions using information from the "
        'Conversation Plan.',
    'Do NOT provide any additional information the Agent did not explicitly '
        'ask for.',
    'If you do not have the information requested by the Agent, inform the '
        'Agent. Do NOT make up information that is not in the Conversation '
        "Plan. Acknowledge you don't know the information.",
  ],
  violationRubrics: <String>[
    'The Agent asked a question (or multiple questions), and the Generated '
        'User Response failed to address one or all of them.',
    'The Agent asked for information NOT in the Conversation Plan, and the '
        'Generated User Response made up an answer instead of stating, e.g., '
        '"I don\'t know" or "I don\'t have that info."',
  ],
);

final UserBehavior _correctAgent = UserBehavior(
  name: 'Correct the Agent if it makes a mistake',
  description:
      "The User Simulator should catch and correct the Agent's mistakes.",
  behaviorInstructions: <String>[
    'Challenge illogical or incorrect statements made by the Agent.',
    'If the Agent did an incorrect operation, ask the Agent to fix it.',
  ],
  violationRubrics: <String>[
    'The Agent provided incorrect information, and the Generated User Response '
        'continues as if it was correct.',
    'The Agent made a dangerous assumption (e.g., sending an email without '
        'asking for the content first), and the Generated User Response '
        'continues without correcting the Agent.',
  ],
);

final UserBehavior _doNotCorrectAgent = UserBehavior(
  name: 'Do not correct the Agent',
  description:
      'The User Simulator should end the conversation when the Agent provides '
      'an illogical or incorrect statement.',
  behaviorInstructions: <String>[
    'If the Agent made an illogical or incorrect statement, end the '
        'conversation with `{{ stop_signal }}`.',
  ],
  violationRubrics: <String>[
    'The Agent makes a mistake or an assumption and the Generated User '
        'Response corrects the Agent.',
  ],
);

final UserBehavior _troubleshootOnce = UserBehavior(
  name: 'Troubleshoot once (if necessary)',
  description:
      'The User Simulator should only troubleshoot the Agent ONCE. '
      'Troubleshooting is defined as the User Simulator helping the Agent '
      'after the Agent fails to execute an action (e.g., calls a function '
      'incorrectly) or fails to provide a response expected by the '
      'Conversation Plan. Answering a clarification question from the Agent is '
      'NOT troubleshooting. NOTE: Please check the conversation history count '
      'for Agent errors.',
  behaviorInstructions: <String>[
    'If the Agent failed to complete a request for the first time, '
        'troubleshoot the failure.',
    'You should only troubleshoot ONCE per conversation. DO NOT troubleshoot '
        'again if the Conversation History shows that the you have already '
        'tried to troubleshoot any request.',
  ],
  violationRubrics: <String>[
    'The Generated User Response ends the conversation immediately after the '
        'first Agent failure.',
    'On the second Agent failure, the Generated User Response response '
        'continues the conversation without using `{{ stop_signal }}`.',
    'After the second Agent failure, the Generated User Response tries to '
        'continue the conversation or continues addressing failures without '
        'using `{{ stop_signal }}`.',
  ],
);

final UserBehavior _endLimitedTroubleshooting = UserBehavior(
  name: 'End the conversation appropriately',
  description:
      'A conversation is complete if ANY of the following stop conditions are '
      'true:\n- The Agent has confirmed the completion of all the high-level '
      'goals in the Conversation Plan.\n- The Agent successfully transferred '
      'the User Simulator to a human/live agent.\n- The Agent failed more than '
      'once.\nThe Agent fails if it is unable to execute an action (e.g., '
      'calls a function incorrectly) or fails to provide a response expected '
      'by the Conversation Plan. Asking a clarification question is not a '
      'failure.',
  behaviorInstructions: <String>[
    'End the conversation only when any of the stopping conditions are met; '
        'do NOT end prematurely.',
    'When ending the conversation because the Agent has completed all the '
        'high-level goals, you must wait until the Agent has confirmed the '
        'completion of all the goals before ending.',
    'Output `{{ stop_signal }}` as part of your response to indicate that the '
        'conversation with the Agent is over.',
    'Pay attention to the Conversation History and count the number of Agent '
        'failures. A second failure should trigger the end of the conversation.',
  ],
  violationRubrics: <String>[
    'The conversation meets one of the stop conditions above, but the '
        'Generated User Response did not use `{{ stop_signal }}`.',
    'The Generated User Response used `{{ stop_signal }}` but the conversation '
        'does not meet any of the stop conditions above.',
  ],
);

final UserBehavior _endNoTroubleshooting = UserBehavior(
  name: 'End the conversation appropriately',
  description:
      'A conversation is considered completed if ANY of the following stop '
      'conditions are true:\n- The Agent has confirmed the completion of all '
      'the high-level goals in the Conversation Plan.\n- The Agent '
      'successfully transferred the User Simulator to a human/live agent.\n- '
      'The Agent failed.\nThe Agent fails if it is unable to execute an action '
      '(e.g., calls a function incorrectly) or fails to provide a response '
      'expected by the Conversation Plan. Asking a clarification question is '
      'not a failure.',
  behaviorInstructions: <String>[
    'End the conversation when any of the stopping conditions are met; do NOT '
        'end prematurely.',
    'When ending the conversation because the Agent has completed all the '
        'high-level goals, you must wait until the Agent has confirmed the '
        'completion of all the goals before ending.',
    'Output `{{ stop_signal }}` as part of your response to indicate that the '
        'conversation with the Agent is over.',
    'Pay attention to the last Agent message in the Conversation History. If '
        'the Agent message contains a failure, end the conversation.',
  ],
  violationRubrics: <String>[
    'The conversation meets one of the stop conditions above, but the '
        'Generated User Response did not use `{{ stop_signal }}`.',
    'The Generated User Response used `{{ stop_signal }}` but the conversation '
        'does not meet any of the stop conditions above.',
    'On the first Agent failure, the Generated User Response continues the '
        'conversation without using `{{ stop_signal }}`.',
    'After the first Agent failure, the Generated User Response tries to '
        'continue the conversation without using `{{ stop_signal }}`.',
  ],
);

final UserBehavior _toneProfessional = UserBehavior(
  name: 'Professional tone',
  description:
      'The User Simulator use clear, technical language. NOTE: '
      '`{{ stop_signal }}` is appropriate language.',
  behaviorInstructions: <String>[
    'The User Simulator should use clear, technical language.',
    'Avoid slang, frequent abbreviations, emojis, or excessive social filler '
        'and personal asides.',
  ],
  violationRubrics: <String>[
    'The Generated User Response includes slang (e.g., "gimme," "kinda," '
        '"lol"), frequent abbreviations (e.g., "info," "btw"), or emojis.',
    'The Generated User Response includes significant social filler or '
        'personal asides, e.g., "Hi there! I hope you\'re having a good day.',
    'The Generated User Response is a "wall of text" where a a direct '
        'sentence would suffice.',
    'The tone of the Generated User Response is inconsist with previous user '
        'turns (if present).',
  ],
);

final UserBehavior _toneConversational = UserBehavior(
  name: 'Conversational tone',
  description:
      'The User Simulator sounds informal. NOTE: `{{ stop_signal }}` is '
      'appropriate language.',
  behaviorInstructions: <String>[
    'The User Simulator should sound like a normal human having a casual '
        'conversation.',
    'Avoid answers that are too formal in nature or employ overly polite '
        'phrases and expressions.',
    'Avoid answers that lack natural conversational framing, for example, '
        'sterile or purely functional responses.',
  ],
  violationRubrics: <String>[
    'The Generated User Response is sterile and purely functional (direct '
        'commands) with no natural conversational framing.',
    'The Generated User Response is too formal in nature, employing overly '
        'polite phrases and expressions.',
    'The Generated User Response is a "wall of text" where a simple sentence '
        'would suffice.',
    'The tone of the Generated User Response is inconsist with previous user '
        'turns (if present).',
  ],
);

final UserPersona _expertPersona = UserPersona(
  id: 'EXPERT',
  description:
      'An Expert knows exactly what they want and views the Agent as a tool '
      'to execute their commands as efficiently as possible. Experts have '
      'little patience for chit-chat or unnecessary questions.',
  behaviors: <UserBehavior>[
    _advanceDetailOriented,
    _answerRelevantOnly,
    _correctAgent,
    _troubleshootOnce,
    _endLimitedTroubleshooting,
    _toneProfessional,
  ],
);

final UserPersona _novicePersona = UserPersona(
  id: 'NOVICE',
  description:
      "A Novice is trying to solve a problem they don't fully understand, and "
      "they rely heavily on the Agent for guidance. Novices are patient with "
      "the Agent's questions, but are unable to troubleshoot the Agent's "
      'mistakes. Novices are also unable to correct the Agent.',
  behaviors: <UserBehavior>[
    _advanceGoalOriented,
    _doNotCorrectAgent,
    _answerAll,
    _endNoTroubleshooting,
    _toneConversational,
  ],
);

final UserPersona _evaluatorPersona = UserPersona(
  id: 'EVALUATOR',
  description:
      'An Evaluator is trying to assess whether the Agent can help accomplish '
      'the goals in the Conversation Plan.',
  behaviors: <UserBehavior>[
    _advanceDetailOriented,
    _answerRelevantOnly,
    _endNoTroubleshooting,
    _doNotCorrectAgent,
    _toneConversational,
  ],
);

final UserPersona _legacyDefaultGoalOrientedPersona = UserPersona(
  id: 'default_goal_oriented',
  description:
      'Goal-oriented user who follows the conversation plan and provides '
      'required details when asked.',
  behaviors: <UserBehavior>[_advanceGoalOriented],
);

UserPersonaRegistry getDefaultPersonaRegistry() {
  final UserPersonaRegistry registry = UserPersonaRegistry();
  registry.registerPersona(_expertPersona.id, _expertPersona);
  registry.registerPersona(_novicePersona.id, _novicePersona);
  registry.registerPersona(_evaluatorPersona.id, _evaluatorPersona);
  registry.registerPersona(
    _legacyDefaultGoalOrientedPersona.id,
    _legacyDefaultGoalOrientedPersona,
  );
  return registry;
}
