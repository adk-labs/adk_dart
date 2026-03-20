import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('environment simulation rename parity', () {
    test('exports renamed config/factory/plugin aliases', () {
      final EnvironmentSimulationConfig config = EnvironmentSimulationConfig(
        toolSimulationConfigs: <ToolSimulationConfig>[
          ToolSimulationConfig(
            toolName: 'search',
            injectionConfigs: <InjectionConfig>[
              InjectionConfig(
                injectedResponse: <String, Object?>{'status': 'ok'},
              ),
            ],
          ),
        ],
      );

      final EnvironmentSimulationPlugin plugin =
          EnvironmentSimulationFactory.createPlugin(config);
      final EnvironmentSimulationCallback callback =
          EnvironmentSimulationFactory.createCallback(config);

      expect(plugin, isA<AgentSimulatorPlugin>());
      expect(callback, isA<Function>());
      expect(config.toolSimulationConfigs.single.toolName, 'search');
    });

    test('exports renamed mapping aliases', () {
      final EnvironmentSimulationToolConnectionMap map =
          EnvironmentSimulationToolConnectionMap(
            statefulParameters: <StatefulParameter>[
              StatefulParameter(
                parameterName: 'ticket_id',
                creatingTools: <String>['create_ticket'],
                consumingTools: <String>['get_ticket'],
              ),
            ],
          );

      expect(map.statefulParameters.single.parameterName, 'ticket_id');
      expect(map.toJson()['stateful_parameters'], isA<List<Object?>>());
    });
  });
}
