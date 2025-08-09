// file: lib/letters_archive_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class LettersArchivePage extends StatefulWidget {
  const LettersArchivePage({super.key});

  @override
  State<LettersArchivePage> createState() => _LettersArchivePageState();
}

class _LettersArchivePageState extends State<LettersArchivePage> {
  @override
  Widget build(BuildContext context) {
    final diaryService = context.watch<DiaryService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('精灵信箱'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: diaryService.getAllWeeklyLetters(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('信箱还是空的哦～'));
          }
          final letters = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: letters.length,
            itemBuilder: (context, index) {
              final letter = letters[index];
              final date = DateTime.parse(letter['generationDate']);
              return Slidable(
                key: ValueKey(letter['id']),
                endActionPane: ActionPane(
                  motion: const StretchMotion(),
                  children: [
                    SlidableAction(
                      onPressed: (context) async {
                        await diaryService.deleteWeeklyLetter(letter['id']);
                        // No need to call setState here as FutureBuilder will refetch
                      },
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      icon: Icons.delete_forever,
                      label: '删除',
                    ),
                  ],
                ),
                child: Card(
                  child: ExpansionTile(
                    title: Text("来自 ${DateFormat('yyyy年M月d日').format(date)} 的信"),
                    leading: const Icon(Icons.mark_email_read_outlined),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: MarkdownBody(
                          data: letter['letterContent'],
                          selectable: true,
                        ),
                      )
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