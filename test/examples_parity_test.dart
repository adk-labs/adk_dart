import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

class _ExampleProvider extends BaseExampleProvider {
  _ExampleProvider(this.examples);

  final List<Example> examples;

  @override
  List<Example> getExamples(String query) {
    return examples;
  }
}

void main() {
  group('examples parity', () {
    test('convertExamplesToText uses gemini2 formatting by default', () {
      final Example example = Example(
        input: Content(
          role: 'user',
          parts: <Part>[Part.text('time in seoul?')],
        ),
        output: <Content>[
          Content(
            role: 'model',
            parts: <Part>[
              Part.fromFunctionCall(
                name: 'get_current_time',
                args: <String, dynamic>{'city': 'Seoul'},
              ),
              Part.fromFunctionResponse(
                name: 'get_current_time',
                response: <String, dynamic>{'time': '10:30 AM'},
              ),
              Part.text('The current time in Seoul is 10:30 AM.'),
            ],
          ),
        ],
      );

      final String text = convertExamplesToText(<Example>[example], null);

      expect(text, contains('<EXAMPLES>'));
      expect(text, contains('EXAMPLE 1:'));
      expect(text, contains('[user]'));
      expect(text, contains('[model]'));
      expect(text, contains("get_current_time(city='Seoul')"));
      expect(text, isNot(contains('```tool_code')));
      expect(text, contains('The current time in Seoul is 10:30 AM.'));
    });

    test(
      'convertExamplesToText uses non-gemini2 function fences when needed',
      () {
        final Example example = Example(
          input: Content(role: 'user', parts: <Part>[Part.text('query')]),
          output: <Content>[
            Content(
              role: 'model',
              parts: <Part>[
                Part.fromFunctionCall(
                  name: 'lookup',
                  args: <String, dynamic>{'q': 'x'},
                ),
                Part.fromFunctionResponse(
                  name: 'lookup',
                  response: <String, dynamic>{'ok': true},
                ),
              ],
            ),
          ],
        );

        final String text = convertExamplesToText(<Example>[
          example,
        ], 'gemini-1.5-pro');

        expect(text, contains('```tool_code'));
        expect(text, contains('```tool_outputs'));
      },
    );

    test('buildExampleSi accepts list and provider', () {
      final List<Example> examples = <Example>[
        Example(
          input: Content.userText('hi'),
          output: <Content>[Content.modelText('hello')],
        ),
      ];

      final String fromList = buildExampleSi(examples, 'ignored', null);
      final String fromProvider = buildExampleSi(
        _ExampleProvider(examples),
        'ignored',
        null,
      );

      expect(fromList, contains('EXAMPLE 1'));
      expect(fromProvider, equals(fromList));
    });

    test('getLatestMessageFromUser follows user-last-message rule', () {
      final Session session = Session(
        id: 's1',
        appName: 'app',
        userId: 'u1',
        events: <Event>[
          Event(
            invocationId: 'inv_1',
            author: 'user',
            content: Content.userText('first'),
          ),
          Event(
            invocationId: 'inv_2',
            author: 'user',
            content: Content.userText('latest'),
          ),
        ],
      );

      expect(getLatestMessageFromUser(session), 'latest');

      final Session withFunctionResponse = session.copyWith(
        events: <Event>[
          ...session.events,
          Event(
            invocationId: 'inv_3',
            author: 'user',
            content: Content(
              role: 'user',
              parts: <Part>[
                Part.fromFunctionResponse(
                  name: 'adk_request_input',
                  response: <String, dynamic>{'answer': 'done'},
                ),
              ],
            ),
          ),
        ],
      );

      expect(getLatestMessageFromUser(withFunctionResponse), isEmpty);
    });
  });
}
