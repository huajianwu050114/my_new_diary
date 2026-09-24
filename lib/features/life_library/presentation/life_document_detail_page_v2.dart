import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../domain/life_document_repository_v2.dart';
import '../domain/life_document_v2.dart';
import '../domain/life_space_v2.dart';
import 'life_document_editor_page_v2.dart';

class LifeDocumentDetailPageV2 extends StatefulWidget {
  const LifeDocumentDetailPageV2({
    required this.document,
    required this.repository,
    super.key,
  });

  final LifeDocumentV2 document;
  final LifeDocumentRepositoryV2 repository;

  @override
  State<LifeDocumentDetailPageV2> createState() =>
      _LifeDocumentDetailPageV2State();
}

class _LifeDocumentDetailPageV2State extends State<LifeDocumentDetailPageV2> {
  late LifeDocumentV2 _document;
  String _spaceName = LifeSpaceDefaultsV2.inboxName;

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _loadSpaceName();
  }

  @override
  Widget build(BuildContext context) {
    var taskIndex = 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(_document.title),
        actions: [
          IconButton(
            tooltip: _document.isPinned ? '取消置顶' : '置顶',
            onPressed: _togglePinned,
            icon: Icon(
              _document.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenu,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              if (_document.type == LifeDocumentTypeV2.template)
                const PopupMenuItem(value: 'today', child: Text('生成今天的记录')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(_spaceName)),
              Chip(label: Text(_document.type.label)),
              if (_document.documentDate != null)
                Chip(
                  avatar: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    DateFormat(
                      'yyyy年M月d日',
                    ).format(_document.documentDate!.toLocal()),
                  ),
                ),
              for (final tag in _document.tags) Chip(label: Text('#$tag')),
              if (_document.checklistTotal > 0)
                Chip(
                  avatar: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(
                    '${_document.checklistCompleted}/${_document.checklistTotal}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          MarkdownBody(
            data: _document.markdown,
            selectable: true,
            checkboxBuilder: (checked) {
              final index = taskIndex++;
              return SizedBox(
                width: 32,
                height: 30,
                child: Checkbox(
                  value: checked,
                  onChanged: (_) => _toggleTask(index),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('编辑'),
      ),
    );
  }

  Future<void> _toggleTask(int targetIndex) async {
    var current = 0;
    final pattern = RegExp(r'^(\s*[-*+]\s+)\[([ xX])\]', multiLine: true);
    final updatedMarkdown = _document.markdown.replaceAllMapped(pattern, (
      match,
    ) {
      if (current++ != targetIndex) return match.group(0)!;
      final checked = match.group(2)!.toLowerCase() == 'x';
      return '${match.group(1)}[${checked ? ' ' : 'x'}]';
    });
    final updated = _document.copyWith(
      markdown: updatedMarkdown,
      updatedAt: DateTime.now().toUtc(),
    );
    setState(() => _document = updated);
    await widget.repository.save(updated);
  }

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<LifeDocumentV2>(
      MaterialPageRoute(
        builder: (_) => LifeDocumentEditorPageV2(
          repository: widget.repository,
          initialSpace: _document.space,
          document: _document,
        ),
      ),
    );
    if (updated != null && mounted) setState(() => _document = updated);
    if (updated != null) await _loadSpaceName();
  }

  Future<void> _togglePinned() async {
    final updated = _document.copyWith(
      isPinned: !_document.isPinned,
      updatedAt: DateTime.now().toUtc(),
    );
    setState(() => _document = updated);
    await widget.repository.save(updated);
  }

  Future<void> _handleMenu(String value) async {
    switch (value) {
      case 'edit':
        await _edit();
      case 'today':
        await _createTodayLog();
      case 'delete':
        await _delete();
    }
  }

  Future<void> _createTodayLog() async {
    final now = DateTime.now();
    final existingLogs = await widget.repository.watchDocuments().first;
    for (final item in existingLogs) {
      final date = item.documentDate?.toLocal();
      if (item.templateId == _document.id &&
          date != null &&
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        if (!mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => LifeDocumentDetailPageV2(
              document: item,
              repository: widget.repository,
            ),
          ),
        );
        return;
      }
    }
    final createdAt = now.toUtc();
    final log = LifeDocumentV2(
      id: const Uuid().v4(),
      space: _document.space,
      title: '${DateFormat('M月d日').format(now)} · ${_document.title}',
      markdown: _document.markdown.replaceAllMapped(
        RegExp(r'^(\s*[-*+]\s+)\[[xX]\]', multiLine: true),
        (match) => '${match.group(1)}[ ]',
      ),
      type: LifeDocumentTypeV2.dailyLog,
      documentDate: DateTime(now.year, now.month, now.day).toUtc(),
      templateId: _document.id,
      tags: _document.tags,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await widget.repository.save(log);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LifeDocumentDetailPageV2(
          document: log,
          repository: widget.repository,
        ),
      ),
    );
  }

  Future<void> _loadSpaceName() async {
    final space = await widget.repository.getSpaceById(_document.space);
    if (!mounted) return;
    setState(
      () => _spaceName =
          space?.name ?? LifeSpaceDefaultsV2.legacyName(_document.space),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这篇文档？'),
        content: const Text('第一版会将它移出生活库。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.delete(_document.id);
    if (mounted) Navigator.pop(context);
  }
}
