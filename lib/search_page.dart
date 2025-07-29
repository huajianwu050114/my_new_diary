// file: lib/search_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';
import 'diary_view_page.dart';
import 'package:intl/intl.dart';

class SearchPage extends StatefulWidget {
  // VVV 1. 添加一个可选参数，用于接收初始搜索词 VVV
  final String? initialQuery;

  const SearchPage({super.key, this.initialQuery});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<DiaryEntry> _searchResults = [];
  bool _isLoading = false;
  String _message = '请输入关键词开始搜索...';

  // VVV 2. 在 initState 中处理初始搜索词 VVV
  @override
  void initState() {
    super.initState();
    // 如果有初始搜索词，则设置到搜索框并立即执行搜索
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      _performSearch(widget.initialQuery!);
    }
  }

  Future<void> _performSearch(String keyword) async {
    if (keyword.isEmpty) {
      setState(() {
        _searchResults = [];
        _message = '请输入关键词开始搜索...';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _message = '';
    });

    // --- 核心逻辑：在这里获取数据并进行客户端搜索 ---
    try {
      // 1. 获取所有日记
      // 注意：这里我们直接使用 Future，而不是 Stream，因为搜索是一次性操作
      final allEntries = await context.read<DiaryService>().getAllEntriesSortedStream().first;

      // 2. 在内存中进行过滤
      final lowerCaseKeyword = keyword.toLowerCase();
      final results = allEntries.where((entry) {
        return entry.text.toLowerCase().contains(lowerCaseKeyword);
      }).toList();
      // --- 搜索结束 ---

      if (!mounted) return;

      setState(() {
        _searchResults = results;
        _isLoading = false;
        if (results.isEmpty) {
          _message = '没有找到包含“$keyword”的日记';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _message = '搜索时发生错误: $e';
      });
    }
  }

  Widget _buildHighlightedText(String text, String keyword) {
    if (keyword.isEmpty || !text.toLowerCase().contains(keyword.toLowerCase())) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    final List<TextSpan> spans = [];
    final textLower = text.toLowerCase();
    final keywordLower = keyword.toLowerCase();

    int start = 0;
    int indexOfKeyword;

    while ((indexOfKeyword = textLower.indexOf(keywordLower, start)) != -1) {
      if (indexOfKeyword > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfKeyword)));
      }
      spans.add(TextSpan(
        text: text.substring(indexOfKeyword, indexOfKeyword + keyword.length),
        style: TextStyle(
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          fontWeight: FontWeight.bold,
        ),
      ));
      start = indexOfKeyword + keyword.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyLarge,
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          // VVV 3. 如果有初始词，就不再自动弹出键盘 VVV
          autofocus: widget.initialQuery == null,
          decoration: InputDecoration(
            hintText: '搜索日记内容...',
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                _performSearch('');
              },
            ),
          ),
          onSubmitted: (value) {
            _performSearch(value);
          },
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          _message,
          style: const TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final entry = _searchResults[index];
        final keyword = _searchController.text;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: _buildHighlightedText(entry.text, keyword),
            subtitle: Text(DateFormat('yyyy-MM-dd').format(entry.date)),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => DiaryViewPage(entry: entry)),
              );
            },
          ),
        );
      },
    );
  }
}