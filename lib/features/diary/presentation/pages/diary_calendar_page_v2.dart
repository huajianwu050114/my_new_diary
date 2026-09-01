import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../application/ports/diary_image_store_v2.dart';
import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import '../../../life_guide/domain/life_fragment_repository_v2.dart';
import 'diary_detail_page_v2.dart';

class DiaryCalendarPageV2 extends StatefulWidget {
  const DiaryCalendarPageV2({
    required this.repository,
    required this.imageStore,
    this.embedded = false,
    this.lifeFragmentRepository,
    super.key,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;
  final bool embedded;
  final LifeFragmentRepositoryV2? lifeFragmentRepository;

  @override
  State<DiaryCalendarPageV2> createState() => _DiaryCalendarPageV2State();
}

class _DiaryCalendarPageV2State extends State<DiaryCalendarPageV2> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(_focusedDay.year, _focusedDay.month);
    final nextMonth = DateTime(_focusedDay.year, _focusedDay.month + 1);

    final body = StreamBuilder<List<DiaryEntryV2>>(
      stream: widget.repository.watchEntries(
        query: DiaryQuery(from: monthStart, to: nextMonth),
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!;
        final recordedDays = entries
            .map(
              (entry) => DateTime(
                entry.entryDate.year,
                entry.entryDate.month,
                entry.entryDate.day,
              ),
            )
            .toSet();
        final longestStreak = _longestStreak(recordedDays);
        final selectedEntries = entries
            .where((entry) => isSameDay(entry.entryDate, _selectedDay))
            .toList(growable: false);

        return ListView(
          children: [
            TableCalendar<DiaryEntryV2>(
              locale: 'zh_CN',
              firstDay: DateTime(2000),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              headerStyle: const HeaderStyle(formatButtonVisible: false),
              selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
              eventLoader: (day) => entries
                  .where((entry) => isSameDay(entry.entryDate, day))
                  .toList(growable: false),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onPageChanged: (focusedDay) {
                setState(() => _focusedDay = focusedDay);
              },
              onFormatChanged: (format) {
                setState(() => _calendarFormat = format);
              },
              calendarStyle: CalendarStyle(
                markerDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '本月记录 ${recordedDays.length} 天 · '
                      '最长连续 $longestStreak 天',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<CalendarFormat>(
                    segments: const [
                      ButtonSegment(
                        value: CalendarFormat.month,
                        label: Text('月'),
                      ),
                      ButtonSegment(
                        value: CalendarFormat.twoWeeks,
                        label: Text('双周'),
                      ),
                      ButtonSegment(
                        value: CalendarFormat.week,
                        label: Text('周'),
                      ),
                    ],
                    selected: {_calendarFormat},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onSelectionChanged: (selection) {
                      setState(() => _calendarFormat = selection.first);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (selectedEntries.isEmpty)
              const SizedBox(
                height: 180,
                child: Center(child: Text('这一天还没有日记')),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < selectedEntries.length;
                      index++
                    ) ...[
                      if (index > 0) const Divider(),
                      ListTile(
                        leading: selectedEntries[index].mood == null
                            ? const Icon(Icons.notes)
                            : Text(
                                selectedEntries[index].mood!,
                                style: const TextStyle(fontSize: 24),
                              ),
                        title: Text(
                          selectedEntries[index].body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => DiaryDetailPageV2(
                              repository: widget.repository,
                              imageStore: widget.imageStore,
                              entryId: selectedEntries[index].id,
                              lifeFragmentRepository:
                                  widget.lifeFragmentRepository,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('日历')),
      body: body,
    );
  }

  int _longestStreak(Set<DateTime> recordedDays) {
    if (recordedDays.isEmpty) return 0;

    final days = recordedDays.toList()..sort();
    var longest = 1;
    var current = 1;
    for (var index = 1; index < days.length; index++) {
      if (days[index].difference(days[index - 1]).inDays == 1) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 1;
      }
    }
    return longest;
  }
}
