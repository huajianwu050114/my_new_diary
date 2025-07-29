// file: lib/gemini_service_local.dart

import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiServiceLocal {
  static const _apiKey = String.fromEnvironment('API_KEY');

  /// 核心方法：接收对话历史，返回AI的回复和思考时长
  Future<(String?, Duration)> generateResponse(List<Content> history) async {
    if (_apiKey.isEmpty) {
      return ('错误：API Key 未配置。', Duration.zero);
    }
    if (history.isEmpty) {
      return ('错误：无法凭空开始对话。', Duration.zero);
    }

    final stopwatch = Stopwatch()..start(); // 开始计时

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-pro',
        apiKey: _apiKey,
      );

      final response = await model.generateContent(history);
      stopwatch.stop(); // 停止计时
      return (response.text, stopwatch.elapsed);
    } catch (e) {
      stopwatch.stop();
      print('Gemini API call failed: $e');
      if (e.toString().contains('quota')) {
        return ('您已超出当前的使用配额，请检查您的套餐和结算详情。', stopwatch.elapsed);
      }
      return ('对话失败，请检查网络或重试。\n错误: $e', stopwatch.elapsed);
    }
  }
}