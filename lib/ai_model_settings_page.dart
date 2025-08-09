// file: lib/ai_model_settings_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ai_model_service.dart';

class AiModelSettingsPage extends StatelessWidget {
  const AiModelSettingsPage({super.key});

  String _getFeatureName(AiFeature feature) {
    switch (feature) {
      case AiFeature.dailyInspiration: return '每日灵感';
      case AiFeature.weeklyLetter: return '每周信件';
      case AiFeature.chat: return 'AI聊天';
      case AiFeature.reflection: return '时光回顾';
      case AiFeature.diaryAnalysis: return '日记初次分析';
    }
  }

  String _getFeatureDescription(AiFeature feature) {
    switch (feature) {
      case AiFeature.dailyInspiration: return '用于在主页生成快速的写作提示。';
      case AiFeature.weeklyLetter: return '用于撰写总结性的每周信件。';
      case AiFeature.chat: return '用于您与AI的实时深入对话。';
      case AiFeature.reflection: return '用于生成“那年今日”等历史回顾。';
      case AiFeature.diaryAnalysis: return '用于保存日记时，生成摘要和问题。';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI模型配置'),
      ),
      body: Consumer<AiModelService>(
        builder: (context, modelService, child) {
          return ListView(
            children: AiFeature.values.map((feature) {
              return ListTile(
                title: Text(_getFeatureName(feature)),
                subtitle: Text(_getFeatureDescription(feature)),
                trailing: DropdownButton<String>(
                  value: modelService.getModelFor(feature),
                  items: modelService.availableModels.map((String model) {
                    return DropdownMenuItem<String>(
                      value: model,
                      child: Text(
                        model.replaceAll('-latest', '').replaceAll('gemini-2.5-', ''),
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newModel) {
                    if (newModel != null) {
                      modelService.setModelFor(feature, newModel);
                    }
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}