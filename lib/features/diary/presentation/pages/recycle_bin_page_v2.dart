import 'package:flutter/material.dart';

import '../../application/ports/diary_image_store_v2.dart';
import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';

class RecycleBinPageV2 extends StatelessWidget {
  const RecycleBinPageV2({
    required this.repository,
    required this.imageStore,
    super.key,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: StreamBuilder<List<DiaryEntryV2>>(
        stream: repository.watchEntries(
          query: const DiaryQuery(onlyDeleted: true),
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data!;
          if (entries.isEmpty) {
            return const Center(child: Text('回收站是空的'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                title: Text(
                  entry.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('删除于 ${_formatDate(entry.deletedAt)}'),
                trailing: PopupMenuButton<_TrashAction>(
                  onSelected: (action) {
                    if (action == _TrashAction.restore) {
                      repository.restore(entry.id);
                    } else {
                      _confirmPermanentDelete(context, entry);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _TrashAction.restore,
                      child: Text('恢复'),
                    ),
                    PopupMenuItem(
                      value: _TrashAction.delete,
                      child: Text('永久删除'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmPermanentDelete(
    BuildContext context,
    DiaryEntryV2 entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('永久删除？'),
        content: const Text('此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      for (final imageId in entry.imageIds) {
        await imageStore.delete(imageId);
      }
      await repository.deletePermanently(entry.id);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return '未知时间';
    }
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

enum _TrashAction { restore, delete }
