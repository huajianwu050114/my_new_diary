// file: lib/diary_view_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'gemini_service_local.dart';
import 'ai_chat_page.dart';
import 'add_diary_page.dart';
import 'package:my_new_diary/diary_model.dart';
import 'gallery_page.dart';

class DiaryViewPage extends StatefulWidget {
  final DiaryEntry entry;
  final String? highlightKeyword;

  const DiaryViewPage({
    super.key,
    required this.entry,
    this.highlightKeyword });


  @override
  State<DiaryViewPage> createState() => _DiaryViewPageState();
}

// file: lib/diary_view_page.dart

class _DiaryViewPageState extends State<DiaryViewPage> {
  // VVV 1. 将 'late' 声明改为可空类型 'DiaryEntry?' VVV
  DiaryEntry? _currentEntry;
  int _currentPage = 0;
  final GeminiServiceLocal _geminiService = GeminiServiceLocal();

  @override
  void initState() {
    super.initState();
    // VVV 2. 在 initState 中初始化它 VVV
    _currentEntry = widget.entry;
  }

  Widget _buildMoodIndicator() {
    final entry = _currentEntry!;
    // 如果这篇日记没有设置心情，则不显示任何东西
    if (entry.mood == null || entry.mood!.isEmpty) {
      return const SizedBox.shrink();
    }

    // 从 add_diary_page.dart 复制心情代码到文字的映射
    const Map<String, String> moodMap = {
      '1': '特别开心', '2': '很开心', '3': '有点开心', '4': '一般',
      '5': '有点伤心', '6': '伤心', '7': '很伤心', '8': '崩溃', '0': '生病',
    };

    // 创建一个辅助函数来获取对应心情的图标
    IconData _getMoodIcon(String moodCode) {
      switch (moodCode) {
        case '1': return Icons.sentiment_very_satisfied;
        case '2': return Icons.sentiment_satisfied;
        case '3': return Icons.mood;
        case '4': return Icons.sentiment_neutral;
        case '5': return Icons.sentiment_dissatisfied;
        case '6': return Icons.sentiment_dissatisfied;
        case '7': return Icons.sentiment_very_dissatisfied;
        case '8': return Icons.mood_bad;
        case '0': return Icons.sick;
        default: return Icons.help_outline;
      }
    }

    final moodText = moodMap[entry.mood!] ?? '未知心情';
    final moodIcon = _getMoodIcon(entry.mood!);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          avatar: Icon(moodIcon, color: Theme.of(context).colorScheme.primary),
          label: Text('今日心情: $moodText'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
          side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
        ),
      ),
    );
  }

  Widget _buildHighlightedText(String text, String keyword) {
    // 在详情页，如果没传关键词，就直接显示普通文本
    if (keyword.isEmpty) {
      return Text(
        text.isNotEmpty ? text : '(这天没有写下任何文字)',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize: 18,
          height: 1.6,
        ),
      );
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

    // 返回 RichText，但没有 maxLines 和 overflow 限制
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize: 18,
          height: 1.6,
        ),
        children: spans,
      ),
    );
  }

  Future<void> _reloadData() async {
    // VVV 3. 使用 '!' 来安全地访问非空变量 VVV
    final diaryService = context.read<DiaryService>();
    final updatedEntry = await diaryService.getEntryById(_currentEntry!.diaryId);
    if (mounted && updatedEntry != null) {
      setState(() {
        _currentEntry = updatedEntry;
      });
    }
  }

  void _deleteDiary() async {
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('移入回收站'),
          content: const Text('你确定要把这篇日记移入回收站吗？'),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('移入回收站'),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmDelete == true && mounted) {
      await context.read<DiaryService>().moveEntryToTrash(_currentEntry!.diaryId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Widget _buildImageViewer() {
    return AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          children: [
        PageView.builder(
        itemCount: _currentEntry!.imagePaths.length,
          onPageChanged: (index) {
            setState(() {
              _currentPage = index;
            });
          },
          itemBuilder: (context, index) {
            final imagePath = _currentEntry!.imagePaths[index];

            // VVV 关键修改：用 GestureDetector 包裹图片，使其可以被点击 VVV
            return GestureDetector(
              onTap: () {
                // 点击后，导航到我们新的画廊页面
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => GalleryPage(
                      imagePaths: _currentEntry!.imagePaths,
                      initialIndex: index,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Hero( // 添加 Hero 动画，让页面切换更平滑
                  tag: imagePath,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15.0),
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildImageErrorPlaceholder(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (_currentEntry!.imagePaths.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children:
                List.generate(_currentEntry!.imagePaths.length, (index) {
                  return Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == index
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // VVV 4. 同样，在这里使用 '!' 来确保 entry 非空 VVV
    final entry = _currentEntry!;
    final bool hasImages = entry.imagePaths.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'edit') { // VVV 2. 添加处理 'edit' 的逻辑 VVV
                // 使用 await 等待编辑页面返回
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    // 跳转到 AddDiaryPage，并把当前日记作为参数传过去
                    builder: (context) =>
                        AddDiaryPage(entryToEdit: _currentEntry),
                  ),
                );
                // 编辑完成后，重新加载数据以刷新页面
                _reloadData();
              }else if (value == 'chat_with_ai') {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => AiChatPage(entry: _currentEntry!),
                  ),
                );
                _reloadData();
              } else if (value == 'delete') {
                _deleteDiary();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('编辑日记'),
                ),
              ),
              const PopupMenuItem<String>(

                value: 'chat_with_ai',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('与AI交流'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('删除日记'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24.0),
        children: [
          if (hasImages)
            SizedBox(
                height: MediaQuery.of(context).padding.top + kToolbarHeight),
          if (hasImages) _buildImageViewer(),
          if (entry.address != null && entry.address!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(entry.address!),
                dense: true,
              ),
            ),

          _buildMoodIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 8.0),
            child: _buildHighlightedText(entry.text, widget.highlightKeyword ?? ''),
          ),
          if (entry.tags.isNotEmpty)
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children:
                entry.tags.map((tag) => Chip(label: Text(tag))).toList(),
              ),
            ),
          if (entry.aiAnalyses.isNotEmpty)
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                    const EdgeInsets.only(left: 16.0, top: 8, bottom: 8),
                    child: Text(
                      "AI 分析记录 (${entry.aiAnalyses.length})",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ...entry.aiAnalyses
                      .map((analysis) => _buildAnalysisTile(analysis))
                      .toList(),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 32, right: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '写于 ${DateFormat('yyyy-MM-dd HH:mm').format(entry.creationTime)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                // 如果存在 lastModifiedTime，就显示这一行
                if (entry.lastModifiedTime != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      '修改于 ${DateFormat('yyyy-MM-dd HH:mm').format(entry.lastModifiedTime!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11, // 让修改时间稍微小一点
                        color: Colors.grey, // 颜色变淡以作区分
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageErrorPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(15.0),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.grey, size: 50),
            SizedBox(height: 8),
            Text('图片加载失败', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisTile(String analysisText) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(Icons.bookmark_border, color: Colors.amber.shade800),
        title: Text(
          analysisText.split('\n').first,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        children: <Widget>[
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: MarkdownBody(
                data: analysisText,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                    .copyWith(
                  p: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(height: 1.6),
                ),
              ))
        ],
      ),
    );
  }
}