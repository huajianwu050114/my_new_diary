import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/public_holiday_service_v2.dart';
import '../domain/festival_repository_v2.dart';
import '../domain/festival_v2.dart';

class FestivalsPageV2 extends StatefulWidget {
  const FestivalsPageV2({
    required this.repository,
    required this.publicHolidayService,
    super.key,
  });

  final FestivalRepositoryV2 repository;
  final PublicHolidayServiceV2 publicHolidayService;

  @override
  State<FestivalsPageV2> createState() => _FestivalsPageV2State();
}

class _FestivalsPageV2State extends State<FestivalsPageV2> {
  late Future<List<FestivalOccurrenceV2>> _publicHolidays;

  @override
  void initState() {
    super.initState();
    _reloadPublicHolidays();
  }

  void _reloadPublicHolidays() {
    final year = DateTime.now().year;
    _publicHolidays = Future.wait([
      widget.publicHolidayService.loadYear(year),
      widget.publicHolidayService.loadYear(year + 1),
    ]).then((years) => [...years[0], ...years[1]]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('节日与纪念日')),
      body: StreamBuilder<List<CustomFestivalV2>>(
        stream: widget.repository.watchCustomFestivals(),
        builder: (context, customSnapshot) {
          if (!customSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<List<FestivalOccurrenceV2>>(
            future: _publicHolidays,
            builder: (context, publicSnapshot) {
              final occurrences = _combine(
                customSnapshot.data!,
                publicSnapshot.data ?? const [],
              );
              return RefreshIndicator(
                onRefresh: () async {
                  setState(_reloadPublicHolidays);
                  await _publicHolidays;
                },
                child: occurrences.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 240),
                          Center(child: Text('还没有可显示的节日')),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: occurrences.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final occurrence = occurrences[index];
                          return _FestivalCard(
                            occurrence: occurrence,
                            onDelete: occurrence.isCustom
                                ? () => widget.repository.delete(occurrence.id)
                                : null,
                          );
                        },
                      ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomFestival,
        icon: const Icon(Icons.add),
        label: const Text('添加纪念日'),
      ),
    );
  }

  List<FestivalOccurrenceV2> _combine(
    List<CustomFestivalV2> customFestivals,
    List<FestivalOccurrenceV2> publicHolidays,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final values = publicHolidays
        .where((festival) => !festival.date.isBefore(today))
        .toList();
    values.addAll(
      customFestivals.map(
        (festival) => FestivalOccurrenceV2(
          id: festival.id,
          name: festival.name,
          date: festival.nextOccurrence(now),
          isCustom: true,
        ),
      ),
    );
    final unique = <String, FestivalOccurrenceV2>{
      for (final value in values) '${value.name}:${value.date}': value,
    }.values.toList();
    unique.sort((a, b) => a.date.compareTo(b.date));
    return unique;
  }

  Future<void> _addCustomFestival() async {
    final nameController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    final result = await showDialog<CustomFestivalV2>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加纪念日'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：相识纪念日',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text('${selectedDate.month}月${selectedDate.day}日'),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: selectedDate,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  CustomFestivalV2(
                    id: const Uuid().v4(),
                    name: name,
                    month: selectedDate.month,
                    day: selectedDate.day,
                    createdAt: DateTime.now().toUtc(),
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (result != null) {
      await widget.repository.save(result);
    }
  }
}

class _FestivalCard extends StatelessWidget {
  const _FestivalCard({required this.occurrence, this.onDelete});

  final FestivalOccurrenceV2 occurrence;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final days = occurrence.daysUntil(DateTime.now());
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(days == 0 ? '今' : '$days')),
        title: Text(occurrence.name),
        subtitle: Text(
          '${occurrence.date.year}年${occurrence.date.month}月'
          '${occurrence.date.day}日 · '
          '${days == 0 ? '就是今天' : '还有 $days 天'}',
        ),
        trailing: onDelete == null
            ? const Chip(label: Text('公共'))
            : IconButton(
                tooltip: '删除纪念日',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
      ),
    );
  }
}
