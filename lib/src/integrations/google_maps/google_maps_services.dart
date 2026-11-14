/// Core Google Maps Platform service functions for ADK multimodal agents.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'google_maps_config.dart';
import 'google_maps_models.dart';

/// Google Street View Static API metadata endpoint.
const String streetViewMetadataUrl =
    'https://maps.googleapis.com/maps/api/streetview/metadata';

/// Google Street View Static API imagery endpoint.
const String streetViewImageUrl =
    'https://maps.googleapis.com/maps/api/streetview';

/// Google Address Validation API v1 endpoint.
const String addressValidationUrl =
    'https://addressvalidation.googleapis.com/v1:validateAddress';

/// Google Geocoding API endpoint.
const String geocodeUrl = 'https://maps.googleapis.com/maps/api/geocode/json';

final RegExp _queryKeyRedactRe = RegExp(
  r'([?&]key=)[^&\s"'
  "'"
  r']+',
  caseSensitive: false,
);

/// Statuses that mean "no match", as opposed to a failed request.
const Set<String> _noResultStatuses = <String>{'ZERO_RESULTS', 'NOT_FOUND'};

/// Exception thrown when a Google Maps Platform request fails or cannot be sent.
class MapsApiError implements Exception {
  /// Creates a [MapsApiError] with a human-readable [message].
  const MapsApiError(this.message);

  /// Sanitized error description.
  final String message;

  @override
  String toString() => message;
}

/// HTTP GET transport callback signature for Google Maps requests.
typedef GoogleMapsHttpGet =
    Future<(int statusCode, Uint8List body)> Function(
      String url, {
      required Map<String, Object?> params,
      required double timeout,
      Map<String, String>? headers,
      GoogleMapsConfig? config,
    });

/// HTTP POST JSON transport callback signature for Google Maps requests.
typedef GoogleMapsHttpPostJson =
    Future<(int statusCode, Uint8List body)> Function(
      String url, {
      required Map<String, Object?> params,
      required Map<String, Object?> payload,
      required double timeout,
      Map<String, String>? headers,
      GoogleMapsConfig? config,
    });

GoogleMapsHttpGet? _customHttpGet;
GoogleMapsHttpPostJson? _customHttpPostJson;

/// Overrides outbound HTTP transport callbacks for Google Maps services in tests.
void setGoogleMapsHttpTransport({
  GoogleMapsHttpGet? httpGet,
  GoogleMapsHttpPostJson? httpPostJson,
}) {
  _customHttpGet = httpGet;
  _customHttpPostJson = httpPostJson;
}

/// Restores default outbound HTTP transport callbacks for Google Maps services.
void resetGoogleMapsHttpTransport() {
  _customHttpGet = null;
  _customHttpPostJson = null;
}

/// In-memory bounded least-recently-used (LRU) cache backed by [LinkedHashMap].
class BoundedLruCache<K, V> {
  /// Creates a [BoundedLruCache] with maximum entry capacity [maxSize].
  BoundedLruCache({int maxSize = 1024}) : _maxSize = maxSize {
    if (maxSize <= 0) {
      throw ArgumentError.value(maxSize, 'maxSize', 'Must be positive');
    }
  }

  final int _maxSize;
  final LinkedHashMap<K, V> _store = LinkedHashMap<K, V>();

  /// Number of entries currently stored.
  int get length => _store.length;

  /// Looks up [key] and marks it as most-recently-used when found.
  (bool, V?) get(K key) {
    if (!_store.containsKey(key)) {
      return (false, null);
    }
    final V value = _store.remove(key) as V;
    _store[key] = value;
    return (true, value);
  }

  /// Inserts or updates [key] with [value], evicting the least-recently-used
  /// entry if capacity is exceeded.
  void put(K key, V value) {
    if (_store.containsKey(key)) {
      _store.remove(key);
    }
    _store[key] = value;
    if (_store.length > _maxSize) {
      _store.remove(_store.keys.first);
    }
  }

  /// Removes all cached entries.
  void clear() {
    _store.clear();
  }
}

