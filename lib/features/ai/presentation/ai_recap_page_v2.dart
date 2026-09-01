import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../diary/domain/entities/diary_entry.dart';
import '../application/diary_ai_service_v2.dart';
import '../data/ai_configuration_store_v2.dart';
import '../data/gemini_rest_client_v2.dart';
import '../domain/ai_models_v2.dart';
import 'ai_settings_page_v2.dart';

class AiRecapPageV2 extends StatefulWidget {
  const AiRecapPageV2({required this.entries, super.key});

  final List<DiaryEntryV2> entries;

  @override
  State<AiRecapPageV2> createState() => _AiRecapPageV2State();
}

class _AiRecapPageV2State extends State<AiRecapPageV2> {
  late final DiaryAiServiceV2 _service;
  String? _result;
  String? _period;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _service = DiaryAiServiceV2(
      GeminiRestClientV2(configurationStore: AiConfigurationStoreV2()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 时光回顾')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '把散落的日子，整理成一张卡片',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _loading
                      ? null
                      : () => _generate(const Duration(days: 7), '本周'),
                  icon: const Icon(Icons.view_week_outlined),
                  label: const Text('本周回顾'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _loading
                      ? null
                      : () => _generate(const Duration(days: 30), '近一个月'),
                  icon: const Icon(Icons.calendar_view_month_outlined),
                  label: const Text('月度回顾'),
                ),
              ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 40),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            const Center(child: Text('正在整理你的时光…')),
          ],
          if (_result != null && !_loading) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$_period回顾卡片',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Divider(height: 28),
                    MarkdownBody(data: _result!, selectable: true),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _generate(Duration duration, String periodName) async {
    final cutoff = DateTime.now().subtract(duration);
    final selected = widget.entries
        .where((entry) => entry.entryDate.isAfter(cutoff))
        .toList(growable: false);
    if (selected.isEmpty) {
      _message('$periodName还没有日记可供回顾');
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final response = await _service.recap(
        entries: selected,
        periodName: periodName,
      );
      if (mounted) {
        setState(() {
          _result = response.text;
          _period = periodName;
        });
      }
    } on AiNotConfiguredV2 catch (error) {
      if (mounted) await _showConfiguration(error.message);
    } on AiFailureV2 catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showConfiguration(String message) async {
    final open =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('AI 尚未配置'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('前往设置'),
              ),
            ],
          ),
        ) ??
        false;
    if (open && mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AiSettingsPageV2()));
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
