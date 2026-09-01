enum AiCompanionStyleV2 {
  listen('先倾听', '先接住感受，少给方案'),
  balanced('平衡', '理解与建议保持平衡'),
  practical('一起想办法', '更关注可执行的小步骤');

  const AiCompanionStyleV2(this.label, this.description);
  final String label;
  final String description;
}

enum AiReplyLengthV2 {
  short('简短'),
  medium('适中'),
  long('详细');

  const AiReplyLengthV2(this.label);
  final String label;
}

class AiResponsePreferencesV2 {
  const AiResponsePreferencesV2({
    this.style = AiCompanionStyleV2.balanced,
    this.length = AiReplyLengthV2.medium,
    this.allowQuestions = true,
    this.avoidPlatitudes = true,
  });

  final AiCompanionStyleV2 style;
  final AiReplyLengthV2 length;
  final bool allowQuestions;
  final bool avoidPlatitudes;
}
