// file: lib/ai_chat_page.dart

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:provider/provider.dart';
import 'gemini_service_local.dart';
import 'diary_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:uuid/uuid.dart';

class AiChatPage extends StatefulWidget {
  final DiaryEntry entry;
  const AiChatPage({super.key, required this.entry});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  // --- Services & Controllers ---
  final GeminiServiceLocal _geminiService = GeminiServiceLocal();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- State Variables ---
  // VVV 1. MODIFICATION: Changed from 'late' to nullable 'DiaryEntry?' VVV
  DiaryEntry? _currentEntry;
  Conversation? _activeConversation;
  bool _isLoading = false;
  final Set<Content> _selectedMessages = {};

  @override
  void initState() {
    super.initState();
    // VVV 2. MODIFICATION: Initialize the nullable variable. It's now guaranteed to be non-null after this point. VVV
    _currentEntry = widget.entry;


    if (_currentEntry!.conversations.isEmpty) {
      _createNewConversation();
    } else {
      setState(() {
        _activeConversation = _currentEntry!.conversations.first;
      });
    }
  }

  Future<void> _startAnalysisForConversation(Conversation conversation) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // 使用日记原文作为上下文
    final (responseText, _) = await _geminiService.generateResponse([Content.text(_currentEntry!.text)]);

    if (mounted) {
      setState(() {
        // 将日记原文和AI的首次回复加入该对话的历史记录
        conversation.history.add(Content.text(_currentEntry!.text));
        conversation.history.add(Content.model([TextPart(responseText ?? "抱歉，发生了错误...")]));
        // 将日记的第一行作为对话标题
        conversation.title = _currentEntry!.text.split('\n').first;
        _isLoading = false;
      });
      _scrollToBottom();
      await _saveConversations();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- Core Logic ---
  // VVV 3. MODIFICATION: Use the '!' operator to assert that _currentEntry is not null. VVV

  Conversation? get _getActiveConversation {
    if (_activeConversation == null) return null;
    // This is a safer way to find the conversation without causing an error.
    for (final conversation in _currentEntry!.conversations) {
      if (conversation.id == _activeConversation!.id) {
        return conversation;
      }
    }
    return null; // Return null if no matching conversation is found in the list.
  }

  void _createNewConversation() {
    final newConversation = Conversation(
      id: const Uuid().v4(),
      title: '正在分析...', // 临时标题
      history: [],
    );
    setState(() {
      _currentEntry!.conversations.insert(0, newConversation);
      _activeConversation = newConversation;
    });

    // 创建后立即开始分析
    _startAnalysisForConversation(newConversation);
  }

  void _deleteConversation(String conversationId) {
    setState(() {
      _currentEntry!.conversations.removeWhere((c) => c.id == conversationId);
      if (_activeConversation?.id == conversationId) {
        _activeConversation = _currentEntry!.conversations.isNotEmpty ? _currentEntry!.conversations.first : null;
      }
    });
    _saveConversations();
    Navigator.of(context).pop();
  }

  Future<void> _saveConversations() async {
    await context.read<DiaryService>().updateEntry(_currentEntry!);
  }

  Future<void> _startInitialAnalysisForConversation(Conversation conversation) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final (responseText, _) = await _geminiService.generateResponse([Content.text(_currentEntry!.text)]);

    if (mounted) {
      setState(() {
        conversation.history.add(Content.text(_currentEntry!.text));
        conversation.history.add(Content.model([TextPart(responseText ?? "抱歉，发生了错误...")]));
        conversation.title = _currentEntry!.text.split('\n').first;
        _isLoading = false;
      });
      _scrollToBottom();
      await _saveConversations();
    }
  }

  Future<void> _sendMessage() async {
    final conversation = _getActiveConversation;
    if (_textController.text.trim().isEmpty || _isLoading || conversation == null) return;

    final message = _textController.text.trim();
    _textController.clear();

    final userMessage = Content.text(message);
    setState(() {
      _isLoading = true;
      conversation.history.add(userMessage);
    });
    _scrollToBottom();

    // VVV 3a. 关键修改：不再需要手动添加上下文 VVV
    // 因为上下文（日记原文）已经是 history 的第一条消息了
    final (responseText, _) = await _geminiService.generateResponse(conversation.history);

    if (mounted) {
      setState(() {
        conversation.history.add(Content.model([TextPart(responseText ?? "抱歉，发生了错误...")]));
        _isLoading = false;
      });
      _scrollToBottom();
      await _saveConversations();
    }
  }

