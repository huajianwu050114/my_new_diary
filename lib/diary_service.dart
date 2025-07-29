import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// 日记条目的数据模型。
/// 已为云端存储进行适配，包含云端特有字段。
class DiaryEntry {
  final String diaryId;          // Firestore文档的唯一ID
  final String authorId;         // 日记作者的Firebase用户UID
  final List<String> imagePaths; // 存储图片的云端下载URL
  final String text;             // 日记正文
  final DateTime date;           // 日记所属日期
  final DateTime creationTime;   // 日记创建/编辑的具体时间
  final String? mood;            // 心情
  final List<String> tags;       // 标签
  final double? latitude;        // 地理位置纬度
  final double? longitude;       // 地理位置经度
  final String? address;         // 地址名称
  List<String> aiAnalyses;     // AI分析结果列表
  final bool isDeleted;          // 用于实现回收站功能的软删除标记

  // DiaryEntry的构造函数
  DiaryEntry({
    required this.diaryId,
    required this.authorId,
    required this.imagePaths,
    required this.text,
    required this.date,
    required this.creationTime,
    this.mood,
    this.tags = const [],
    this.latitude,
    this.longitude,
    this.address,
    this.aiAnalyses = const [],
    this.isDeleted = false,
  });

  /// 工厂方法：从Firestore文档的Map数据创建DiaryEntry实例。
  /// [map] 是从Firestore获取的文档数据。
  /// [diaryId] 是该文档在Firestore中的唯一ID。
  factory DiaryEntry.fromMap(Map<String, dynamic> map, String diaryId) {
    return DiaryEntry(
      diaryId: diaryId,
      authorId: map['authorId'] ?? '',
      imagePaths: List<String>.from(map['imagePaths'] ?? []),
      text: map['text'] ?? '',
      // Firestore存储的是Timestamp类型，需要转换为DateTime
      date: (map['date'] as Timestamp).toDate(),
      creationTime: (map['creationTime'] as Timestamp).toDate(),
      mood: map['mood'],
      tags: List<String>.from(map['tags'] ?? []),
      latitude: map['latitude'],
      longitude: map['longitude'],
      address: map['address'],
      aiAnalyses: List<String>.from(map['aiAnalyses'] ?? []),
      isDeleted: map['isDeleted'] ?? false,
    );
  }

  /// 将DiaryEntry实例转换为Map，以便写入Firestore。
  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'imagePaths': imagePaths,
      'text': text,
      // 为了能在Firestore中进行有效的查询和排序，将DateTime转换为Timestamp类型
      'date': Timestamp.fromDate(date),
      'creationTime': Timestamp.fromDate(creationTime),
      'mood': mood,
      'tags': tags,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'aiAnalyses': aiAnalyses,
      'isDeleted': isDeleted,
    };
  }
}


/// 管理日记所有操作的服务类，与Firebase后端交互。
class DiaryService extends ChangeNotifier {
  // 获取Firebase核心服务的实例
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;

  /// 添加一篇新的日记。
  /// 此方法会先将本地图片上传到Firebase Storage，然后将包含图片URL的日记数据写入Cloud Firestore。
  /// [entry] 是包含用户输入的基础日记信息的实例。
  /// [localImageFiles] 是用户选择的本地图片文件列表。
  // 文件: lib/diary_service.dart

// 请找到 addEntry 方法，并用下面的代码完整替换它
  Future<void> addEntry(DiaryEntry entry, List<File> localImageFiles) async {
    // --- 诊断代码 ---
    print("SERVICE DEBUG: A. 'addEntry' 方法开始执行。");

    final user = _auth.currentUser;
    if (user == null) {
      print("SERVICE DEBUG: B. 错误：用户未登录。");
      throw Exception("用户未登录，无法添加日记");
    }

    print("SERVICE DEBUG: C. 用户已登录: ${user.uid}");
    print("SERVICE DEBUG: D. 准备上传 ${localImageFiles.length} 张图片...");

    List<String> cloudImageUrls = [];
    try {
      for (int i = 0; i < localImageFiles.length; i++) {
        File localFile = localImageFiles[i];
        print("SERVICE DEBUG: E-$i. 开始上传第 ${i+1} 张图片: ${p.basename(localFile.path)}");

        String fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(localFile.path)}';
        Reference ref = _storage.ref('users/${user.uid}/images/$fileName');

        // 等待图片上传完成
        await ref.putFile(localFile);
        print("SERVICE DEBUG: F-$i. 第 ${i+1} 张图片上传成功。");

        // 等待获取下载URL
        String downloadUrl = await ref.getDownloadURL();
        cloudImageUrls.add(downloadUrl);
        print("SERVICE DEBUG: G-$i. 成功获取第 ${i+1} 张图片的下载URL。");
      }
    } catch (e) {
      print("SERVICE DEBUG: X1. 图片上传过程中发生错误: $e");
      rethrow; // 重新抛出异常，让UI层能捕获到
    }

