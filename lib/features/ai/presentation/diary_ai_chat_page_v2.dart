import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:uuid/uuid.dart';

import '../../diary/domain/entities/diary_entry.dart';
import '../../diary/domain/repositories/diary_repository_v2.dart';
import '../application/diary_ai_service_v2.dart';
import '../data/ai_configuration_store_v2.dart';
import '../data/gemini_rest_client_v2.dart';
import '../domain/ai_models_v2.dart';
import '../domain/ai_chat_session_v2.dart';

class DiaryAiChatPageV2 extends StatefulWidget {
  const DiaryAiChatPageV2({
    required this.entry,
    required this.repository,
    super.key,
    DiaryAiServiceV2? service,
    this.session,
  }) : _service = service;

  final DiaryEntryV2 entry;
  final DiaryRepositoryV2 repository;
  final DiaryAiServiceV2? _service;
  final AiChatSessionV2? session;

  @override
  State<DiaryAiChatPageV2> createState() => _DiaryAiChatPageV2State();
}

class _DiaryAiChatPageV2State extends State<DiaryAiChatPageV2> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<AiSessionMessageV2> _messages = [];
  late final DiaryAiServiceV2 _service;
  late DiaryEntryV2 _entry;
  late AiChatSessionV2 _session;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    final now = DateTime.now().toUtc();
    _session =
        widget.session ??
        AiChatSessionV2(
          id: const Uuid().v4(),
          title: '新对话',
          createdAt: now,
          updatedAt: now,
          messages: const [],
        );
    _messages.addAll(_session.messages);
    _service =
        widget._service ??
        DiaryAiServiceV2(
          GeminiRestClientV2(configurationStore: AiConfigurationStoreV2()),
        );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_session.title)),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const _EmptyChat()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _MessageBubble(message: _messages[index]),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: '想围绕这篇日记聊些什么？',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now().toUtc();
    final userMessage = AiSessionMessageV2(
      role: AiChatRoleV2.user,
      text: text,
      createdAt: now,
    );
    setState(() {
      _messages.add(userMessage);
      _sending = true;
      _controller.clear();
    });
    _scrollToEnd();
    try {
      final response = await _service.chat(
        entry: _entry,
        conversation: _messages
            .map((message) => message.toChatMessage())
            .toList(growable: false),
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          AiSessionMessageV2(
            role: AiChatRoleV2.model,
            text: response.text,
            createdAt: DateTime.now().toUtc(),
          ),
        );
      });
      final firstUserMessage = _messages.firstWhere(
        (message) => message.role == AiChatRoleV2.user,
      );
      _session = _session.copyWith(
        title: _session.title == '新对话'
            ? _sessionTitle(firstUserMessage.text)
            : _session.title,
        updatedAt: DateTime.now().toUtc(),
        messages: _messages,
      );
      final storedSession = _session.encode();
      final analyses = [..._entry.aiAnalyses];
      final existingIndex = analyses.indexWhere(
        (value) => AiChatSessionV2.tryDecode(value)?.id == _session.id,
      );
      if (existingIndex == -1) {
        analyses.add(storedSession);
      } else {
        analyses[existingIndex] = storedSession;
      }
      _entry = _entry.copyWith(
        aiAnalyses: analyses,
        updatedAt: DateTime.now().toUtc(),
      );
      await widget.repository.save(_entry);
      if (mounted) setState(() {});
    } on AiFailureV2 catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToEnd();
      }
    }
  }

  String _sessionTitle(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 18
        ? normalized
        : '${normalized.substring(0, 18)}…';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 54,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('从这篇日记开始聊聊', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('可以梳理感受、回顾细节，或者只是找一个安静的回应。'),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AiSessionMessageV2 message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == AiChatRoleV2.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: isUser
            ? SelectableText(message.text)
            : MarkdownBody(data: message.text, selectable: true),
      ),
    );
  }
}
