// file: lib/letters_archive_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LettersArchivePage extends StatefulWidget {
  const LettersArchivePage({super.key});

  @override
  State<LettersArchivePage> createState() => _LettersArchivePageState();
}

class _LettersArchivePageState extends State<LettersArchivePage> {
  String _selectedModel = 'gemini-1.5-pro-latest';
  final List<String> _availableModels = const ['gemini-1.5-flash-latest', 'gemini-1.5-pro-latest'];

  @override
  void initState() {
    super.initState();
    _loadModelSelection();
  }

  Future<void> _loadModelSelection() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedModel = prefs.getString('weekly_letter_model') ?? 'gemini-1.5-pro-latest';
    });
  }

  Future<void> _saveModelSelection(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('weekly_letter_model', model);
    setState(() {
      _selectedModel = model;
    });
  }

  void _showModelSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择信件生成模型'),
          children: _availableModels.map((model) {
            return RadioListTile<String>(
              title: Text(model.contains('pro') ? '专业模型 (高质量)' : '快速模型 (高效率)'),
              value: model,
              groupValue: _selectedModel,
              onChanged: (value) {
                if (value != null) {
                  _saveModelSelection(value);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('模型设置已保存！')),
                  );
                }
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final diaryService = context.watch<DiaryService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('精灵信箱'),
        actions: [
          IconButton(
            icon: const Icon(Icons.model_training_outlined),
            tooltip: '设置生成模型',
            onPressed: _showModelSelectionDialog,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        // ... (The FutureBuilder and ListView.builder code remains the same as before)
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
              // ... (The Slidable card logic remains the same)
            },
          );
        },
      ),
    );
  }
}