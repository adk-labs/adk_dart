import 'dart:convert';
import 'dart:io';

Object? loadYamlFile(String filePath) {
  final File file = File(filePath);
  if (!file.existsSync()) {
    throw FileSystemException('YAML file not found', filePath);
  }
  return _decodeYamlOrJson(file.readAsStringSync());
}

void dumpPydanticToYaml(
  Object model,
  String filePath, {
  int indent = 2,
  bool sortKeys = true,
  bool excludeNone = true,
  bool excludeDefaults = true,
  Set<String>? exclude,
}) {
  final Object? normalized = _normalizeObject(model);
  if (normalized is! Map) {
    throw ArgumentError('Model must serialize to a map.');
  }
  final Map<String, Object?> map = _normalizeMap(normalized);
  if (exclude != null && exclude.isNotEmpty) {
    for (final String key in exclude) {
      map.remove(key);
    }
  }
  if (excludeNone) {
    map.removeWhere((String _, Object? value) => value == null);
  }
  final File output = File(filePath);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    _YamlEncoder(indent: indent, sortKeys: sortKeys).encode(map),
  );
  // Kept for API parity with Python signature.
  if (!excludeDefaults) {
    // No-op: Dart map/object models do not carry default metadata.
  }
}

Object? _decodeYamlOrJson(String content) {
  final String trimmed = content.trim();
  if (trimmed.isEmpty) {
    return <String, Object?>{};
  }
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return jsonDecode(trimmed);
  }
  return _SimpleYamlDecoder().decode(trimmed);
}

Object? _normalizeObject(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is Map) {
    return _normalizeMap(value);
  }
  if (value is List) {
    return value.map(_normalizeObject).toList(growable: false);
  }
  final dynamic dynamicValue = value;
  final Object? json = dynamicValue.toJson();
  if (json is Map) {
    return _normalizeMap(json);
  }
  return json;
}

Map<String, Object?> _normalizeMap(Map value) {
  return value.map(
    (Object? key, Object? item) => MapEntry('$key', _normalizeObject(item)),
  );
}

class _YamlEncoder {
  _YamlEncoder({required this.indent, required this.sortKeys});

  final int indent;
  final bool sortKeys;

  String encode(Object? value) {
    final String text = _encodeValue(value, 0);
    return text.endsWith('\n') ? text : '$text\n';
  }

  String _encodeValue(Object? value, int level) {
    if (value is Map) {
      return _encodeMap(value, level);
    }
    if (value is List) {
      return _encodeList(value, level);
    }
    return '${' ' * level}${_encodeScalar(value)}\n';
  }

  String _encodeMap(Map value, int level) {
    final List<String> keys = value.keys.map((Object? key) => '$key').toList();
    if (sortKeys) {
      keys.sort();
    }

    final StringBuffer out = StringBuffer();
    for (final String key in keys) {
      final Object? entryValue = value[key];
      if (entryValue is Map || entryValue is List) {
        out.writeln('${' ' * level}$key:');
        out.write(_encodeValue(entryValue, level + indent));
        continue;
      }
      if (entryValue is String && _isMultilineString(entryValue)) {
        out.writeln('${' ' * level}$key: |');
        for (final String line in const LineSplitter().convert(entryValue)) {
          out.writeln('${' ' * (level + indent)}$line');
        }
        continue;
      }
      out.writeln('${' ' * level}$key: ${_encodeScalar(entryValue)}');
    }
    return out.toString();
  }

  String _encodeList(List value, int level) {
    final StringBuffer out = StringBuffer();
    for (final Object? item in value) {
      if (item is Map || item is List) {
        out.writeln('${' ' * level}-');
        out.write(_encodeValue(item, level + indent));
        continue;
      }
      if (item is String && _isMultilineString(item)) {
        out.writeln('${' ' * level}- |');
        for (final String line in const LineSplitter().convert(item)) {
          out.writeln('${' ' * (level + indent)}$line');
        }
        continue;
      }
      out.writeln('${' ' * level}- ${_encodeScalar(item)}');
    }
    return out.toString();
  }

