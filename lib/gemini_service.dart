// file: lib/gemini_service.dart

import 'package:firebase_vertexai/firebase_vertexai.dart'; // 1. 导入新的包
import 'diary_service.dart';

class GeminiService {
  // 2. 不需要API Key了，Firebase会自动处理认证

  // 3. 使用新的 Content.system() 来定义系统指令
  static final _diaryAnalystPrompt = Content.system(
      '你是一位专业的日记分析师。你的任务是基于用户提供的日记内容，进行全面且富有同理心的分析。请遵循以下规则：'
          '1. **总结核心事件**: 简洁地总结日记中记录的主要事件或活动。'
          '2. **情感洞察**: 分析字里行间流露出的情绪，无论是积极的、消极的还是复杂的，并进行描述。'
          '3. **发现闪光点**: 即使在平淡或负面的记录中，也要努力发现积极的、有价值的或值得肯定的闪光点。'
          '4. **提出开放式问题**: 提出1-2个温和的、引导性的开放式问题，鼓励用户进行更深入的思考。'
          '5. **输出格式**: 请以 Markdown 格式返回你的分析，并使用清晰的标题（例如：## 今日回顾, ## 情绪洞察, ## 闪光时刻, ## 一点思考）。');

  static final _psychologicalAnalystPrompt = Content.system(
      '你是一个AI心理分析助手，基于认知行为理论(CBT)为用户提供初步的思维模式分析。你的回答必须遵循严格的道德和安全准则：'
          '1. **安全声明**: 在回答的【最开始】，必须包含免责声明：“重要提示：我是一个AI模型，无法提供专业的心理咨询或治疗。以下分析仅供参考，不能替代专业人士的建议。如果您感到困扰，请寻求专业心理帮助。”'
          '2. **识别思维模式**: 根据日记内容，识别出可能的非适应性思维模式（例如：灾难化思维、非黑即白、过度概括等），并用通俗的语言解释。'
          '3. **提供积极视角**: 针对识别出的思维模式，提供一个或多个更平衡、更具建设性的视角或思维方式作为参考。'
          '4. **保持中立和支持**: 你的语气必须是中立、支持性和非评判性的。'
          '5. **绝不诊断**: 严禁使用任何诊断性术语或做出任何形式的心理健康诊断。'
          '6. **输出格式**: 以 Markdown 格式返回，并使用清晰的标题（例如：## 免责声明, ## 思维模式观察, ## 换个角度看）。');

  Future<String?> getDiaryAnalysis(DiaryEntry entry) async {
    return _generateContent(
      systemPrompt: _diaryAnalystPrompt,
      userContent: '这是我的日记内容：\n\n${entry.text}',
    );
  }

  Future<String?> getPsychologicalAnalysis(DiaryEntry entry) async {
    return _generateContent(
      systemPrompt: _psychologicalAnalystPrompt,
      userContent: '请帮我分析这篇日记中的思维模式：\n\n${entry.text}',
    );
  }

  // 核心生成函数
  Future<String?> _generateContent({
    required Content systemPrompt,
    required String userContent,
  }) async {
    try {
      // 4. 使用新的方式初始化模型
      final model = FirebaseVertexAI.instance.generativeModel(
        model: 'gemini-1.5-flash-latest', // 同样先用Flash模型测试
        systemInstruction: systemPrompt,
      );

      final response = await model.generateContent([
        Content.text(userContent),
      ]);

      return response.text;
    } catch (e) {
      print('Firebase VertexAI 调用失败: $e');
      return '分析失败，请稍后再试。可能是您的 Firebase 项目未正确配置或服务暂时不可用。';
    }
  }
}