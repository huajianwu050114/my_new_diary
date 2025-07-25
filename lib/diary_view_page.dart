// file: lib/diary_view_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';
import 'gemini_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class DiaryViewPage extends StatefulWidget {
  final DiaryEntry entry;
  const DiaryViewPage({super.key, required this.entry});

  @override
  State<DiaryViewPage> createState() => _DiaryViewPageState();
}

class _DiaryViewPageState extends State<DiaryViewPage> {
  // VVV 1. 添加状态来追踪当前图片页码 VVV
  int _currentPage = 0;
  final GeminiService _geminiService = GeminiService();

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
      await context.read<DiaryService>().moveEntryToTrash(widget.entry.filePath);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _showAnalysis(String title, Future<String?> analysisFuture) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const Divider(height: 24),
              Expanded(
                child: FutureBuilder<String?>(
                  future: analysisFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text('分析失败或无结果。'));
                    }
                    // 使用 Markdown 组件来渲染AI返回的格式化文本
                    return Markdown(
                      data: snapshot.data!,
                      selectable: true, // 让用户可以复制文本
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // VVV 2. 构建图片浏览器 VVV
  Widget _buildImageViewer() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        children: [
          // 可滑动的 PageView
          PageView.builder(
            itemCount: widget.entry.imagePaths.length,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15.0),
                  child: Image.file(
                    File(widget.entry.imagePaths[index]),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _buildImageErrorPlaceholder(),
                  ),
                ),
              );
            },
          ),
          // 底部的页码指示器
          if (widget.entry.imagePaths.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.entry.imagePaths.length, (index) {
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
    final entry = widget.entry;
    // VVV 3. 更新判断逻辑 VVV
    final bool hasImages = entry.imagePaths.isNotEmpty;

    return Scaffold(
      extendBodyBehindAppBar: hasImages,
      appBar: AppBar(
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(DateFormat('yyyy年M月d日', 'zh_CN').format(entry.date)),
            Text(
              '${DateFormat('HH:mm').format(entry.creationTime)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor:
        hasImages ? Colors.transparent : Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        titleTextStyle: hasImages
            ? TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontFamily: 'MiSans',
          shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 4)],
        ) : null,
        iconTheme: hasImages
            ? IconThemeData(
          color: Colors.white,
          shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 4)],
        ) : null,
        actions: [
          // 使用这个新的 PopupMenuButton 替换旧的删除按钮
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert), // 使用更常见的“更多”图标
            onSelected: (value) {
              if (value == 'diary_analysis') {
                _showAnalysis('AI 日记分析师', _geminiService.getDiaryAnalysis(widget.entry));
              } else if (value == 'psychological_analysis') {
                _showAnalysis('AI 心理洞察', _geminiService.getPsychologicalAnalysis(widget.entry));
              } else if (value == 'delete') {
                _deleteDiary();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'diary_analysis',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome_outlined), // AI 图标
                  title: Text('日记分析'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'psychological_analysis',
                child: ListTile(
                  leading: Icon(Icons.psychology_outlined),
                  title: Text('心理洞察'),
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
        padding: const EdgeInsets.only(bottom: 24.0), // Add some padding to the bottom
        children: [
          if (hasImages)
            SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),

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

          // Diary Text
          Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 8.0),
            child: Text(
              entry.text.isNotEmpty ? entry.text : '(这天没有写下任何文字)',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: 18,
                height: 1.6,
              ),
            ),
          ),

          // Tags
          if (entry.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: entry.tags.map((tag) => Chip(label: Text(tag))).toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 32, right: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '写于 ${DateFormat('yyyy-MM-dd HH:mm').format(entry.creationTime)}',
                  style: Theme.of(context).textTheme.bodySmall,
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
}