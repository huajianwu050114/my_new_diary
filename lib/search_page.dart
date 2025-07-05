// file: lib/search_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';
import 'diary_view_page.dart';
import 'package:intl/intl.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<DiaryEntry> _searchResults = [];
  bool _isLoading = false;
  String _message = '请输入关键词开始搜索...';

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
      _message = ''; // 清空消息
    });

    final results = await context.read<DiaryService>().searchEntries(keyword);

    setState(() {
      _searchResults = results;
      _isLoading = false;
      if (results.isEmpty) {
        _message = '没有找到相关的日记';
      }
    });
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
        // 在AppBar中直接放置搜索框
        title: TextField(
          controller: _searchController,
          autofocus: true, // 自动弹出键盘
          decoration: InputDecoration(
            hintText: '搜索日记内容...',
            border: InputBorder.none,
            // 添加一个清除按钮
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                _performSearch('');
              },
            ),
          ),
          onSubmitted: (value) {
            // 用户按下键盘上的“完成”或“搜索”时执行搜索
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
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(
              entry.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(DateFormat('yyyy-MM-dd').format(entry.date)),
            onTap: () {
              // 点击搜索结果可以跳转到日记详情页
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