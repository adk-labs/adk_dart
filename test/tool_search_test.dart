import 'package:adk_dart/adk_dart.dart';
import 'package:test/test.dart';

void main() {
  group('ToolSearchToolset', () {
    final tool1 = FunctionTool(
      name: 'weather_lookup',
      description: 'Get the current weather forecast for a given city',
      func: ({required String city}) => 'Sunny in $city',
    );
    final tool2 = FunctionTool(
      name: 'stock_price',
      description: 'Fetch real-time stock ticker quotes and prices',
      func: ({required String ticker}) => 'Price for $ticker: 100',
    );
    final tool3 = FunctionTool(
      name: 'send_email',
      description: 'Send an email message to a recipient address',
      func: ({required String to, required String body}) => 'Sent to $to',
    );

    test('searches and ranks tools using BM25', () async {
      final toolset = ToolSearchToolset(
        tools: [tool1, tool2, tool3],
      );
      final catalog = await toolset.resolveCatalogTools();

      final matches = toolset.searchCatalog(
        query: 'current weather city',
        catalog: catalog,
        maxResults: 2,
      );
      expect(matches, isNotEmpty);
      expect(matches.first.name, equals('weather_lookup'));
    });

    test('supports exact tool name selection using select: syntax', () async {
      final toolset = ToolSearchToolset(
        tools: [tool1, tool2, tool3],
      );
      final catalog = await toolset.resolveCatalogTools();

      final matches = toolset.searchCatalog(
        query: 'select:stock_price,send_email',
        catalog: catalog,
      );
      expect(matches.map((t) => t.name), containsAll(['stock_price', 'send_email']));
      expect(matches.map((t) => t.name), isNot(contains('weather_lookup')));
    });

    test('exposes search_tools and alwaysLoadedTools in getTools', () async {
      final toolset = ToolSearchToolset(
        tools: [tool1, tool2, tool3],
        config: const ToolSearchConfig(
          alwaysLoadedTools: {'weather_lookup'},
        ),
      );

      final tools = await toolset.getTools();
      final toolNames = tools.map((t) => t.name).toSet();

      expect(toolNames, contains('search_tools'));
      expect(toolNames, contains('weather_lookup'));
      expect(toolNames, isNot(contains('stock_price')));
    });
  });
}
