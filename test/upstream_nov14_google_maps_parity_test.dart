import 'dart:convert';
import 'dart:typed_data';

import 'package:adk_dart/integrations.dart';
import 'package:adk_dart/src/agents/context.dart';
import 'package:adk_dart/src/agents/invocation_context.dart';
import 'package:adk_dart/src/agents/llm_agent.dart';
import 'package:adk_dart/src/artifacts/in_memory_artifact_service.dart';
import 'package:adk_dart/src/models/llm_request.dart';
import 'package:adk_dart/src/plugins/plugin_manager.dart';
import 'package:adk_dart/src/sessions/in_memory_session_service.dart';
import 'package:adk_dart/src/sessions/session.dart';
import 'package:adk_dart/src/tools/base_tool.dart';
import 'package:adk_dart/src/types/content.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const String _key = 'AIzaSySecretKey12345';

Future<({Context context, InMemoryArtifactService? artifactService})>
_createToolContext({bool withArtifactService = true}) async {
  final InMemorySessionService sessionService = InMemorySessionService();
  final Session session = await sessionService.createSession(
    appName: 'maps_test_app',
    userId: 'user_1',
  );
  final InMemoryArtifactService? artifactService = withArtifactService
      ? InMemoryArtifactService()
      : null;
  final InvocationContext invocationContext = InvocationContext(
    invocationId: 'inv_maps_1',
    agent: LlmAgent(name: 'maps_agent', model: 'gemini-2.5-flash'),
    session: session,
    sessionService: sessionService,
    artifactService: artifactService,
    pluginManager: PluginManager(),
  );
  return (
    context: Context(invocationContext),
    artifactService: artifactService,
  );
}

GoogleMapsHttpGet _jsonGet(Map<String, Object?> response, {int status = 200}) {
  return (
    String url, {
    required Map<String, Object?> params,
    required double timeout,
    Map<String, String>? headers,
    GoogleMapsConfig? config,
  }) async {
    return (status, Uint8List.fromList(utf8.encode(jsonEncode(response))));
  };
}

GoogleMapsHttpPostJson _jsonPost(
  Map<String, Object?> response, {
  int status = 200,
}) {
  return (
    String url, {
    required Map<String, Object?> params,
    required Map<String, Object?> payload,
    required double timeout,
    Map<String, String>? headers,
    GoogleMapsConfig? config,
  }) async {
    return (status, Uint8List.fromList(utf8.encode(jsonEncode(response))));
  };
}

