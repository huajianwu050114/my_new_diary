// file: lib/diary_service.dart (改造後)
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diary_repository.dart';
// 導入我們剛剛創建的兩個倉庫實現
import 'local_diary_repository.dart';
import 'cloud_diary_repository.dart';

// 重新導出 DiaryEntry，這樣UI層只需要 import 這一個文件
export 'diary_repository.dart' show DiaryEntry;

// 定義存儲模式的枚舉
enum StorageMode { local, cloud }

class DiaryService extends ChangeNotifier {
  late DiaryRepository _repository;
  StorageMode _mode = StorageMode.local; // 默認啟動時為本地模式

  StorageMode get currentMode => _mode;

  DiaryService() {
    // 默認使用本地倉庫
    _repository = LocalDiaryRepository();
    _loadModePreference();
  }

  // 從本地加載用戶偏好（本地/雲端）
  Future<void> _loadModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final isCloud = prefs.getBool('is_cloud_mode') ?? false;
    if (isCloud) {
      switchToCloudMode(notify: false); // 首次加載不通知，避免不必要的重繪
    }
  }

  // 切換到本地模式
  void switchToLocalMode({bool notify = true}) {
    _repository = LocalDiaryRepository();
    _mode = StorageMode.local;
    _saveModePreference(false);
    if (notify) notifyListeners(); // 通知UI模式已切換
  }

  // 切換到雲端模式
  void switchToCloudMode({bool notify = true}) {
    _repository = CloudDiaryRepository();
    _mode = StorageMode.cloud;
    _saveModePreference(true);
    if (notify) notifyListeners();
  }

  // 保存用戶的模式選擇
  Future<void> _saveModePreference(bool isCloud) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_cloud_mode', isCloud);
  }

  // --- 所有數據操作都直接委託給當前的 _repository ---

  Future<void> addEntry(DiaryEntry entry, List<File> localImageFiles) async {
    await _repository.addEntry(entry, localImageFiles);
    notifyListeners(); // 寫操作後通知UI刷新
  }

  Stream<List<DiaryEntry>> getAllEntriesSortedStream() {
    // 讀操作直接返回流，不需要 notifyListeners
    return _repository.getAllEntriesSortedStream();
  }

  Future<void> updateEntry(DiaryEntry originalEntry, DiaryEntry updatedData, List<File> newImageFiles, List<String> remainingImagePaths) async {
    await _repository.updateEntry(originalEntry, updatedData, newImageFiles, remainingImagePaths);
    notifyListeners();
  }

  Future<void> moveEntryToTrash(String diaryId) async {
    await _repository.moveEntryToTrash(diaryId);
    notifyListeners();
  }

  Stream<List<DiaryEntry>> getTrashEntriesStream() {
    return _repository.getTrashEntriesStream();
  }

  Future<void> restoreFromTrash(String diaryId) async {
    await _repository.restoreFromTrash(diaryId);
    notifyListeners();
  }

  Future<void> deletePermanently(String diaryId) async {
    await _repository.deletePermanently(diaryId);
    notifyListeners();
  }

  Future<void> addAnalysisToEntry(DiaryEntry entry, String newAnalysis) async {
    await _repository.addAnalysisToEntry(entry, newAnalysis);
    notifyListeners();
  }
}