  Future<void> _saveSelectedAsAnalysis() async {
    if (_selectedMessages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先勾选需要保存的内容。')));
      return;
    }

    final conversation = _getActiveConversation;
    if (conversation == null) return;

    final sortedSelected = conversation.history.where((msg) => _selectedMessages.contains(msg)).toList();

    // VVV 5a. 在保存的内容顶部加上对话标题 VVV
    final String header = '**${conversation.title}**\n\n---\n\n';

    final conversationBody = sortedSelected.map((content) {
      final role = content.role == 'user' ? '**我:**' : '**AI:**';
      final text = content.parts.whereType<TextPart>().map((p) => p.text).join('');
      return '$role\n$text';
    }).join('\n\n---\n\n');

    final formattedText = header + conversationBody;

    if (formattedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有可保存的对话。')));
      return;
    }

    await context.read<DiaryService>().saveConversationAsAnalysis(_currentEntry!.filePath, formattedText);

    if(mounted) {
      setState(() => _selectedMessages.clear());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存到AI分析记录！')));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }


  // --- UI Widgets ---

  @override
  Widget build(BuildContext context) {
    final conversation = _getActiveConversation;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(conversation?.title ?? '与AI对话'),
        actions: [
          // “追加勾选内容”按钮
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined), // 换一个更贴切的图标
            tooltip: '保存勾选内容到分析记录',
            onPressed: _selectedMessages.isEmpty ? null : _saveSelectedAsAnalysis, // 调用新方法
          ),
          // 打开侧边栏按钮
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: '对话列表',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      // VVV 侧边栏 VVV
      endDrawer: _buildConversationDrawer(),
      body: Column(
        children: [
          Expanded(
            child: conversation == null
                ? const Center(child: Text('没有活动的对话。'))
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              itemCount: conversation.history.length,
              itemBuilder: (context, index) {
                final message = conversation.history[index];
                final isUser = message.role == 'user';
                final text = message.parts.whereType<TextPart>().map((p) => p.text).join('');

                if (index == 0 && isUser) {
                  return _buildDiaryContextCard(text);
                }

                return _buildChatBubble(
                  message: message,
                  text: text,
                  isUser: isUser,
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

  /// 构建侧边栏
  Widget _buildConversationDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('新建对话'),
              onTap: () {
                _createNewConversation();
                Navigator.of(context).pop();
              },
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _currentEntry!.conversations.length,
                itemBuilder: (context, index) {
                  final conv = _currentEntry!.conversations[index];
                  final bool isActive = _activeConversation?.id == conv.id;
                  return ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: Text(
                      conv.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: isActive,
                    selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    onTap: () {
                      setState(() => _activeConversation = conv);
                      Navigator.of(context).pop();
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _deleteConversation(conv.id),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建带有勾选框的聊天气泡
  Widget _buildChatBubble({required Content message, required String text, required bool isUser}) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSelected = _selectedMessages.contains(message);

    return Row(
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // AI消息的勾选框在左边
        if (!isUser)
          Checkbox(
            value: isSelected,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedMessages.add(message);
                } else {
                  _selectedMessages.remove(message);
                }
              });
            },
          ),

        // 气泡本身
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: screenWidth * 0.65),
            child: Card(
              elevation: 2,
              color: isUser ? theme.colorScheme.primary : theme.colorScheme.surfaceVariant,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                child: MarkdownBody(
                  data: text,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodyLarge?.copyWith(
                      color: isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                      fontSize: 16, height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 用户消息的勾选框在右边
        if (isUser)
          Checkbox(
            value: isSelected,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedMessages.add(message);
                } else {
                  _selectedMessages.remove(message);
                }
              });
            },
          ),
      ],
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
            Text("对话上下文 (你的日记)", style: Theme.of(context).textTheme.bodySmall),
            const Divider(height: 16),
            SelectableText(text, style: const TextStyle(height: 1.5)),
          ],
        ),
      ),
    );
  }

  // VVV 15. 修改 _buildChatBubble 定义，移除不再需要的参数 VVV

  Widget _buildInputBar() {
    // This method remains the same
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