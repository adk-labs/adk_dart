/// Data models for the Google Maps Platform integration.
library;

import 'dart:typed_data';

/// Classification of the physical real-estate property.
enum AddressType {
  /// Detached or single-unit property.
  singleFamily('SINGLE_FAMILY'),

  /// Apartment, suite, room, or other multi-unit building.
  multiUnit('MULTI_UNIT');

  /// Creates an [AddressType] with its wire [value].
  const AddressType(this.value);

  /// Serialized wire value (`SINGLE_FAMILY` or `MULTI_UNIT`).
  final String value;

  /// Parses an [AddressType] from its wire [value].
  static AddressType fromValue(String value) {
    for (final AddressType candidate in AddressType.values) {
      if (candidate.value == value) {
        return candidate;
      }
    }
    throw ArgumentError.value(value, 'value', 'Unknown AddressType');
  }
}

/// Result of address normalization and property classification.
class PropertyClassification {
  /// Creates an immutable [PropertyClassification].
  const PropertyClassification({
    required this.standardizedAddress,
    required this.baseAddress,
    required this.addressType,
    this.subunit,
    this.locationType = 'RESIDENTIAL',
    this.isMissingSubunit = false,
  });

  /// Deserializes a [PropertyClassification] from JSON.
  factory PropertyClassification.fromJson(Map<String, Object?> json) {
    return PropertyClassification(
      standardizedAddress: json['standardized_address'] as String,
      baseAddress: json['base_address'] as String,
      addressType: AddressType.fromValue(json['address_type'] as String),
      subunit: json['subunit'] as String?,
      locationType: json['location_type'] as String?,
      isMissingSubunit: json['is_missing_subunit'] as bool? ?? false,
    );
  }

  /// Full normalized address string.
  final String standardizedAddress;

  /// Address without apartment or unit identifier.
  final String baseAddress;

  /// Single-family vs. multi-unit classification.
  final AddressType addressType;

  /// Extracted subunit (for example, `APT 4B`, `SUITE 200`).
  final String? subunit;

  /// Property usage type (`RESIDENTIAL` or `BUSINESS`).
  final String? locationType;

  /// `true` if a subpremise is expected by the postal database but omitted.
  final bool isMissingSubunit;

  /// Serializes this classification into a JSON-compatible map matching
  /// upstream Pydantic `model_dump()`.
  Map<String, Object?> toJson() => <String, Object?>{
    'standardized_address': standardizedAddress,
    'base_address': baseAddress,
    'address_type': addressType.value,
    'subunit': subunit,
    'location_type': locationType,
    'is_missing_subunit': isMissingSubunit,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PropertyClassification &&
            other.standardizedAddress == standardizedAddress &&
            other.baseAddress == baseAddress &&
            other.addressType == addressType &&
            other.subunit == subunit &&
            other.locationType == locationType &&
            other.isMissingSubunit == isMissingSubunit);
  }

  @override
  int get hashCode => Object.hash(
    standardizedAddress,
    baseAddress,
    addressType,
    subunit,
    locationType,
    isMissingSubunit,
  );
}

/// Result of a Street View outdoor baseline query.
class StreetViewResult {
  /// Creates a [StreetViewResult].
  StreetViewResult({
    required this.available,
    List<int>? imageBytes,
    this.mapsUrl,
    required this.coordinates,
    this.panoId,
    this.imageryDate,
    this.cameraCoordinates,
    this.heading,
  }) : imageBytes = imageBytes == null
           ? null
           : (imageBytes is Uint8List
                 ? imageBytes
                 : Uint8List.fromList(imageBytes));

  /// Whether a valid outdoor panoramic photo was found.
  final bool available;

  /// JPEG image bytes of the Street View panorama, when available.
  final Uint8List? imageBytes;

  /// Direct deep-link URL to Google Maps panorama view.
  final String? mapsUrl;

  /// `(latitude, longitude)` coordinates evaluated.
  final (double, double) coordinates;

  /// Panorama ID from Street View pre-flight metadata.
  final String? panoId;

  /// Capture date (`YYYY-MM`) of the Street View panorama.
  final String? imageryDate;

  /// Actual `(latitude, longitude)` of the Street View camera car.
  final (double, double)? cameraCoordinates;

  /// Compass bearing (`0`–`360` degrees) from camera to target.
  final double? heading;
}
