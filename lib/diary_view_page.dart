import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'diary_service.dart';

class DiaryViewPage extends StatelessWidget {
  final DiaryEntry entry;

  const DiaryViewPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    // --- 侦探工作：打印接收到的数据 ---
    // 当你点击卡片进入这个页面时，请查看 Android Studio 底部的 "Run" 窗口，
    // 你会看到类似 "详情页收到的日记内容: ..." 的打印信息。
    print('详情页收到的日记内容: text=${entry.text}, imagePath=${entry.imagePath}');

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('yyyy年M月d日', 'zh_CN').format(entry.date)),
        // 我们暂时先把删除按钮放在这里，之后可以再加回来
      ),
      body: ListView( // 使用 ListView 代替 SingleChildScrollView，可以更好地处理不同尺寸的屏幕
        padding: const EdgeInsets.all(16.0),
        children: [
          // --- 图片显示区域 ---
          // 检查图片路径是否存在且不为空
          if (entry.imagePath != null && entry.imagePath!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12.0),
              // 使用 Image.file 加载本地图片
              child: Image.file(
                File(entry.imagePath!),
                // 如果图片加载失败，显示一个错误图标
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.grey, size: 50),
                    ),
                  );
                },
              ),
            )
          else // 如果没有图片路径，显示一个占位符
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.image_not_supported, color: Colors.grey, size: 50),
              ),
            ),

          const SizedBox(height: 24),

          // --- 文本显示区域 ---
          // 检查文本是否为空
          Text(
            entry.text.isNotEmpty ? entry.text : '(这天没有写下任何文字)', // 如果文本为空，给一个提示
            style: const TextStyle(fontSize: 18, height: 1.5),
          ),
        ],
      ),
    );
  }
}