/// Redacts `key=` query values and explicit [apiKey] occurrences from [text].
String redactMapsSecret(String text, [String? apiKey]) {
  String sanitized = text.replaceAllMapped(
    _queryKeyRedactRe,
    (Match match) => '${match.group(1)}[REDACTED]',
  );
  if (apiKey != null && apiKey.isNotEmpty) {
    sanitized = sanitized.replaceAll(apiKey, '[REDACTED]');
  }
  return sanitized;
}

/// Validates that [url] uses HTTPS and has a non-empty host.
///
/// Throws an [ArgumentError] for non-HTTPS or hostless URLs.
Uri ensureHttpsMapsUrl(String url) {
  final Uri? parsed = Uri.tryParse(url);
  if (parsed == null ||
      parsed.scheme != 'https' ||
      !parsed.hasAuthority ||
      parsed.host.isEmpty) {
    throw ArgumentError.value(
      url,
      'url',
      'Only HTTPS Google Maps endpoints are allowed: $url',
    );
  }
  return parsed;
}

/// Returns `true` if [latitude] and [longitude] are finite and within WGS84 bounds.
bool validateCoordinates(double latitude, double longitude) {
  if (!latitude.isFinite || !longitude.isFinite) {
    return false;
  }
  return latitude >= -90.0 &&
      latitude <= 90.0 &&
      longitude >= -180.0 &&
      longitude <= 180.0;
}

/// Calculates forward compass bearing (`0`–`360` degrees) from start to end GPS.
///
/// Used to orient the Street View camera from its road capture position
/// directly toward the target property coordinates. Returns `null` if both
/// points are identical or invalid.
double? calculateCompassBearing(
  double startLat,
  double startLng,
  double endLat,
  double endLng,
) {
  if (!validateCoordinates(startLat, startLng) ||
      !validateCoordinates(endLat, endLng)) {
    return null;
  }
  if ((startLat - endLat).abs() < 1e-6 && (startLng - endLng).abs() < 1e-6) {
    return null;
  }

  final double lat1 = startLat * math.pi / 180.0;
  final double lat2 = endLat * math.pi / 180.0;
  final double diffLng = (endLng - startLng) * math.pi / 180.0;

  final double x = math.sin(diffLng) * math.cos(lat2);
  final double y =
      math.cos(lat1) * math.sin(lat2) -
      (math.sin(lat1) * math.cos(lat2) * math.cos(diffLng));
  final double initialBearing = math.atan2(x, y) * 180.0 / math.pi;
  final double normalized = (initialBearing + 360.0) % 360.0;
  final double rounded = (normalized * 10.0).roundToDouble() / 10.0;
  return rounded == 0.0 ? 0.0 : rounded;
}

Uri _buildUriWithParams(String url, Map<String, Object?> params) {
  final Uri baseUri = ensureHttpsMapsUrl(url);
  if (params.isEmpty) {
    return baseUri;
  }
  final Map<String, String> merged = <String, String>{
    ...baseUri.queryParameters,
    for (final MapEntry<String, Object?> entry in params.entries)
      if (entry.value != null) entry.key: '${entry.value}',
  };
  return baseUri.replace(queryParameters: merged);
}

void _emitRedactedHttpLog(
  String method,
  Uri uri,
  int statusCode,
  GoogleMapsConfig? config,
) {
  final String redactedLine = redactMapsSecret(
    'HTTP Request: $method $uri "HTTP/1.1 $statusCode"',
  );
  developer.log(redactedLine, name: 'adk_dart.google_maps.http');
  config?.onHttpLog?.call(redactedLine);
}

Future<(int, Uint8List)> _asyncHttpGet(
  String url, {
  required Map<String, Object?> params,
  required double timeout,
  Map<String, String>? headers,
  GoogleMapsConfig? config,
}) async {
  ensureHttpsMapsUrl(url);
  final GoogleMapsHttpGet? override = _customHttpGet;
  if (override != null) {
    return override(
      url,
      params: params,
      timeout: timeout,
      headers: headers,
      config: config,
    );
  }

  final Uri uri = _buildUriWithParams(url, params);
  final http.Client? injectedClient = config?.httpClient;
  final http.Client client = injectedClient ?? http.Client();
  try {
    final http.Response response = await client
        .get(uri, headers: headers)
        .timeout(Duration(milliseconds: (timeout * 1000).round()));
    _emitRedactedHttpLog('GET', uri, response.statusCode, config);
    return (response.statusCode, response.bodyBytes);
  } finally {
    if (injectedClient == null) {
      client.close();
    }
  }
}

