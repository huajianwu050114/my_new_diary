import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../diary/domain/entities/diary_entry.dart';
import '../application/diary_ai_service_v2.dart';
import '../data/ai_memory_store_v2.dart';
import '../domain/ai_memory_suggestions_v2.dart';
import '../domain/ai_memory_v2.dart';
import '../domain/ai_models_v2.dart';

class AiMemorySuggestionPageV2 extends StatefulWidget {
  const AiMemorySuggestionPageV2({
    required this.entry,
    required this.service,
    super.key,
  });

  final DiaryEntryV2 entry;
  final DiaryAiServiceV2 service;

  @override
  State<AiMemorySuggestionPageV2> createState() =>
      _AiMemorySuggestionPageV2State();
}

class _AiMemorySuggestionPageV2State extends State<AiMemorySuggestionPageV2> {
  final _store = AiMemoryStoreV2();
  final List<TextEditingController> _controllers = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _saving = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('记忆建议')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
      children: [
        Text('哪些内容值得以后记得？', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('默认不会保存。请逐条选择，也可以先修改AI的措辞。'),
        const SizedBox(height: 20),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(_note!),
          ),
        for (var index = 0; index < _controllers.length; index++)
          Card(
            child: CheckboxListTile(
              value: _selected.contains(index),
              onChanged: (value) => setState(() {
                value == true ? _selected.add(index) : _selected.remove(index);
              }),
              title: TextField(
                controller: _controllers[index],
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
          ),
        if (_controllers.isNotEmpty) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _selected.isEmpty || _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_saving ? '保存中…' : '保存选中的记忆'),
          ),
        ],
      ],
    ),
  );

  Future<void> _generate() async {
    try {
      final response = await widget.service.suggestMemories(widget.entry);
      final suggestions = AiMemorySuggestionsV2.parse(response.text);
      if (!mounted) return;
      setState(() {
        _controllers.addAll(
          suggestions.map((text) => TextEditingController(text: text)),
        );
        _note = suggestions.isEmpty ? '这篇日记里没有需要长期记住的内容。' : null;
      });
    } on AiFailureV2 catch (error) {
      if (mounted) setState(() => _note = error.message);
    } on FormatException {
      if (mounted) setState(() => _note = 'AI返回的建议格式不完整，请稍后重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final existing = (await _store.load()).map((item) => item.text).toSet();
    for (final index in _selected) {
      final text = _controllers[index].text.trim();
      if (text.isEmpty || existing.contains(text)) continue;
      await _store.save(
        AiMemoryV2(
          id: const Uuid().v4(),
          text: text,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      existing.add(text);
    }
    if (mounted) Navigator.pop(context, _selected.length);
  }
}
