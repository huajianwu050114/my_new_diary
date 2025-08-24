// file: libs/gemini_service_local.dart

import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'ai_model_service.dart';

class GeminiServiceLocal {
  static const _apiKey = 'AIzaSyC3U9eB_VwvfbybGT6OCRe0ZIOEC22Tu6s';

  Future<(String?, Duration)> generateResponse(
      List<Content> history, {
        required String modelName,
      }) async {
    if (_apiKey.isEmpty) {
      return ('错误：API Key 未配置。', Duration.zero);
    }

    // VVVV  【关键调试代码】 VVVV
    // 在调用API之前，打印出准备发送的所有内容
    debugPrint("----------- DEBUG: DATA SENT TO GEMINI API -----------");
    debugPrint("Model Name: $modelName");
    if (history.isEmpty) {
      debugPrint("History is EMPTY!");
    } else {
      for (int i = 0; i < history.length; i++) {
        final content = history[i];
        final textParts = content.parts.whereType<TextPart>().map((p) => p.text).join('');
        debugPrint("Item ${i + 1} |  Role: '${content.role}' | Content: '$textParts'");
      }
    }
    debugPrint("-------------------- END DEBUG --------------------");
    // ^^^^  【关键调试代码】 ^^^^

    final stopwatch = Stopwatch()..start();

    try {
      final model = GenerativeModel(
        model: modelName,
        apiKey: _apiKey,
      );
      final response = await model.generateContent(history).timeout(
        const Duration(seconds: 50),
        onTimeout: () {
          throw TimeoutException('AI响应超时（超过50秒），请检查网络或稍后重试。');
        },
      );
      stopwatch.stop();
      return (response.text, stopwatch.elapsed);

    } catch (e) {
      stopwatch.stop();
      debugPrint('Gemini API call failed ($modelName): ${e.runtimeType} - $e');

      if (e is TimeoutException) {
        return (e.message, stopwatch.elapsed);
      }
      if (e.toString().contains('quota')) {
        return ('您已超出当前的使用配额，请检查您的套餐和结算详情。', stopwatch.elapsed);
      }
      return ('对话失败，请检查网络或重试。\n错误: $e', stopwatch.elapsed);
    }
  }
}