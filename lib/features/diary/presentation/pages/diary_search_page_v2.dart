import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../application/ports/diary_image_store_v2.dart';
import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import '../widgets/diary_mood_text_v2.dart';
import '../../../life_guide/domain/life_fragment_repository_v2.dart';
import 'diary_detail_page_v2.dart';

class DiarySearchPageV2 extends StatefulWidget {
  const DiarySearchPageV2({
    required this.repository,
    required this.imageStore,
    this.lifeFragmentRepository,
    super.key,
  });

  final DiaryRepositoryV2 repository;
  final DiaryImageStoreV2 imageStore;
  final LifeFragmentRepositoryV2? lifeFragmentRepository;

  @override
  State<DiarySearchPageV2> createState() => _DiarySearchPageV2State();
}

class _DiarySearchPageV2State extends State<DiarySearchPageV2> {
  static const _recentSearchesKey = 'v2_recent_diary_searches';

  final TextEditingController _queryController = TextEditingController();
  final Set<String> _selectedTags = {};
  final Set<String> _selectedMoods = {};
  List<String> _recentSearches = const [];
  String _query = '';
  DateTimeRange? _dateRange;
  bool _onlyFavorites = false;
  bool _withPhotos = false;

  bool get _hasFilters =>
      _query.isNotEmpty ||
      _selectedTags.isNotEmpty ||
      _selectedMoods.isNotEmpty ||
      _dateRange != null ||
      _onlyFavorites ||
      _withPhotos;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索日记'),
        actions: [
          if (_hasFilters)
            TextButton(onPressed: _clearFilters, child: const Text('清除')),
        ],
      ),
      body: StreamBuilder<List<DiaryEntryV2>>(
        stream: widget.repository.watchEntries(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('读取日记失败：${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allEntries = snapshot.data!;
          final tags = allEntries.expand((entry) => entry.tags).toSet().toList()
            ..sort();
          final moods = allEntries
              .map((entry) => entry.mood)
              .whereType<String>()
              .where((mood) => mood.isNotEmpty)
              .toSet()
              .toList();
          final entries = allEntries.where(_matches).toList(growable: false);
          return Column(
            children: [
              _buildSearchField(),
              _buildPrimaryFilters(),
              if (tags.isNotEmpty)
                _ChoiceFilters(
                  values: tags,
                  selected: _selectedTags,
                  labelFor: (tag) => '#$tag',
                  onSelected: _toggleTag,
                ),
              if (moods.isNotEmpty)
                _ChoiceFilters(
                  values: moods,
                  selected: _selectedMoods,
                  labelFor: (mood) => mood,
                  onSelected: _toggleMood,
                ),
              Expanded(
                child: !_hasFilters
                    ? _SearchPrompt(
                        recentSearches: _recentSearches,
                        onRecentTap: _useRecentSearch,
                        onClearRecent: _clearRecentSearches,
                      )
                    : entries.isEmpty
                    ? _EmptySearchResult(onReset: _clearFilters)
                    : _SearchResults(
                        entries: entries,
                        query: _query,
                        onTap: _openEntry,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _queryController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _query = value.trim()),
        onSubmitted: (_) => _rememberCurrentSearch(),
        decoration: InputDecoration(
          hintText: '搜索正文、标签、地点或心情',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空关键词',
                  onPressed: () {
                    _queryController.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      ),
    );
  }

  Widget _buildPrimaryFilters() {
    final dateLabel = _dateRange == null
        ? '日期'
        : '${_dateRange!.start.month}/${_dateRange!.start.day}–'
              '${_dateRange!.end.month}/${_dateRange!.end.day}';
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          FilterChip(
            avatar: const Icon(Icons.date_range_outlined, size: 18),
            label: Text(dateLabel),
            selected: _dateRange != null,
            onSelected: (_) => _pickDateRange(),
          ),
          const SizedBox(width: 8),
          FilterChip(
            avatar: const Icon(Icons.favorite_border_rounded, size: 18),
            label: const Text('收藏'),
            selected: _onlyFavorites,
            onSelected: (value) => setState(() => _onlyFavorites = value),
          ),
          const SizedBox(width: 8),
          FilterChip(
            avatar: const Icon(Icons.photo_outlined, size: 18),
            label: const Text('有照片'),
            selected: _withPhotos,
            onSelected: (value) => setState(() => _withPhotos = value),
          ),
        ],
      ),
    );
  }

  bool _matches(DiaryEntryV2 entry) {
    final normalizedQuery = _query.toLowerCase();
    final searchable = [
      entry.body,
      ...entry.tags,
      if (entry.location?.address case final address?) address,
      if (entry.mood case final mood?) mood,
    ].join('\n').toLowerCase();
    if (normalizedQuery.isNotEmpty && !searchable.contains(normalizedQuery)) {
      return false;
    }
    if (!_selectedTags.every(entry.tags.contains)) return false;
    if (_selectedMoods.isNotEmpty && !(_selectedMoods.contains(entry.mood))) {
      return false;
    }
    if (_onlyFavorites && !entry.isFavorite) return false;
    if (_withPhotos && entry.imageIds.isEmpty) return false;
    final range = _dateRange;
    if (range != null) {
      final date = entry.entryDate.toLocal();
      final day = DateTime(date.year, date.month, date.day);
      final start = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      final endExclusive = DateTime(
        range.end.year,
        range.end.month,
        range.end.day + 1,
      );
      if (day.isBefore(start) || !day.isBefore(endExclusive)) return false;
    }
    return true;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _dateRange,
      helpText: '选择日记日期范围',
      saveText: '确定',
    );
    if (picked != null && mounted) setState(() => _dateRange = picked);
  }

  void _toggleTag(String tag, bool selected) {
    setState(
      () => selected ? _selectedTags.add(tag) : _selectedTags.remove(tag),
    );
  }

  void _toggleMood(String mood, bool selected) {
    setState(
      () => selected ? _selectedMoods.add(mood) : _selectedMoods.remove(mood),
    );
  }

  void _clearFilters() {
    _queryController.clear();
    setState(() {
      _query = '';
      _selectedTags.clear();
      _selectedMoods.clear();
      _dateRange = null;
      _onlyFavorites = false;
      _withPhotos = false;
    });
  }

  void _openEntry(DiaryEntryV2 entry) {
    _rememberCurrentSearch();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DiaryDetailPageV2(
          repository: widget.repository,
          imageStore: widget.imageStore,
          entryId: entry.id,
          lifeFragmentRepository: widget.lifeFragmentRepository,
        ),
      ),
    );
  }

  Future<void> _loadRecentSearches() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _recentSearches =
          preferences.getStringList(_recentSearchesKey) ?? const [];
    });
  }

  Future<void> _rememberCurrentSearch() async {
    final query = _query.trim();
    if (query.isEmpty) return;
    final values = [
      query,
      ..._recentSearches.where((value) => value != query),
    ].take(6).toList(growable: false);
    setState(() => _recentSearches = values);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_recentSearchesKey, values);
  }

  void _useRecentSearch(String query) {
    _queryController.text = query;
    _queryController.selection = TextSelection.collapsed(offset: query.length);
    setState(() => _query = query);
  }

  Future<void> _clearRecentSearches() async {
    setState(() => _recentSearches = const []);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_recentSearchesKey);
  }
}

