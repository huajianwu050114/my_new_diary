import 'dart:convert';

import '../domain/diary_sync_record_v2.dart';

class DiarySyncFormatException implements FormatException {
  const DiarySyncFormatException(this.message, [this.source, this.offset]);

  @override
  final String message;
  @override
  final Object? source;
  @override
  final int? offset;

  @override
  String toString() => 'DiarySyncFormatException: $message';
}

class UnsupportedDiarySyncSchemaException extends DiarySyncFormatException {
  const UnsupportedDiarySyncSchemaException(int version)
    : super('Unsupported schemaVersion: $version');
}

class DiarySyncCodecV2 {
  const DiarySyncCodecV2();

  static const schemaVersion = 1;

  DiarySyncRecordV2 decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw DiarySyncFormatException(
        'Malformed JSON',
        error.source,
        error.offset,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const DiarySyncFormatException('The root value must be an object.');
    }
    final version = _requiredInt(decoded, 'schemaVersion');
    if (version != schemaVersion) {
      throw UnsupportedDiarySyncSchemaException(version);
    }
    final id = _requiredString(decoded, 'id');
    if (id.trim().isEmpty) {
      throw const DiarySyncFormatException('id must not be empty.');
    }
    final purged = _bool(decoded, 'purged', fallback: false);
    final updatedAt = _requiredTime(decoded, 'updatedAt');
    if (purged) {
      return DiarySyncRecordV2.purged(id: id, updatedAt: updatedAt);
    }
    final latitude = _nullableDouble(decoded, 'latitude');
    final longitude = _nullableDouble(decoded, 'longitude');
    if ((latitude == null) != (longitude == null)) {
      throw const DiarySyncFormatException(
        'latitude and longitude must both be present or null.',
      );
    }
    return DiarySyncRecordV2(
      id: id,
      body: _requiredString(decoded, 'body'),
      contentDelta: _nullableString(decoded, 'contentDelta'),
      entryDate: _requiredTime(decoded, 'entryDate'),
      createdAt: _requiredTime(decoded, 'createdAt'),
      updatedAt: updatedAt,
      imageIds: _stringList(decoded, 'imageIds'),
      mood: _nullableString(decoded, 'mood'),
      tags: _stringList(decoded, 'tags'),
      latitude: latitude,
      longitude: longitude,
      address: _nullableString(decoded, 'address'),
      aiAnalyses: _stringList(decoded, 'aiAnalyses'),
      isFavorite: _bool(decoded, 'isFavorite', fallback: false),
      deletedAt: _nullableTime(decoded, 'deletedAt'),
    );
  }

  String encode(DiarySyncRecordV2 record) => jsonEncode(toCanonicalMap(record));

  Map<String, Object?> toCanonicalMap(DiarySyncRecordV2 record) {
    if (record.purged) {
      return <String, Object?>{
        'schemaVersion': schemaVersion,
        'id': record.id,
        'updatedAt': _time(record.updatedAt),
        'deletedAt': _time(record.deletedAt ?? record.updatedAt),
        'purged': true,
      };
    }
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'id': record.id,
      'body': record.body,
      'contentDelta': record.contentDelta,
      'entryDate': _time(record.entryDate),
      'createdAt': _time(record.createdAt),
      'updatedAt': _time(record.updatedAt),
      'imageIds': record.imageIds,
      'mood': record.mood,
      'tags': record.tags,
      'latitude': record.latitude,
      'longitude': record.longitude,
      'address': record.address,
      'aiAnalyses': record.aiAnalyses,
      'isFavorite': record.isFavorite,
      'deletedAt': record.deletedAt == null ? null : _time(record.deletedAt!),
    };
  }

  String _time(DateTime value) => value.toUtc().toIso8601String();

  String _requiredString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String) throw DiarySyncFormatException('$key is required.');
    return value;
  }

  int _requiredInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! int) throw DiarySyncFormatException('$key is required.');
    return value;
  }

  String? _nullableString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String) {
      throw DiarySyncFormatException('$key must be a string or null.');
    }
    return value;
  }

  double? _nullableDouble(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! num) {
      throw DiarySyncFormatException('$key must be a number or null.');
    }
    return value.toDouble();
  }

  bool _bool(Map<String, dynamic> map, String key, {required bool fallback}) {
    final value = map[key];
    if (value == null) return fallback;
    if (value is! bool) {
      throw DiarySyncFormatException('$key must be a boolean.');
    }
    return value;
  }

  List<String> _stringList(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw DiarySyncFormatException('$key must be a list of strings.');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  DateTime _requiredTime(Map<String, dynamic> map, String key) {
    final value = _requiredString(map, key);
    return _parseTime(value, key);
  }

  DateTime? _nullableTime(Map<String, dynamic> map, String key) {
    final value = _nullableString(map, key);
    return value == null ? null : _parseTime(value, key);
  }

  DateTime _parseTime(String value, String key) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !value.endsWith('Z')) {
      throw DiarySyncFormatException('$key must be a UTC ISO8601 timestamp.');
    }
    return parsed.toUtc();
  }
}