Future<(int, Uint8List)> _asyncHttpPostJson(
  String url, {
  required Map<String, Object?> params,
  required Map<String, Object?> payload,
  required double timeout,
  Map<String, String>? headers,
  GoogleMapsConfig? config,
}) async {
  ensureHttpsMapsUrl(url);
  final GoogleMapsHttpPostJson? override = _customHttpPostJson;
  if (override != null) {
    return override(
      url,
      params: params,
      payload: payload,
      timeout: timeout,
      headers: headers,
      config: config,
    );
  }

  final Uri uri = _buildUriWithParams(url, params);
  final http.Client? injectedClient = config?.httpClient;
  final http.Client client = injectedClient ?? http.Client();
  final Map<String, String> mergedHeaders = <String, String>{
    HttpHeaders.contentTypeHeader: 'application/json',
    ...?headers,
  };
  try {
    final http.Response response = await client
        .post(
          uri,
          headers: mergedHeaders,
          body: utf8.encode(jsonEncode(payload)),
        )
        .timeout(Duration(milliseconds: (timeout * 1000).round()));
    _emitRedactedHttpLog('POST', uri, response.statusCode, config);
    return (response.statusCode, response.bodyBytes);
  } finally {
    if (injectedClient == null) {
      client.close();
    }
  }
}

Future<String> _requireApiKey(GoogleMapsConfig cfg) async {
  final String? apiKey = await cfg.getApiKeyAsync();
  if (apiKey == null || apiKey.isEmpty) {
    throw const MapsApiError('MAPS_API_KEY unconfigured');
  }
  return apiKey;
}

String _errorDetail(Uint8List body) {
  final Object? data;
  try {
    data = jsonDecode(utf8.decode(body));
  } on FormatException {
    return '';
  }
  if (data is! Map) {
    return '';
  }
  final Object? err = data['error'];
  if (err is Map) {
    final Object? message = err['message'] ?? err['status'];
    return message == null ? '' : '$message';
  }
  final Object? errorMessage = data['error_message'];
  return errorMessage == null ? '' : '$errorMessage';
}

Future<Uint8List> _send(
  String api,
  String apiKey,
  Future<(int, Uint8List)> Function() sendRequest,
) async {
  final int status;
  final Uint8List body;
  try {
    (status, body) = await sendRequest();
  } on http.ClientException catch (exc) {
    throw MapsApiError(
      '$api request failed: ${redactMapsSecret(exc.toString(), apiKey)}',
    );
  } on SocketException catch (exc) {
    throw MapsApiError(
      '$api request failed: ${redactMapsSecret(exc.toString(), apiKey)}',
    );
  } on HttpException catch (exc) {
    throw MapsApiError(
      '$api request failed: ${redactMapsSecret(exc.toString(), apiKey)}',
    );
  } on HandshakeException catch (exc) {
    throw MapsApiError(
      '$api request failed: ${redactMapsSecret(exc.toString(), apiKey)}',
    );
  } on TimeoutException catch (exc) {
    throw MapsApiError(
      '$api request failed: ${redactMapsSecret(exc.toString(), apiKey)}',
    );
  }

  if (status != 200) {
    final String detail = redactMapsSecret(_errorDetail(body), apiKey);
    throw MapsApiError(
      '$api returned HTTP $status${detail.isNotEmpty ? ': $detail' : ''}',
    );
  }
  return body;
}

Map<String, Object?> _parseJson(String api, Uint8List body) {
  final Object? data;
  try {
    data = jsonDecode(utf8.decode(body));
  } on FormatException {
    throw MapsApiError('$api returned invalid JSON');
  }
  if (data is! Map) {
    throw MapsApiError('$api returned invalid JSON');
  }
  return data.map((Object? k, Object? v) => MapEntry('$k', v));
}

MapsApiError _statusError(
  String api,
  Map<String, Object?> data,
  String apiKey,
) {
  String message = '$api returned ${data['status']}';
  final Object? detail = data['error_message'];
  if (detail != null && '$detail'.isNotEmpty) {
    message += ': ${redactMapsSecret('$detail', apiKey)}';
  }
  return MapsApiError(message);
}