class _ChoiceFilters extends StatelessWidget {
  const _ChoiceFilters({
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final List<String> values;
  final Set<String> selected;
  final String Function(String value) labelFor;
  final void Function(String value, bool selected) onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(
        children: [
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(labelFor(value)),
                selected: selected.contains(value),
                onSelected: (isSelected) => onSelected(value, isSelected),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt({
    required this.recentSearches,
    required this.onRecentTap,
    required this.onClearRecent,
  });

  final List<String> recentSearches;
  final ValueChanged<String> onRecentTap;
  final VoidCallback onClearRecent;

  @override
  Widget build(BuildContext context) {
    if (recentSearches.isEmpty) {
      return const Center(child: Text('输入关键词或选择筛选条件开始搜索'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '最近搜索',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(onPressed: onClearRecent, child: const Text('清空')),
          ],
        ),
        for (final query in recentSearches)
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(query),
            onTap: () => onRecentTap(query),
          ),
      ],
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, size: 42),
          const SizedBox(height: 12),
          const Text('没有找到相关日记'),
          const SizedBox(height: 8),
          TextButton(onPressed: onReset, child: const Text('清除全部筛选')),
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.entries,
    required this.query,
    required this.onTap,
  });

  final List<DiaryEntryV2> entries;
  final String query;
  final ValueChanged<DiaryEntryV2> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final date = entry.entryDate.toLocal();
        return ListTile(
          leading: entry.mood == null
              ? null
              : DiaryMoodTextV2(mood: entry.mood!, maxWidth: 72, maxLines: 2),
          title: _HighlightedText(text: entry.body, query: query),
          subtitle: Text(
            [
              '${date.year}年${date.month}月${date.day}日',
              if (entry.tags.isNotEmpty)
                entry.tags.map((tag) => '#$tag').join(' '),
              if (entry.location?.address case final address?) address,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => onTap(entry),
        );
      },
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final match = lowerText.indexOf(lowerQuery, start);
      if (match < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (match > start) {
        spans.add(TextSpan(text: text.substring(start, match)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match, match + query.length),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = match + query.length;
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
