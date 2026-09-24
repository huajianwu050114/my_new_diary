import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../domain/life_document_repository_v2.dart';
import '../domain/life_document_v2.dart';
import '../domain/life_space_v2.dart';

class LifeDocumentEditorPageV2 extends StatefulWidget {
  const LifeDocumentEditorPageV2({
    required this.repository,
    required this.initialSpace,
    this.document,
    this.initialType = LifeDocumentTypeV2.note,
    this.initialMarkdown = '',
    super.key,
  });

  final LifeDocumentRepositoryV2 repository;
  final String initialSpace;
  final LifeDocumentV2? document;
  final LifeDocumentTypeV2 initialType;
  final String initialMarkdown;

  @override
  State<LifeDocumentEditorPageV2> createState() =>
      _LifeDocumentEditorPageV2State();
}

class _LifeDocumentEditorPageV2State extends State<LifeDocumentEditorPageV2> {
  late final TextEditingController _title;
  late final TextEditingController _markdown;
  late final TextEditingController _tags;
  late String _space;
  late LifeDocumentTypeV2 _type;
  DateTime? _documentDate;
  List<LifeSpaceV2> _spaces = const [];
  StreamSubscription<List<LifeSpaceV2>>? _spacesSubscription;
  bool _preview = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.document?.title ?? '');
    _markdown = TextEditingController(
      text: widget.document?.markdown ?? widget.initialMarkdown,
    );
    _tags = TextEditingController(text: widget.document?.tags.join('，') ?? '');
    _space = widget.document?.space ?? widget.initialSpace;
    _type = widget.document?.type ?? widget.initialType;
    _documentDate = widget.document?.documentDate?.toLocal();
    _spacesSubscription = widget.repository.watchSpaces().listen((spaces) {
      if (!mounted) return;
      setState(() => _spaces = spaces);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _markdown.dispose();
    _tags.dispose();
    _spacesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.document == null ? '新建生活文档' : '编辑文档'),
      actions: [
        IconButton(
          tooltip: '从剪贴板粘贴',
          onPressed: _paste,
          icon: const Icon(Icons.content_paste_rounded),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(
            labelText: '标题',
            prefixIcon: Icon(Icons.title_rounded),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _space,
                decoration: const InputDecoration(labelText: '分区'),
                items: _spaces
                    .map(
                      (space) => DropdownMenuItem(
                        value: space.id,
                        child: Text(space.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _space = value ?? _space),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<LifeDocumentTypeV2>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: '类型'),
                items: _availableTypes
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _type = value ?? _type),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tags,
          decoration: const InputDecoration(
            labelText: '标签（可选）',
            hintText: '旅行，待读，每周复盘',
            prefixIcon: Icon(Icons.tag_rounded),
          ),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: const Icon(Icons.event_outlined),
          title: Text(
            _documentDate == null
                ? '不安排日期'
                : DateFormat('yyyy年M月d日').format(_documentDate!),
          ),
          subtitle: const Text('设置后会在对应日期和“今天”中出现'),
          trailing: _documentDate == null
              ? const Icon(Icons.chevron_right_rounded)
              : IconButton(
                  tooltip: '清除日期',
                  onPressed: () => setState(() => _documentDate = null),
                  icon: const Icon(Icons.close_rounded),
                ),
          onTap: _pickDate,
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('编辑'),
              icon: Icon(Icons.edit_note_rounded),
            ),
            ButtonSegment(
              value: true,
              label: Text('预览'),
              icon: Icon(Icons.visibility_outlined),
            ),
          ],
          selected: {_preview},
          onSelectionChanged: (value) =>
              setState(() => _preview = value.single),
        ),
        const SizedBox(height: 12),
        if (_preview)
          Container(
            constraints: const BoxConstraints(minHeight: 360),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: AnimatedBuilder(
              animation: _markdown,
              builder: (context, _) =>
                  MarkdownBody(data: _markdown.text, selectable: true),
            ),
          )
        else
          TextField(
            controller: _markdown,
            minLines: 18,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontFamily: 'monospace', height: 1.5),
            decoration: const InputDecoration(
              hintText: '# 标题\n\n从这里开始写 Markdown…',
              alignLabelWithHint: true,
            ),
          ),
      ],
    ),
  );

  List<LifeDocumentTypeV2> get _availableTypes {
    const common = [
      LifeDocumentTypeV2.note,
      LifeDocumentTypeV2.checklist,
      LifeDocumentTypeV2.plan,
      LifeDocumentTypeV2.template,
    ];
    return common.contains(_type) ? common : [_type, ...common];
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _documentDate ?? now,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 20),
    );
    if (value != null && mounted) setState(() => _documentDate = value);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    setState(() {
      _markdown.text = text;
      if (_title.text.trim().isEmpty) {
        _title.text = _titleFromMarkdown(text);
      }
    });
  }

  String _titleFromMarkdown(String value) {
    for (final line in value.split('\n')) {
      final cleaned = line.replaceFirst(RegExp(r'^\s*#+\s*'), '').trim();
      if (cleaned.isNotEmpty) return cleaned;
    }
    return '未命名文档';
  }

  Future<void> _save() async {
    final markdown = _markdown.text.trim();
    final title = _title.text.trim().isEmpty
        ? _titleFromMarkdown(markdown)
        : _title.text.trim();
    if (markdown.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Markdown 内容不能为空')));
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now().toUtc();
    final existing = widget.document;
    final tags = _tags.text
        .split(RegExp(r'[,，]'))
        .map((value) => value.trim().replaceFirst(RegExp(r'^#'), ''))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final value = LifeDocumentV2(
      id: existing?.id ?? const Uuid().v4(),
      space: _space,
      title: title,
      markdown: markdown,
      type: _type,
      documentDate: _documentDate == null
          ? null
          : DateTime(
              _documentDate!.year,
              _documentDate!.month,
              _documentDate!.day,
            ).toUtc(),
      templateId: existing?.templateId,
      tags: tags,
      isPinned: existing?.isPinned ?? false,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await widget.repository.save(value);
    if (mounted) Navigator.pop(context, value);
  }
}
