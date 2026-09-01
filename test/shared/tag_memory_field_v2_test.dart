import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/shared/tag_memory_field_v2.dart';

void main() {
  testWidgets('可以选择和取消历史标签，同时保留新标签输入', (tester) async {
    final controller = TextEditingController(text: '新标签');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TagMemoryFieldV2(
            controller: controller,
            suggestions: const ['生活', '工作', '生活'],
          ),
        ),
      ),
    );

    expect(find.text('以前用过'), findsOneWidget);
    expect(find.text('生活'), findsOneWidget);
    await tester.tap(find.text('生活'));
    await tester.pump();
    expect(controller.text, contains('新标签'));
    expect(controller.text, contains('生活'));

    await tester.tap(find.text('生活'));
    await tester.pump();
    expect(controller.text, '新标签');
  });
}
