// file: libs/search_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_new_diary/diary_model.dart';
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
  String _message = '输入关键词或使用筛选器开始搜索...';

  // VVV 1. 添加用于存储筛选条件的状态变量 VVV
  DateTimeRange? _selectedDateRange;
  String? _selectedMood;
  final Set<String> _selectedTags = {};

  final Map<String, String> _moodMap = {
    '1': '特别开心', '2': '很开心', '3': '有点开心', '4': '一般',
    '5': '有点伤心', '6': '伤心', '7': '很伤心', '8': '崩溃', '0': '生病',
  };

  // VVV 2. 改造搜索方法以使用所有筛选条件 VVV
  Future<void> _performSearch() async {
    setState(() {
      _isLoading = true;
      _message = '';
    });

    final diaryService = context.read<DiaryService>();
    final results = await diaryService.searchEntries(
      keyword: _searchController.text.trim(),
      dateRange: _selectedDateRange,
      mood: _selectedMood,
      selectedTags: _selectedTags,
    );

    if (!mounted) return;

    setState(() {
      _searchResults = results;
      _isLoading = false;
      if (results.isEmpty && (_searchController.text.isNotEmpty || _selectedDateRange != null || _selectedMood != null || _selectedTags.isNotEmpty)) {
        _message = '没有找到符合条件的日记';
      }
    });
  }

  // VVV 3. 添加用于选择筛选器的方法 VVV
  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _selectedDateRange,
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
      _performSearch();
    }
  }

  Future<void> _selectMood() async {
    final mood = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择心情'),
        children: _moodMap.entries.map((entry) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, entry.key),
            child: Text(entry.value),
          );
        }).toList(),
      ),
    );
    if (mood != null) {
      setState(() => _selectedMood = mood);
      _performSearch();
    }
  }

  Future<void> _selectTags() async {
    final diaryService = context.read<DiaryService>();
    final allTags = await diaryService.getAllUniqueTags();

    await showDialog(
      context: context,
      builder: (context) {
        // 使用 StatefulWidget 来管理对话框内的状态
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('选择标签'),
              content: Wrap(
                spacing: 8.0,
                children: allTags.map((tag) {
                  final isSelected = _selectedTags.contains(tag);
                  return FilterChip(
                    label: Text(tag),
                    selected: isSelected,
                    onSelected: (selected) {
                      setDialogState(() {
                        if (selected) {
                          _selectedTags.add(tag);
                        } else {
                          _selectedTags.remove(tag);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成'),
                ),
              ],
            );
          },
        );
      },
    );
    // 关闭对话框后，更新状态并执行搜索
    setState(() {});
    _performSearch();
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
          autofocus: true,
          decoration: InputDecoration(
            hintText: '搜索日记内容...',
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                _performSearch();
              },
            ),
          ),
          onSubmitted: (_) => _performSearch(),
        ),
      ),
      body: Column(
        children: [
          // VVV 4. 添加筛选器按钮行 VVV
          _buildFilterChips(),
          // VVV 5. 添加显示已选筛选条件的区域 VVV
          _buildActiveFilters(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHighlightedText(String text, String keyword) {
    if (keyword.isEmpty || !text.toLowerCase().contains(keyword.toLowerCase())) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    final textLower = text.toLowerCase();
    final keywordLower = keyword.toLowerCase();

    // VVV 智能截取逻辑 VVV
    final int firstMatchIndex = textLower.indexOf(keywordLower);
    const int contextLength = 40; // 关键词前后各截取40个字符作为上下文

    int startIndex = firstMatchIndex - contextLength;
    if (startIndex < 0) {
      startIndex = 0;
    }

    // 截取包含关键词的文本片段
    String snippet = text.substring(startIndex);
    // 如果是从中间截取的，在开头加上省略号
    if (startIndex > 0) {
      snippet = "... $snippet";
    }

    // VVV 后续高亮逻辑基于 snippet 进行 VVV
    final List<TextSpan> spans = [];
    final snippetLower = snippet.toLowerCase();
    int startInSnippet = 0;
    int indexOfKeywordInSnippet;

    while ((indexOfKeywordInSnippet = snippetLower.indexOf(keywordLower, startInSnippet)) != -1) {
      if (indexOfKeywordInSnippet > startInSnippet) {
        spans.add(TextSpan(text: snippet.substring(startInSnippet, indexOfKeywordInSnippet)));
      }
      spans.add(TextSpan(
        text: snippet.substring(indexOfKeywordInSnippet, indexOfKeywordInSnippet + keyword.length),
        style: TextStyle(
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          fontWeight: FontWeight.bold,
        ),
      ));
      startInSnippet = indexOfKeywordInSnippet + keyword.length;
    }

    if (startInSnippet < snippet.length) {
      spans.add(TextSpan(text: snippet.substring(startInSnippet)));
    }

    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  // VVV 6. 新增的 UI 构建辅助方法 VVV
  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Wrap(
        spacing: 8.0,
        children: [
          ActionChip(
            avatar: const Icon(Icons.date_range_outlined, size: 18),
            label: const Text('日期'),
            onPressed: _selectDateRange,
          ),
          ActionChip(
            avatar: const Icon(Icons.mood_outlined, size: 18),
            label: const Text('心情'),
            onPressed: _selectMood,
          ),
          ActionChip(
            avatar: const Icon(Icons.label_outline, size: 18),
            label: const Text('标签'),
            onPressed: _selectTags,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilters() {
    if (_selectedDateRange == null && _selectedMood == null && _selectedTags.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Wrap(
        spacing: 8.0,
        children: [
          if (_selectedDateRange != null)
            Chip(
              label: Text('${DateFormat('y/M/d').format(_selectedDateRange!.start)} - ${DateFormat('y/M/d').format(_selectedDateRange!.end)}'),
              onDeleted: () {
                setState(() => _selectedDateRange = null);
                _performSearch();
              },
            ),
          if (_selectedMood != null)
            Chip(
              label: Text(_moodMap[_selectedMood!] ?? ''),
              onDeleted: () {
                setState(() => _selectedMood = null);
                _performSearch();
              },
            ),
          ..._selectedTags.map((tag) => Chip(
            label: Text(tag),
            onDeleted: () {
              setState(() => _selectedTags.remove(tag));
              _performSearch();
            },
          )),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(child: Text(_message, style: const TextStyle(fontSize: 18, color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final entry = _searchResults[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: _buildHighlightedText(entry.text, _searchController.text),
            subtitle: Text(DateFormat('yyyy-MM-dd').format(entry.date)),
            onTap: () {
              // VVV 唯一的修改在这里 VVV
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (context) => DiaryViewPage(
                      entry: entry,
                      highlightKeyword: _searchController.text,// 将关键词传递过去
                    )
                ),
              );
            },
          ),
        );
      },
    );
  }
}