/// Fetches outdoor Street View imagery using the 2-step Metadata pattern.
///
/// Returns `available: false` when coordinates are invalid or have no outdoor
/// coverage.
///
/// Throws a [MapsApiError] if the API key is missing or an HTTP/API call fails.
Future<StreetViewResult> fetchStreetViewBaseline(
  double latitude,
  double longitude, {
  GoogleMapsConfig? config,
  double? timeout,
  int? pitch,
  int? fov,
  String? size,
  double? heading,
}) async {
  if (!validateCoordinates(latitude, longitude)) {
    developer.log(
      'Invalid GPS coordinates ($latitude, $longitude); skipping Street View query.',
      name: 'adk_dart.google_maps',
      level: 900,
    );
    return StreetViewResult(
      available: false,
      coordinates: (latitude, longitude),
    );
  }

  final GoogleMapsConfig cfg = config ?? defaultGoogleMapsConfig;
  final String apiKey = await _requireApiKey(cfg);

  final double reqTimeout = timeout ?? cfg.timeout;
  final int reqPitch = pitch ?? cfg.defaultPitch;
  final int reqFov = fov ?? cfg.defaultFov;
  final String reqSize = size ?? cfg.defaultSize;

  final Map<String, Object?> metaParams = <String, Object?>{
    'location': '$latitude,$longitude',
    'source': 'outdoor',
    'key': apiKey,
  };
  final Uint8List metaBody = await _send(
    'Street View metadata',
    apiKey,
    () => _asyncHttpGet(
      streetViewMetadataUrl,
      params: metaParams,
      timeout: reqTimeout,
      config: cfg,
    ),
  );
  final Map<String, Object?> metaJson = _parseJson(
    'Street View metadata',
    metaBody,
  );
  final Object? metaStatus = metaJson['status'];
  if (metaStatus is String && _noResultStatuses.contains(metaStatus)) {
    developer.log(
      'No Street View imagery at ($latitude, $longitude): $metaStatus',
      name: 'adk_dart.google_maps',
    );
    return StreetViewResult(
      available: false,
      coordinates: (latitude, longitude),
    );
  }
  if (metaStatus != 'OK') {
    throw _statusError('Street View metadata', metaJson, apiKey);
  }

  final String? panoId = metaJson['pano_id'] as String?;
  final String? imageryDate = metaJson['date'] as String?;
  (double, double)? cameraCoords;
  double? computedHeading = heading;
  final Object? loc = metaJson['location'];
  if (loc is Map && loc.containsKey('lat') && loc.containsKey('lng')) {
    final Object? rawLat = loc['lat'];
    final Object? rawLng = loc['lng'];
    if (rawLat is num && rawLng is num) {
      final double camLat = rawLat.toDouble();
      final double camLng = rawLng.toDouble();
      cameraCoords = (camLat, camLng);
      computedHeading ??= calculateCompassBearing(
        camLat,
        camLng,
        latitude,
        longitude,
      );
    }
  }

  final Map<String, Object?> svParams = <String, Object?>{
    'size': reqSize,
    'pitch': reqPitch,
    'fov': reqFov,
    'source': 'outdoor',
    'key': apiKey,
  };
  if (panoId != null && panoId.isNotEmpty && computedHeading != null) {
    svParams['pano'] = panoId;
    svParams['heading'] = computedHeading;
  } else {
    svParams['location'] = '$latitude,$longitude';
    if (panoId != null && panoId.isNotEmpty) {
      svParams['pano'] = panoId;
    }
    if (computedHeading != null) {
      svParams['heading'] = computedHeading;
    }
  }

  final Uint8List imgBytes = await _send(
    'Street View image',
    apiKey,
    () => _asyncHttpGet(
      streetViewImageUrl,
      params: svParams,
      timeout: reqTimeout,
      config: cfg,
    ),
  );
  if (imgBytes.isEmpty) {
    throw const MapsApiError('Street View image returned no data');
  }

  String mapsUrl =
      'https://www.google.com/maps/@?api=1&map_action=pano'
      '&viewpoint=$latitude,$longitude';
  if (panoId != null && panoId.isNotEmpty) {
    mapsUrl += '&pano=$panoId';
  }
  if (computedHeading != null) {
    mapsUrl += '&heading=$computedHeading&pitch=$reqPitch&fov=$reqFov';
  }

  return StreetViewResult(
    available: true,
    imageBytes: imgBytes,
    mapsUrl: mapsUrl,
    coordinates: (latitude, longitude),
    panoId: panoId,
    imageryDate: imageryDate,
    cameraCoordinates: cameraCoords,
    heading: computedHeading,
  );
}

