import 'package:flutter/material.dart';

class DiaryMoodTextV2 extends StatelessWidget {
  const DiaryMoodTextV2({
    required this.mood,
    this.prominent = false,
    this.maxWidth,
    this.maxLines = 1,
    this.textAlign = TextAlign.start,
    super.key,
  });

  final String mood;
  final bool prominent;
  final double? maxWidth;
  final int maxLines;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final trimmedMood = mood.trim();
    final isCompact = trimmedMood.runes.length <= 4;
    final text = Text(
      trimmedMood,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: isCompact ? (prominent ? 30 : 22) : (prominent ? 15 : 13),
        height: isCompact ? 1.1 : 1.35,
      ),
    );
    final width = maxWidth;
    return width == null
        ? text
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: text,
          );
  }
}
