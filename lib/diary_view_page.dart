// file: libs/diary_view_page.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:my_new_diary/add_diary_page.dart';
import 'package:my_new_diary/ai_chat_page.dart';
import 'package:my_new_diary/diary_model.dart';
import 'package:my_new_diary/diary_service.dart';
import 'package:my_new_diary/gallery_page.dart';
import 'package:my_new_diary/gemini_service_local.dart';
import 'package:provider/provider.dart';
import 'package:google_generative_ai/google_generative_ai.dart';


class DiaryViewPage extends StatefulWidget {
  final DiaryEntry entry;
  final String? highlightKeyword;

  const DiaryViewPage({
    super.key,
    required this.entry,
    this.highlightKeyword,
  });

  @override
  State<DiaryViewPage> createState() => _DiaryViewPageState();
}

class _DiaryViewPageState extends State<DiaryViewPage> {
  // 1. 使用可空类型，并通过逻辑保证其安全
  DiaryEntry? _currentEntry;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _currentEntry = widget.entry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadData();
    });
  }

  // 2. 所有方法都加入了对 _currentEntry 的安全处理
  Future<void> _reloadData() async {
    final entry = _currentEntry;
    if (entry == null || !mounted) return;

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final diaryService = context.read<DiaryService>();
    final updatedEntry = await diaryService.getEntryById(entry.diaryId);
    if (mounted && updatedEntry != null) {
      setState(() {
        _currentEntry = updatedEntry;
      });
    }
  }

  Future<void> _togglePrivacy() async {
    final entry = _currentEntry;
    // 在方法开头增加安全检查
    if (entry == null || !mounted) return;

    final diaryService = context.read<DiaryService>();
    final updatedEntry = entry.copyWith(isPrivate: !entry.isPrivate);
    await diaryService.updateEntry(updatedEntry);

    setState(() {
      _currentEntry = updatedEntry;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(updatedEntry.isPrivate ? '已设为私密日记' : '已设为公开日记')),
      );
    }
  }

  void _deleteDiary() async {
    final entry = _currentEntry;
    if (entry == null || !mounted) return;

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('移入回收站'),
          content: const Text('你确定要把这篇日记移入回收站吗？'),
          actions: <Widget>[
            TextButton(child: const Text('取消'), onPressed: () => Navigator.of(context).pop(false)),
            TextButton(
              child: const Text('移入回收站'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmDelete == true && mounted) {
      await context.read<DiaryService>().moveEntryToTrash(entry.diaryId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  // 文件位置: libs/diary_view_page.dart -> _DiaryViewPageState class

  // +++ 这是修正后的新代码 +++
  // 文件位置: lib/diary_view_page.dart -> _DiaryViewPageState

  // 文件位置: lib/diary_view_page.dart -> _DiaryViewPageState

  // +++ 这是最终修正版，能智能判断日记类型并使用不同Prompt +++
  Future<void> _regenerateAiAnalysis() async {
    final entry = _currentEntry;
    if (entry == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在重新请求AI分析...')));

    final diaryService = context.read<DiaryService>();
    final geminiService = GeminiServiceLocal();

    // 1. 清理文本，移除AI范例回答部分，得到干净的分析材料
    String textForAnalysis = entry.text;
    const String sampleAnswerSeparator = "---AI_SAMPLE_ANSWER---";
    if (textForAnalysis.contains(sampleAnswerSeparator)) {
      textForAnalysis = textForAnalysis.split(sampleAnswerSeparator)[0].trim();
    }

    if (textForAnalysis.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日记内容为空，无法分析。')));
      return;
    }

    // 2. 智能判断日记类型，并构建不同的Prompt
    String finalPrompt;
    const String inspirationSeparator = "\n---\n";

    // 检查是否为“灵感回复”类型的日记
    if (textForAnalysis.contains('> ## AI 灵感:') && textForAnalysis.contains(inspirationSeparator)) {
      final parts = textForAnalysis.split(inspirationSeparator);
      final aiQuestion = parts[0].replaceAll('> ## AI 灵感:', '').replaceAll('>', '').trim();
      final userAnswer = parts.length > 1 ? parts[1].trim() : '';

      // VVVV  这是为“灵感回复”场景定制的全新Prompt VVVV
      finalPrompt = """
      你是一位充满同理心的日记分析师。之前，你向我提出了一个写作灵感问题，现在我做出了回应。请你专注于分析**我的回应**，而不是你之前提出的问题。

      你当时提出的问题是：
      "$aiQuestion"

      我的回应是：
      "$userAnswer"

      请你仔细阅读**我的回应**，并严格按照以下JSON格式返回对**我的回应**的分析，不要有任何额外的解释或修-饰:
      {
        "suggestedTitles": ["<根据我的回应生成的标题1>", "<标题2>", "<标题3>"],
        "summary": "<对我回应内容的大约50字摘要>",
        "detectedEmotion": "<从我的回应中解读出的微妙情绪>",
        "detectedThemes": ["<我回应中涉及的主题1>", "<主题2>", "<主题3>"],
        "proactiveQuestion": "<基于我的回应，提出一个能引导我深入思考的、友善的新问题>"
      }
      """;
    } else {
      // 如果是普通日记，则使用原来的通用Prompt
      finalPrompt = """
      请深度分析以下日记内容。请你扮演一个充满同理心、善于倾听的朋友。
      请严格按照以下JSON格式返回，不要有任何额外的解释或修饰:
      {
        "suggestedTitles": ["<标题1>", "<标题2>", "<标题3>"],
        "summary": "<大约50字的摘要>",
        "detectedEmotion": "<用一个描述性的词或短语总结文本中微妙的情绪>",
        "detectedThemes": ["<主题词1>", "<主题词2>", "<主题词3>"],
        "proactiveQuestion": "<基于日记内容，提出一个开放式的、能引导我深入思考的、友善的问题>"
      }
      日记内容如下:
      ---
      $textForAnalysis
      """;
    }

    // 3. 使用构建好的 aifinalPrompt 发起请求
    final (responseText, _) = await geminiService.generateResponse([Content.text(finalPrompt)], modelName: 'gemini-2.5-pro');

    if (responseText != null) {
      // ... 后续的JSON解析和保存逻辑保持不变 ...
      if (responseText.startsWith("ERROR:")) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI分析失败: ${responseText.substring(6)}'), backgroundColor: Colors.red));
        return;
      }
      try {
        String cleanedJson = responseText.trim().replaceAll("```json", "").replaceAll("```", "").trim();
        final decodedJson = jsonDecode(cleanedJson);
        final newMetadata = AiMetadata.fromJson(decodedJson);
        final updatedEntry = entry.copyWith(aiMetadata: newMetadata);
        await diaryService.updateEntry(updatedEntry);

        await _reloadData();

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI分析已更新！'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI分析失败: $e'), backgroundColor: Colors.red));
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI未能返回有效内容。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 3. 在 build 方法入口处进行一次总的空值检查
    final entry = _currentEntry;

    if (entry == null) {
      // 如果 entry 为空，显示加载动画，避免后续所有操作出错
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // 检查通过后，后续所有代码都可以安全地使用 entry
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(entry),
          _buildSliverContent(entry),
        ],
      ),
    );
  }

  // 4. 所有 _build... 辅助方法都接收一个非空的 DiaryEntry 对象
  Widget _buildSliverAppBar(DiaryEntry entry) {
    final hasImages = entry.imagePaths.isNotEmpty;
    return SliverAppBar(
      expandedHeight: hasImages ? 250.0 : 0,
      pinned: true,
      stretch: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      foregroundColor: Theme.of(context).colorScheme.onBackground,
      actions: [
        IconButton(
          icon: Icon(
            entry.isSelfHelp ? Icons.lightbulb : Icons.lightbulb_outline,
            color: entry.isSelfHelp ? Colors.amber : null,
          ),
          tooltip: entry.isSelfHelp ? '移出生存指南' : '收入生存指南',
          onPressed: _toggleSelfHelp, // 我们将创建这个方法
        ),
        IconButton(
          icon: Icon(entry.isPrivate ? Icons.lock_outline : Icons.lock_open_outlined),
          tooltip: entry.isPrivate ? '设为公开' : '设为私密',
          onPressed: _togglePrivacy,
        ),
        PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await Navigator.of(context).push(MaterialPageRoute(builder: (context) => AddDiaryPage(entryToEdit: entry)));
              _reloadData();
            } else if (value == 'chat_with_ai') {
              // 直接将原始的、完整的日记 entry 传递给聊天页面
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => AiChatPage(entry: entry)));
              _reloadData();
            } else if (value == 'delete') {
              _deleteDiary();
            } else if (value == 're_analyze') {
              _regenerateAiAnalysis();
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('编辑日记'))),
            const PopupMenuItem<String>(value: 'chat_with_ai', child: ListTile(leading: Icon(Icons.auto_awesome_outlined), title: Text('与AI交流'))),
            const PopupMenuItem<String>(value: 're_analyze', child: ListTile(leading: Icon(Icons.psychology_outlined), title: Text('重新生成AI分析'))),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('删除日记'))),
          ],
        ),
      ],
      flexibleSpace: hasImages
          ? FlexibleSpaceBar(stretchModes: const [StretchMode.zoomBackground], background: _buildImageViewer(entry))
          : null,
    );
  }

  // 文件位置: libs/diary_view_page.dart -> _DiaryViewPageState class

