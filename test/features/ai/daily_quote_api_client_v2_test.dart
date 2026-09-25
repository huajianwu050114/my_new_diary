import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:my_new_diary/features/ai/data/daily_quote_api_client_v2.dart';

void main() {
  test('parses a Hitokoto quote with attribution and source link', () async {
    late Uri requestedUri;
    final client = DailyQuoteApiClientV2(
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'hitokoto': '生活最佳状态是冷冷清清地风风火火。',
              'type': 'd',
              'from_who': '木心',
              'from': '云雀叫了一整天',
              'uuid': 'quote-id',
            }),
          ),
          200,
        );
      }),
    );

    final quote = await client.fetch(dateKey: '2026-09-25', recentTexts: []);

    expect(quote.text, '生活最佳状态是冷冷清清地风风火火。');
    expect(quote.author, '木心');
    expect(quote.work, '云雀叫了一整天');
    expect(quote.provider, '一言');
    expect(quote.sourceUrl, 'https://hitokoto.cn?uuid=quote-id');
    expect(
      requestedUri.queryParametersAll['c'],
      containsAll(['d', 'e', 'f', 'k']),
    );
    expect(requestedUri.queryParametersAll['c'], isNot(contains('i')));
  });

  test('rejects a poetry response even if the API returns one', () async {
    final client = DailyQuoteApiClientV2(
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'hitokoto': '行到水穷处，坐看云起时。', 'type': 'i'})),
          200,
        ),
      ),
    );

    final quote = await client.fetch(dateKey: '2026-09-25', recentTexts: []);

    expect(quote.text, isNot('行到水穷处，坐看云起时。'));
    expect(quote.provider, isNull);
  });

  test('uses a non-poetry offline line for a non-Chinese result', () async {
    final client = DailyQuoteApiClientV2(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'hitokoto': 'Stay hungry, stay foolish.', 'type': 'k'}),
          200,
        ),
      ),
    );

    final quote = await client.fetch(dateKey: '2026-09-26', recentTexts: []);

    expect(quote.text, isNot('Stay hungry, stay foolish.'));
    expect(quote.provider, isNull);
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
    expect(first.provider, isNull);
  });
}
