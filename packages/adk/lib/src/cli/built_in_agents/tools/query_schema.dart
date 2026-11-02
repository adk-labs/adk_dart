// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// ADK `AgentConfig` schema query tool for dynamic schema information access.
library;

import '../utils/adk_source_utils.dart';

/// Dynamically queries the ADK `AgentConfig` schema for specific information.
///
/// Supported [queryType] values:
/// - `"overview"`: high-level schema structure and main properties
/// - `"component"`: detailed info about a specific top-level [component]
/// - `"field"`: details about a specific field using dot-separated [fieldPath]
/// - `"properties"`: flat list of all available properties
Future<Map<String, dynamic>> querySchema(
  String queryType, {
  String? component,
  String? fieldPath,
  // ignore: non_constant_identifier_names
  String? field_path,
}) async {
  final String? effectiveFieldPath = field_path ?? fieldPath;
  try {
    final Map<String, dynamic> schema = loadAgentConfigSchemaMap();

    if (queryType == 'overview') {
      return _getSchemaOverview(schema);
    } else if (queryType == 'component' &&
        component != null &&
        component.isNotEmpty) {
      return _getComponentDetails(schema, component);
    } else if (queryType == 'field' &&
        effectiveFieldPath != null &&
        effectiveFieldPath.isNotEmpty) {
      return _getFieldDetails(schema, effectiveFieldPath);
    } else if (queryType == 'properties') {
      return _getAllProperties(schema);
    } else {
      return <String, dynamic>{
        'error':
            "Invalid query_type '$queryType' or missing required parameters",
        'supported_queries': <String>[
          'overview - Get high-level schema structure',
          'component - Get details for specific component (requires component parameter)',
          'field - Get details for specific field (requires field_path parameter)',
          'properties - Get all available properties',
        ],
      };
    }
  } catch (e) {
    return <String, dynamic>{'error': 'Schema exploration failed: $e'};
  }
}

/// Snake-case alias for [querySchema].
// ignore: non_constant_identifier_names
Future<Map<String, dynamic>> query_schema(
  String queryType, {
  String? component,
  String? fieldPath,
  // ignore: non_constant_identifier_names
  String? field_path,
}) => querySchema(
  queryType,
  component: component,
  fieldPath: fieldPath,
  field_path: field_path,
);

