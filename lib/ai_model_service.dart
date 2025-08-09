// file: lib/ai_model_service.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1. 定义App中所有使用AI的“功能板块”
enum AiFeature {
  dailyInspiration, // 每日灵感
  weeklyLetter,     // 每周信件
  chat,             // AI聊天
  reflection,       // 时光回顾 (那年/那月/百日)
  diaryAnalysis,    // 日记保存时的初次分析
}

class AiModelService extends ChangeNotifier {
  // 2. 在这里列举您希望在App中使用的所有模型
  final List<String> availableModels = const [
    'gemini-2.5-flash',
    'gemini-2.5-pro',
    // 如果未来有其他模型，可以加在这里
  ];

  // 3. 存储每个功能的模型选择
  late Map<AiFeature, String> _modelSelections;

  AiModelService() {
    _modelSelections = {};
    loadModelSelections();
  }

  // 获取指定功能的模型
  String getModelFor(AiFeature feature) {
    // 如果用户没有设置过，则提供一个智能的默认值
    return _modelSelections[feature] ?? _getDefaultModelFor(feature);
  }

  // 为每个功能设置一个合理的默认模型
  String _getDefaultModelFor(AiFeature feature) {
    switch (feature) {
      case AiFeature.dailyInspiration:
        return 'gemini-2.5-flash'; // 每日灵感用快速模型
      case AiFeature.weeklyLetter:
      case AiFeature.chat:
      case AiFeature.reflection:
      case AiFeature.diaryAnalysis:
        return 'gemini-2.5-pro'; // 其他都用专业模型
    }
  }

  // 从本地存储加载用户的模型选择
  Future<void> loadModelSelections() async {
    final prefs = await SharedPreferences.getInstance();
    for (final feature in AiFeature.values) {
      final savedModel = prefs.getString('ai_model_for_${feature.name}');
      if (savedModel != null && availableModels.contains(savedModel)) {
        _modelSelections[feature] = savedModel;
      }
    }
    notifyListeners();
  }

  // 更新并保存一个功能的模型选择
  Future<void> setModelFor(AiFeature feature, String modelName) async {
    if (!availableModels.contains(modelName)) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_model_for_${feature.name}', modelName);
    _modelSelections[feature] = modelName;
    notifyListeners();
  }
}