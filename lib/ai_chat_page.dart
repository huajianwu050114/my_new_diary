// file: libs/ai_chat_page.dart

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:provider/provider.dart';
import 'gemini_service_local.dart';
import 'diary_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:uuid/uuid.dart';
import 'package:my_new_diary/diary_model.dart';

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

  // VVV 1. 添加这两个新的状态变量 VVV
  String _selectedChatModel = 'gemini-2.5-pro'; // 默认使用专业模型
  final List<String> _availableModels = const ['gemini-2.5-flash', 'gemini-2.5-pro'];

  // 文件位置: lib/ai_chat_page.dart -> _AiChatPageState

  @override
  void initState() {
    super.initState();
    _currentEntry = widget.entry;

    // VVVV  核心修改区域 VVVV
    if (_currentEntry!.conversations.isEmpty) {
      // 使用 WidgetsBinding 来延迟调用，确保在UI渲染完成后再执行
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) { // 再次检查以确保安全
          _createNewConversation();
        }
      });
    } else {
      // 这部分逻辑保持不变
      setState(() {
        _activeConversation = _currentEntry!.conversations.first;
      });
    }
    // ^^^^ 修改结束 ^^^^
  }

  // +++ 这是修正后的 _startAnalysisForConversation 方法 +++
  Future<void> _startAnalysisForConversation(Conversation conversation) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // VVVV 核心修改：在这里创建临时的、干净的文本用于聊天 VVVV
    String chatContext = _currentEntry!.text;
    const String separator = "---AI_SAMPLE_ANSWER---";
    if (chatContext.contains(separator)) {
      // 仅使用用户回复的部分作为聊天上下文
      chatContext = chatContext.split(separator)[0].trim();
    }
    // ^^^^ 修改结束 ^^^^

    // 使用我们刚刚处理过的 chatContext
    final (responseText, _) = await _geminiService.generateResponse(
      [Content.text(chatContext)],
      modelName: _selectedChatModel,
    );
    if (mounted) {
      setState(() {
        // 将干净的上下文和AI的回复加入对话历史
        conversation.history.add(Content.text(chatContext));
        conversation.history.add(Content.model([TextPart(responseText ?? "抱歉，发生了错误...")]));
        conversation.title = _currentEntry!.text.split('\n').first;
        _isLoading = false;
      });
      _scrollToBottom();
      // 关键：这里保存的 _currentEntry 仍然是完整的，包含AI样本答案！
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

  // 文件位置: lib/ai_chat_page.dart -> _AiChatPageState

  Future<void> _saveConversations() async {
    final diaryService = context.read<DiaryService>();
    if (_currentEntry == null) return;

    // 1. 先从数据库获取最新的、最完整的原始日记
    final pristineEntry = await diaryService.getEntryById(_currentEntry!.diaryId);

    if (pristineEntry != null) {
      // 2. 基于这个完整的原始日记，只更新它的对话列表
      final entryToSave = pristineEntry.copyWith(
        conversations: _currentEntry!.conversations,
      );
      // 3. 保存这个“合并”后的、信息完整的日记
      await diaryService.updateEntry(entryToSave);
    } else {
      // 备用方案：如果因故没找到，则保存当前内存中的版本
      await diaryService.updateEntry(_currentEntry!);
    }
  }

  // +++ 这是修正后的 _startInitialAnalysisForConversation 方法 +++
  Future<void> _startInitialAnalysisForConversation(Conversation conversation) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // VVVV 核心修改：同样在这里创建临时的、干净的文本用于聊天 VVVV
    String chatContext = _currentEntry!.text;
    const String separator = "---AI_SAMPLE_ANSWER---";
    if (chatContext.contains(separator)) {
      // 仅使用用户回复的部分作为聊天上下文
      chatContext = chatContext.split(separator)[0].trim();
    }
    // ^^^^ 修改结束 ^^^^

    final (responseText, _) = await _geminiService.generateResponse(
      [Content.text(chatContext)], // 使用干净的上下文
      modelName: _selectedChatModel,
    );
    if (mounted) {
      setState(() {
        conversation.history.add(Content.text(chatContext)); // 使用干净的上下文
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
    final (responseText, _) = await _geminiService.generateResponse(
      conversation.history,
      modelName: _selectedChatModel, // <-- VVV 使用状态变量
    );

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

    await context.read<DiaryService>().saveConversationAsAnalysis(_currentEntry!.diaryId, formattedText);

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: DropdownButton<String>(
              value: _selectedChatModel,
              items: _availableModels.map((String model) {
                return DropdownMenuItem<String>(
                  value: model,
                  // 为了显示简洁，我们只显示 pro 或 flash
                  child: Text(
                    model.contains('pro') ? 'Pro' : 'Flash',
                    style: TextStyle(
                      color: Theme.of(context).appBarTheme.foregroundColor,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (String? newModel) {
                if (newModel != null) {
                  setState(() {
                    _selectedChatModel = newModel;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('模型已切换为: $newModel'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              underline: const SizedBox(), // 隐藏下划线
              icon: Icon(
                Icons.model_training,
                color: Theme.of(context).appBarTheme.foregroundColor,
              ),
            ),
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
  /// 构建带有勾选框的聊天气泡
  Widget _buildChatBubble({required Content message, required String text, required bool isUser}) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSelected = _selectedMessages.contains(message);


    return Row(
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // VVVV 核心修改 1: 用户消息的勾选框现在在左边 VVVV
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

        // 气泡本身 (保持不变)
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: screenWidth * 0.8),
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

        // VVVV 核心修改 2: AI 消息的勾选框现在在右边 VVVV
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
      ],
    );
  }

  // 文件位置: libs/ai_chat_page.dart -> _AiChatPageState

  // 文件位置: lib/ai_chat_page.dart -> _AiChatPageState

  Widget _buildDiaryContextCard(String text) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      // 保持 Card 的颜色不变，我们只处理 MarkdownBody
      color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("对话上下文 (你的日记)", style: theme.textTheme.bodySmall),
            const Divider(height: 16),
            MarkdownBody(
              data: text,
              selectable: true,
              // VVVV 核心修改: 严格按照您的要求，应用与上一个问题完全相同的解决方案 VVVV
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: const TextStyle(height: 1.5),
                // 明确指定 "引用块" 的样式
                blockquoteDecoration: BoxDecoration(
                  color: Colors.transparent, // 强制引用块背景透明
                  border: Border(
                    left: BorderSide(
                      color: theme.dividerColor, // 左侧加一条淡淡的竖线以示区分
                      width: 4.0,
                    ),
                  ),
                ),
                blockquotePadding: const EdgeInsets.only(left: 16.0),
              ),
            ),
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