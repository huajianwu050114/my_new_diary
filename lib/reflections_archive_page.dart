import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';

class ReflectionsArchivePage extends StatelessWidget {
  const ReflectionsArchivePage({super.key});

  @override
  Widget build(BuildContext context) {
    final diaryService = context.watch<DiaryService>();
    return Scaffold(
      appBar: AppBar(title: const Text('AI回忆录')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: diaryService.getAllAiReflections(), // 我们需要添加这个方法
        builder: (context, snapshot) {
          // ... (加载、空状态、错误处理) ...
          final reflections = snapshot.data!;
          return ListView.builder(
            itemCount: reflections.length,
            itemBuilder: (context, index) {
              // ... (构建每个回忆录卡片) ...
            },
          );
        },
      ),
    );
  }
}