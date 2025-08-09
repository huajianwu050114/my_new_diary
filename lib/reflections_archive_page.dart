// file: lib/reflections_archive_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';

class ReflectionsArchivePage extends StatelessWidget {
  const ReflectionsArchivePage({super.key});

  String _getReflectionTitle(String type) {
    switch (type) {
      case 'annual': return '那年今日';
      case 'monthly': return '那月今日';
      case 'hundred_day': return '百日回顾';
      default: return 'AI 回忆录';
    }
  }

  @override
  Widget build(BuildContext context) {
    final diaryService = context.watch<DiaryService>();
    return Scaffold(
      appBar: AppBar(title: const Text('AI回忆录')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: diaryService.getAllAiReflections(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('还没有任何AI生成的回忆录'));
          }
          final reflections = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: reflections.length,
            itemBuilder: (context, index) {
              final reflection = reflections[index];
              final date = DateTime.parse(reflection['generationDate']);
              return Card(
                child: ExpansionTile(
                  title: Text(_getReflectionTitle(reflection['reflectionType'])),
                  subtitle: Text(DateFormat('yyyy年M月d日').format(date)),
                  leading: const Icon(Icons.auto_stories_outlined),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: MarkdownBody(
                        data: reflection['reflectionContent'],
                        selectable: true,
                      ),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}