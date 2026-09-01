import 'package:flutter/material.dart';

import '../data/ai_response_preferences_store_v2.dart';
import '../domain/ai_response_preferences_v2.dart';

class AiResponsePreferencesPageV2 extends StatefulWidget {
  const AiResponsePreferencesPageV2({super.key});

  @override
  State<AiResponsePreferencesPageV2> createState() =>
      _AiResponsePreferencesPageV2State();
}

class _AiResponsePreferencesPageV2State
    extends State<AiResponsePreferencesPageV2> {
  final _store = AiResponsePreferencesStoreV2();
  AiResponsePreferencesV2? _value;

  @override
  void initState() {
    super.initState();
    _store.load().then((value) {
      if (mounted) setState(() => _value = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return Scaffold(
      appBar: AppBar(title: const Text('回复偏好')),
      body: value == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
              children: [
                Text('陪伴方式', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...AiCompanionStyleV2.values.map(
                  (style) => RadioListTile<AiCompanionStyleV2>(
                    value: style,
                    groupValue: value.style,
                    title: Text(style.label),
                    subtitle: Text(style.description),
                    onChanged: (selected) {
                      if (selected != null) _save(style: selected);
                    },
                  ),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<AiReplyLengthV2>(
                  value: value.length,
                  decoration: const InputDecoration(labelText: '回复长度'),
                  items: AiReplyLengthV2.values
                      .map(
                        (length) => DropdownMenuItem(
                          value: length,
                          child: Text(length.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (length) {
                    if (length != null) _save(length: length);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: value.allowQuestions,
                  title: const Text('允许AI在结尾提问'),
                  subtitle: const Text('关闭后，AI会减少追问，给你更多安静空间'),
                  onChanged: (enabled) => _save(allowQuestions: enabled),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: value.avoidPlatitudes,
                  title: const Text('避免鸡汤和口号'),
                  subtitle: const Text('尽量使用具体、朴素的表达'),
                  onChanged: (enabled) => _save(avoidPlatitudes: enabled),
                ),
              ],
            ),
    );
  }

  Future<void> _save({
    AiCompanionStyleV2? style,
    AiReplyLengthV2? length,
    bool? allowQuestions,
    bool? avoidPlatitudes,
  }) async {
    final current = _value!;
    final updated = AiResponsePreferencesV2(
      style: style ?? current.style,
      length: length ?? current.length,
      allowQuestions: allowQuestions ?? current.allowQuestions,
      avoidPlatitudes: avoidPlatitudes ?? current.avoidPlatitudes,
    );
    setState(() => _value = updated);
    await _store.save(updated);
  }
}
