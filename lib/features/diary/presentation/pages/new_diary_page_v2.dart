import 'package:flutter/material.dart';

import '../../../ai/domain/ai_chat_session_v2.dart';
import '../../application/ports/diary_image_store_v2.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import 'diary_editor_page_v2.dart';

class NewDiaryPageV2 extends StatelessWidget {
  const NewDiaryPageV2({
    required this.repository,
    required this.imageStore,
    this.initialBody = '',
    this.initialAiSession,
    this.skipAutomaticReply = false,
    super.key,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;
  final String initialBody;
  final AiChatSessionV2? initialAiSession;
  final bool skipAutomaticReply;

  @override
  Widget build(BuildContext context) {
    return DiaryEditorPageV2(
      repository: repository,
      imageStore: imageStore,
      initialBody: initialBody,
      initialAiSession: initialAiSession,
      skipAutomaticReply: skipAutomaticReply,
    );
  }
}