    print("SERVICE DEBUG: H. 所有图片处理完成，准备写入Firestore。");

    DiaryEntry entryForCloud = DiaryEntry(
      diaryId: '',
      authorId: user.uid,
      imagePaths: cloudImageUrls,
      text: entry.text,
      date: entry.date,
      creationTime: entry.creationTime,
      mood: entry.mood,
      tags: entry.tags,
      latitude: entry.latitude,
      longitude: entry.longitude,
      address: entry.address,
    );

    try {
      // 等待写入Firestore
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('diaries')
          .add(entryForCloud.toMap());

      print("SERVICE DEBUG: I. 数据成功写入Firestore。");
    } catch (e) {
      print("SERVICE DEBUG: X2. 写入Firestore时发生错误: $e");
      rethrow;
    }

    notifyListeners();
    print("SERVICE DEBUG: J. 'addEntry' 方法执行完毕。");
  }

  /// 获取当前用户所有未被软删除的日记流。
  /// 返回一个Stream，可以实时监听数据变化。
  Stream<List<DiaryEntry>> getAllEntriesSortedStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]); // 如果用户未登录，返回空流

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('diaries')
        .where('isDeleted', isEqualTo: false) // 仅获取未被删除的日记
        .orderBy('creationTime', descending: true) // 按创建时间倒序排列
        .snapshots() // snapshots()方法返回一个Stream，实现实时更新
        .map((snapshot) => snapshot.docs
        .map((doc) => DiaryEntry.fromMap(doc.data(), doc.id))
        .toList());
  }

  /// 获取指定某一天的所有日记流。
  Stream<List<DiaryEntry>> getEntriesForDayStream(DateTime day) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // 计算查询范围：从指定日期的0点0分到下一天的0点0分
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('diaries')
        .where('isDeleted', isEqualTo: false)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay))
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => DiaryEntry.fromMap(doc.data(), doc.id))
        .toList());
  }

  /// 将日记移动到回收站（软删除）。
  /// 只是将`isDeleted`字段更新为`true`，并不会真正删除数据。
  Future<void> moveEntryToTrash(String diaryId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('diaries')
        .doc(diaryId)
        .update({'isDeleted': true});
    notifyListeners();
  }

  /// 获取回收站中的所有日记流。
  Stream<List<DiaryEntry>> getTrashEntriesStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('diaries')
        .where('isDeleted', isEqualTo: true) // 查询被标记为删除的日记
        .orderBy('creationTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => DiaryEntry.fromMap(doc.data(), doc.id))
        .toList());
  }

  /// 从回收站恢复日记。
  /// 将`isDeleted`字段更新为`false`。
  Future<void> restoreFromTrash(String diaryId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('diaries')
        .doc(diaryId)
        .update({'isDeleted': false});
    notifyListeners();
  }

  /// 永久删除一篇日记及其在Storage中的所有图片。
  /// 这是一个不可逆的操作。
  Future<void> deletePermanently(String diaryId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final docRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('diaries')
        .doc(diaryId);

    // 在删除文档前，先获取文档快照以拿到图片URL列表
    final docSnapshot = await docRef.get();
    if (!docSnapshot.exists) return; // 如果文档不存在，直接返回

    final entry = DiaryEntry.fromMap(docSnapshot.data()!, docSnapshot.id);

    // 1. 遍历URL，从Storage中删除对应的图片文件
    for (String url in entry.imagePaths) {
      if (url.isEmpty) continue;
      try {
        await _storage.refFromURL(url).delete();
      } catch (e) {
        // 即便某张图片删除失败，也继续尝试删除其他的，并打印错误
        print("从Storage删除图片失败: $e");
      }
    }

    // 2. 最后，从Firestore中删除该文档
    await docRef.delete();
    notifyListeners();
  }

  /// 为某篇日记添加一条AI分析记录。
  Future<void> addAnalysisToEntry(DiaryEntry entry, String newAnalysis) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final docRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('diaries')
        .doc(entry.diaryId);

    // 使用FieldValue.arrayUnion可以高效、安全地向数组字段中添加新元素，避免重复添加。
    await docRef.update({
      'aiAnalyses': FieldValue.arrayUnion([newAnalysis])
    });
    notifyListeners();
  }
}