PropertyClassification _parseAddressValidationResponse(
  Map<String, Object?> data,
) {
  final Object? rawResult = data['result'];
  final Map<Object?, Object?> result = rawResult == null
      ? const <Object?, Object?>{}
      : rawResult as Map<Object?, Object?>;
  final Object? rawAddress = result['address'];
  final Map<Object?, Object?> addressData = rawAddress == null
      ? const <Object?, Object?>{}
      : rawAddress as Map<Object?, Object?>;
  final Object? rawComponents = addressData['addressComponents'];
  final List<Object?> components = rawComponents == null
      ? const <Object?>[]
      : rawComponents as List<Object?>;
  final Object? rawMissing = addressData['missingComponentTypes'];
  final List<Object?> missing = rawMissing == null
      ? const <Object?>[]
      : rawMissing as List<Object?>;
  final Object? rawMetadata = result['metadata'];
  final Map<Object?, Object?> metadata = rawMetadata == null
      ? const <Object?, Object?>{}
      : rawMetadata as Map<Object?, Object?>;

  final bool isBusiness = metadata['business'] == true;
  final String locationType = isBusiness ? 'BUSINESS' : 'RESIDENTIAL';

  String? subunit;
  String streetNumber = '';
  String route = '';
  String locality = '';
  String adminArea = '';
  String postalCode = '';

  const List<String> subunitPrefixes = <String>[
    'APT',
    'UNIT',
    'STE',
    'SUITE',
    'RM',
    'ROOM',
    '#',
  ];

  for (final Object? rawComp in components) {
    final Map<Object?, Object?> comp = rawComp as Map<Object?, Object?>;
    final Object? ctype = comp['componentType'];
    final Object? rawCompName = comp['componentName'];
    final Map<Object?, Object?> compName = rawCompName == null
        ? const <Object?, Object?>{}
        : rawCompName as Map<Object?, Object?>;
    final String cname = (compName['text'] as String? ?? '')
        .trim()
        .toUpperCase();
    if (cname.isEmpty) {
      continue;
    }
    if (ctype == 'subpremise' || ctype == 'room') {
      if (subunitPrefixes.any(cname.startsWith)) {
        subunit = cname;
      } else {
        subunit = 'APT $cname';
      }
    } else if (ctype == 'street_number') {
      streetNumber = cname;
    } else if (ctype == 'route') {
      route = cname;
    } else if (ctype == 'locality') {
      locality = cname;
    } else if (ctype == 'administrative_area_level_1') {
      adminArea = cname;
    } else if (ctype == 'postal_code') {
      postalCode = cname;
    }
  }

  String streetLine = '$streetNumber $route'.trim().toUpperCase();
  if (streetLine.isEmpty) {
    final String formatted = addressData['formattedAddress'] as String? ?? '';
    streetLine = formatted.isNotEmpty
        ? formatted.split(',').first.trim().toUpperCase()
        : 'UNKNOWN';
  }

  final String stateZip = '$adminArea $postalCode'.trim();
  final String cityStateZip = <String>[
    locality,
    stateZip,
  ].where((String p) => p.isNotEmpty).join(', ');
  final String base = cityStateZip.isNotEmpty
      ? '$streetLine, $cityStateZip'
      : streetLine;

  final bool isMissingSub =
      missing.contains('subpremise') || missing.contains('room');
  if (subunit != null || isMissingSub) {
    final String stdAddr;
    if (subunit != null) {
      final List<String> stdParts = <String>[
        streetLine,
        subunit,
        if (cityStateZip.isNotEmpty) cityStateZip,
      ];
      stdAddr = stdParts.join(', ');
    } else {
      stdAddr = base;
    }
    return PropertyClassification(
      standardizedAddress: stdAddr,
      baseAddress: base,
      addressType: AddressType.multiUnit,
      subunit: subunit,
      locationType: locationType,
      isMissingSubunit: isMissingSub,
    );
  }

  return PropertyClassification(
    standardizedAddress: base,
    baseAddress: base,
    addressType: AddressType.singleFamily,
    subunit: null,
    locationType: locationType,
    isMissingSubunit: false,
  );
}