Map<String, dynamic> _getSchemaOverview(Map<String, dynamic> schema) {
  final List<Map<String, dynamic>> mainProperties = <Map<String, dynamic>>[];
  final Map<String, dynamic> properties =
      (schema['properties'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final List<Object?> requiredList =
      (schema['required'] as List<Object?>?) ?? const <Object?>[];

  properties.forEach((String propName, Object? rawDetails) {
    final Map<String, dynamic> propDetails = rawDetails is Map<String, dynamic>
        ? rawDetails
        : <String, dynamic>{};
    mainProperties.add(<String, dynamic>{
      'name': propName,
      'type': propDetails['type'] ?? 'unknown',
      'description': propDetails['description'] ?? '',
      'required': requiredList.contains(propName),
    });
  });

  return <String, dynamic>{
    'title': schema['title'] ?? 'ADK Agent Configuration',
    'description': schema['description'] ?? '',
    'schema_version': schema[r'$schema'] ?? '',
    'main_properties': mainProperties,
  };
}

Map<String, dynamic> _getComponentDetails(
  Map<String, dynamic> schema,
  String component,
) {
  final Map<String, dynamic> properties =
      (schema['properties'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  if (!properties.containsKey(component)) {
    return <String, dynamic>{
      'error': "Component '$component' not found",
      'available_components': properties.keys.toList(),
    };
  }

  final Map<String, dynamic> componentSchema =
      (properties[component] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final List<Object?> requiredList =
      (schema['required'] as List<Object?>?) ?? const <Object?>[];

  final Map<String, dynamic> result = <String, dynamic>{
    'component': component,
    'type': componentSchema['type'] ?? 'unknown',
    'description': componentSchema['description'] ?? '',
    'required': requiredList.contains(component),
  };

  if (componentSchema['type'] == 'object') {
    final Map<String, dynamic> nestedProps =
        (componentSchema['properties'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    final List<Object?> nestedRequired =
        (componentSchema['required'] as List<Object?>?) ?? const <Object?>[];
    final Map<String, dynamic> mappedProps = <String, dynamic>{};
    nestedProps.forEach((String propName, Object? rawDetails) {
      final Map<String, dynamic> propDetails =
          rawDetails is Map<String, dynamic>
          ? rawDetails
          : <String, dynamic>{};
      mappedProps[propName] = <String, dynamic>{
        'type': propDetails['type'] ?? 'unknown',
        'description': propDetails['description'] ?? '',
        'required': nestedRequired.contains(propName),
      };
    });
    result['properties'] = mappedProps;
  }

  if (componentSchema['type'] == 'array') {
    final Map<String, dynamic> items =
        (componentSchema['items'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    final Map<String, dynamic> itemsInfo = <String, dynamic>{
      'type': items['type'] ?? 'unknown',
      'description': items['description'] ?? '',
    };
    if (items['type'] == 'object') {
      itemsInfo['properties'] = items['properties'] ?? <String, dynamic>{};
    }
    result['items'] = itemsInfo;
  }

  return result;
}

Map<String, dynamic> _getFieldDetails(
  Map<String, dynamic> schema,
  String fieldPath,
) {
  final List<String> pathParts = fieldPath.split('.');
  Object? current = schema['properties'] ?? <String, dynamic>{};

  final List<Map<String, dynamic>> pathTraversal = <Map<String, dynamic>>[];
  final Map<String, dynamic> result = <String, dynamic>{
    'field_path': fieldPath,
    'path_traversal': pathTraversal,
  };

  for (int i = 0; i < pathParts.length; i++) {
    final String part = pathParts[i];
    if (current is! Map<String, dynamic> || !current.containsKey(part)) {
      return <String, dynamic>{
        'error': "Field path '$fieldPath' not found at '$part'",
        'traversed': pathParts.sublist(0, i).join('.'),
        'available_at_level': current is Map<String, dynamic>
            ? current.keys.toList()
            : <String>[],
      };
    }

    final Map<String, dynamic> fieldInfo =
        (current[part] as Map<String, dynamic>?) ?? <String, dynamic>{};
    pathTraversal.add(<String, dynamic>{
      'field': part,
      'type': fieldInfo['type'] ?? 'unknown',
      'description': fieldInfo['description'] ?? '',
    });

    if (fieldInfo['type'] == 'object') {
      current = fieldInfo['properties'] ?? <String, dynamic>{};
    } else if (fieldInfo['type'] == 'array' &&
        (fieldInfo['items'] as Map<String, dynamic>?)?['type'] == 'object') {
      current =
          (fieldInfo['items'] as Map<String, dynamic>?)?['properties'] ??
          <String, dynamic>{};
    } else {
      result['final_field'] = fieldInfo;
      break;
    }
  }

  return result;
}

Map<String, dynamic> _getAllProperties(Map<String, dynamic> schema) {
  final Map<String, dynamic> properties = <String, dynamic>{};

  void extractProperties(Object? obj, [String prefix = '']) {
    if (obj is! Map<String, dynamic>) {
      return;
    }

    obj.forEach((String key, Object? value) {
      if (key == 'properties' && value is Map<String, dynamic>) {
        value.forEach((String propName, Object? rawDetails) {
          final Map<String, dynamic> propDetails =
              rawDetails is Map<String, dynamic>
              ? rawDetails
              : <String, dynamic>{};
          final String fullPath = prefix.isNotEmpty
              ? '$prefix.$propName'
              : propName;
          properties[fullPath] = <String, dynamic>{
            'type': propDetails['type'] ?? 'unknown',
            'description': propDetails['description'] ?? '',
          };

          if (propDetails['type'] == 'object') {
            extractProperties(propDetails, fullPath);
          } else if (propDetails['type'] == 'array' &&
              (propDetails['items'] as Map<String, dynamic>?)?['type'] ==
                  'object') {
            extractProperties(propDetails['items'], fullPath);
          }
        });
      }
    });
  }

  extractProperties(schema);

  return <String, dynamic>{
    'total_properties': properties.length,
    'properties': properties,
  };
}
