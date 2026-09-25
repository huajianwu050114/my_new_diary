import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:my_new_diary/app/diary_app_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_chat_session_v2.dart';
import 'package:my_new_diary/features/ai/domain/ai_models_v2.dart';
import 'package:my_new_diary/features/diary/application/ports/diary_image_store_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/diary/domain/repositories/diary_repository_v2.dart';
import 'package:my_new_diary/features/festival/data/public_holiday_service_v2.dart';
import 'package:my_new_diary/features/festival/domain/festival_repository_v2.dart';
import 'package:my_new_diary/features/festival/domain/festival_v2.dart';
import 'package:my_new_diary/features/settings/application/theme_controller_v2.dart';
import 'package:my_new_diary/features/settings/application/app_lock_controller_v2.dart';

Future<void> main() async {
  await initializeDateFormatting('zh_CN');
  testWidgets('creates the first local diary entry', (tester) async {
    final repository = _MemoryDiaryRepository();
    await tester.pumpWidget(
      DiaryAppV2(
        repository: repository,
        imageStore: _MemoryImageStore(),
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有日记，从此刻开始吧'), findsOneWidget);

    await tester.tap(find.byTooltip('写日记'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('语音成稿'), findsOneWidget);
    expect(find.text('陪我聊着写'), findsOneWidget);
    await tester.tap(find.text('直接写'));
    await tester.pumpAndSettle();
    final richEditor = tester.widget<QuillEditor>(
      find.byKey(const Key('diary-rich-editor')),
    );
    expect(
      richEditor.config.customStyles?.paragraph?.style.fontWeight,
      FontWeight.w400,
    );
    expect(richEditor.config.customStyles?.bold?.fontWeight, FontWeight.w700);
    expect(find.text('日记日期'), findsNothing);
    expect(find.text('地点'), findsNothing);
    expect(find.byTooltip('日记信息'), findsOneWidget);
    expect(find.byTooltip('在这里插入图片'), findsOneWidget);
    await tester.tap(find.byTooltip('日记信息'));
    await tester.pumpAndSettle();
    expect(find.text('时间'), findsOneWidget);
    expect(find.text('地点'), findsOneWidget);
    expect(find.text('心情'), findsOneWidget);
    expect(find.text('标签'), findsWidgets);
    await tester.tap(find.byTooltip('完成'));
    await tester.pumpAndSettle();
    _replaceRichEditorText(tester, 'v2 的第一篇日记');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('v2 的第一篇日记', findRichText: true), findsOneWidget);
    expect(repository.entries, hasLength(1));
  });

  testWidgets('turns a voice transcript into an editable diary draft', (
    tester,
  ) async {
    final repository = _MemoryDiaryRepository();
    await tester.pumpWidget(
      DiaryAppV2(
        repository: repository,
        imageStore: _MemoryImageStore(),
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('写日记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('语音成稿'));
    await tester.pumpAndSettle();
    expect(find.text('语音成稿'), findsOneWidget);

    await tester.enterText(
      find.byType(EditableText).first,
      '今天说了很多，最后整理成一篇日记。',
    );
    await tester.pump();
    final useTranscript = find.text('使用文字草稿');
    await tester.drag(find.byType(ListView).last, const Offset(0, -320));
    await tester.pumpAndSettle();
    await tester.tap(useTranscript);
    await tester.pumpAndSettle();

    expect(find.text('新日记'), findsOneWidget);
    expect(find.text('今天说了很多，最后整理成一篇日记。', findRichText: true), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(repository.entries.single.body, '今天说了很多，最后整理成一篇日记。');
  });

  testWidgets('opens and edits an existing entry', (tester) async {
    final repository = _MemoryDiaryRepository(entries: [_entry()]);
    await tester.pumpWidget(
      DiaryAppV2(
        repository: repository,
        imageStore: _MemoryImageStore(),
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Original entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    _replaceRichEditorText(tester, 'Edited entry');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('Edited entry', findRichText: true), findsOneWidget);
    expect(repository.entries.single.body, 'Edited entry');
  });

  testWidgets('filters search results by tag and keyword', (tester) async {
    final now = DateTime.now().toUtc();
    final repository = _MemoryDiaryRepository(
      entries: [
        DiaryEntryV2(
          id: 'work',
          body: '完成项目方案',
          entryDate: now,
          createdAt: now,
          updatedAt: now,
          tags: const ['工作'],
        ),
        DiaryEntryV2(
          id: 'life',
          body: '傍晚去公园散步',
          entryDate: now.subtract(const Duration(days: 1)),
          createdAt: now,
          updatedAt: now,
          tags: const ['生活'],
        ),
      ],
    );
    await tester.pumpWidget(
      DiaryAppV2(
        repository: repository,
        imageStore: _MemoryImageStore(),
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#工作'));
    await tester.pumpAndSettle();

    expect(find.text('完成项目方案'), findsOneWidget);
    expect(find.text('傍晚去公园散步'), findsNothing);

    await tester.enterText(find.byType(EditableText).first, '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关日记'), findsOneWidget);
  });

  testWidgets('searches location and filters favorites with photos', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final repository = _MemoryDiaryRepository(
      entries: [
        DiaryEntryV2(
          id: 'library',
          body: '在安静角落读了一会儿书',
          entryDate: now,
          createdAt: now,
          updatedAt: now,
          imageIds: const ['photo-1'],
          isFavorite: true,
          location: const DiaryLocation(
            latitude: 30,
            longitude: 120,
            address: '城市图书馆',
          ),
        ),
        DiaryEntryV2(
          id: 'home',
          body: '在家整理桌面',
          entryDate: now.subtract(const Duration(days: 1)),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    await tester.pumpWidget(
      DiaryAppV2(
        repository: repository,
        imageStore: _MemoryImageStore(),
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, '图书馆');
    await tester.pumpAndSettle();

    expect(find.text('在安静角落读了一会儿书', findRichText: true), findsOneWidget);
    expect(find.text('在家整理桌面', findRichText: true), findsNothing);

    await tester.tap(find.byTooltip('清空关键词'));
    final favoriteFilter = find.widgetWithText(FilterChip, '收藏');
    final photoFilter = find.widgetWithText(FilterChip, '有照片');
    await tester.ensureVisible(favoriteFilter);
    await tester.tap(favoriteFilter);
    await tester.ensureVisible(photoFilter);
    await tester.tap(photoFilter);
    await tester.pumpAndSettle();

    expect(find.text('在安静角落读了一会儿书'), findsOneWidget);
    expect(find.text('在家整理桌面'), findsNothing);
  });

  testWidgets('shows AI card above collapsible chat history', (tester) async {
    final now = DateTime.now().toUtc();
    final repository = _MemoryDiaryRepository(
      entries: [
        DiaryEntryV2(
          id: 'ai-entry',
          body: '今天完成了一件期待很久的事情',
          entryDate: now,
          createdAt: now,
          updatedAt: now,
          aiAnalyses: const [
            '【AI 总结】\n## 今日摘要\n这是值得纪念的一天。',
            '【AI 伴聊】\n这是一条温柔的陪伴记录。',
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      DiaryAppV2(
        repository: repository,
        imageStore: _MemoryImageStore(),
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('今天完成了一件期待很久的事情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('今天完成了一件期待很久的事情'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('与 AI 交流'), findsOneWidget);
    expect(find.text('AI 的悄悄话'), findsOneWidget);
    expect(find.text('今日摘要'), findsOneWidget);
    expect(find.text('AI 对话记录'), findsOneWidget);
    expect(find.textContaining('温柔的陪伴记录'), findsNothing);

    await tester.tap(find.text('AI 对话记录'));
    await tester.pumpAndSettle();
    final legacySection = find.text('旧版保存内容');
    await tester.ensureVisible(legacySection);
    await tester.pumpAndSettle();
    await tester.tap(legacySection);
    await tester.pumpAndSettle();
    expect(find.textContaining('温柔的陪伴记录'), findsOneWidget);
  });

  testWidgets('hides the friend letter until AI has replied', (tester) async {
    final repository = _MemoryDiaryRepository(entries: [_entry()]);
    await tester.pumpWidget(
      DiaryAppV2(
        repository: repository,
        imageStore: _MemoryImageStore(),
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Original entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Original entry'));
    await tester.pumpAndSettle();

    expect(find.text('AI 的悄悄话'), findsNothing);
    expect(find.textContaining('写于 '), findsOneWidget);
  });

  testWidgets(
    'uses journal, calendar, life, memories, and profile navigation',
    (tester) async {
      final now = DateTime.now();
      final repository = _MemoryDiaryRepository(
        entries: [
          DiaryEntryV2(
            id: 'current-month',
            body: '这个月的记录',
            entryDate: now.toUtc(),
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
          DiaryEntryV2(
            id: 'previous-month',
            body: '上个月的记录',
            entryDate: DateTime(now.year, now.month - 1, 15).toUtc(),
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        ],
      );
      await tester.pumpWidget(
        DiaryAppV2(
          repository: repository,
          imageStore: _MemoryImageStore(),
          festivalRepository: _MemoryFestivalRepository(),
          publicHolidayService: PublicHolidayServiceV2(),
          themeController: ThemeControllerV2(),
          appLockController: AppLockControllerV2(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('今天，想记下什么？'), findsOneWidget);
      expect(find.text('最近日记'), findsOneWidget);
      expect(find.text('写下这一刻'), findsNothing);
      expect(find.byTooltip('写日记'), findsOneWidget);
      expect(find.text('日历'), findsOneWidget);
      expect(find.text('生活'), findsOneWidget);
      expect(find.text('回忆'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);

      await tester.tap(find.text('回忆'));
      await tester.pumpAndSettle();
      expect(find.text('AI 时光回顾'), findsOneWidget);
      expect(find.text('地点'), findsOneWidget);

      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('统计分析'), findsOneWidget);
      expect(find.text('导出与备份'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    },
  );

  testWidgets('journal page fits in landscape', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DiaryAppV2(
        repository: _MemoryDiaryRepository(entries: [_entry()]),
        imageStore: _MemoryImageStore(),
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今天，想记下什么？'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar month view scrolls without landscape overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      DiaryAppV2(
        repository: _MemoryDiaryRepository(entries: [_entry()]),
        imageStore: _MemoryImageStore(),
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.text('月'), findsOneWidget);
    expect(find.text('双周'), findsOneWidget);
    expect(find.text('周'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows paged diary images and creation signature', (
    tester,
  ) async {
    final imageStore = _MemoryImageStore();
    final firstImage = await imageStore.save(
      bytes: Uint8List.fromList(const [0, 1, 2]),
      extension: '.png',
    );
    final secondImage = await imageStore.save(
      bytes: Uint8List.fromList(const [3, 4, 5]),
      extension: '.png',
    );
    final createdAt = DateTime.utc(2024, 3, 8, 9, 6);
    final repository = _MemoryDiaryRepository(
      entries: [
        DiaryEntryV2(
          id: 'photo-entry',
          body: '带有两张照片的日记',
          entryDate: createdAt,
          createdAt: createdAt,
          updatedAt: createdAt,
          imageIds: [firstImage, secondImage],
        ),
      ],
    );
    await tester.pumpWidget(
      DiaryAppV2(
        repository: repository,
        imageStore: imageStore,
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('带有两张照片的日记').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('带有两张照片的日记').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('detail-image-viewer')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('detail-image-indicator-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('detail-image-indicator-1')),
      findsOneWidget,
    );
    await tester.fling(
      find.byKey(const Key('detail-image-viewer')),
      const Offset(-600, 0),
      1200,
    );
    await tester.pumpAndSettle();
    final secondIndicator = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('detail-image-indicator-1')),
    );
    expect(secondIndicator.constraints?.maxWidth, 20);

    await tester.scrollUntilVisible(
      find.textContaining('写于 '),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('写于 '), findsOneWidget);
  });

  testWidgets('groups complete AI conversations by Chat session', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    AiChatSessionV2 session(String id, String title) => AiChatSessionV2(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
      messages: [
        AiSessionMessageV2(
          role: AiChatRoleV2.user,
          text: '用户消息 $id',
          createdAt: now,
        ),
        AiSessionMessageV2(
          role: AiChatRoleV2.model,
          text: 'AI 回复 $id',
          createdAt: now,
        ),
      ],
    );
    final repository = _MemoryDiaryRepository(
      entries: [
        DiaryEntryV2(
          id: 'sessions',
          body: '拥有多个会话的日记',
          entryDate: now,
          createdAt: now,
          updatedAt: now,
          aiAnalyses: [
            session('one', '第一个 Chat').encode(),
            session('two', '第二个 Chat').encode(),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      DiaryAppV2(
        repository: repository,
        imageStore: _MemoryImageStore(),
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('拥有多个会话的日记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拥有多个会话的日记'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('AI 对话记录'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('AI 对话记录'));
    await tester.pumpAndSettle();

    expect(find.text('第一个 Chat'), findsOneWidget);
    expect(find.text('第二个 Chat'), findsOneWidget);
    expect(find.text('2 个 Chat'), findsOneWidget);
  });

  testWidgets('keeps the first page short and links to the archive', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    final entries = List.generate(
      13,
      (index) => DiaryEntryV2(
        id: 'archive-$index',
        body: '归档测试日记 $index',
        entryDate: now.subtract(Duration(days: index)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await tester.pumpWidget(
      DiaryAppV2(
        repository: _MemoryDiaryRepository(entries: entries),
        imageStore: _MemoryImageStore(),
        festivalRepository: _MemoryFestivalRepository(),
        publicHolidayService: PublicHolidayServiceV2(),
        themeController: ThemeControllerV2(),
        appLockController: AppLockControllerV2(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('归档测试日记 0'), findsOneWidget);
    expect(find.text('归档测试日记 6'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('继续查看'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('继续查看'));
    await tester.pumpAndSettle();
    expect(find.text('时光归档'), findsOneWidget);
    expect(find.text(entries.first.body), findsOneWidget);
  });
}

void _replaceRichEditorText(WidgetTester tester, String text) {
  final editor = tester.widget<QuillEditor>(
    find.byKey(const Key('diary-rich-editor')),
  );
  editor.controller.replaceText(
    0,
    editor.controller.document.length - 1,
    text,
    TextSelection.collapsed(offset: text.length),
  );
}

class _MemoryImageStore implements DiaryImageStoreV2 {
  final _images = <String, Uint8List>{};

  @override
  Future<void> delete(String imageId) async {
    _images.remove(imageId);
  }

  @override
  Future<Uint8List?> read(String imageId) async => _images[imageId];

  @override
  Future<String> save({
    required Uint8List bytes,
    required String extension,
  }) async {
    final id = 'image-${_images.length + 1}.$extension';
    _images[id] = bytes;
    return id;
  }
}

class _MemoryFestivalRepository implements FestivalRepositoryV2 {
  final _festivals = <CustomFestivalV2>[];

  @override
  Future<void> delete(String id) async {
    _festivals.removeWhere((festival) => festival.id == id);
  }

  @override
  Future<void> save(CustomFestivalV2 festival) async {
    _festivals.add(festival);
  }

  @override
  Stream<List<CustomFestivalV2>> watchCustomFestivals() async* {
    yield _festivals;
  }
}

class _MemoryDiaryRepository implements DiaryRepositoryV2 {
  _MemoryDiaryRepository({List<DiaryEntryV2> entries = const []})
    : entries = [...entries];

  final List<DiaryEntryV2> entries;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<void> deletePermanently(String id) async {
    entries.removeWhere((entry) => entry.id == id);
    _emit();
  }

  @override
  Future<DiaryEntryV2?> getById(String id) async {
    return entries.where((entry) => entry.id == id).firstOrNull;
  }

  @override
  Future<void> moveToTrash(String id, {required DateTime deletedAt}) async {
    final index = entries.indexWhere((entry) => entry.id == id);
    entries[index] = entries[index].copyWith(deletedAt: deletedAt);
    _emit();
  }

  @override
  Future<void> restore(String id) async {
    final index = entries.indexWhere((entry) => entry.id == id);
    entries[index] = entries[index].copyWith(restore: true);
    _emit();
  }

  @override
  Future<void> setFavorite(String id, {required bool isFavorite}) async {
    final index = entries.indexWhere((entry) => entry.id == id);
    entries[index] = entries[index].copyWith(isFavorite: isFavorite);
    _emit();
  }

  @override
  Future<void> save(DiaryEntryV2 entry) async {
    entries.removeWhere((existing) => existing.id == entry.id);
    entries.add(entry);
    _emit();
  }

  @override
  Stream<List<DiaryEntryV2>> watchEntries({
    DiaryQuery query = const DiaryQuery(),
  }) async* {
    yield _filter(query);
    await for (final _ in _changes.stream) {
      yield _filter(query);
    }
  }

  void _emit() {
    _changes.add(null);
  }

  List<DiaryEntryV2> _filter(DiaryQuery query) {
    return entries
        .where((entry) {
          if (query.onlyDeleted && !entry.isDeleted) {
            return false;
          }
          if (!query.includeDeleted && !query.onlyDeleted && entry.isDeleted) {
            return false;
          }
          final text = query.text;
          if (query.onlyFavorites && !entry.isFavorite) {
            return false;
          }
          return text == null || entry.body.contains(text);
        })
        .toList(growable: false);
  }
}

DiaryEntryV2 _entry() {
  final now = DateTime.utc(2026, 7, 28);
  return DiaryEntryV2(
    id: 'entry-1',
    body: 'Original entry',
    entryDate: now,
    createdAt: now,
    updatedAt: now,
  );
}
