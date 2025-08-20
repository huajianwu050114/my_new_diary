// file: lib/diary_view_page.dart

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

  // 文件位置: lib/diary_view_page.dart -> _DiaryViewPageState class

  Future<void> _regenerateAiAnalysis() async {
    final entry = _currentEntry;
    if (entry == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在重新请求AI分析...')));

    final diaryService = context.read<DiaryService>();
    final geminiService = GeminiServiceLocal();
    if (entry.text.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日记内容为空，无法分析。')));
      return;
    }

    final prompt = """
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
  ${entry.text}
  """;
    final (responseText, _) = await geminiService.generateResponse([Content.text(prompt)], modelName: 'gemini-1.5-pro-latest');

    if (responseText != null) {
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

        // 关键：调用 _reloadData 来刷新当前页，而不是 pop
        await _reloadData();

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI分析已更新！'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI分析失败: $e'), backgroundColor: Colors.red));
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI未能返回有效内容。')));
    }
    // 确保这个方法的末尾没有 Navigator.of(context).pop()
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
              await Navigator.of(context).push(MaterialPageRoute(builder: (context) => AiChatPage(entry: entry)));
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

  // 文件位置: lib/diary_view_page.dart -> _DiaryViewPageState class

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

  // 文件位置: lib/diary_view_page.dart -> _DiaryViewPageState class

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
        if (aiSampleAnswer != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ExpansionTile(
              title: const Text("看看AI会怎么写..."),
              leading: Icon(Icons.auto_awesome_outlined, color: theme.colorScheme.secondary),
              backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              collapsedBackgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: MarkdownBody(
                    data: "> $aiSampleAnswer", selectable: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyMedium?.copyWith(height: 1.5, fontStyle: FontStyle.italic, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              ],
            ),
          ),
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