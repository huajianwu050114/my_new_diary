import 'package:flutter/material.dart';

import '../../application/legacy_migration_controller_v2.dart';
import '../../data/migration/legacy_diary_migrator_v2.dart';

class LegacyMigrationPageV2 extends StatelessWidget {
  const LegacyMigrationPageV2({required this.controller, super.key});

  final LegacyMigrationControllerV2 controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('旧版数据迁移')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final run = controller.lastRun;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '迁移会扫描旧版 diary.db 和 diaries 文件夹。'
                          '已经导入的日记会自动跳过，不会重复创建；原始文件不会被删除。',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (run == null)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.history),
                    title: Text('暂无迁移记录'),
                    subtitle: Text('可以手动扫描当前设备上的旧版数据。'),
                  ),
                )
              else ...[
                Text('最近一次迁移', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_formatTime(run.completedAt)),
                        const Divider(height: 26),
                        _ReportGrid(report: run.report),
                        if (run.report.failed > 0) ...[
                          const SizedBox(height: 14),
                          Text(
                            '有 ${run.report.failed} 项未能导入。请确认旧文件可读取后重试。',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: controller.running ? null : () => _retry(context),
                icon: controller.running
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(controller.running ? '正在扫描…' : '重新扫描并迁移'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _retry(BuildContext context) async {
    try {
      final report = await controller.run();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '扫描完成：导入 ${report.imported}，跳过 ${report.skipped}，'
            '失败 ${report.failed}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('迁移无法完成：$error')));
    }
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _ReportGrid extends StatelessWidget {
  const _ReportGrid({required this.report});

  final MigrationReportV2 report;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Metric(label: '发现', value: report.discovered),
        _Metric(label: '已导入', value: report.imported),
        _Metric(label: '已跳过', value: report.skipped),
        _Metric(label: '失败', value: report.failed),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: Theme.of(context).textTheme.headlineSmall),
          Text(label),
        ],
      ),
    );
  }
}
