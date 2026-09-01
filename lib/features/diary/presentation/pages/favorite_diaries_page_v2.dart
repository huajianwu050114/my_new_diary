import 'package:flutter/material.dart';

import '../../application/ports/diary_image_store_v2.dart';
import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import '../../../life_guide/domain/life_fragment_repository_v2.dart';
import 'diary_detail_page_v2.dart';

class FavoriteDiariesPageV2 extends StatelessWidget {
  const FavoriteDiariesPageV2({
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
      appBar: AppBar(title: const Text('收藏')),
      body: StreamBuilder<List<DiaryEntryV2>>(
        stream: repository.watchEntries(
          query: const DiaryQuery(onlyFavorites: true),
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(child: Text('还没有收藏的日记'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Card(
                child: ListTile(
                  title: Text(
                    entry.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_formatDate(entry.entryDate)),
                  trailing: IconButton(
                    tooltip: '取消收藏',
                    onPressed: () =>
                        repository.setFavorite(entry.id, isFavorite: false),
                    icon: const Icon(Icons.favorite),
                  ),
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
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime value) {
    final date = value.toLocal();
    return '${date.year}年${date.month}月${date.day}日';
  }
}
