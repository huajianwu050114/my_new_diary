import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:uuid/uuid.dart';

class Conversation {
  final String id;
  String title;
  final List<Content> history;

  Conversation({required this.id, required this.title, required this.history});

  // 从 Map 创建 Conversation
  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String? ?? const Uuid().v4(),
      title: json['title'] as String? ?? '新对话',
      history: (json['history'] as List<dynamic>? ?? [])
          .map((item) => _contentFromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  // 将 Conversation 转换为 Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'history': history.map((c) => _contentToJson(c)).toList(),
    };
  }
}

Map<String, dynamic> _contentToJson(Content content) {
  return {
    'role': content.role,
    'parts': content.parts.map((part) {
      if (part is TextPart) {
        return {'type': 'text', 'text': part.text};
      }
      // 可以根据需要在这里添加对其他 Part 类型的处理
      return {};
    }).toList(),
  };
}

// VVV 2. 手动添加的辅助函数，用于反序列化 Content VVV
Content _contentFromJson(Map<String, dynamic> json) {
  final role = json['role'] as String?;

  // --- 关键修正 ---
  // 1. 安全地获取 parts 列表，如果不存在则默认为一个空列表
  final partsList = json['parts'] as List<dynamic>? ?? [];

  // 2. 在安全的列表上进行 map 操作
  final parts = partsList.map((partJson) {
    final partMap = partJson as Map<String, dynamic>;
    if (partMap['type'] == 'text') {
      // 确保 text 字段也安全地处理
      return TextPart(partMap['text'] as String? ?? '');
    }
    return TextPart('');
  }).toList();

  return Content(role ?? 'model', parts);
}

class DiaryEntry {
  final String diaryId;
  final String text;
  final DateTime date;
  final DateTime creationTime;
  final DateTime? lastModifiedTime;
  final String? mood;
  final String? address;
  final double? latitude;
  final double? longitude;
  final List<String> imagePaths;
  final List<String> tags;
  final List<String> aiAnalyses;
  final List<Conversation> conversations;
  final bool isDeleted;

  DiaryEntry({
    required this.diaryId,
    required this.text,
    required this.date,
    required this.creationTime,
    this.lastModifiedTime,
    this.mood,
    this.address,
    this.latitude,
    this.longitude,
    this.imagePaths = const [],
    this.tags = const [],
    this.aiAnalyses = const [],
    this.conversations = const [],
    this.isDeleted = false,
  });

  DiaryEntry copyWith({
    String? diaryId,
    String? text,
    DateTime? date,
    DateTime? creationTime,
    DateTime? lastModifiedTime,
    String? mood,
    String? address,
    double? latitude,
    double? longitude,
    List<String>? imagePaths,
    List<String>? tags,
    List<String>? aiAnalyses,
    List<Conversation>? conversations,
    bool? isDeleted,
  }) {
    return DiaryEntry(
      diaryId: diaryId ?? this.diaryId,
      text: text ?? this.text,
      date: date ?? this.date,
      creationTime: creationTime ?? this.creationTime,
      lastModifiedTime: lastModifiedTime ?? this.lastModifiedTime,
      mood: mood ?? this.mood,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imagePaths: imagePaths ?? this.imagePaths,
      tags: tags ?? this.tags,
      aiAnalyses: aiAnalyses ?? this.aiAnalyses,
      conversations: conversations ?? this.conversations,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  // 从数据库的 Map 记录创建 DiaryEntry 对象
  factory DiaryEntry.fromMap(Map<String, dynamic> map) {
    return DiaryEntry(
      diaryId: map['diaryId'],
      text: map['text'],
      date: DateTime.parse(map['date']),
      creationTime: DateTime.parse(map['creationTime']),
      lastModifiedTime: map['lastModifiedTime'] != null ? DateTime.parse(map['lastModifiedTime']) : null,
      mood: map['mood'],
      address: map['address'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      imagePaths: (jsonDecode(map['imagePaths']) as List<dynamic>).cast<String>(),
      tags: (jsonDecode(map['tags']) as List<dynamic>).cast<String>(),
      aiAnalyses: (jsonDecode(map['aiAnalyses']) as List<dynamic>).cast<String>(),
      conversations: (jsonDecode(map['conversations']) as List<dynamic>).map((c) => Conversation.fromJson(c)).toList(),
      isDeleted: map['isDeleted'] == 1,
    );
  }

  // 将 DiaryEntry 对象转换为用于数据库的 Map
  Map<String, dynamic> toMap() {
    return {
      'diaryId': diaryId,
      'text': text,
      'date': date.toIso8601String(),
      'creationTime': creationTime.toIso8601String(),
      'lastModifiedTime': lastModifiedTime?.toIso8601String(),
      'mood': mood,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'imagePaths': jsonEncode(imagePaths),
      'tags': jsonEncode(tags),
      'aiAnalyses': jsonEncode(aiAnalyses),
      'conversations': jsonEncode(conversations.map((c) => c.toJson()).toList()),
      'isDeleted': isDeleted ? 1 : 0,
    };
  }
}