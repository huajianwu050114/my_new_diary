import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_new_diary/features/diary/presentation/widgets/diary_rich_text_v2.dart';

void main() {
  test('legacy text and photos become one ordered rich document', () {
    final document = diaryDocumentFromContent(
      plainText: '第一段\n第二段',
      trailingImageIds: const ['photo-1', 'photo-2'],
    );

    expect(diaryPlainText(document), '第一段\n第二段');
    expect(diaryImageIds(document), ['photo-1', 'photo-2']);
  });

  test('delta keeps formatting and inline image positions across reloads', () {
    final controller = QuillController.basic();
    controller
      ..replaceText(0, 0, '图片之前\n', const TextSelection.collapsed(offset: 5))
      ..replaceText(
        5,
        0,
        BlockEmbed.image('inline-photo'),
        const TextSelection.collapsed(offset: 6),
      )
      ..replaceText(6, 0, '\n图片之后', const TextSelection.collapsed(offset: 11))
      ..formatText(0, 4, Attribute.bold);

    final encoded = encodeDiaryDocument(controller.document);
    final restored = diaryDocumentFromContent(deltaJson: encoded);

    expect(diaryPlainText(restored), '图片之前\n\n图片之后');
    expect(diaryImageIds(restored), ['inline-photo']);
    expect(restored.toDelta().toJson(), controller.document.toDelta().toJson());
    controller.dispose();
  });

  test('bold is stored for selected text and newly entered text', () {
    bool containsBoldText(QuillController controller) {
      return controller.document.toDelta().toJson().any((operation) {
        final attributes = operation['attributes'];
        return operation['insert'] == 'bold' &&
            attributes is Map &&
            attributes['bold'] == true;
      });
    }

    final selectedTextController = QuillController.basic();
    selectedTextController
      ..replaceText(
        0,
        0,
        'plain bold',
        const TextSelection.collapsed(offset: 10),
      )
      ..updateSelection(
        const TextSelection(baseOffset: 6, extentOffset: 10),
        ChangeSource.local,
      )
      ..formatSelection(Attribute.bold);

    expect(containsBoldText(selectedTextController), isTrue);

    final newlyEnteredTextController = QuillController.basic();
    newlyEnteredTextController
      ..formatSelection(Attribute.bold)
      ..replaceText(0, 0, 'bold', const TextSelection.collapsed(offset: 4));

    expect(containsBoldText(newlyEnteredTextController), isTrue);

    selectedTextController.dispose();
    newlyEnteredTextController.dispose();
  });
}