void main() {
  tearDown(() {
    clearGoogleMapsCaches();
    resetGoogleMapsHttpTransport();
    resetGoogleMapsSecretFetcher();
  });

  group('CompassBearingAndCoordinates', () {
    test('cardinal directions', () {
      expect(
        calculateCompassBearing(37.0, -122.0, 37.001, -122.0),
        closeTo(0.0, 0.05),
      );
      expect(
        calculateCompassBearing(37.0, -122.0, 37.0, -121.999),
        closeTo(90.0, 0.5),
      );
      expect(
        calculateCompassBearing(37.0, -122.0, 36.999, -122.0),
        closeTo(180.0, 0.05),
      );
      expect(
        calculateCompassBearing(37.0, -122.0, 37.0, -122.001),
        closeTo(270.0, 0.5),
      );
    });

    test('identical or invalid coordinates return null / false', () {
      expect(
        calculateCompassBearing(37.4220, -122.0841, 37.4220, -122.0841),
        isNull,
      );
      expect(validateCoordinates(95.0, -122.0), isFalse);
      expect(validateCoordinates(37.0, -190.0), isFalse);
      expect(validateCoordinates(double.nan, -122.0), isFalse);
      expect(validateCoordinates(37.0, double.infinity), isFalse);
      expect(
        calculateCompassBearing(95.0, -122.0, 37.4220, -122.0841),
        isNull,
      );
    });

    test('bounded LRU cache evicts least recently used', () {
      final BoundedLruCache<String, int> cache = BoundedLruCache<String, int>(
        maxSize: 2,
      );
      cache.put('a', 1);
      cache.put('b', 2);
      expect(cache.get('a'), (true, 1));
      cache.put('c', 3);
      expect(cache.get('b'), (false, null));
      expect(cache.get('a'), (true, 1));
      expect(cache.get('c'), (true, 3));
    });

    test('ensureHttpsMapsUrl rejects non-https and hostless URLs', () {
      expect(
        () => ensureHttpsMapsUrl('http://maps.googleapis.com/maps/api/geocode/json'),
        throwsArgumentError,
      );
      expect(
        () => ensureHttpsMapsUrl('file:///etc/passwd'),
        throwsArgumentError,
      );
      expect(ensureHttpsMapsUrl(geocodeUrl).scheme, 'https');
    });
  });

  group('GoogleMapsConfig', () {
    test('explicit apiKey priority and non-reversible fingerprint', () {
      final GoogleMapsConfig cfg = GoogleMapsConfig(
        apiKey: 'explicit-key',
        environment: const <String, String>{'MAPS_API_KEY': 'env-key'},
      );
      expect(cfg.getApiKey(), 'explicit-key');
      expect(cfg.getKeyFingerprint(), isNot('explicit-key'));
      expect(cfg.getKeyFingerprint().length, 16);
    });

    test('environment variable fallback', () {
      final GoogleMapsConfig cfg = GoogleMapsConfig(
        environment: const <String, String>{'MAPS_API_KEY': 'env-key-123'},
      );
      expect(cfg.getApiKey(), 'env-key-123');
    });

    test('unconfigured or placeholder returns null', () {
      final GoogleMapsConfig cfg = GoogleMapsConfig(
        environment: const <String, String>{
          'MAPS_API_KEY': '<TODO: update-this-value>',
          'MAPS_API_KEY_SECRET_RESOURCE': '<YOUR_SECRET_RESOURCE>',
        },
      );
      expect(cfg.getApiKey(), isNull);
      expect(cfg.getKeyFingerprint(), 'unconfigured');
    });

    test('missing secret manager support throws helpful error', () async {
      final GoogleMapsConfig cfg = GoogleMapsConfig(
        secretResourceName: 'projects/p/secrets/s/versions/latest',
        environment: const <String, String>{},
        secretManagerAvailable: false,
      );
      expect(
        cfg.getApiKey,
        throwsA(
          isA<UnsupportedError>().having(
            (UnsupportedError e) => e.message,
            'message',
            contains('google-adk[gcp]'),
          ),
        ),
      );
      await expectLater(
        cfg.getApiKeyAsync(),
        throwsA(
          isA<UnsupportedError>().having(
            (UnsupportedError e) => e.message,
            'message',
            contains('google-adk[gcp]'),
          ),
        ),
      );
    });

    test('resolves and caches API key from Secret Manager fetcher', () async {
      int fetchCount = 0;
      String? capturedSa;
      String? capturedEngineId;
      final GoogleMapsConfig cfg = GoogleMapsConfig(
        secretResourceName: 'projects/p/secrets/maps-key/versions/latest',
        serviceAccountEmail: 'maps-sa@example.iam.gserviceaccount.com',
        environment: const <String, String>{
          'GOOGLE_CLOUD_AGENT_ENGINE_ID': 'engine-99',
        },
        secretFetcher: ({
          required String resourceName,
          String? serviceAccountEmail,
          String? agentEngineId,
        }) async {
          fetchCount += 1;
          capturedSa = serviceAccountEmail;
          capturedEngineId = agentEngineId;
          expect(resourceName, 'projects/p/secrets/maps-key/versions/latest');
          return '  sm-secret-key-xyz  ';
        },
      );

      expect(await cfg.getApiKeyAsync(), 'sm-secret-key-xyz');
      expect(await cfg.getApiKeyAsync(), 'sm-secret-key-xyz');
      expect(cfg.getApiKey(), 'sm-secret-key-xyz');
      expect(fetchCount, 1);
      expect(capturedSa, 'maps-sa@example.iam.gserviceaccount.com');
      expect(capturedEngineId, 'engine-99');
    });

    test('Secret Manager lookup failure logs warning and returns null', () async {
      final GoogleMapsConfig cfg = GoogleMapsConfig(
        secretResourceName: 'projects/p/secrets/maps-key/versions/latest',
        environment: const <String, String>{},
        secretFetcher: ({
          required String resourceName,
          String? serviceAccountEmail,
          String? agentEngineId,
        }) async {
          throw StateError('permission denied');
        },
      );
      expect(await cfg.getApiKeyAsync(), isNull);
    });
  });

  group('ServicesAndTools', () {
    late GoogleMapsConfig config;
    late GoogleMapsConfig unconfigured;

    setUp(() {
      clearGoogleMapsCaches();
      config = GoogleMapsConfig(
        apiKey: _key,
        environment: const <String, String>{},
      );
      unconfigured = GoogleMapsConfig(
        apiKey: null,
        environment: const <String, String>{},
      );
    });

    test('street view preflight ZERO_RESULTS skips image', () async {
      final List<(String, Map<String, Object?>)> calls =
          <(String, Map<String, Object?>)>[];

      setGoogleMapsHttpTransport(
        httpGet: (
          String url, {
          required Map<String, Object?> params,
          required double timeout,
          Map<String, String>? headers,
          GoogleMapsConfig? config,
        }) async {
          calls.add((url, params));
          return (
            200,
            Uint8List.fromList(
              utf8.encode(jsonEncode(<String, Object?>{'status': 'ZERO_RESULTS'})),
            ),
          );
        },
      );

      final ({Context context, InMemoryArtifactService? artifactService}) env =
          await _createToolContext();
      final StreetViewResult result = await fetchStreetViewBaseline(
        37.422,
        -122.084,
        config: config,
      );
      final String out = await getStreetViewImage(
        37.422,
        -122.084,
        env.context,
        config: config,
      );

      expect(result.available, isFalse);
      expect(result.imageBytes, isNull);
      expect(calls.length, 2);
      expect(calls[0].$1, contains('streetview/metadata'));
      expect(out, contains('not available'));
      expect(env.context.state['street_view_available'], isFalse);
    });

    test('street view preflight OK fetches image with heading', () async {
      final Uint8List fakeJpeg = Uint8List.fromList(<int>[
        0xff,
        0xd8,
        0xff,
        0xe0,
        ...utf8.encode('FAKE_JPEG_DATA'),
      ]);
      final List<(String, Map<String, Object?>)> calls =
          <(String, Map<String, Object?>)>[];

      setGoogleMapsHttpTransport(
        httpGet: (
          String url, {
          required Map<String, Object?> params,
          required double timeout,
          Map<String, String>? headers,
          GoogleMapsConfig? config,
        }) async {
          calls.add((url, params));
          if (url.contains('metadata')) {
            final Map<String, Object?> meta = <String, Object?>{
              'status': 'OK',
              'pano_id': 'pano_abc123',
              'date': '2025-08',
              'location': <String, Object?>{'lat': 37.4219, 'lng': -122.0840},
            };
            return (200, Uint8List.fromList(utf8.encode(jsonEncode(meta))));
          }
          return (200, fakeJpeg);
        },
      );

      final StreetViewResult result = await fetchStreetViewBaseline(
        37.4220,
        -122.0840,
        config: config,
      );

      expect(result.available, isTrue);
      expect(result.imageBytes, fakeJpeg);
      expect(result.panoId, 'pano_abc123');
      expect(result.imageryDate, '2025-08');
      expect(result.heading, 0.0);
      expect(result.mapsUrl, contains('pano=pano_abc123'));
      expect(calls.length, 2);
      expect(calls[1].$2['pano'], 'pano_abc123');
      expect(calls[1].$2['heading'], 0.0);
    });

    test('missing API key is reported by every tool without HTTP calls', () async {
      int getCalls = 0;
      int postCalls = 0;
      setGoogleMapsHttpTransport(
        httpGet: (
          String url, {
          required Map<String, Object?> params,
          required double timeout,
          Map<String, String>? headers,
          GoogleMapsConfig? config,
        }) async {
          getCalls += 1;
          return (200, Uint8List(0));
        },
        httpPostJson: (
          String url, {
          required Map<String, Object?> params,
          required Map<String, Object?> payload,
          required double timeout,
          Map<String, String>? headers,
          GoogleMapsConfig? config,
        }) async {
          postCalls += 1;
          return (200, Uint8List(0));
        },
      );

      final ({Context context, InMemoryArtifactService? artifactService}) env =
          await _createToolContext();
      final String svOut = await getStreetViewImage(
        37.422,
        -122.084,
        env.context,
        config: unconfigured,
      );
      final String addrOut = await validateAddress(
        '742 Evergreen Terrace Apt 2B',
        env.context,
        config: unconfigured,
      );
      final String geoOut = await reverseGeocode(
        37.422,
        -122.084,
        env.context,
        config: unconfigured,
      );

      expect(svOut, 'Street View lookup failed: MAPS_API_KEY unconfigured.');
      expect(addrOut, 'Address validation failed: MAPS_API_KEY unconfigured.');
      expect(geoOut, 'Reverse geocoding failed: MAPS_API_KEY unconfigured.');
      expect(env.context.state.toMap(), isEmpty);
      expect(getCalls, 0);
      expect(postCalls, 0);
    });

    test('REQUEST_DENIED is reported, not treated as no result', () async {
      final Map<String, Object?> denied = <String, Object?>{
        'status': 'REQUEST_DENIED',
        'error_message': 'This API project is not authorized to use this API.',
      };
      setGoogleMapsHttpTransport(httpGet: _jsonGet(denied));

      final ({Context context, InMemoryArtifactService? artifactService}) env =
          await _createToolContext();
      final String svOut = await getStreetViewImage(
        37.422,
        -122.084,
        env.context,
        config: config,
      );
      final String geoOut = await reverseGeocode(
        37.422,
        -122.084,
        env.context,
        config: config,
      );

      expect(svOut, contains('Street View lookup failed'));
      expect(svOut, contains('REQUEST_DENIED'));
      expect(svOut, contains('not authorized'));
      expect(geoOut, contains('Reverse geocoding failed'));
      expect(geoOut, contains('REQUEST_DENIED'));
      expect(env.context.state.toMap(), isEmpty);
    });

    test('HTTP error is reported and writes no state', () async {
      final Map<String, Object?> forbidden = <String, Object?>{
        'error': <String, Object?>{
          'code': 403,
          'message': 'Address Validation API has not been used.',
          'status': 'PERMISSION_DENIED',
        },
      };
      setGoogleMapsHttpTransport(
        httpPostJson: _jsonPost(forbidden, status: 403),
        httpGet: _jsonGet(const <String, Object?>{}, status: 500),
      );

      final ({Context context, InMemoryArtifactService? artifactService}) env =
          await _createToolContext();
      final String addrOut = await validateAddress(
        '742 Evergreen Terrace',
        env.context,
        config: config,
      );
      final String svOut = await getStreetViewImage(
        37.422,
        -122.084,
        env.context,
        config: config,
      );

      expect(
        addrOut,
        'Address validation failed: Address Validation returned HTTP 403:'
        ' Address Validation API has not been used..',
      );
      expect(svOut, contains('Street View metadata returned HTTP 500'));
      expect(addrOut, isNot(contains('SINGLE_FAMILY')));
      expect(env.context.state.toMap(), isEmpty);
    });

    test('reverse_geocode ZERO_RESULTS is not an error', () async {
      setGoogleMapsHttpTransport(
        httpGet: _jsonGet(<String, Object?>{
          'status': 'ZERO_RESULTS',
          'results': const <Object?>[],
        }),
      );

      final ({Context context, InMemoryArtifactService? artifactService}) env =
          await _createToolContext();
      final String out = await reverseGeocode(
        0.0,
        -150.0,
        env.context,
        config: config,
      );

      expect(out, contains('Could not resolve a street address'));
      expect(env.context.state.toMap(), isEmpty);
    });

    test('address validation uses header and preserves city/state', () async {
      final Map<String, Object?> fakeApiResponse = <String, Object?>{
        'result': <String, Object?>{
          'address': <String, Object?>{
            'formattedAddress':
                '500 Terry A Francois Blvd, San Francisco, CA 94158, USA',
            'addressComponents': <Map<String, Object?>>[
              <String, Object?>{
                'componentType': 'street_number',
                'componentName': <String, Object?>{'text': '500'},
              },
              <String, Object?>{
                'componentType': 'route',
                'componentName': <String, Object?>{
                  'text': 'Terry A Francois Blvd',
                },
              },
              <String, Object?>{
                'componentType': 'locality',
                'componentName': <String, Object?>{'text': 'San Francisco'},
              },
              <String, Object?>{
                'componentType': 'administrative_area_level_1',
                'componentName': <String, Object?>{'text': 'CA'},
              },
              <String, Object?>{
                'componentType': 'postal_code',
                'componentName': <String, Object?>{'text': '94158'},
              },
            ],
            'missingComponentTypes': <String>['subpremise'],
          },
          'metadata': <String, Object?>{'business': false},
        },
      };

      final List<Map<String, String>?> capturedHeaders =
          <Map<String, String>?>[];
      final List<Map<String, Object?>> capturedParams =
          <Map<String, Object?>>[];

      setGoogleMapsHttpTransport(
        httpPostJson: (
          String url, {
          required Map<String, Object?> params,
          required Map<String, Object?> payload,
          required double timeout,
          Map<String, String>? headers,
          GoogleMapsConfig? config,
        }) async {
          capturedParams.add(params);
          capturedHeaders.add(headers);
          return (
            200,
            Uint8List.fromList(utf8.encode(jsonEncode(fakeApiResponse))),
          );
        },
      );

      final PropertyClassification res = await classifyPropertyAddressAsync(
        '500 Terry A Francois Blvd, SF',
        config: config,
      );

      expect(res.addressType, AddressType.multiUnit);
      expect(res.isMissingSubunit, isTrue);
      expect(
        res.baseAddress,
        '500 TERRY A FRANCOIS BLVD, SAN FRANCISCO, CA 94158',
      );
      expect(res.subunit, isNull);
      expect(capturedParams.single, isEmpty);
      expect(capturedHeaders.single?['X-Goog-Api-Key'], _key);
    });

    test('API key redacted and transient error not cached', () async {
      int attempt = 0;

      setGoogleMapsHttpTransport(
        httpPostJson: (
          String url, {
          required Map<String, Object?> params,
          required Map<String, Object?> payload,
          required double timeout,
          Map<String, String>? headers,
          GoogleMapsConfig? config,
        }) async {
          attempt += 1;
          if (attempt == 1) {
            throw http.ClientException(
              'Connection failed for https://example.com?key=$_key',
            );
          }
          return (
            200,
            Uint8List.fromList(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'result': <String, Object?>{
                    'address': <String, Object?>{
                      'addressComponents': <Map<String, Object?>>[
                        <String, Object?>{
                          'componentType': 'street_number',
                          'componentName': <String, Object?>{'text': '10'},
                        },
                        <String, Object?>{
                          'componentType': 'route',
                          'componentName': <String, Object?>{'text': 'Oak St'},
                        },
                      ],
                      'missingComponentTypes': const <String>[],
                    },
                    'metadata': <String, Object?>{'business': false},
                  },
                }),
              ),
            ),
          );
        },
      );

      await expectLater(
        classifyPropertyAddressAsync('10 Oak St', config: config),
        throwsA(
          isA<MapsApiError>()
              .having((MapsApiError e) => e.message, 'no raw key', isNot(contains(_key)))
              .having((MapsApiError e) => e.message, 'redacted', contains('[REDACTED]')),
        ),
      );

      final PropertyClassification second = await classifyPropertyAddressAsync(
        '10 Oak St',
        config: config,
      );
      expect(second.standardizedAddress, '10 OAK ST');
      expect(second.addressType, AddressType.singleFamily);
    });

    test('address validation parse error propagates', () async {
      setGoogleMapsHttpTransport(
        httpPostJson: _jsonPost(<String, Object?>{'result': const <Object?>[]}),
      );

      await expectLater(
        classifyPropertyAddressAsync('10 Oak St', config: config),
        throwsA(isA<TypeError>()),
      );
    });

    test('reverse geocode caches rounded coordinates', () async {
      final Map<String, Object?> fakeGeo = <String, Object?>{
        'status': 'OK',
        'results': <Map<String, Object?>>[
          <String, Object?>{
            'formatted_address':
                '1600 Amphitheatre Pkwy, Mountain View, CA 94043, USA',
          },
        ],
      };
      int httpCallCount = 0;
      setGoogleMapsHttpTransport(
        httpGet: (
          String url, {
          required Map<String, Object?> params,
          required double timeout,
          Map<String, String>? headers,
          GoogleMapsConfig? config,
        }) async {
          httpCallCount += 1;
          return (200, Uint8List.fromList(utf8.encode(jsonEncode(fakeGeo))));
        },
      );

      final String? addr = await reverseGeocodeCoordinatesAsync(
        37.4220656,
        -122.0840897,
        config: config,
      );
      final String? cachedAddr = await reverseGeocodeCoordinatesAsync(
        37.4220659,
        -122.0840899,
        config: config,
      );

      expect(addr, '1600 Amphitheatre Pkwy, Mountain View, CA 94043, USA');
      expect(cachedAddr, addr);
      expect(httpCallCount, 1);
    });

    test('API key not in HTTP request log', () async {
      final List<String> httpLogs = <String>[];
      final MockClient mockClient = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'status': 'OK',
            'results': <Map<String, Object?>>[
              <String, Object?>{'formatted_address': '1 Main'},
            ],
          }),
          200,
        );
      });

      final GoogleMapsConfig clientConfig = GoogleMapsConfig(
        apiKey: _key,
        environment: const <String, String>{},
        httpClient: mockClient,
        onHttpLog: httpLogs.add,
      );

      final String? addr = await reverseGeocodeCoordinatesAsync(
        37.422,
        -122.084,
        config: clientConfig,
      );
      expect(addr, '1 Main');
      final String output = httpLogs.join('\n');
      expect(output, contains('HTTP Request'));
      expect(output, contains('key=[REDACTED]'));
      expect(output, isNot(contains(_key)));
    });

    test('tools keep session state JSON serializable and save artifact', () async {
      final Uint8List fakeJpeg = Uint8List.fromList(<int>[
        0xff,
        0xd8,
        0xff,
        0xe0,
        ...utf8.encode('STREET_VIEW_BYTES'),
      ]);

      setGoogleMapsHttpTransport(
        httpGet: (
          String url, {
          required Map<String, Object?> params,
          required double timeout,
          Map<String, String>? headers,
          GoogleMapsConfig? config,
        }) async {
          if (url.contains('metadata')) {
            return (
              200,
              Uint8List.fromList(
                utf8.encode(
                  jsonEncode(<String, Object?>{
                    'status': 'OK',
                    'pano_id': 'pano_xyz',
                    'date': '2026-01',
                    'location': <String, Object?>{
                      'lat': 37.421,
                      'lng': -122.084,
                    },
                  }),
                ),
              ),
            );
          }
          if (url.contains('geocode')) {
            return (
              200,
              Uint8List.fromList(
                utf8.encode(
                  jsonEncode(<String, Object?>{
                    'status': 'OK',
                    'results': <Map<String, Object?>>[
                      <String, Object?>{
                        'formatted_address': '1600 Amphitheatre Pkwy',
                      },
                    ],
                  }),
                ),
              ),
            );
          }
          return (200, fakeJpeg);
        },
        httpPostJson: _jsonPost(<String, Object?>{
          'result': <String, Object?>{
            'address': <String, Object?>{
              'addressComponents': <Map<String, Object?>>[
                <String, Object?>{
                  'componentType': 'street_number',
                  'componentName': <String, Object?>{'text': '123'},
                },
                <String, Object?>{
                  'componentType': 'route',
                  'componentName': <String, Object?>{'text': 'Main St'},
                },
                <String, Object?>{
                  'componentType': 'subpremise',
                  'componentName': <String, Object?>{'text': '4A'},
                },
              ],
            },
          },
        }),
      );

      final ({Context context, InMemoryArtifactService? artifactService}) env =
          await _createToolContext(withArtifactService: true);
      final Map<String, BaseTool> tools = <String, BaseTool>{
        for (final BaseTool tool
            in await GoogleMapsToolset(config: config).getTools())
          tool.name: tool,
      };

      final Object? svOut = await tools['get_street_view_image']!.run(
        args: <String, dynamic>{'latitude': 37.422, 'longitude': -122.084},
        toolContext: env.context,
      );
      final Object? invalidOut = await tools['get_street_view_image']!.run(
        args: <String, dynamic>{'latitude': 999.0, 'longitude': -122.084},
        toolContext: env.context,
      );
      final Object? addrOut = await tools['validate_address']!.run(
        args: <String, dynamic>{'raw_address': '123 Main St #4A'},
        toolContext: env.context,
      );
      final Object? geoOut = await tools['reverse_geocode']!.run(
        args: <String, dynamic>{'latitude': 37.422, 'longitude': -122.084},
        toolContext: env.context,
      );

      expect(svOut, contains('Captured Street View imagery'));
      expect(invalidOut, contains('Invalid coordinates'));
      expect(addrOut, contains('MULTI_UNIT'));
      expect(geoOut, contains('1600 Amphitheatre Pkwy'));

      final Map<String, Object?> stateMap = env.context.state.toMap();
      expect(jsonEncode(stateMap), isA<String>());
      expect(stateMap['street_view_available'], isTrue);
      expect(
        stateMap['street_view_artifact_name'],
        streetViewArtifactFilename,
      );
      final Part? savedPart = await env.context.loadArtifact(
        streetViewArtifactFilename,
      );
      expect(savedPart, isNotNull);
      expect(savedPart!.inlineData?.mimeType, 'image/jpeg');
      expect(savedPart.inlineData?.data, fakeJpeg);
      expect(stateMap.containsKey('street_view_image_b64'), isFalse);
      expect(stateMap['is_multi_unit'], isTrue);
      expect(stateMap['reverse_geocoded_address'], '1600 Amphitheatre Pkwy');
    });

    test('falls back to base64 session state when artifact service is unavailable', () async {
      final Uint8List fakeJpeg = Uint8List.fromList(utf8.encode('RAW_JPEG'));
      setGoogleMapsHttpTransport(
        httpGet: (
          String url, {
          required Map<String, Object?> params,
          required double timeout,
          Map<String, String>? headers,
          GoogleMapsConfig? config,
        }) async {
          if (url.contains('metadata')) {
            return (
              200,
              Uint8List.fromList(
                utf8.encode(jsonEncode(<String, Object?>{'status': 'OK'})),
              ),
            );
          }
          return (200, fakeJpeg);
        },
      );

      final ({Context context, InMemoryArtifactService? artifactService}) env =
          await _createToolContext(withArtifactService: false);
      final String out = await getStreetViewImage(
        37.422,
        -122.084,
        env.context,
        config: config,
      );

      expect(out, contains('Captured Street View imagery'));
      expect(out, isNot(contains('ADK Artifact')));
      expect(
        env.context.state['street_view_image_b64'],
        base64Encode(fakeJpeg),
      );
      expect(
        env.context.state.toMap().containsKey('street_view_artifact_name'),
        isFalse,
      );
    });

    test('toolset names, filtering, prefixing, and declarations', () async {
      final GoogleMapsToolset toolset = GoogleMapsToolset(config: config);
      final List<BaseTool> tools = await toolset.getTools();
      expect(
        tools.map((BaseTool t) => t.name).toList(),
        <String>['get_street_view_image', 'validate_address', 'reverse_geocode'],
      );

      for (final BaseTool tool in tools) {
        final FunctionDeclaration? decl = tool.getDeclaration();
        expect(decl, isNotNull);
        final Map<String, dynamic> props =
            decl!.parameters['properties'] as Map<String, dynamic>;
        expect(props.containsKey('tool_context'), isFalse);
        expect(props.containsKey('toolContext'), isFalse);
        expect(props.containsKey('config'), isFalse);
      }

      final GoogleMapsToolset filteredToolset = GoogleMapsToolset(
        config: config,
        toolFilter: <String>['get_street_view_image'],
      );
      final List<BaseTool> filteredTools = await filteredToolset.getTools();
      expect(
        filteredTools.map((BaseTool t) => t.name).toList(),
        <String>['get_street_view_image'],
      );

      final GoogleMapsToolset prefixedToolset = GoogleMapsToolset(
        config: config,
        toolNamePrefix: 'maps',
      );
      final List<BaseTool> prefixedTools = await prefixedToolset
          .getToolsWithPrefix();
      expect(
        prefixedTools.map((BaseTool t) => t.name).toList(),
        <String>[
          'maps_get_street_view_image',
          'maps_validate_address',
          'maps_reverse_geocode',
        ],
      );
      await prefixedToolset.close();
    });
  });
}
