
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
  // 确认是否永久删除的对话框
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
    ) ?? false; // 如果用户直接关闭对话框，也视为取消
  }

  @override
  Widget build(BuildContext context) {
    // 这里我们用 watch，这样在恢复或删除后，列表能自动刷新
    final diaryService = context.watch<DiaryService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
      ),
      body: FutureBuilder<List<DiaryEntry>>(
        future: diaryService.getTrashEntries(),
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
                    // 在回收站里也可以查看日记详情
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
                          diaryService.restoreFromTrash(entry.filePath);
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
                            diaryService.deletePermanently(entry.filePath);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('日记已永久删除')),
                            );
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