final BoundedLruCache<(String, String), PropertyClassification> _addressCache =
    BoundedLruCache<(String, String), PropertyClassification>(maxSize: 1024);

final BoundedLruCache<(double, double, String), String> _geocodeCache =
    BoundedLruCache<(double, double, String), String>(maxSize: 1024);

/// Standardizes [rawAddress] and classifies the physical property type.
///
/// Throws a [MapsApiError] if the API key is missing or the request fails.
Future<PropertyClassification> classifyPropertyAddressAsync(
  String rawAddress, {
  GoogleMapsConfig? config,
}) async {
  final GoogleMapsConfig cfg = config ?? defaultGoogleMapsConfig;
  final String apiKey = await _requireApiKey(cfg);
  final String normalizedInput = rawAddress
      .trim()
      .toUpperCase()
      .split(RegExp(r'\s+'))
      .where((String s) => s.isNotEmpty)
      .join(' ');
  final (String, String) cacheKey = (normalizedInput, cfg.getKeyFingerprint());
  final (bool hit, PropertyClassification? cached) = _addressCache.get(
    cacheKey,
  );
  if (hit && cached != null) {
    return cached;
  }

  final Uint8List body = await _send(
    'Address Validation',
    apiKey,
    () => _asyncHttpPostJson(
      addressValidationUrl,
      params: const <String, Object?>{},
      payload: <String, Object?>{
        'address': <String, Object?>{
          'addressLines': <String>[rawAddress],
        },
      },
      timeout: cfg.timeout,
      headers: <String, String>{'X-Goog-Api-Key': apiKey},
      config: cfg,
    ),
  );
  final PropertyClassification classification = _parseAddressValidationResponse(
    _parseJson('Address Validation', body),
  );
  _addressCache.put(cacheKey, classification);
  return classification;
}

double _roundTo5Decimals(double value) {
  final double rounded = (value * 100000.0).roundToDouble() / 100000.0;
  return rounded == 0.0 ? 0.0 : rounded;
}

/// Resolves WGS84 coordinates into a formatted street address.
///
/// Returns `null` when coordinates are invalid or match no street address.
///
/// Throws a [MapsApiError] if the API key is missing or the request fails.
Future<String?> reverseGeocodeCoordinatesAsync(
  double latitude,
  double longitude, {
  GoogleMapsConfig? config,
}) async {
  if (!validateCoordinates(latitude, longitude)) {
    return null;
  }

  final GoogleMapsConfig cfg = config ?? defaultGoogleMapsConfig;
  final String apiKey = await _requireApiKey(cfg);

  final double roundedLat = _roundTo5Decimals(latitude);
  final double roundedLng = _roundTo5Decimals(longitude);
  final (double, double, String) cacheKey = (
    roundedLat,
    roundedLng,
    cfg.getKeyFingerprint(),
  );
  final (bool hit, String? cached) = _geocodeCache.get(cacheKey);
  if (hit && cached != null) {
    return cached;
  }

  final Uint8List body = await _send(
    'Geocoding',
    apiKey,
    () => _asyncHttpGet(
      geocodeUrl,
      params: <String, Object?>{
        'latlng': '$roundedLat,$roundedLng',
        'key': apiKey,
      },
      timeout: cfg.timeout,
      config: cfg,
    ),
  );
  final Map<String, Object?> data = _parseJson('Geocoding', body);
  final Object? status = data['status'];
  if (status is String && _noResultStatuses.contains(status)) {
    return null;
  }
  if (status != 'OK') {
    throw _statusError('Geocoding', data, apiKey);
  }
  final Object? results = data['results'];
  final Object? first = (results is List && results.isNotEmpty)
      ? results.first
      : null;
  final Object? formatted = first is Map ? first['formatted_address'] : null;
  if (formatted is! String || formatted.isEmpty) {
    return null;
  }
  _geocodeCache.put(cacheKey, formatted);
  return formatted;
}

/// Clears internal address validation and reverse geocoding caches.
void clearGoogleMapsCaches() {
  _addressCache.clear();
  _geocodeCache.clear();
}
