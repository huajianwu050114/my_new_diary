import 'dart:convert';

import '../../domain/entities/diary_entry.dart';

class DiaryEntryMapperV2 {
  const DiaryEntryMapperV2();

  Map<String, Object?> toRow(DiaryEntryV2 entry) {
    return {
      'id': entry.id,
      'body': entry.body,
      'content_delta': entry.contentDelta,
      'entry_date': entry.entryDate.toUtc().toIso8601String(),
      'created_at': entry.createdAt.toUtc().toIso8601String(),
      'updated_at': entry.updatedAt.toUtc().toIso8601String(),
      'image_ids': jsonEncode(entry.imageIds),
      'mood': entry.mood,
      'tags': jsonEncode(entry.tags),
      'latitude': entry.location?.latitude,
      'longitude': entry.location?.longitude,
      'address': entry.location?.address,
      'ai_analyses': jsonEncode(entry.aiAnalyses),
      'is_favorite': entry.isFavorite ? 1 : 0,
      'deleted_at': entry.deletedAt?.toUtc().toIso8601String(),
    };
  }

  DiaryEntryV2 fromRow(Map<String, Object?> row) {
    final latitude = _asDouble(row['latitude']);
    final longitude = _asDouble(row['longitude']);

    return DiaryEntryV2(
      id: row['id']! as String,
      body: row['body']! as String,
      contentDelta: row['content_delta'] as String?,
      entryDate: DateTime.parse(row['entry_date']! as String),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      imageIds: _stringList(row['image_ids']),
      mood: row['mood'] as String?,
      tags: _stringList(row['tags']),
      location: latitude == null || longitude == null
          ? null
          : DiaryLocation(
              latitude: latitude,
              longitude: longitude,
              address: row['address'] as String?,
            ),
      aiAnalyses: _stringList(row['ai_analyses']),
      isFavorite: row['is_favorite'] == 1,
      deletedAt: _optionalDate(row['deleted_at']),
    );
  }

  List<String> _stringList(Object? value) {
    if (value is! String || value.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      return const [];
    }
    return List.unmodifiable(decoded.whereType<String>());
  }

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  DateTime? _optionalDate(Object? value) {
    return value is String && value.isNotEmpty ? DateTime.parse(value) : null;
  }
}
