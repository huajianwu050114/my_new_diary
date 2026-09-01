import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../application/diary_ai_service_v2.dart';
import '../data/ai_configuration_store_v2.dart';
import '../data/gemini_rest_client_v2.dart';
import '../domain/ai_chat_session_v2.dart';
import '../domain/ai_models_v2.dart';
import '../domain/guided_journal_v2.dart';

class GuidedJournalPageV2 extends StatefulWidget {
  const GuidedJournalPageV2({super.key, DiaryAiServiceV2? service})
    : _service = service;

  final DiaryAiServiceV2? _service;

  @override
  State<GuidedJournalPageV2> createState() => _GuidedJournalPageV2State();
}

class _GuidedJournalPageV2State extends State<GuidedJournalPageV2> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<AiSessionMessageV2> _messages = [];
  late final DiaryAiServiceV2 _service;
  GuidedJournalCadenceV2 _cadence = GuidedJournalCadenceV2.natural;
  Timer? _responseTimer;
  bool _responding = false;
  bool _composing = false;

  bool get _hasUserMessages =>
      _messages.any((message) => message.role == AiChatRoleV2.user);

  int get _pendingUserMessages {
    var count = 0;
    for (final message in _messages.reversed) {
      if (message.role == AiChatRoleV2.model) break;
      count++;
    }
    return count;
  }

  int get _pendingUserCharacters {
    var count = 0;
    for (final message in _messages.reversed) {
      if (message.role == AiChatRoleV2.model) break;
      count += message.text.length;
    }
    return count;
  }

  bool get _hasModelReply =>
      _messages.any((message) => message.role == AiChatRoleV2.model);

  bool get _shouldReplyAutomatically {
    if (!_hasModelReply) return true;
    return switch (_cadence) {
      GuidedJournalCadenceV2.quiet =>
        _pendingUserMessages >= 3 || _pendingUserCharacters >= 140,
      GuidedJournalCadenceV2.natural =>
        _pendingUserMessages >= 2 || _pendingUserCharacters >= 90,
      GuidedJournalCadenceV2.curious => true,
    };
  }

  @override
  void initState() {
    super.initState();
    _service =
        widget._service ??
        DiaryAiServiceV2(
          GeminiRestClientV2(configurationStore: AiConfigurationStoreV2()),
        );
  }

  @override
  void dispose() {
    _responseTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('陪我聊着写'),
        actions: [
          TextButton(
            onPressed: !_hasUserMessages || _responding || _composing
                ? null
                : _composeDiary,
            child: Text(_composing ? '整理中…' : '整理成日记'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          _buildCadenceBar(),
          const Divider(height: 1),
          Expanded(
            child: _messages.isEmpty
                ? const _GuidedJournalEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _GuidedMessageBubble(message: _messages[index]),
                  ),
          ),
          if (_pendingUserMessages > 0 || _responding)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.hearing_rounded,
                    size: 17,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _responding ? '对方正在输入…' : '我在听，你可以继续说',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: _responding ? null : () => _requestReply(true),
                    child: const Text('请回应'),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Focus(
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent ||
                            event.logicalKey != LogicalKeyboardKey.enter ||
                            HardwareKeyboard.instance.isShiftPressed) {
                          return KeyEventResult.ignored;
                        }
                        final composing = _controller.value.composing;
                        if (composing.isValid && !composing.isCollapsed) {
                          return KeyEventResult.ignored;
                        }
                        _send();
                        return KeyEventResult.handled;
                      },
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        onChanged: (value) {
                          if (value.trim().isNotEmpty) _responseTimer?.cancel();
                        },
                        decoration: const InputDecoration(
                          hintText: '想到什么就说什么，可以连续发几句…',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: '先记下，不要求立即回应',
                    onPressed: _composing ? null : _send,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCadenceBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: SegmentedButton<GuidedJournalCadenceV2>(
        showSelectedIcon: false,
        segments: GuidedJournalCadenceV2.values
            .map(
              (value) => ButtonSegment(value: value, label: Text(value.label)),
            )
            .toList(growable: false),
        selected: {_cadence},
        onSelectionChanged: (values) => setState(() {
          _cadence = values.first;
        }),
      ),
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _responseTimer?.cancel();
    setState(() {
      _messages.add(
        AiSessionMessageV2(
          role: AiChatRoleV2.user,
          text: text,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      _controller.clear();
    });
    _scrollToEnd();
    _scheduleAutomaticReply();
  }

  void _scheduleAutomaticReply() {
    _responseTimer?.cancel();
    final delay = switch (_cadence) {
      GuidedJournalCadenceV2.quiet => const Duration(seconds: 6),
      GuidedJournalCadenceV2.natural => const Duration(milliseconds: 2800),
      GuidedJournalCadenceV2.curious => const Duration(milliseconds: 1200),
    };
    _responseTimer = Timer(delay, () {
      if (mounted &&
          !_composing &&
          _controller.text.trim().isEmpty &&
          _pendingUserMessages > 0 &&
          _shouldReplyAutomatically) {
        _requestReply(false);
      }
    });
  }

  Future<void> _requestReply(bool force) async {
    if (_responding || _pendingUserMessages == 0) return;
    _responseTimer?.cancel();
    final messageCountAtRequest = _messages.length;
    var becameStale = false;
    setState(() => _responding = true);
    try {
      final decision = await _service.guidedJournalReply(
        conversation: _messages
            .map((message) => message.toChatMessage())
            .toList(growable: false),
        cadence: _cadence,
        force: force,
      );
      if (!mounted) return;
      becameStale =
          _messages.length != messageCountAtRequest ||
          _controller.text.trim().isNotEmpty;
      if (becameStale) return;
      if (decision.respond) {
        setState(() {
          _messages.add(
            AiSessionMessageV2(
              role: AiChatRoleV2.model,
              text: decision.reply,
              createdAt: DateTime.now().toUtc(),
            ),
          );
        });
        _scrollToEnd();
      }
    } on AiFailureV2 catch (error) {
      if (mounted) _message(error.message);
    } on FormatException {
      if (mounted) _message('AI这次没有组织好回应，你可以继续说');
    } finally {
      if (mounted) {
        becameStale =
            becameStale ||
            _messages.length != messageCountAtRequest ||
            _controller.text.trim().isNotEmpty;
        setState(() => _responding = false);
        if (becameStale && _controller.text.trim().isEmpty) {
          _scheduleAutomaticReply();
        }
      }
    }
  }

  Future<void> _composeDiary() async {
    _responseTimer?.cancel();
    setState(() => _composing = true);
    try {
      final response = await _service.composeGuidedJournal(_messages);
      if (!mounted) return;
      final now = DateTime.now().toUtc();
      final first = _messages.firstWhere(
        (message) => message.role == AiChatRoleV2.user,
      );
      final session = AiChatSessionV2(
        id: const Uuid().v4(),
        title: _sessionTitle(first.text),
        createdAt: _messages.first.createdAt,
        updatedAt: now,
        messages: List.unmodifiable(_messages),
      );
      Navigator.of(
        context,
      ).pop(GuidedJournalDraftV2(body: response.text, session: session));
    } on AiFailureV2 catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _composing = false);
    }
  }

  String _sessionTitle(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.length <= 16
        ? '陪我写 · $normalized'
        : '陪我写 · ${normalized.substring(0, 16)}…';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _GuidedJournalEmptyState extends StatelessWidget {
  const _GuidedJournalEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('不用先想好要写什么', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              '像聊天一样，一句一句说出来。\n我会先听，不会每句话都打断你。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidedMessageBubble extends StatelessWidget {
  const _GuidedMessageBubble({required this.message});

  final AiSessionMessageV2 message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == AiChatRoleV2.user;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: user
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(message.text),
      ),
    );
  }
}
