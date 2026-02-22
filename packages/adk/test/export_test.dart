import 'package:adk/adk.dart';
import 'package:test/test.dart';

void main() {
  test('adk exports core types', () {
    final Agent agent = Agent(name: 'root_agent', model: _NoopModel());
    expect(agent.name, 'root_agent');
  });
}

class _NoopModel extends BaseLlm {
  _NoopModel() : super(model: 'noop');

  @override
  Stream<LlmResponse> generateContent(
    LlmRequest request, {
    bool stream = false,
  }) async* {}
}
