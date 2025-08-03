// file: lib/cloud_diary_repository.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'diary_repository.dart';

// 這是你原有DiaryService的雲端實現版本
class CloudDiaryRepository implements DiaryRepository {
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;

  // DiaryEntry模型現在從diary_repository.dart導入，這裡不需要再定義

  @override
  Future<void> addEntry(DiaryEntry entry, List<File> localImageFiles) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not logged in");

    final List<String> imageUrls = [];
    for (var file in localImageFiles) {
      final ref = _storage.ref('users/${user.uid}/images/${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      imageUrls.add(url);
    }

    final entryWithImages = DiaryEntry(
      diaryId: '', // Firestore will auto-generate
      authorId: user.uid,
      text: entry.text,
      imagePaths: imageUrls,
      date: entry.date,
      creationTime: entry.creationTime,
      mood: entry.mood,
      tags: entry.tags,
      latitude: entry.latitude,
      longitude: entry.longitude,
      address: entry.address,
    );

    // 注意：在雲端模式下，我們需要將日期轉回Timestamp
    final entryMap = entryWithImages.toMap();
    entryMap['date'] = Timestamp.fromDate(entryWithImages.date);
    entryMap['creationTime'] = Timestamp.fromDate(entryWithImages.creationTime);

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('diaries')
        .add(entryMap);
  }

  @override
  Stream<List<DiaryEntry>> getAllEntriesSortedStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('diaries')
        .where('isDeleted', isEqualTo: false)
        .orderBy('creationTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => DiaryEntry.fromMap(doc.data(), doc.id))
        .toList());
  }

  // --- 將你原有DiaryService中的其他所有方法複製到這裡 ---
  // --- 注意：要加上 @override 標記，並刪除 notifyListeners() ---

  @override
  Future<void> updateEntry(
      DiaryEntry originalEntry,
      DiaryEntry updatedData,
      List<File> newImageFiles,
      List<String> remainingImageUrls) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final docRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('diaries')
        .doc(originalEntry.diaryId);

    final List<String> deletedImageUrls = originalEntry.imagePaths
        .where((url) => !remainingImageUrls.contains(url))
        .toList();

    for (final url in deletedImageUrls) {
      try {
        await _storage.refFromURL(url).delete();
      } catch (e) {
        print("從Storage刪除舊圖片失敗: $e");
      }
    }

    final List<String> newImageUrls = [];
    for (final file in newImageFiles) {
      final ref = _storage.ref('users/${user.uid}/images/${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      newImageUrls.add(url);
    }

    final finalImageUrls = [...remainingImageUrls, ...newImageUrls];

    final Map<String, dynamic> dataToUpdate = {
      'text': updatedData.text,
      'mood': updatedData.mood,
      'tags': updatedData.tags,
      'imagePaths': finalImageUrls,
    };

    await docRef.update(dataToUpdate);
  }

  @override
  Future<void> moveEntryToTrash(String diaryId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).collection('diaries').doc(diaryId).update({'isDeleted': true});
  }

  @override
  Stream<List<DiaryEntry>> getTrashEntriesStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);
    return _firestore.collection('users').doc(user.uid).collection('diaries').where('isDeleted', isEqualTo: true).orderBy('creationTime', descending: true).snapshots().map((snapshot) => snapshot.docs.map((doc) => DiaryEntry.fromMap(doc.data(), doc.id)).toList());
  }

  @override
  Future<void> restoreFromTrash(String diaryId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).collection('diaries').doc(diaryId).update({'isDeleted': false});
  }

  @override
  Future<void> deletePermanently(String diaryId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final docRef = _firestore.collection('users').doc(user.uid).collection('diaries').doc(diaryId);
    final docSnapshot = await docRef.get();
    if (!docSnapshot.exists) return;
    final entry = DiaryEntry.fromMap(docSnapshot.data()!, docSnapshot.id);
    for (String url in entry.imagePaths) {
      if (url.isEmpty) continue;
      try {
        await _storage.refFromURL(url).delete();
      } catch (e) {
        print("從Storage刪除圖片失敗: $e");
      }
    }
    await docRef.delete();
  }

  @override
  Future<void> addAnalysisToEntry(DiaryEntry entry, String newAnalysis) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final docRef = _firestore.collection('users').doc(user.uid).collection('diaries').doc(entry.diaryId);
    await docRef.update({
      'aiAnalyses': FieldValue.arrayUnion([newAnalysis])
    });
  }
}