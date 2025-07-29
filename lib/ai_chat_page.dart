// file: lib/ai_chat_page.dart

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:provider/provider.dart';
import 'gemini_service_local.dart';
import 'diary_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

// Data structure to hold the chat message and its metadata
class ChatMessage {
  final Content content;
  final Duration? thinkingTime;
  ChatMessage(this.content, {this.thinkingTime});
}

class AiChatPage extends StatefulWidget {
  final DiaryEntry entry;
  const AiChatPage({super.key, required this.entry});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final GeminiServiceLocal _geminiService = GeminiServiceLocal();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialAnalysis();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialAnalysis() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final initialHistory = [Content.text(widget.entry.text)];

    // FIX: Unpack the (String?, Duration) record into two separate variables.
    final (responseText, duration) = await _geminiService.generateResponse(
        initialHistory);
    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(Content.text(widget.entry.text)));
        _messages.add(ChatMessage(Content.model(
            [TextPart(responseText ?? "Sorry, an error occurred...")]),
            thinkingTime: duration));
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendMessage() async {
    if (_textController.text
        .trim()
        .isEmpty || _isLoading) return;
    final message = _textController.text.trim();
    _textController.clear();

    final userMessage = Content.text(message);
    setState(() {
      _isLoading = true;
      _messages.add(ChatMessage(userMessage));
    });
    _scrollToBottom();

    final history = _messages.map((m) => m.content).toList();

    // FIX: Unpack the record here as well.
    final (responseText, duration) = await _geminiService.generateResponse(
        history);

    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(Content.model(
            [TextPart(responseText ?? "Sorry, an error occurred...")]),
            thinkingTime: duration));
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _saveAnalysis(String analysisText) async {
    await context.read<DiaryService>().addAnalysisToEntry(widget.entry, analysisText);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Analysis saved!'), duration: Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('与AI对话')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message.content.role == 'user';
                final isFirstMessage = index == 0;
                final text = message.content.parts.whereType<TextPart>().map((p) => p.text).join('');

                if (isFirstMessage) {
                  return _buildDiaryContextCard(text);
                }

                return _buildChatBubble(
                  text: text,
                  isUser: isUser,
                  thinkingTime: message.thinkingTime,
                  onSave: () => _saveAnalysis(text),
                );
              },
            ),
          ),
          if (_isLoading) const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: CircularProgressIndicator()),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildDiaryContextCard(String text) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("对话内容（你的日记）", style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 16),
            SelectableText(text, style: const TextStyle(height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble({required String text, required bool isUser, Duration? thinkingTime, required VoidCallback onSave}) {
    final theme = Theme.of(context);
    // 获取屏幕宽度，用于计算气泡的最大宽度
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          // 【修正2】: 使用ConstrainedBox来限制气泡的最大宽度
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screenWidth * 0.75, // 气泡最大宽度为屏幕的75%
            ),
            child: Card(
              elevation: 2,
              color: isUser ? theme.colorScheme.primary : theme.colorScheme.surfaceVariant,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Padding(
                // 【修正1】: 增加了垂直和水平的内边距
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                child: SelectableText( // 或者您之前修改的MarkdownBody
                  text,
                  style: TextStyle(
                    color: isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                    fontSize: 16, // 可以适当调整字体大小
                    height: 1.5,  // 增加行高，让多行文字也更舒适
                  ),
                ),
              ),
            ),
          ),
        ),
        // 下方的“思考耗时”和“保存”按钮部分保持不变
        if (!isUser)
          Padding(
            padding: const EdgeInsets.only(left: 16.0, top: 4.0),
            child: Row(
              children: [
                if (thinkingTime != null)
                  Text(
                    '思考耗时: ${(thinkingTime.inMilliseconds / 1000).toStringAsFixed(1)}s',
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(width: 16),
                TextButton.icon(
                  icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: const Text('保存此条'),
                  onPressed: onSave,
                  style: TextButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInputBar() {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    hintText: '继续对话...',
                    contentPadding: EdgeInsets.symmetric(horizontal: 20),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendMessage,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}