import 'package:flutter/material.dart';

import '../../../shared/tag_memory_field_v2.dart';
import '../domain/life_fragment_repository_v2.dart';
import '../domain/life_fragment_v2.dart';

class LifeFragmentEditPageV2 extends StatefulWidget {
  const LifeFragmentEditPageV2({
    required this.fragment,
    required this.repository,
    super.key,
  });

  final LifeFragmentV2 fragment;
  final LifeFragmentRepositoryV2 repository;

  @override
  State<LifeFragmentEditPageV2> createState() => _LifeFragmentEditPageV2State();
}

class _LifeFragmentEditPageV2State extends State<LifeFragmentEditPageV2> {
  late final TextEditingController _title;
  late final TextEditingController _insight;
  late final TextEditingController _context;
  late final TextEditingController _evidence;
  late final TextEditingController _futureUse;
  late final TextEditingController _message;
  late final TextEditingController _theme;
  late final TextEditingController _tags;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final value = widget.fragment;
    _title = TextEditingController(text: value.title);
    _insight = TextEditingController(text: value.coreInsight);
    _context = TextEditingController(text: value.context);
    _evidence = TextEditingController(text: value.evidence);
    _futureUse = TextEditingController(text: value.futureUse);
    _message = TextEditingController(text: value.messageToFutureSelf);
    _theme = TextEditingController(text: value.theme);
    _tags = TextEditingController(text: value.tags.join(', '));
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _insight,
      _context,
      _evidence,
      _futureUse,
      _message,
      _theme,
      _tags,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('编辑人生碎片'),
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
      children: [
        _field(_title, '标题', 1),
        _field(_insight, '核心认识', 3),
        _field(_context, '它来自什么经历', 3),
        _field(_evidence, '支撑这份认识的真实证据', 3),
        _field(_futureUse, '未来什么时候值得重新读', 3),
        _field(_message, '写给未来自己的话', 3),
        _field(_theme, '主题（由你命名）', 1),
        StreamBuilder<List<LifeFragmentV2>>(
          stream: widget.repository.watchFragments(),
          builder: (context, snapshot) => TagMemoryFieldV2(
            controller: _tags,
            suggestions: (snapshot.data ?? const <LifeFragmentV2>[]).expand(
              (fragment) => fragment.tags,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('保存前的内容会自动进入修改历史。', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  Widget _field(TextEditingController controller, String label, int lines) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller,
          minLines: lines,
          maxLines: null,
          decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: true,
          ),
        ),
      );

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _insight.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('标题和核心认识不能为空')));
      return;
    }
    setState(() => _saving = true);
    final updated = widget.fragment.copyWith(
      title: _title.text.trim(),
      coreInsight: _insight.text.trim(),
      context: _context.text.trim(),
      evidence: _evidence.text.trim(),
      futureUse: _futureUse.text.trim(),
      messageToFutureSelf: _message.text.trim(),
      theme: _theme.text.trim(),
      tags: _tags.text
          .split(RegExp(r'[,，]'))
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList(growable: false),
      updatedAt: DateTime.now().toUtc(),
    );
    await widget.repository.updateWithRevision(
      updated,
      previous: widget.fragment,
    );
    if (mounted) Navigator.pop(context, updated);
  }
}
