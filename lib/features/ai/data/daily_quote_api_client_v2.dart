import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/daily_encouragement_v2.dart';

class DailyQuoteApiClientV2 {
  DailyQuoteApiClientV2({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<DailyEncouragementDraftV2> fetch({
    required String dateKey,
    required List<String> recentTexts,
  }) async {
    final recent = recentTexts.map(_normalized).toSet();
    try {
      final value = await _fromHitokoto();
      if (!recent.contains(_normalized(value.text))) return value;
    } catch (_) {
      // A deterministic non-poetry line is used when the remote source is
      // unavailable or returns an unsuitable sentence.
    }
    return _offlineQuote(dateKey, recent);
  }

  Future<DailyEncouragementDraftV2> _fromHitokoto() async {
    final response = await _httpClient
        .get(
          Uri.parse(
            'https://v1.hitokoto.cn/?c=d&c=e&c=f&c=k&max_length=70&encode=json',
          ),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      throw http.ClientException('一言返回 ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map) throw const FormatException('一言响应格式错误');
    if (json['type'] == 'i') throw const FormatException('忽略诗词内容');
    final text = _requiredText(json['hitokoto']);
    final uuid = _optionalText(json['uuid']);
    final namedAuthor = _optionalText(json['from_who']);
    final source = _optionalText(json['from']);
    return DailyEncouragementDraftV2(
      text: text,
      author: namedAuthor ?? source,
      work: namedAuthor != null && source != namedAuthor ? source : null,
      provider: '一言',
      sourceUrl: uuid == null
          ? 'https://hitokoto.cn'
          : 'https://hitokoto.cn?uuid=$uuid',
    );
  }

  DailyEncouragementDraftV2 _offlineQuote(String dateKey, Set<String> recent) {
    final start = _stableIndex(dateKey, _offlineQuotes.length);
    for (var offset = 0; offset < _offlineQuotes.length; offset++) {
      final value = _offlineQuotes[(start + offset) % _offlineQuotes.length];
      if (!recent.contains(_normalized(value.text))) return value;
    }
    return _offlineQuotes[start];
  }

  static String _requiredText(Object? value) {
    final text = _optionalText(value);
    if (text == null || text.length > 160 || !_containsChinese(text)) {
      throw const FormatException('句子内容为空、过长或不是中文');
    }
    return text;
  }

  static String? _optionalText(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String _normalized(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), '');

  static bool _containsChinese(String value) =>
      RegExp(r'[\u3400-\u9fff]').hasMatch(value);

  static int _stableIndex(String value, int length) =>
      value.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % length;

  static const _offlineQuotes = [
    DailyEncouragementDraftV2(text: '先把今天过好，不急着一次想明白整个人生。'),
    DailyEncouragementDraftV2(text: '允许事情慢一点，也允许自己暂时没有答案。'),
    DailyEncouragementDraftV2(text: '认真生活不一定声势浩大，也可以只是按时吃饭和好好睡觉。'),
    DailyEncouragementDraftV2(text: '注意力放在哪里，日子就会在哪里慢慢长出形状。'),
    DailyEncouragementDraftV2(text: '不必把每一天都过成转折点，平常本身就值得记录。'),
    DailyEncouragementDraftV2(text: '能清楚地感受到自己，也是一种稳稳的前进。'),
    DailyEncouragementDraftV2(text: '先完成眼前这一小步，剩下的路会在行动里变清楚。'),
    DailyEncouragementDraftV2(text: '休息不是偏离生活，而是生活本来就有的一部分。'),
  ];
}
