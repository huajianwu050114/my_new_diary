import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/life_guide/domain/life_fragment_repository_v2.dart';
import 'package:my_new_diary/features/life_guide/domain/life_fragment_revision_v2.dart';
import 'package:my_new_diary/features/life_guide/domain/life_fragment_v2.dart';
import 'package:my_new_diary/features/life_guide/presentation/life_guide_page_v2.dart';

void main() {
  testWidgets('switches between confirmed fragments, ropes, and drafts', (
    tester,
  ) async {
    final repository = _MemoryLifeFragmentRepository([
      _fragment(id: 'guide', title: '允许自己慢一点'),
      _fragment(id: 'rope', title: '先把今晚过完', isRope: true),
      _fragment(
        id: 'draft',
        title: '还需要想想',
        status: LifeFragmentStatusV2.draft,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: LifeGuidePageV2(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('允许自己慢一点'), findsOneWidget);
    expect(find.text('先把今晚过完'), findsOneWidget);
    expect(find.text('还需要想想'), findsNothing);

    await tester.tap(find.text('重要提醒'));
    await tester.pumpAndSettle();
    expect(find.text('先把今晚过完'), findsOneWidget);
    expect(find.text('允许自己慢一点'), findsNothing);

    await tester.tap(find.text('草稿'));
    await tester.pumpAndSettle();
    expect(find.text('还需要想想'), findsOneWidget);
  });

  testWidgets('confirms a draft from fragment detail', (tester) async {
    final repository = _MemoryLifeFragmentRepository([
      _fragment(
        id: 'draft',
        title: '还需要想想',
        status: LifeFragmentStatusV2.draft,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: LifeGuidePageV2(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('还需要想想'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('确认并收进人生指南'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('确认并收进人生指南'));
    await tester.pumpAndSettle();

    expect(
      (await repository.getById('draft'))?.status,
      LifeFragmentStatusV2.confirmed,
    );
  });
}

LifeFragmentV2 _fragment({
  required String id,
  required String title,
  bool isRope = false,
  LifeFragmentStatusV2 status = LifeFragmentStatusV2.confirmed,
}) {
  final now = DateTime.utc(2026, 8, 18);
  return LifeFragmentV2(
    id: id,
    title: title,
    coreInsight: '我可以照顾自己的感受，也可以一步一步行动。',
    context: '来自一段真实经历。',
    evidence: '我曾经做到过。',
    futureUse: '再次感到不确定的时候。',
    messageToFutureSelf: '先停一停，你不必一次解决所有事情。',
    theme: '对我有用的方法',
    sourceDiaryIds: const ['diary-1'],
    isRope: isRope,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

class _MemoryLifeFragmentRepository implements LifeFragmentRepositoryV2 {
  _MemoryLifeFragmentRepository(List<LifeFragmentV2> fragments)
    : _fragments = {for (final item in fragments) item.id: item};

  final Map<String, LifeFragmentV2> _fragments;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final List<LifeFragmentRevisionV2> _revisions = [];

  @override
  Future<void> delete(String id) async {
    _fragments.remove(id);
    _changes.add(null);
  }

  @override
  Future<LifeFragmentV2?> getById(String id) async => _fragments[id];

  @override
  Future<List<LifeFragmentRevisionV2>> getRevisions(String fragmentId) async =>
      _revisions.where((item) => item.fragmentId == fragmentId).toList();

  @override
  Future<void> restoreRevision(LifeFragmentRevisionV2 revision) async {
    if (_revisions.every((item) => item.id != revision.id)) {
      _revisions.add(revision);
    }
  }

  @override
  Future<void> save(LifeFragmentV2 fragment) async {
    _fragments[fragment.id] = fragment;
    _changes.add(null);
  }

  @override
  Future<void> updateWithRevision(
    LifeFragmentV2 fragment, {
    required LifeFragmentV2 previous,
  }) async {
    _revisions.add(
      LifeFragmentRevisionV2(
        id: 'revision-${_revisions.length}',
        fragmentId: previous.id,
        snapshot: previous,
        createdAt: DateTime.now(),
      ),
    );
    await save(fragment);
  }

  @override
  Stream<List<LifeFragmentV2>> watchFragments({
    LifeFragmentStatusV2? status,
    bool onlyRopes = false,
  }) async* {
    List<LifeFragmentV2> current() => _fragments.values
        .where((item) => status == null || item.status == status)
        .where((item) => !onlyRopes || item.isRope)
        .toList(growable: false);
    yield current();
    await for (final _ in _changes.stream) {
      yield current();
    }
  }
}