  bool _isMultilineString(String value) {
    return value.contains('\n') || value.contains('"') || value.contains("'");
  }

  String _encodeScalar(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is bool || value is num) {
      return '$value';
    }
    final String text = '$value';
    if (text.isEmpty) {
      return "''";
    }
    if (RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(text)) {
      return text;
    }
    return "'${text.replaceAll("'", "''")}'";
  }
}

class _SimpleYamlDecoder {
  Object? decode(String source) {
    final List<_YamlLine> lines = _toLines(source);
    if (lines.isEmpty) {
      return <String, Object?>{};
    }
    final _ParseResult result = _parseBlock(lines, 0, lines.first.indent);
    return result.value;
  }

  List<_YamlLine> _toLines(String source) {
    final List<_YamlLine> lines = <_YamlLine>[];
    for (String line in const LineSplitter().convert(source)) {
      final String stripped = line.trimRight();
      if (stripped.trim().isEmpty || stripped.trimLeft().startsWith('#')) {
        continue;
      }
      final int indent = stripped.length - stripped.trimLeft().length;
      lines.add(_YamlLine(indent: indent, text: stripped.trimLeft()));
    }
    return lines;
  }

  _ParseResult _parseBlock(List<_YamlLine> lines, int index, int indent) {
    if (index >= lines.length) {
      return _ParseResult(<String, Object?>{}, index);
    }
    if (lines[index].text.startsWith('- ')) {
      return _parseList(lines, index, indent);
    }
    return _parseMap(lines, index, indent);
  }

  _ParseResult _parseMap(List<_YamlLine> lines, int index, int indent) {
    final Map<String, Object?> map = <String, Object?>{};
    int cursor = index;
    while (cursor < lines.length) {
      final _YamlLine line = lines[cursor];
      if (line.indent < indent) {
        break;
      }
      if (line.indent != indent || line.text.startsWith('- ')) {
        break;
      }
      final int split = line.text.indexOf(':');
      if (split <= 0) {
        throw FormatException('Invalid YAML mapping line `${line.text}`.');
      }
      final String key = line.text.substring(0, split).trim();
      final String rawValue = line.text.substring(split + 1).trim();
      cursor += 1;
      if (rawValue.isEmpty) {
        if (cursor < lines.length && lines[cursor].indent > indent) {
          final _ParseResult nested = _parseBlock(
            lines,
            cursor,
            lines[cursor].indent,
          );
          map[key] = nested.value;
          cursor = nested.nextIndex;
        } else {
          map[key] = <String, Object?>{};
        }
      } else if (_isLiteralBlockScalarIndicator(rawValue)) {
        final _ParseResult literal = _parseLiteralBlockScalar(
          lines,
          cursor,
          indent,
          rawValue,
        );
        map[key] = literal.value;
        cursor = literal.nextIndex;
      } else {
        map[key] = _parseScalar(rawValue);
      }
    }
    return _ParseResult(map, cursor);
  }

