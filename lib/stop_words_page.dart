// file: libs/stop_words_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StopWordsPage extends StatefulWidget {
  const StopWordsPage({super.key});

  @override
  State<StopWordsPage> createState() => _StopWordsPageState();
}

class _StopWordsPageState extends State<StopWordsPage> {
  // 从 analysis_page.dart 复制过来的默认停用词
  final Set<String> _defaultStopWords = const {
    '的', '了', '我', '你', '他', '她', '它', '我们', '你们', '他们',
    '是', '在', '有', '也', '还', '就', '都', '不', '和', '与', '或',
    '一个', '一些', '这个', '那个', '这', '那', '被', '把', '会', '能',
    '吗', '吧', '呢', '啊', '哦', '嗯', '!', '?', '.', ',', '，', '。',
    '：', '“', '”', '（', '）', '《', '》', ' '
  };

  final List<String> _customStopWords = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomStopWords();
  }

  Future<void> _loadCustomStopWords() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _customStopWords.clear();
      _customStopWords.addAll(prefs.getStringList('custom_stop_words') ?? []);
      _isLoading = false;
    });
  }

  Future<void> _saveCustomStopWords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('custom_stop_words', _customStopWords);
  }

  void _addStopWord(String word) {
    final trimmedWord = word.trim();
    if (trimmedWord.isNotEmpty && !_customStopWords.contains(trimmedWord) && !_defaultStopWords.contains(trimmedWord)) {
      setState(() {
        _customStopWords.add(trimmedWord);
      });
      _saveCustomStopWords();
      Navigator.of(context).pop(); // 关闭对话框
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('不能添加空、重复或默认的停用词')),
      );
    }
  }

  void _removeStopWord(String word) {
    setState(() {
      _customStopWords.remove(word);
    });
    _saveCustomStopWords();
  }

  Future<void> _showAddStopWordDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('添加停用词'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '输入要忽略的词汇'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => _addStopWord(controller.text),
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('词云停用词管理'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text('自定义停用词', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '您可以在此添加不希望出现在词云中的词汇。点击“+”号添加，点击词汇上的“x”删除。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _customStopWords.isEmpty
              ? const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: Text('暂无自定义停用词', style: TextStyle(color: Colors.grey)),
            ),
          )
              : Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: _customStopWords.map((word) {
              return Chip(
                label: Text(word),
                onDeleted: () => _removeStopWord(word),
              );
            }).toList(),
          ),
          const Divider(height: 48),
          Text('默认停用词', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '这些是系统内置的常用停用词，用于过滤常见的功能词和标点符号。此列表不可修改。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: _defaultStopWords.map((word) {
              return Chip(
                label: Text(word),
                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              );
            }).toList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddStopWordDialog,
        child: const Icon(Icons.add),
        tooltip: '添加停用词',
      ),
    );
  }
}