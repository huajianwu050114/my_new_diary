// file: lib/gemini_service_local.dart

import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/widgets.dart'; //
import 'package:provider/provider.dart';
import 'ai_model_service.dart';

class GeminiServiceLocal {
  //static const _apiKey = String.fromEnvironment('API_KEY');
  static const _apiKey = 'AIzaSyC3U9eB_VwvfbybGT6OCRe0ZIOEC22Tu6s';

  /// 核心方法：接收对话历史，返回AI的回复和思考时长
  Future<(String?, Duration)> generateResponse(
      List<Content> history, {
        required String modelName, // 1. 参数改为必须传入一个明确的模型名称
      }) async {
    if (_apiKey.isEmpty) {
      return ('错误：API Key 未配置。', Duration.zero);
    }
    if (history.isEmpty) {
      return ('错误：无法凭空开始对话。', Duration.zero);
    }

    final stopwatch = Stopwatch()..start();

    try {
      final model = GenerativeModel(
        model: modelName, // 2. 直接使用传入的模型名称
        apiKey: _apiKey,
      );


      final response = await model.generateContent(history).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('AI响应超时（超过30秒），请检查网络或稍后重试。');
        },
      );

      stopwatch.stop();
      return (response.text, stopwatch.elapsed);

    } catch (e) {
      stopwatch.stop();
      print('Gemini API call failed ($modelName): ${e.runtimeType} - $e');

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