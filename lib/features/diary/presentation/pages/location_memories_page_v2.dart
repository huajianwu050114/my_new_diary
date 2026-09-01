import 'package:flutter/material.dart';

import '../../application/ports/diary_image_store_v2.dart';
import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import '../../../life_guide/domain/life_fragment_repository_v2.dart';
import 'diary_detail_page_v2.dart';

class LocationMemoriesPageV2 extends StatelessWidget {
  const LocationMemoriesPageV2({
    required this.repository,
    required this.imageStore,
    this.lifeFragmentRepository,
    super.key,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;
  final LifeFragmentRepositoryV2? lifeFragmentRepository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('地点回忆')),
      body: StreamBuilder<List<DiaryEntryV2>>(
        stream: repository.watchEntries(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = _group(snapshot.data!);
          if (groups.isEmpty) {
            return const Center(child: Text('带地点的日记会出现在这里'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final group = groups[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(group.label),
                  subtitle: Text('${group.entries.length} 篇日记'),
                  children: group.entries
                      .map(
                        (entry) => ListTile(
                          title: Text(
                            entry.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(_formatDate(entry.entryDate)),
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => DiaryDetailPageV2(
                                repository: repository,
                                imageStore: imageStore,
                                entryId: entry.id,
                                lifeFragmentRepository: lifeFragmentRepository,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              );
            },
          );
        },
      ),
    );
  }

  List<_LocationGroup> _group(List<DiaryEntryV2> entries) {
    final values = <String, List<DiaryEntryV2>>{};
    for (final entry in entries) {
      final location = entry.location;
      if (location == null) {
        continue;
      }
      final label = location.address?.trim().isNotEmpty == true
          ? location.address!.trim()
          : '${location.latitude.toStringAsFixed(4)}, '
                '${location.longitude.toStringAsFixed(4)}';
      values.putIfAbsent(label, () => []).add(entry);
    }
    final groups = values.entries
        .map((entry) => _LocationGroup(entry.key, entry.value))
        .toList(growable: false);
    groups.sort((a, b) => b.entries.length.compareTo(a.entries.length));
    return groups;
  }

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    return '${date.year}年${date.month}月${date.day}日';
  }
}

class _LocationGroup {
  const _LocationGroup(this.label, this.entries);

  final String label;
  final List<DiaryEntryV2> entries;
}
