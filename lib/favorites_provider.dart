// file: lib/favorites_provider.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 用于表示一条收藏的句子的数据结构
class FavoriteQuote {
  final String quote;
  final String from;
  final DateTime creationTime;

  FavoriteQuote({
    required this.quote,
    required this.from,
    required this.creationTime,
  });

  // VVV 用下面这个更健壮的方法来替换旧的 fromMap VVV
  factory FavoriteQuote.fromMap(Map<String, dynamic> map) {
    // 尝试从map中读取时间字符串
    final timeString = map['creationTime'] as String?;
    DateTime parsedTime;

    // 如果时间字符串存在且不为空，就尝试解析它
    if (timeString != null && timeString.isNotEmpty) {
      // tryParse 在解析失败时会返回 null，而不是抛出错误，更安全
      parsedTime = DateTime.tryParse(timeString) ?? DateTime.now();
    } else {
      // 如果时间字符串不存在或为空，直接使用当前时间作为默认值
      parsedTime = DateTime.now();
    }

    return FavoriteQuote(
      quote: map['quote'] ?? '',
      from: map['from'] ?? '',
      creationTime: parsedTime,
    );
  }

  // 转换为Map（用于编码为JSON）
  Map<String, dynamic> toMap() {
    return {
      'quote': quote,
      'from': from,
      'creationTime': creationTime.toIso8601String(),
    };
  }
}


class FavoritesProvider extends ChangeNotifier {
  final List<FavoriteQuote> _favorites = [];
  late SharedPreferences _prefs;

  List<FavoriteQuote> get favorites => _favorites;

  FavoritesProvider() {
    _init();
  }

  // 初始化，加载本地保存的收藏
  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    final savedFavorites = _prefs.getStringList('favorite_quotes') ?? [];

    final List<FavoriteQuote> loadedFavorites = [];
    for (var favString in savedFavorites) {
      try {
        loadedFavorites.add(FavoriteQuote.fromMap(jsonDecode(favString)));
      } catch (e) {
        // 如果解析失败，打印错误并跳过这条损坏的数据
        print('Failed to parse favorite: $favString, Error: $e');
      }
    }

    _favorites.clear();
    _favorites.addAll(loadedFavorites);

    // 按收藏时间倒序排列，让最新的显示在最上面
    _favorites.sort((a, b) => b.creationTime.compareTo(a.creationTime));
    notifyListeners();
  }

  // 保存收藏列表到本地
  Future<void> _saveFavorites() async {
    final List<String> favListToSave =
    _favorites.map((fav) => jsonEncode(fav.toMap())).toList();
    await _prefs.setStringList('favorite_quotes', favListToSave);
  }

  // 检查当前句子是否已被收藏
  bool isFavorite(String quote, String from) {
    return _favorites.any((fav) => fav.quote == quote && fav.from == from);
  }

  // 添加收藏
  void addFavorite(String quote, String from) {
    if (!isFavorite(quote, from)) {
      _favorites.insert(0, FavoriteQuote(quote: quote, from: from, creationTime: DateTime.now()));
      _saveFavorites();
      notifyListeners();
    }
  }

  // 移除收藏
  void removeFavorite(String quote, String from) {
    _favorites.removeWhere((fav) => fav.quote == quote && fav.from == from);
    _saveFavorites();
    notifyListeners();
  }
}