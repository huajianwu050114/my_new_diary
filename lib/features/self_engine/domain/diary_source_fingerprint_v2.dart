import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../../diary/domain/entities/diary_entry.dart';
import 'entities/diary_revision_v2.dart';

abstract final class DiarySourceFingerprintV2 {
  static const version = 1;

  static String calculate(DiaryEntryV2 entry) {
    return _calculate(
      body: entry.body,
      entryDate: entry.entryDate,
      mood: entry.mood,
      tags: entry.tags,
      latitude: entry.location?.latitude,
      longitude: entry.location?.longitude,
      address: entry.location?.address,
    );
  }

  static String calculateRevision(DiaryRevisionV2 revision) => _calculate(
    body: revision.body,
    entryDate: revision.entryDate,
    mood: revision.mood,
    tags: revision.tags,
    latitude: revision.latitude,
    longitude: revision.longitude,
    address: revision.address,
  );

  static String _calculate({
    required String body,
    required DateTime entryDate,
    required String? mood,
    required List<String> tags,
    required double? latitude,
    required double? longitude,
    required String? address,
  }) {
    if ((latitude == null) != (longitude == null)) {
      throw const FormatException(
        'A diary location must contain both latitude and longitude.',
      );
    }
    if (latitude != null &&
        (!latitude.isFinite || latitude < -90 || latitude > 90)) {
      throw const FormatException(
        'Latitude must be finite and within [-90, 90].',
      );
    }
    if (longitude != null &&
        (!longitude.isFinite || longitude < -180 || longitude > 180)) {
      throw const FormatException(
        'Longitude must be finite and within [-180, 180].',
      );
    }
    final normalizedTags =
        tags
            .map((tag) => _normalizeTrimmedText(tag))
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final canonical = <String, Object?>{
      'fingerprintVersion': version,
      'body': _normalizeBody(body),
      'entryDate': entryDate.toUtc().toIso8601String(),
      'mood': _emptyToNull(mood),
      'tags': normalizedTags,
      'location': latitude == null
          ? null
          : {
              'latitude': _coordinate(latitude),
              'longitude': _coordinate(longitude!),
              'address': _emptyToNull(address),
            },
    };
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  // The body is the authoritative semantic source. Preserve leading and
  // trailing whitespace because it can be meaningful in Markdown or quotes.
  static String _normalizeBody(String value) =>
      unicode.nfc(value.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));

  static String _normalizeTrimmedText(String value) =>
      unicode.nfc(value.trim());

  static String _coordinate(double value) {
    final normalized = value == 0 ? 0.0 : value;
    return normalized.toStringAsFixed(6);
  }

  static String? _emptyToNull(String? value) {
    final normalized = value == null ? null : _normalizeTrimmedText(value);
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
