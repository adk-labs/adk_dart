/// Implementations of the Google Maps Platform ADK tools.
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../../tools/tool_context.dart';
import '../../types/content.dart';
import 'google_maps_config.dart';
import 'google_maps_models.dart';
import 'google_maps_services.dart';

/// Default session artifact filename used when persisting Street View imagery.
const String streetViewArtifactFilename = 'street_view.jpg';

String _invalidCoordinates(double latitude, double longitude) {
  return 'Invalid coordinates ($latitude, $longitude). '
      'Latitude must be in [-90, 90] and longitude in [-180, 180].';
}

Future<String?> _persistStreetViewImage(
  ToolContext? toolContext,
  Uint8List imageBytes, {
  String artifactFilename = streetViewArtifactFilename,
}) async {
  if (toolContext == null) {
    return null;
  }

  String? savedArtifactName;
  try {
    final Part part = Part.fromInlineData(
      mimeType: 'image/jpeg',
      data: imageBytes,
    );
    await toolContext.saveArtifact(artifactFilename, part);
    savedArtifactName = artifactFilename;
  } catch (exc) {
    developer.log(
      'saveArtifact unavailable; falling back to base64 state: $exc',
      name: 'adk_dart.google_maps',
    );
  }

  if (savedArtifactName != null) {
    toolContext.state['street_view_artifact_name'] = savedArtifactName;
  } else {
    toolContext.state['street_view_image_b64'] = base64Encode(imageBytes);
  }

  return savedArtifactName;
}

/// Fetches an outdoor Street View image and saves it to the ADK session.
Future<String> getStreetViewImage(
  double latitude,
  double longitude,
  ToolContext? toolContext, {
  GoogleMapsConfig? config,
}) async {
  if (!validateCoordinates(latitude, longitude)) {
    return _invalidCoordinates(latitude, longitude);
  }

  final StreetViewResult result;
  try {
    result = await fetchStreetViewBaseline(latitude, longitude, config: config);
  } on MapsApiError catch (exc) {
    return 'Street View lookup failed: $exc.';
  }

  if (!result.available ||
      result.imageBytes == null ||
      result.imageBytes!.isEmpty) {
    if (toolContext != null) {
      toolContext.state['street_view_available'] = false;
    }
    return 'Street View imagery is not available for coordinates '
        '($latitude, $longitude).';
  }

  final String? artifactName = await _persistStreetViewImage(
    toolContext,
    result.imageBytes!,
  );

  if (toolContext != null) {
    toolContext.state['street_view_available'] = true;
    toolContext.state['street_view_url'] = result.mapsUrl;
    toolContext.state['street_view_pano_id'] = result.panoId;
    toolContext.state['street_view_imagery_date'] = result.imageryDate;
    toolContext.state['street_view_heading'] = result.heading;
  }

  final List<String> details = <String>[
    'Captured Street View imagery for ($latitude, $longitude).',
    '- **Deep Link**: ${result.mapsUrl}',
  ];
  if (result.panoId != null && result.panoId!.isNotEmpty) {
    details.add('- **Panorama ID**: `${result.panoId}`');
  }
  if (result.imageryDate != null && result.imageryDate!.isNotEmpty) {
    details.add('- **Capture Date**: ${result.imageryDate}');
  }
  if (result.heading != null) {
    details.add('- **Camera Heading**: ${result.heading}°');
  }
  if (artifactName != null) {
    details.add('- **ADK Artifact**: `$artifactName`');
  }

  return details.join('\n');
}

/// Validates an address and saves the classification to the ADK session.
Future<String> validateAddress(
  String rawAddress,
  ToolContext? toolContext, {
  GoogleMapsConfig? config,
}) async {
  if (rawAddress.trim().isEmpty) {
    return 'Cannot validate an empty address.';
  }

  final PropertyClassification classification;
  try {
    classification = await classifyPropertyAddressAsync(
      rawAddress,
      config: config,
    );
  } on MapsApiError catch (exc) {
    return 'Address validation failed: $exc.';
  }

  if (toolContext != null) {
    toolContext.state['address_classification'] = classification.toJson();
    toolContext.state['is_multi_unit'] =
        classification.addressType == AddressType.multiUnit;
    toolContext.state['is_missing_subunit'] = classification.isMissingSubunit;
    toolContext.state['standardized_address'] =
        classification.standardizedAddress;
  }

  final List<String> report = <String>[
    '### Address Validation',
    '- **Standardized Address**: ${classification.standardizedAddress}',
    '- **Base Address**: ${classification.baseAddress}',
    '- **Property Type**: ${classification.addressType.value}',
    '- **Location Type**: ${classification.locationType}',
  ];
  if (classification.subunit != null && classification.subunit!.isNotEmpty) {
    report.add('- **Sub-unit**: ${classification.subunit}');
  }
  if (classification.isMissingSubunit) {
    report.add(
      '- **Warning**: Address appears to be a multi-unit property '
      'with a missing unit/apartment number.',
    );
  }

  return report.join('\n');
}

/// Resolves coordinates into a street address and saves it to the ADK session.
Future<String> reverseGeocode(
  double latitude,
  double longitude,
  ToolContext? toolContext, {
  GoogleMapsConfig? config,
}) async {
  if (!validateCoordinates(latitude, longitude)) {
    return _invalidCoordinates(latitude, longitude);
  }

  final String? formattedAddress;
  try {
    formattedAddress = await reverseGeocodeCoordinatesAsync(
      latitude,
      longitude,
      config: config,
    );
  } on MapsApiError catch (exc) {
    return 'Reverse geocoding failed: $exc.';
  }

  if (formattedAddress == null || formattedAddress.isEmpty) {
    return 'Could not resolve a street address for coordinates '
        '($latitude, $longitude).';
  }

  if (toolContext != null) {
    toolContext.state['reverse_geocoded_address'] = formattedAddress;
    toolContext.state['reverse_geocoded_coordinates'] = <double>[
      latitude,
      longitude,
    ];
  }

  return '### Reverse Geocoded Address\n'
      '- **Coordinates**: ($latitude, $longitude)\n'
      '- **Street Address**: $formattedAddress';
}