// VVVV 在类中添加这个新方法 VVVV
  Future<void> _toggleSelfHelp() async {
    final entry = _currentEntry;
    if (entry == null || !mounted) return;

    final diaryService = context.read<DiaryService>();
    final updatedEntry = entry.copyWith(isSelfHelp: !entry.isSelfHelp);
    await diaryService.updateEntry(updatedEntry);

    setState(() {
      _currentEntry = updatedEntry;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(updatedEntry.isSelfHelp ? '已收入生存指南' : '已移出生存指南')),
      );
    }
  }

  // 文件位置: libs/diary_view_page.dart -> _DiaryViewPageState class

  Widget _buildSliverContent(DiaryEntry entry) {
    final theme = Theme.of(context);
    String mainContent = entry.text;
    String? aiSampleAnswer;
    const String separator = "---AI_SAMPLE_ANSWER---";

    if (entry.text.contains(separator)) {
      final parts = entry.text.split(separator);
      mainContent = parts[0].trim();
      aiSampleAnswer = parts.length > 1 ? parts[1].trim() : null;
    }

    return SliverList(
      delegate: SliverChildListDelegate([
        // VVVV 布局顺序调整开始 VVVV

        // 1. AI提问卡片、心情、位置等信息保持在顶部

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Wrap(
            spacing: 8.0, runSpacing: 8.0,
            children: [
              if (entry.isPrivate)
                const Chip(avatar: Icon(Icons.lock_outline, size: 16), label: Text('私密日记')),
              if (entry.mood != null) _buildMoodIndicator(entry),
              if (entry.address != null && entry.address!.isNotEmpty)
                Chip(avatar: const Icon(Icons.location_on_outlined, size: 16), label: Text(entry.address!)),
            ],
          ),
        ),

        // 2. 日记正文
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
          child: MarkdownBody(
            data: mainContent, selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
              blockquoteDecoration: BoxDecoration(color: theme.colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),

        // 如果有AI示例回答，紧跟在正文后
        // 文件位置: lib/diary_view_page.dart -> _buildSliverContent()

// ...紧跟在 MarkdownBody(data: mainContent, ...) 之后...

// 如果有AI示例回答，紧跟在正文后
        // 文件位置: lib/diary_view_page.dart -> _buildSliverContent()

// ...紧跟在 MarkdownBody(data: mainContent, ...) 之后...

// 如果有AI示例回答，紧跟在正文后
        // 文件位置: lib/diary_view_page.dart -> _buildSliverContent()

// ...紧跟在 MarkdownBody(data: mainContent, ...) 之后...

// 如果有AI示例回答，紧跟在正文后
        if (aiSampleAnswer != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            // VVVV 使用我们全新的自定义小部件 VVVV
            child: CustomExpansionCard(
              leading: Icon(Icons.auto_awesome_outlined, color: Theme.of(context).colorScheme.secondary),
              title: const Text("看看AI会怎么写..."),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: MarkdownBody( // <--- 就是这个小部件
                    data: "> $aiSampleAnswer",
                    selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                      p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                      ),
                      // VVVV 这是决定性的一行代码 VVVV
                      // 直接告诉 "引用块" 使用一个带边框的透明背景
                      blockquoteDecoration: BoxDecoration(
                        color: Colors.transparent, // 背景透明
                        border: Border(
                          left: BorderSide(
                            color: Theme.of(context).dividerColor, // 左侧加一条淡淡的竖线以示区分
                            width: 4.0,
                          ),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.only(left: 16.0), // 增加一些左边距
                    ),
                  ),
                )
              ],
            ),
          ),

// ...后续代码保持不变...

// ...后续代码保持不变...

// ...后续代码保持不变...
        if (entry.tags.isNotEmpty) _buildTags(entry),
        _buildTimestamps(entry),

        // 3. 将 "AI悄悄话" 移动到这里
        if (entry.aiMetadata != null) _buildAiAnalysisSection(entry.aiMetadata!),
        _buildProactiveQuestionCard(entry),

        // 4. 其他信息（标签、分析记录、时间戳）保持在最下方

        if (entry.aiAnalyses.isNotEmpty) _buildAiAnalysisRecords(entry),




        // ^^^^ 布局顺序调整结束 ^^^^
      ]),
    );
  }



  // --- 所有辅助方法现在都接收 entry 作为参数 ---
  Widget _buildImageViewer(DiaryEntry entry) {
    return PageView.builder(
      itemCount: entry.imagePaths.length,
      onPageChanged: (index) {
        setState(() => _currentPage = index);
      },
      itemBuilder: (context, index) {
        final imagePath = entry.imagePaths[index];
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => GalleryPage(
                  imagePaths: entry.imagePaths,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: Hero(
            tag: imagePath,
            child: Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildImageErrorPlaceholder(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAiAnalysisSection(AiMetadata aiMeta) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.auto_awesome_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text("AI的悄悄话", style: Theme.of(context).textTheme.titleMedium),
              ]),
              const Divider(height: 24),
              if (aiMeta.detectedEmotion != null && aiMeta.detectedEmotion!.isNotEmpty) ...[
                Text("我感觉到，你的心情似乎是...", style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Chip(label: Text(aiMeta.detectedEmotion!)),
                const SizedBox(height: 16),
              ],
              if (aiMeta.summary != null && aiMeta.summary!.isNotEmpty) ...[
                Text("这篇日记的核心是...", style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                MarkdownBody(data: aiMeta.summary!, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: const TextStyle(height: 1.5, fontStyle: FontStyle.italic))),
                const SizedBox(height: 16),
              ],
              if (aiMeta.detectedThemes.isNotEmpty) ...[
                Text("你提到了这些主题...", style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8.0, children: aiMeta.detectedThemes.map((theme) => Chip(label: Text(theme))).toList()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProactiveQuestionCard(DiaryEntry entry) {
    if (entry.aiMetadata?.proactiveQuestion == null || entry.aiMetadata!.proactiveQuestion!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => AiChatPage(entry: entry)),
            ).then((_) => _reloadData());
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkdownBody(
                  data: entry.aiMetadata!.proactiveQuestion!,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('与AI继续聊聊', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: Theme.of(context).colorScheme.primary),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoodIndicator(DiaryEntry entry) {
    if (entry.mood == null || entry.mood!.isEmpty) return const SizedBox.shrink();
    const Map<String, String> moodMap = {'1': '特别开心', '2': '很开心', '3': '有点开心', '4': '一般', '5': '有点伤心', '6': '伤心', '7': '很伤心', '8': '崩溃', '0': '生病'};
    IconData getMoodIcon(String moodCode) {
      switch (moodCode) {
        case '1': return Icons.sentiment_very_satisfied; case '2': return Icons.sentiment_satisfied;
        case '3': return Icons.mood; case '4': return Icons.sentiment_neutral;
        case '5': return Icons.sentiment_dissatisfied; case '6': return Icons.sentiment_dissatisfied;
        case '7': return Icons.sentiment_very_dissatisfied; case '8': return Icons.mood_bad;
        case '0': return Icons.sick; default: return Icons.help_outline;
      }
    }
    final moodText = moodMap[entry.mood!] ?? '未知心情';
    return Chip(avatar: Icon(getMoodIcon(entry.mood!), size: 16), label: Text(moodText));
  }

  Widget _buildTags(DiaryEntry entry) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(spacing: 8.0, runSpacing: 4.0, children: entry.tags.map((tag) => Chip(label: Text(tag))).toList()),
    );
  }

  Widget _buildAiAnalysisRecords(DiaryEntry entry) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 8, bottom: 8),
            child: Text("AI 分析记录 (${entry.aiAnalyses.length})", style: Theme.of(context).textTheme.titleMedium),
          ),
          ...entry.aiAnalyses.map((analysis) => _buildAnalysisTile(analysis)).toList(),
        ],
      ),
    );
  }

  Widget _buildAnalysisTile(String analysisText) {
    return Card(
      elevation: 1, margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Icon(Icons.bookmark_border, color: Colors.amber.shade800),
        title: Text(analysisText.split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: MarkdownBody(data: analysisText, selectable: true, styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6))),
          )
        ],
      ),
    );
  }

  Widget _buildTimestamps(DiaryEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(top: 32, right: 24.0, bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('写于 ${DateFormat('yyyy-MM-dd HH:mm').format(entry.creationTime)}', style: Theme.of(context).textTheme.bodySmall),
          if (entry.lastModifiedTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                '修改于 ${DateFormat('yyyy-MM-dd HH:mm').format(entry.lastModifiedTime!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageErrorPlaceholder() {
    return Container(
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(15.0)),
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

// 文件: lib/diary_view_page.dart (粘贴到文件最底部)

// VVVV 全新的自定义可展开卡片小部件 VVVV
class CustomExpansionCard extends StatefulWidget {
  final Widget leading;
  final Widget title;
  final List<Widget> children;

  const CustomExpansionCard({
    super.key,
    required this.leading,
    required this.title,
    required this.children,
  });

  @override
  State<CustomExpansionCard> createState() => _CustomExpansionCardState();
}

class _CustomExpansionCardState extends State<CustomExpansionCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // 我们自己定义背景色，确保万无一失
    final cardBackgroundColor = isDarkMode
        ? theme.colorScheme.surfaceContainer // 一个比主背景稍亮的标准深灰色
        : theme.colorScheme.surfaceVariant.withOpacity(0.5);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: cardBackgroundColor, // 在 Card 上应用我们计算好的颜色
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero, // 外边距由外部的 Padding 控制
      child: Column(
        children: [
          // 可点击的头部
          ListTile(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            leading: widget.leading,
            title: widget.title,
            trailing: AnimatedRotation(
              turns: _isExpanded ? 0.5 : 0, // 箭头旋转动画
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.keyboard_arrow_down),
            ),
          ),
          // 可展开的内容区域
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Container(
              width: double.infinity,
              // 根据是否展开来决定是否显示子组件
              child: _isExpanded ? Column(children: widget.children) : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}