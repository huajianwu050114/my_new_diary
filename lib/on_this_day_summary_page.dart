// file: libs/on_this_day_summary_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import 'diary_model.dart';
import 'gemini_service_local.dart';
import 'dart:io';
import 'diary_view_page.dart';
import 'package:provider/provider.dart';
import 'diary_service.dart';

class OnThisDaySummaryPage extends StatefulWidget {
  final List<DiaryEntry> entries;
  final String pageTitle; // VVV 新增：自定义页面标题 VVV
  final String aiPrompt;  // VVV 新增：自定义AI指令 VVV


  const OnThisDaySummaryPage({
    super.key,
    required this.entries,
    this.pageTitle = '时光总结', // 默认标题
    // 默认的“那年今日”AI指令
    this.aiPrompt = """
    你是一个温暖、充满智慧且善于洞察的朋友。下面是我在过去几年同一天写的几篇日记。
    请你仔细阅读并比较它们，然后为我撰写一段充满温度的“时光总结”。

    在总结中，请帮我：
    1. 直接以第二人称“你”对我说话。
    2. 串联起这些不同年份的记忆，看看当时我在关心什么，感受如何。
    3. 敏锐地发现我心态、关注点或生活状态上的变化与成长。
    4. 如果发现有反复出现的主题或情绪，可以指出来。
    5. 最后，用一句鼓励或引人深思的话语作为结尾。

    我的日记内容如下：
    """,
  });

  @override
  State<OnThisDaySummaryPage> createState() => _OnThisDaySummaryPageState();
}

class _OnThisDaySummaryPageState extends State<OnThisDaySummaryPage> {
  String? _aiSummary;
  bool _isLoading = true;
  String _errorMessage = '';
  String _selectedReflectionModel = 'gemini-2.5-pro'; // 默认使用专业模型
  final List<String> _availableModels = const ['gemini-2.5-flash', 'gemini-2.5-pro'];

  @override
  void initState() {
    super.initState();
    // VVV 1. 改造初始化逻辑 VVV
    _loadOrGenerateSummary();
  }

  // VVV 2. 全新的加载/生成方法 VVV
  Future<void> _loadOrGenerateSummary() async {
    if (!mounted) return;

    // 根据页面标题判断回顾类型，用于存储
    final reflectionType = widget.pageTitle.contains('那年') ? 'annual' :
    widget.pageTitle.contains('那月') ? 'monthly' :
    'hundred_day';

    // 步骤A: 尝试从数据库（缓存/存档）加载今天的总结
    final diaryService = context.read<DiaryService>();
    final cachedSummary = await diaryService.getTodaysReflection(reflectionType);

    if (cachedSummary != null) {
      // 如果找到了，直接显示，无需等待
      if (mounted) {
        setState(() {
          _aiSummary = cachedSummary;
          _isLoading = false;
        });
      }
    } else {
      // 步骤B: 如果没找到，才开始生成
      await _generateSummary(diaryService, reflectionType);
    }
  }

  Future<void> _generateSummary(DiaryService diaryService, String reflectionType) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final buffer = StringBuffer();
    // VVV 使用 widget.aiPrompt 作为指令的开头 VVV
    buffer.writeln("${widget.aiPrompt}\n");
    for (final entry in widget.entries) {
      buffer.writeln("--- 日记日期: ${DateFormat('yyyy年M月d日').format(entry.date)} ---");
      buffer.writeln(entry.text);
      buffer.writeln();
    }

    final fullPrompt = buffer.toString();

    final geminiService = GeminiServiceLocal();
    try {
      final (responseText, _) = await geminiService.generateResponse(
        [Content.text(fullPrompt)],
        modelName: _selectedReflectionModel, // <-- VVV 4. Use the state variable
      );
      if (mounted && responseText != null) {
        await diaryService.saveAiReflection(reflectionType, responseText); // <-- 保存！
        setState(() {
          _aiSummary = responseText;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "生成AI总结失败，请稍后再试。\n错误: $e";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // VVV 使用 widget.pageTitle 作为页面标题 VVV
        title: Text(widget.pageTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: DropdownButton<String>(
              value: _selectedReflectionModel,
              items: _availableModels.map((String model) {
                return DropdownMenuItem<String>(
                  value: model,
                  child: Text(
                    model.contains('pro') ? 'Pro' : 'Flash',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).appBarTheme.foregroundColor,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (String? newModel) {
                if (newModel != null && newModel != _selectedReflectionModel) {
                  setState(() {
                    _selectedReflectionModel = newModel;
                  });
                  // When the model is changed, re-run the generation
                  _loadOrGenerateSummary();
                }
              },
              underline: const SizedBox(),
              icon: Icon(
                Icons.model_training,
                color: Theme.of(context).appBarTheme.foregroundColor,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage.isNotEmpty
                  ? Text(_errorMessage, style: TextStyle(color: Theme.of(context).colorScheme.error))
                  : MarkdownBody(
                data: _aiSummary ?? 'AI正在为你连接时光...',
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ),
            ),
          ),
          const Divider(height: 48),
          Text('原始日记回顾', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          ...widget.entries.map((entry) => _buildOnThisDayCard(context, entry)),
        ],
      ),
    );
  }

  Widget _buildOnThisDayCard(BuildContext context, DiaryEntry entry) {
    // ... 这个方法无需改动 ...
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => DiaryViewPage(entry: entry))),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Container(
                width: 80,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.date.year.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('M月d日', 'zh_CN').format(entry.date),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  entry.text.isNotEmpty ? entry.text : '(无文字内容)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (entry.imagePaths.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(entry.imagePaths.first),
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}