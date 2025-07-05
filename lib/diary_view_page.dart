// file: lib/diary_view_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';

class DiaryViewPage extends StatefulWidget {
  final DiaryEntry entry;
  const DiaryViewPage({super.key, required this.entry});

  @override
  State<DiaryViewPage> createState() => _DiaryViewPageState();
}

class _DiaryViewPageState extends State<DiaryViewPage> {
  // 删除日记的逻辑
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

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    // 判断是否存在有效图片路径
    final bool hasImage = entry.imagePath != null && entry.imagePath!.isNotEmpty;

    return Scaffold(
      // 仅在有图片时，才将内容延伸至AppBar后方
      extendBodyBehindAppBar: hasImage,
      appBar: AppBar(
        title: Text(DateFormat('yyyy年M月d日', 'zh_CN').format(entry.date)),
        // 如果有图片，AppBar背景透明；否则使用主题默认色
        backgroundColor:
        hasImage ? Colors.transparent : Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        // 如果有图片，为标题和图标添加阴影以保证可见性
        titleTextStyle: hasImage
            ? TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontFamily: 'MiSans',
          shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 4)],
        )
            : null,
        iconTheme: hasImage
            ? IconThemeData(
          color: Colors.white,
          shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 4)],
        )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteDiary,
          ),
        ],
      ),
      body: ListView(
        // 如果没有图片，则使用默认的padding；否则从顶部开始布局
        padding: hasImage ? EdgeInsets.zero : const EdgeInsets.all(16.0),
        children: [
          // 如果内容延伸到AppBar后，添加一个占位SizedBox把内容往下推
          if (hasImage)
            SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),

          // --- 图片显示区域 (已按要求修改) ---
          if (hasImage)
            Padding(
              // 设置图片的外边距
              padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
              child: ClipRRect(
                // 设置圆角
                borderRadius: BorderRadius.circular(15.0),
                child: Image.file(
                  File(entry.imagePath!),
                  // 核心属性：宽度适应屏幕，高度自动调整
                  fit: BoxFit.fitWidth,
                  // 当图片加载失败时，显示一个错误占位符
                  errorBuilder: (context, error, stackTrace) {
                    return _buildImageErrorPlaceholder();
                  },
                ),
              ),
            ),

          // --- 文本显示区域 ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
            child: Text(
              entry.text.isNotEmpty ? entry.text : '(这天没有写下任何文字)',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: 18,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 当图片文件加载失败时显示的占位Widget
  Widget _buildImageErrorPlaceholder() {
    return Container(
      // 给错误占位符一个固定的高度和背景色，避免布局跳动
      height: 200,
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