import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/daily_encouragement_v2.dart';

enum DailyQuoteProviderV2 { hitokoto, jinrishici }

class DailyQuoteApiClientV2 {
  DailyQuoteApiClientV2({
    http.Client? httpClient,
    List<DailyQuoteProviderV2>? providerOrder,
  }) : _httpClient = httpClient ?? http.Client(),
       _providerOrder = providerOrder;

  final http.Client _httpClient;
  final List<DailyQuoteProviderV2>? _providerOrder;

  Future<DailyEncouragementDraftV2> fetch({
    required String dateKey,
    required List<String> recentTexts,
  }) async {
    final providers =
        _providerOrder ??
        (_stableIndex(dateKey, 2) == 0
            ? const [
                DailyQuoteProviderV2.jinrishici,
                DailyQuoteProviderV2.hitokoto,
              ]
            : const [
                DailyQuoteProviderV2.hitokoto,
                DailyQuoteProviderV2.jinrishici,
              ]);
    final recent = recentTexts.map(_normalized).toSet();
    for (final provider in providers) {
      try {
        final value = switch (provider) {
          DailyQuoteProviderV2.hitokoto => await _fromHitokoto(),
          DailyQuoteProviderV2.jinrishici => await _fromJinrishici(),
        };
        if (!recent.contains(_normalized(value.text))) return value;
      } catch (_) {
        // Continue to the next source. A deterministic offline line is used
        // after every remote source has failed.
      }
    }
    return _offlineQuote(dateKey, recent);
  }

  Future<DailyEncouragementDraftV2> _fromHitokoto() async {
    final response = await _httpClient
        .get(
          Uri.parse(
            'https://v1.hitokoto.cn/?c=d&c=i&c=k&max_length=70&encode=json',
          ),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      throw http.ClientException('一言返回 ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map) throw const FormatException('一言响应格式错误');
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

  Future<DailyEncouragementDraftV2> _fromJinrishici() async {
    final response = await _httpClient
        .get(
          Uri.parse('https://v1.jinrishici.com/all.json'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      throw http.ClientException('今日诗词返回 ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map) throw const FormatException('今日诗词响应格式错误');
    return DailyEncouragementDraftV2(
      text: _requiredText(json['content']),
      author: _optionalText(json['author']),
      work: _optionalText(json['origin']),
      provider: '今日诗词',
      sourceUrl: 'https://www.jinrishici.com',
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
    DailyEncouragementDraftV2(text: '行到水穷处，坐看云起时。', author: '王维', work: '终南别业'),
    DailyEncouragementDraftV2(text: '及时当勉励，岁月不待人。', author: '陶渊明', work: '杂诗'),
    DailyEncouragementDraftV2(
      text: '纸上得来终觉浅，绝知此事要躬行。',
      author: '陆游',
      work: '冬夜读书示子聿',
    ),
    DailyEncouragementDraftV2(
      text: '山重水复疑无路，柳暗花明又一村。',
      author: '陆游',
      work: '游山西村',
    ),
    DailyEncouragementDraftV2(
      text: '不畏浮云遮望眼，自缘身在最高层。',
      author: '王安石',
      work: '登飞来峰',
    ),
    DailyEncouragementDraftV2(text: '静以修身，俭以养德。', author: '诸葛亮', work: '诫子书'),
    DailyEncouragementDraftV2(text: '一蓑烟雨任平生。', author: '苏轼', work: '定风波'),
    DailyEncouragementDraftV2(
      text: '长风破浪会有时，直挂云帆济沧海。',
      author: '李白',
      work: '行路难',
    ),
  ];
}
