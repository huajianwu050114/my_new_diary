import 'package:flutter/material.dart';

import '../data/stop_words_store_v2.dart';
import '../domain/diary_analysis_v2.dart';

class StopWordsPageV2 extends StatefulWidget {
  const StopWordsPageV2({required this.store, super.key});

  final StopWordsStoreV2 store;

  @override
  State<StopWordsPageV2> createState() => _StopWordsPageV2State();
}

class _StopWordsPageV2State extends State<StopWordsPageV2> {
  Set<String>? _customWords;

  @override
  void initState() {
    super.initState();
    widget.store.load().then((words) {
      if (mounted) {
        setState(() => _customWords = words);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final words = _customWords;
    return Scaffold(
      appBar: AppBar(title: const Text('停用词')),
      body: words == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('自定义停用词', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('这些词不会出现在高频词分析中。'),
                const SizedBox(height: 16),
                if (words.isEmpty)
                  const Text('暂无自定义停用词')
                else
                  Wrap(
                    spacing: 8,
                    children: words
                        .map(
                          (word) => Chip(
                            label: Text(word),
                            onDeleted: () => _remove(word),
                          ),
                        )
                        .toList(growable: false),
                  ),
                const Divider(height: 40),
                Text('默认停用词', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: DiaryAnalyzerV2.defaultStopWords
                      .map((word) => Chip(label: Text(word)))
                      .toList(growable: false),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: '添加停用词',
        onPressed: words == null ? null : _add,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加停用词'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null ||
        value.isEmpty ||
        DiaryAnalyzerV2.defaultStopWords.contains(value)) {
      return;
    }
    setState(() => _customWords!.add(value));
    await widget.store.save(_customWords!);
  }

  Future<void> _remove(String word) async {
    setState(() => _customWords!.remove(word));
    await widget.store.save(_customWords!);
  }
}
