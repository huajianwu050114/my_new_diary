// 文件: lib/recycle_bin_page.dart (已适配云端数据)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';
import 'diary_view_page.dart';

class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  // 确认是否永久删除的对话框 (此方法无需修改)
  Future<bool> _showDeleteConfirmDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除'),
        content: const Text('这个操作无法撤销，您确定要永久删除这篇日记吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认删除'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final diaryService = context.watch<DiaryService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
      ),
      // --- 核心修正点 1: 使用 StreamBuilder 替代 FutureBuilder ---
      body: StreamBuilder<List<DiaryEntry>>(
        // 调用新的 stream 方法
        stream: diaryService.getTrashEntriesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                '回收站是空的',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          final entries = snapshot.data!;
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(
                    entry.text.isNotEmpty ? entry.text : '(无文字内容)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(entry.creationTime)),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => DiaryViewPage(entry: entry)),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 恢复按钮
                      IconButton(
                        icon: const Icon(Icons.restore, color: Colors.green),
                        tooltip: '恢复',
                        onPressed: () {
                          // --- 核心修正点 2: 使用 diaryId ---
                          diaryService.restoreFromTrash(entry.diaryId);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('日记已恢复')),
                          );
                        },
                      ),
                      // 永久删除按钮
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                        tooltip: '永久删除',
                        onPressed: () async {
                          final confirm = await _showDeleteConfirmDialog();
                          if (confirm) {
                            // --- 核心修正点 3: 使用 diaryId ---
                            diaryService.deletePermanently(entry.diaryId);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('日记已永久删除')),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}