  _ParseResult _parseList(List<_YamlLine> lines, int index, int indent) {
    final List<Object?> values = <Object?>[];
    int cursor = index;
    while (cursor < lines.length) {
      final _YamlLine line = lines[cursor];
      if (line.indent < indent) {
        break;
      }
      if (line.indent != indent || !line.text.startsWith('- ')) {
        break;
      }

      final String itemText = line.text.substring(2).trim();
      cursor += 1;
      if (itemText.isEmpty) {
        if (cursor < lines.length && lines[cursor].indent > indent) {
          final _ParseResult nested = _parseBlock(
            lines,
            cursor,
            lines[cursor].indent,
          );
          values.add(nested.value);
          cursor = nested.nextIndex;
        } else {
          values.add(null);
        }
        continue;
      }

      if (_isLiteralBlockScalarIndicator(itemText)) {
        final _ParseResult literal = _parseLiteralBlockScalar(
          lines,
          cursor,
          line.indent,
          itemText,
        );
        values.add(literal.value);
        cursor = literal.nextIndex;
        continue;
      }

      final int split = itemText.indexOf(':');
      if (split > 0) {
        final String key = itemText.substring(0, split).trim();
        final String rawValue = itemText.substring(split + 1).trim();
        final Map<String, Object?> itemMap = <String, Object?>{};
        if (rawValue.isEmpty) {
          if (cursor < lines.length && lines[cursor].indent > indent) {
            final _ParseResult nested = _parseBlock(
              lines,
              cursor,
              lines[cursor].indent,
            );
            itemMap[key] = nested.value;
            cursor = nested.nextIndex;
          } else {
            itemMap[key] = <String, Object?>{};
          }
        } else if (_isLiteralBlockScalarIndicator(rawValue)) {
          final _ParseResult literal = _parseLiteralBlockScalar(
            lines,
            cursor,
            line.indent + 2,
            rawValue,
          );
          itemMap[key] = literal.value;
          cursor = literal.nextIndex;
        } else {
          itemMap[key] = _parseScalar(rawValue);
        }

        if (cursor < lines.length &&
            lines[cursor].indent > indent &&
            !lines[cursor].text.startsWith('- ')) {
          final _ParseResult rest = _parseMap(
            lines,
            cursor,
            lines[cursor].indent,
          );
          if (rest.value is Map<String, Object?>) {
            itemMap.addAll(rest.value as Map<String, Object?>);
            cursor = rest.nextIndex;
          }
        }
        values.add(itemMap);
        continue;
      }

      values.add(_parseScalar(itemText));
    }
    return _ParseResult(values, cursor);
  }

  bool _isLiteralBlockScalarIndicator(String text) {
    if (!text.startsWith('|')) {
      return false;
    }
    final String suffix = text.substring(1);
    for (final int codeUnit in suffix.codeUnits) {
      final bool isDigit = codeUnit >= 48 && codeUnit <= 57;
      if (!isDigit && codeUnit != 43 && codeUnit != 45) {
        return false;
      }
    }
    return true;
  }

  _ParseResult _parseLiteralBlockScalar(
    List<_YamlLine> lines,
    int index,
    int parentIndent,
    String indicator,
  ) {
    if (index >= lines.length || lines[index].indent <= parentIndent) {
      return _ParseResult('', index);
    }

    final int blockIndent = lines[index].indent;
    final List<String> values = <String>[];
    int cursor = index;
    while (cursor < lines.length) {
      final _YamlLine line = lines[cursor];
      if (line.indent <= parentIndent) {
        break;
      }
      final int extraIndent = line.indent - blockIndent;
      final String prefix = extraIndent > 0 ? ' ' * extraIndent : '';
      values.add('$prefix${line.text}');
      cursor += 1;
    }

    String result = values.join('\n');
    final String chomp = _blockScalarChompMode(indicator);
    if (values.isNotEmpty && chomp != '-') {
      result = '$result\n';
    }
    return _ParseResult(result, cursor);
  }

  String _blockScalarChompMode(String indicator) {
    if (indicator.contains('-')) {
      return '-';
    }
    if (indicator.contains('+')) {
      return '+';
    }
    return '';
  }

  Object? _parseScalar(String text) {
    if (text == 'null' || text == '~') {
      return null;
    }
    if (text == 'true') {
      return true;
    }
    if (text == 'false') {
      return false;
    }
    if (RegExp(r'^-?\d+$').hasMatch(text)) {
      return int.parse(text);
    }
    if (RegExp(r'^-?\d+\.\d+$').hasMatch(text)) {
      return double.parse(text);
    }
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      return text.substring(1, text.length - 1);
    }
    return text;
  }
}

class _YamlLine {
  _YamlLine({required this.indent, required this.text});

  final int indent;
  final String text;
}

class _ParseResult {
  _ParseResult(this.value, this.nextIndex);

  final Object? value;
  final int nextIndex;
}
