import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/diary/presentation/pages/voice_diary_page_v2.dart';

void main() {
  testWidgets('只保留输入法文字输入和 AI 润色入口', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: VoiceDiaryPageV2(initialText: '已有草稿')),
    );
    await tester.pump();

    expect(find.textContaining('搜狗输入法'), findsOneWidget);
    expect(find.text('AI 轻度润色'), findsOneWidget);
    expect(find.text('使用文字草稿'), findsOneWidget);
    expect(find.text('重新转写'), findsNothing);
    expect(find.text('开始实时听写'), findsNothing);
    expect(find.text('百度语音配置'), findsNothing);

    final field = tester.widget<TextField>(
      find.byKey(const Key('voice_transcript_field')),
    );
    expect(field.controller!.text, '已有草稿');
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('文字草稿可以返回日记编辑页', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const VoiceDiaryPageV2()),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('voice_transcript_field')),
      '今天用搜狗说了一段日记。',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('使用文字草稿'));
    await tester.tap(find.text('使用文字草稿'));
    await tester.pumpAndSettle();

    expect(result, '今天用搜狗说了一段日记。');
  });
}
