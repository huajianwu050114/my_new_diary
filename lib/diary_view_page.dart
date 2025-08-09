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

  Widget _buildProactiveQuestionCard(DiaryEntry entry) {
    if (entry.aiMetadata?.proactiveQuestion == null || entry.aiMetadata!.proactiveQuestion!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => AiChatPage(entry: entry)),
            ).then((_) => _reloadData());
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // VVVV 核心修改：将问题改为 MarkdownBody VVVV
                MarkdownBody(
                  data: entry.aiMetadata!.proactiveQuestion!,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
                  ),
                ),
                // ^^^^ 修改结束 ^^^^
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('与AI继续聊聊', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: Theme.of(context).colorScheme.primary),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
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

  Widget _buildAiAnalysisSection(AiMetadata aiMeta) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_outlined, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text("AI的悄悄话", style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const Divider(height: 24),
              if (aiMeta.detectedEmotion != null && aiMeta.detectedEmotion!.isNotEmpty) ...[
                Text("我感觉到，你的心情似乎是...", style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Chip(label: Text(aiMeta.detectedEmotion!)),
                const SizedBox(height: 16),
              ],
              // VVVV 核心修改：将摘要部分改为 MarkdownBody VVVV
              if (aiMeta.summary != null && aiMeta.summary!.isNotEmpty) ...[
                Text("这篇日记的核心是...", style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                MarkdownBody(
                  data: aiMeta.summary!,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: const TextStyle(height: 1.5, fontStyle: FontStyle.italic),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // ^^^^ 修改结束 ^^^^
              if (aiMeta.detectedThemes.isNotEmpty) ...[
                Text("你提到了这些主题...", style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  children: aiMeta.detectedThemes.map((theme) => Chip(label: Text(theme))).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 我们不再需要常规的 AppBar，因为它现在由 _buildSliverAppBar 管理
      body: CustomScrollView(
        slivers: [
          // 第一个 Sliver 是我们新创建的 AppBar
          _buildSliverAppBar(),

          // 第二个 Sliver 将包含页面的所有其他内容
          _buildSliverContent(),
        ],
      ),
    );
  }

  // 文件位置: lib/diary_view_page.dart -> _DiaryViewPageState

  Widget _buildSliverContent() {
    final theme = Theme.of(context);
    final entry = _currentEntry!;

    // --- 解析日记内容 ---
    String mainContent = entry.text;
    String? aiSampleAnswer;
    const String separator = "---AI_SAMPLE_ANSWER---";

    if (entry.text.contains(separator)) {
      final parts = entry.text.split(separator);
      mainContent = parts[0].trim();
      aiSampleAnswer = parts.length > 1 ? parts[1].trim() : null;
    }

    // SliverList 承载了所有的卡片和小部件
    return SliverList(
      delegate: SliverChildListDelegate(
        [
          // AI 元数据分析卡片
          if (entry.aiMetadata != null) _buildAiAnalysisSection(entry.aiMetadata!),

          // 主动提问卡片
          _buildProactiveQuestionCard(entry),

          // 心情和地点等元信息
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                if (entry.mood != null) _buildMoodIndicator(),
                if (entry.address != null && entry.address!.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.location_on_outlined, size: 16),
                    label: Text(entry.address!),
                  ),
              ],
            ),
          ),

          // 主要日记内容
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
            child: MarkdownBody(
              data: mainContent,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                blockquoteDecoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          // VVVV  新增的折叠区域 (使用 ExpansionTile) VVVV
          if (aiSampleAnswer != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ExpansionTile(
                title: const Text("看看AI会怎么写..."),
                leading: Icon(Icons.auto_awesome_outlined, color: theme.colorScheme.secondary),
                backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                collapsedBackgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: MarkdownBody(
                      data: "> $aiSampleAnswer", // 以引用块样式展示
                      selectable: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 标签、AI分析记录和时间戳
          if (entry.tags.isNotEmpty) _buildTags(),
          if (entry.aiAnalyses.isNotEmpty) _buildAiAnalysisRecords(),
          _buildTimestamps(),
        ],
      ),
    );
  }




  Widget _buildTags() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        children: _currentEntry!.tags.map((tag) => Chip(label: Text(tag))).toList(),
      ),
    );
  }

  Widget _buildAiAnalysisRecords() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 8, bottom: 8),
            child: Text("AI 分析记录 (${_currentEntry!.aiAnalyses.length})", style: Theme.of(context).textTheme.titleMedium),
          ),
          ..._currentEntry!.aiAnalyses.map((analysis) => _buildAnalysisTile(analysis)).toList(),
        ],
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
        title: Text(analysisText.split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: MarkdownBody(data: analysisText, selectable: true, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6))),
          )
        ],
      ),
    );
  }

  Widget _buildTimestamps() {
    return Padding(
      padding: const EdgeInsets.only(top: 32, right: 24.0, bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('写于 ${DateFormat('yyyy-MM-dd HH:mm').format(_currentEntry!.creationTime)}', style: Theme.of(context).textTheme.bodySmall),
          if (_currentEntry!.lastModifiedTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                '修改于 ${DateFormat('yyyy-MM-dd HH:mm').format(_currentEntry!.lastModifiedTime!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageErrorPlaceholder() {
    return Container(
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(15.0)),
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

  Widget _buildSliverAppBar() {
    final entry = _currentEntry!;
    final hasImages = entry.imagePaths.isNotEmpty;

    return SliverAppBar(
      expandedHeight: hasImages ? 250.0 : 0, // 有图片时展开高度为250，否则不展开
      floating: false, // 不会滑出视图
      pinned: true, // 向上滚动时，标题栏会固定在顶部
      stretch: true, // 允许下拉时图片被拉伸
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      foregroundColor: Theme.of(context).colorScheme.onBackground,
      actions: [
        PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => AddDiaryPage(entryToEdit: _currentEntry)),
              );
              _reloadData();
            } else if (value == 'chat_with_ai') {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => AiChatPage(entry: _currentEntry!)),
              );
              _reloadData();
            } else if (value == 'delete') {
              _deleteDiary();
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'edit',
              child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('编辑日记')),
            ),
            const PopupMenuItem<String>(
              value: 'chat_with_ai',
              child: ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('与AI交流')),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: 'delete',
              child: ListTile(leading: Icon(Icons.delete_outline), title: Text('删除日记')),
            ),
          ],
        ),
      ],
      flexibleSpace: hasImages
          ? FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: _buildImageViewer(), // 我们将图片浏览器放在这里
      )
          : null,
    );
  }
}