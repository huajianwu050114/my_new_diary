import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:my_new_diary/features/ai/data/daily_quote_api_client_v2.dart';

void main() {
  test('parses a Hitokoto quote with attribution and source link', () async {
    final client = DailyQuoteApiClientV2(
      providerOrder: const [DailyQuoteProviderV2.hitokoto],
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'hitokoto': '生活最佳状态是冷冷清清地风风火火。',
              'from_who': '木心',
              'from': '云雀叫了一整天',
              'uuid': 'quote-id',
            }),
          ),
          200,
        ),
      ),
    );

    final quote = await client.fetch(dateKey: '2026-09-25', recentTexts: []);

    expect(quote.text, '生活最佳状态是冷冷清清地风风火火。');
    expect(quote.author, '木心');
    expect(quote.work, '云雀叫了一整天');
    expect(quote.provider, '一言');
    expect(quote.sourceUrl, 'https://hitokoto.cn?uuid=quote-id');
  });

  test('parses a Jinrishici quote with author and work', () async {
    final client = DailyQuoteApiClientV2(
      providerOrder: const [DailyQuoteProviderV2.jinrishici],
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'content': '行到水穷处，坐看云起时。',
              'author': '王维',
              'origin': '终南别业',
            }),
          ),
          200,
        ),
      ),
    );

    final quote = await client.fetch(dateKey: '2026-09-25', recentTexts: []);

    expect(quote.text, '行到水穷处，坐看云起时。');
    expect(quote.author, '王维');
    expect(quote.work, '终南别业');
    expect(quote.provider, '今日诗词');
  });

  test('skips a non-Chinese result and tries the next provider', () async {
    final client = DailyQuoteApiClientV2(
      providerOrder: const [
        DailyQuoteProviderV2.hitokoto,
        DailyQuoteProviderV2.jinrishici,
      ],
      httpClient: MockClient((request) async {
        if (request.url.host == 'v1.hitokoto.cn') {
          return http.Response(
            jsonEncode({'hitokoto': 'Stay hungry, stay foolish.'}),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'content': '人闲桂花落，夜静春山空。',
              'author': '王维',
              'origin': '鸟鸣涧',
            }),
          ),
          200,
        );
      }),
    );

    final quote = await client.fetch(dateKey: '2026-09-26', recentTexts: []);

    expect(quote.text, '人闲桂花落，夜静春山空。');
    expect(quote.provider, '今日诗词');
  });

  test('uses a dated offline quote when every API is unavailable', () async {
    final client = DailyQuoteApiClientV2(
      httpClient: MockClient((_) async => http.Response('unavailable', 503)),
    );

    final first = await client.fetch(
      dateKey: '2026-09-25',
      recentTexts: const [],
    );
    final second = await client.fetch(
      dateKey: '2026-09-25',
      recentTexts: const [],
    );

    expect(first.text, isNotEmpty);
    expect(first.text, second.text);
    expect(first.author, isNotEmpty);
  });
}
