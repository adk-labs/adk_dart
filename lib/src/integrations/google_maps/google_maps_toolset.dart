/// ADK toolset for Google Maps Platform.
library;

import '../../agents/readonly_context.dart';
import '../../models/llm_request.dart';
import '../../tools/base_tool.dart';
import '../../tools/base_toolset.dart';
import '../../tools/function_tool.dart';
import '../../tools/tool_context.dart';
import 'google_maps_config.dart';
import 'google_maps_tools.dart' as maps_tools;

const String _getStreetViewImageDescription =
    'Gets an outdoor Street View image of a location.\n\n'
    'Checks for outdoor coverage first, points the camera at the location, '
    'and saves the image as a session artifact.';

const String _validateAddressDescription =
    'Validates and standardizes a street address.\n\n'
    'Uses the Google Address Validation API. Reports whether the address is '
    'single-family or multi-unit, and whether a unit number such as an '
    'apartment or suite is missing.';

const String _reverseGeocodeDescription =
    'Finds the street address at a latitude and longitude.';

/// Toolset for Street View, Address Validation, and Geocoding.
///
/// The exposed tool names are:
/// - `get_street_view_image`
/// - `validate_address`
/// - `reverse_geocode`
///
/// ```dart
/// final toolset = GoogleMapsToolset(
///   config: GoogleMapsConfig(apiKey: 'AIza...'),
/// );
/// ```
class GoogleMapsToolset extends BaseToolset {
  /// Creates a [GoogleMapsToolset] bound to [config] (or [defaultGoogleMapsConfig]).
  GoogleMapsToolset({
    GoogleMapsConfig? config,
    super.toolFilter,
    super.toolNamePrefix,
  }) : config = config ?? defaultGoogleMapsConfig;

  /// Configuration and API key resolver used by tools in this toolset.
  final GoogleMapsConfig config;

  List<FunctionTool> _buildTools() {
    final GoogleMapsConfig cfg = config;

    Future<String> getStreetViewImageBound({
      required num latitude,
      required num longitude,
      required ToolContext toolContext,
    }) {
      return maps_tools.getStreetViewImage(
        latitude.toDouble(),
        longitude.toDouble(),
        toolContext,
        config: cfg,
      );
    }

    Future<String> validateAddressBound({
      // ignore: non_constant_identifier_names
      String? raw_address,
      String? rawAddress,
      required ToolContext toolContext,
    }) {
      return maps_tools.validateAddress(
        raw_address ?? rawAddress ?? '',
        toolContext,
        config: cfg,
      );
    }

    Future<String> reverseGeocodeBound({
      required num latitude,
      required num longitude,
      required ToolContext toolContext,
    }) {
      return maps_tools.reverseGeocode(
        latitude.toDouble(),
        longitude.toDouble(),
        toolContext,
        config: cfg,
      );
    }

    return <FunctionTool>[
      FunctionTool(
        name: 'get_street_view_image',
        description: _getStreetViewImageDescription,
        func: getStreetViewImageBound,
        toolContextParamNames: const <String>['toolContext', 'tool_context'],
        declaration: FunctionDeclaration(
          name: 'get_street_view_image',
          description: _getStreetViewImageDescription,
          parameters: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'latitude': <String, dynamic>{
                'type': 'number',
                'description': 'Latitude in decimal degrees.',
              },
              'longitude': <String, dynamic>{
                'type': 'number',
                'description': 'Longitude in decimal degrees.',
              },
            },
            'required': <String>['latitude', 'longitude'],
          },
        ),
      ),
      FunctionTool(
        name: 'validate_address',
        description: _validateAddressDescription,
        func: validateAddressBound,
        toolContextParamNames: const <String>['toolContext', 'tool_context'],
        declaration: FunctionDeclaration(
          name: 'validate_address',
          description: _validateAddressDescription,
          parameters: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'raw_address': <String, dynamic>{
                'type': 'string',
                'description': 'The street address to validate.',
              },
            },
            'required': <String>['raw_address'],
          },
        ),
      ),
      FunctionTool(
        name: 'reverse_geocode',
        description: _reverseGeocodeDescription,
        func: reverseGeocodeBound,
        toolContextParamNames: const <String>['toolContext', 'tool_context'],
        declaration: FunctionDeclaration(
          name: 'reverse_geocode',
          description: _reverseGeocodeDescription,
          parameters: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'latitude': <String, dynamic>{
                'type': 'number',
                'description': 'Latitude in decimal degrees.',
              },
              'longitude': <String, dynamic>{
                'type': 'number',
                'description': 'Longitude in decimal degrees.',
              },
            },
            'required': <String>['latitude', 'longitude'],
          },
        ),
      ),
    ];
  }

  @override
  Future<List<BaseTool>> getTools({ReadonlyContext? readonlyContext}) async {
    final List<FunctionTool> allTools = _buildTools();
    return allTools
        .where((FunctionTool tool) => isToolSelected(tool, readonlyContext))
        .toList(growable: false);
  }

  @override
  Future<void> close() async {}
}
