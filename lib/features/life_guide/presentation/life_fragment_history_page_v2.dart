import 'package:flutter/material.dart';

import '../domain/life_fragment_repository_v2.dart';
import '../domain/life_fragment_revision_v2.dart';
import '../domain/life_fragment_v2.dart';

class LifeFragmentHistoryPageV2 extends StatefulWidget {
  const LifeFragmentHistoryPageV2({
    required this.fragment,
    required this.repository,
    super.key,
  });

  final LifeFragmentV2 fragment;
  final LifeFragmentRepositoryV2 repository;

  @override
  State<LifeFragmentHistoryPageV2> createState() =>
      _LifeFragmentHistoryPageV2State();
}

class _LifeFragmentHistoryPageV2State extends State<LifeFragmentHistoryPageV2> {
  late Future<List<LifeFragmentRevisionV2>> _history;

  @override
  void initState() {
    super.initState();
    _history = widget.repository.getRevisions(widget.fragment.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('修改历史')),
    body: FutureBuilder<List<LifeFragmentRevisionV2>>(
      future: _history,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(child: Text('还没有修改记录'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final revision = snapshot.data![index];
            final time = revision.createdAt.toLocal();
            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                title: Text(revision.snapshot.title),
                subtitle: Text(
                  '${time.year}年${time.month}月${time.day}日 '
                  '${time.hour.toString().padLeft(2, '0')}:'
                  '${time.minute.toString().padLeft(2, '0')}\n'
                  '${revision.snapshot.coreInsight}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: TextButton(
                  onPressed: () => _restore(revision.snapshot),
                  child: const Text('恢复'),
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Future<void> _restore(LifeFragmentV2 snapshot) async {
    final restored = snapshot.copyWith(updatedAt: DateTime.now().toUtc());
    await widget.repository.updateWithRevision(
      restored,
      previous: widget.fragment,
    );
    if (mounted) Navigator.pop(context, restored);
  }
}
