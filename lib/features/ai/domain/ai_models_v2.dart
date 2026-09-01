class AiChatMessageV2 {
  const AiChatMessageV2({required this.role, required this.text});

  final AiChatRoleV2 role;
  final String text;
}

enum AiChatRoleV2 { user, model }

enum AiTaskKindV2 {
  utility,
  structured,
  quickCompanion,
  companion,
  deepReflection,
}

enum AiThinkingLevelV2 { minimal, low, medium, high }

class AiGenerationOptionsV2 {
  const AiGenerationOptionsV2({
    this.task = AiTaskKindV2.utility,
    this.thinkingLevel = AiThinkingLevelV2.low,
    this.systemInstruction,
    this.jsonOutput = false,
    this.maxOutputTokens = 2048,
  });

  final AiTaskKindV2 task;
  final AiThinkingLevelV2 thinkingLevel;
  final String? systemInstruction;
  final bool jsonOutput;
  final int maxOutputTokens;
}

class AiResponseV2 {
  const AiResponseV2({required this.text, required this.elapsed});

  final String text;
  final Duration elapsed;
}

sealed class AiFailureV2 implements Exception {
  const AiFailureV2(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiNotConfiguredV2 extends AiFailureV2 {
  const AiNotConfiguredV2() : super('请先在设置中启用 AI 并配置 API Key');
}

class AiRequestFailureV2 extends AiFailureV2 {
  const AiRequestFailureV2(super.message);
}
