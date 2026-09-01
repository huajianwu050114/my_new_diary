import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/ai_memory_store_v2.dart';
import '../domain/ai_memory_v2.dart';

class AiMemoryPageV2 extends StatefulWidget {
  const AiMemoryPageV2({super.key, AiMemoryStoreV2? store}) : _store = store;

  final AiMemoryStoreV2? _store;

  @override
  State<AiMemoryPageV2> createState() => _AiMemoryPageV2State();
}

class _AiMemoryPageV2State extends State<AiMemoryPageV2> {
  late final AiMemoryStoreV2 _store;
  List<AiMemoryV2>? _memories;

  @override
  void initState() {
    super.initState();
    _store = widget._store ?? AiMemoryStoreV2();
    _load();
  }

  Future<void> _load() async {
    final values = await _store.load();
    if (mounted) setState(() => _memories = values.reversed.toList());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI 记忆')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(),
      icon: const Icon(Icons.add_rounded),
      label: const Text('添加记忆'),
    ),
    body: _memories == null
        ? const Center(child: CircularProgressIndicator())
        : _memories!.isEmpty
        ? const _EmptyMemory()
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: _memories!.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final memory = _memories![index];
              return Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      value: memory.enabled,
                      onChanged: (enabled) async {
                        await _store.save(memory.copyWith(enabled: enabled));
                        await _load();
                      },
                      title: Text(memory.text),
                      subtitle: Text(memory.enabled ? 'AI 可以使用' : '已暂停使用'),
                    ),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _edit(memory),
                          child: const Text('编辑'),
                        ),
                        TextButton(
                          onPressed: () => _delete(memory),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
  );

  Future<void> _edit([AiMemoryV2? memory]) async {
    final controller = TextEditingController(text: memory?.text);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(memory == null ? '添加一条记忆' : '编辑记忆'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '例如：我不喜欢被催促，更希望先被倾听。'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    await _store.save(
      memory?.copyWith(text: text) ??
          AiMemoryV2(
            id: const Uuid().v4(),
            text: text,
            createdAt: DateTime.now().toUtc(),
          ),
    );
    await _load();
  }

  Future<void> _delete(AiMemoryV2 memory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记忆？'),
        content: const Text('删除后，AI不会再读取它。'),
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
    await _store.delete(memory.id);
    await _load();
  }
}

class _EmptyMemory extends StatelessWidget {
  const _EmptyMemory();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Text(
        'AI还没有长期记忆。\n只有你亲自保存的内容，AI才可以在以后使用。',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
