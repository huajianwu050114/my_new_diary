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

// 文件位置: lib/diary_model.dart

Map<String, dynamic> _contentToJson(Content content) {
  return {
    'role': content.role,
    // VVVV 核心修改：确保只处理 TextPart，并过滤掉其他类型 VVVV
    'parts': content.parts
        .whereType<TextPart>() // 只选择类型为 TextPart 的部分
        .map((part) => {'type': 'text', 'text': part.text})
        .toList(),
  };
}

// VVV 2. 手动添加的辅助函数，用于反序列化 Content VVV
// 文件位置: lib/diary_model.dart

// file: lib/diary_model.dart

// VVVV  用下面这个更健壮的版本替换掉原来的 _contentFromJson 函数 VVVV
Content _contentFromJson(Map<String, dynamic> json) {
  final role = json['role'] as String?;
  final partsList = json['parts'] as List<dynamic>? ?? [];

  // 1. 先像原来一样解析出所有的 part
  final parts = partsList.map((partJson) {
    final partMap = partJson as Map<String, dynamic>;
    if (partMap['type'] == 'text') {
      return TextPart(partMap['text'] as String? ?? '');
    }
    // 对于未知类型，暂时也返回一个空的 TextPart
    return TextPart('');
  }).toList();

  // 2.【关键修正】过滤掉所有内容为空的 TextPart
  final validParts = parts.where((p) {
    if (p is TextPart) {
      return p.text.isNotEmpty; // 只保留文本不为空的 TextPart
    }
    return true; // 保留其他类型的 part (如果未来支持的话)
  }).toList();

  // 3. 使用过滤后的 validParts 列表来判断
  if (validParts.isNotEmpty) {
    // 只有在存在有效内容时，才创建 Content 对象
    return Content(role ?? 'user', validParts);
  } else {
    // 如果过滤后列表为空（说明原始数据是空的或无效的），
    // 则返回一个无害的、空的 user 消息，这可以避免API调用失败，
    // 并且不会因为插入一个空的 model 消息而打乱对话顺序。
    return Content('user', [TextPart('')]);
  }
}


class AiMetadata {
  final List<String> suggestedTitles;
  final String? summary;
  final String? detectedEmotion;
  final List<String> detectedThemes;
  final String? proactiveQuestion;

  AiMetadata({
    this.suggestedTitles = const [],
    this.summary,
    this.detectedEmotion,
    this.detectedThemes = const [],
    this.proactiveQuestion,
  });

  // fromJson and toJson methods
  factory AiMetadata.fromJson(Map<String, dynamic> json) {
    return AiMetadata(
      suggestedTitles: List<String>.from(json['suggestedTitles'] ?? []),
      summary: json['summary'],
      detectedEmotion: json['detectedEmotion'],
      detectedThemes: List<String>.from(json['detectedThemes'] ?? []),
      proactiveQuestion: json['proactiveQuestion'],
    );
  }

  Map<String, dynamic> toJson() => {
    'suggestedTitles': suggestedTitles,
    'summary': summary,
    'detectedEmotion': detectedEmotion,
    'detectedThemes': detectedThemes,
    'proactiveQuestion': proactiveQuestion,
  };
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
  final AiMetadata? aiMetadata;
  final bool isPrivate; // VVVV  新增字段 VVVV
  final bool isSelfHelp;

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
    this.aiMetadata,
    this.isPrivate = false,
    this.isSelfHelp = false, // VVVV  在构造函数中添加，默认为 false VVVV
  });

  factory DiaryEntry.empty({required DateTime date}) {
    return DiaryEntry(
      diaryId: '',
      text: '',
      date: date,
      creationTime: DateTime.now(),
      imagePaths: [],
      tags: [],
      isPrivate: false,
    );
  }

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
    AiMetadata? aiMetadata,
    bool? isPrivate, // VVVV  在 copyWith 中添加 VVVV
    bool? isSelfHelp,
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
      aiMetadata: aiMetadata ?? this.aiMetadata,
      isPrivate: isPrivate ?? this.isPrivate, // VVVV  在 copyWith 中添加 VVVV
      isSelfHelp: isSelfHelp ?? this.isSelfHelp,
    );
  }

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
      aiMetadata: map['aiMetadata'] != null ? AiMetadata.fromJson(jsonDecode(map['aiMetadata'])) : null,
      isDeleted: map['isDeleted'] == 1,
      isPrivate: map['isPrivate'] == 1, // VVVV  从数据库读取 (1 代表 true, 0 代表 false) VVVV
      isSelfHelp: map['isSelfHelp'] == 1,
    );
  }

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
      'aiMetadata': aiMetadata != null ? jsonEncode(aiMetadata!.toJson()) : null,
      'isDeleted': isDeleted ? 1 : 0,
      'isPrivate': isPrivate ? 1 : 0, // VVVV  保存到数据库 (true 转为 1, false 转为 0) VVVV
      'isSelfHelp': isSelfHelp ? 1 : 0,
    };
  }
}