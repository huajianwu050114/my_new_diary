import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/diary_metadata_template_v2.dart';

class DiaryMetadataTemplateStoreV2 {
  static const _storageKey = 'diary_metadata_templates_v2';

  Future<List<DiaryMetadataTemplateV2>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return const [];

    try {
      final values = jsonDecode(encoded) as List;
      return values
          .whereType<Map>()
          .map(
            (value) => DiaryMetadataTemplateV2.fromJson(
              Map<String, Object?>.from(value),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(DiaryMetadataTemplateV2 template) async {
    final templates = (await load()).toList();
    final existingIndex = templates.indexWhere(
      (item) => item.id == template.id,
    );
    if (existingIndex == -1) {
      templates.add(template);
    } else {
      templates[existingIndex] = template;
    }
    await _write(templates);
  }

  Future<void> delete(String id) async {
    final templates = (await load())
        .where((template) => template.id != id)
        .toList(growable: false);
    await _write(templates);
  }

  Future<void> _write(List<DiaryMetadataTemplateV2> templates) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(templates.map((template) => template.toJson()).toList()),
    );
  }
}
