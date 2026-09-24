import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../application/ports/diary_image_store_v2.dart';

Document diaryDocumentFromContent({
  String? deltaJson,
  String plainText = '',
  List<String> trailingImageIds = const [],
}) {
  if (deltaJson != null && deltaJson.trim().isNotEmpty) {
    try {
      final value = jsonDecode(deltaJson);
      if (value is List) {
        return Document.fromJson(value);
      }
    } catch (_) {
      // Fall through to the legacy plain-text representation.
    }
  }

  final delta = Delta();
  if (plainText.isNotEmpty) {
    delta.insert(plainText);
  }
  delta.insert('\n');
  for (final imageId in trailingImageIds) {
    delta
      ..insert(BlockEmbed.image(imageId).toJson())
      ..insert('\n');
  }
  return Document.fromDelta(delta);
}

String encodeDiaryDocument(Document document) =>
    jsonEncode(document.toDelta().toJson());

String diaryPlainText(Document document) {
  final buffer = StringBuffer();
  for (final operation in document.toDelta().operations) {
    final data = operation.data;
    if (data is String) buffer.write(data);
  }
  return buffer.toString().trim();
}

List<String> diaryImageIds(Document document) {
  final ids = <String>[];
  for (final operation in document.toDelta().operations) {
    final data = operation.data;
    if (data is! Map) continue;
    final imageId = data[BlockEmbed.imageType];
    if (imageId is String) {
      if (imageId.isNotEmpty && !ids.contains(imageId)) ids.add(imageId);
    }
  }
  return ids;
}

DefaultStyles quietDiaryStyles(BuildContext context) {
  final defaults = DefaultStyles.getInstance(context);
  TextStyle textStyle(
    DefaultTextBlockStyle? block, {
    required double size,
    required double height,
    FontWeight? weight,
  }) => (block?.style ?? const TextStyle()).copyWith(
    fontFamily: 'MiSans',
    fontSize: size,
    height: height,
    fontWeight: weight,
    color: Theme.of(context).colorScheme.onSurface,
  );

  return DefaultStyles(
    paragraph: defaults.paragraph?.copyWith(
      style: textStyle(defaults.paragraph, size: 17, height: 1.68),
    ),
    h1: defaults.h1?.copyWith(
      style: textStyle(
        defaults.h1,
        size: 28,
        height: 1.32,
        weight: FontWeight.w600,
      ),
    ),
    h2: defaults.h2?.copyWith(
      style: textStyle(
        defaults.h2,
        size: 22,
        height: 1.42,
        weight: FontWeight.w600,
      ),
    ),
    h3: defaults.h3?.copyWith(
      style: textStyle(
        defaults.h3,
        size: 19,
        height: 1.5,
        weight: FontWeight.w600,
      ),
    ),
    quote: defaults.quote?.copyWith(
      style: textStyle(
        defaults.quote,
        size: 17,
        height: 1.62,
      ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
    placeHolder: defaults.placeHolder?.copyWith(
      style: textStyle(
        defaults.placeHolder,
        size: 17,
        height: 1.68,
      ).copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class DiaryRichTextViewV2 extends StatefulWidget {
  const DiaryRichTextViewV2({
    required this.deltaJson,
    required this.imageStore,
    super.key,
  });

  final String deltaJson;
  final DiaryImageStoreV2 imageStore;

  @override
  State<DiaryRichTextViewV2> createState() => _DiaryRichTextViewV2State();
}

class _DiaryRichTextViewV2State extends State<DiaryRichTextViewV2> {
  late QuillController _controller;
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  @override
  void didUpdateWidget(covariant DiaryRichTextViewV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deltaJson == widget.deltaJson) return;
    _controller.dispose();
    _controller = _createController();
  }

  QuillController _createController() => QuillController(
    document: diaryDocumentFromContent(deltaJson: widget.deltaJson),
    selection: const TextSelection.collapsed(offset: 0),
    readOnly: true,
  );

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QuillEditor.basic(
      controller: _controller,
      focusNode: _focusNode,
      scrollController: _scrollController,
      config: QuillEditorConfig(
        scrollable: false,
        padding: EdgeInsets.zero,
        customStyles: quietDiaryStyles(context),
        enableInteractiveSelection: true,
        embedBuilders: [
          DiaryImageEmbedBuilderV2(imageStore: widget.imageStore),
        ],
      ),
    );
  }
}

class DiaryImageEmbedBuilderV2 extends EmbedBuilder {
  const DiaryImageEmbedBuilderV2({required this.imageStore});

  final DiaryImageStoreV2 imageStore;

  @override
  String get key => BlockEmbed.imageType;

  @override
  bool get expanded => false;

  @override
  String toPlainText(Embed node) => '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final imageId = embedContext.node.value.data;
    if (imageId is! String || imageId.isEmpty) {
      return const _MissingDiaryImage();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: FutureBuilder(
        future: imageStore.read(imageId),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) return const _MissingDiaryImage();
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: Image.memory(
                bytes,
                width: double.infinity,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MissingDiaryImage extends StatelessWidget {
  const _MissingDiaryImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
