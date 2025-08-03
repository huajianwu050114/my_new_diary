import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'dart:convert'; // Import for jsonDecode

// The DiaryEntry data model lives here, serving as the single source of truth.
class DiaryEntry {
  final String diaryId;
  final String authorId;
  final List<String> imagePaths;
  final String text;
  final DateTime date;
  final DateTime creationTime;
  final String? mood;
  final List<String> tags;
  final double? latitude;
  final double? longitude;
  final String? address;
  List<String> aiAnalyses;
  final bool isDeleted;

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

  // --- VVV THIS IS THE CORRECTED FACTORY METHOD IN ITS PROPER HOME VVV ---
  factory DiaryEntry.fromMap(Map<String, dynamic> map, String diaryId) {
    // Helper function to safely parse list data from either a JSON string or a List
    List<String> _parseList(dynamic listValue) {
      if (listValue is String && listValue.isNotEmpty) {
        // Data from SQLite is a JSON String, decode it.
        return List<String>.from(jsonDecode(listValue));
      } else if (listValue is List) {
        // Data from Firestore is already a List, just cast it.
        return List<String>.from(listValue);
      }
      // Return an empty list for null or other unexpected types.
      return [];
    }

    // Helper function to safely parse dates from either a Timestamp or a String
    DateTime _parseDate(dynamic dateValue) {
      if (dateValue is Timestamp) {
        return dateValue.toDate();
      } else if (dateValue is String) {
        return DateTime.parse(dateValue);
      }
      // As a fallback, return the current time if the data is malformed.
      return DateTime.now();
    }

    return DiaryEntry(
      diaryId: diaryId,
      authorId: map['authorId'] as String? ?? '',
      // Use the new helper function for list fields
      imagePaths: _parseList(map['imagePaths']),
      text: map['text'] as String? ?? '',
      // Use the new helper function for date fields
      date: _parseDate(map['date']),
      creationTime: _parseDate(map['creationTime']),
      mood: map['mood'] as String?,
      tags: _parseList(map['tags']),
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      address: map['address'] as String?,
      aiAnalyses: _parseList(map['aiAnalyses']),
      // Handle both boolean (from Firestore) and integer (from SQLite) for isDeleted
      isDeleted: map['isDeleted'] is bool
          ? map['isDeleted']
          : (map['isDeleted'] == 1),
    );
  }

  // toMap for writing data out
  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'imagePaths': imagePaths,
      'text': text,
      'date': date.toIso8601String(), // Use ISO8601 string for local storage
      'creationTime': creationTime.toIso8601String(),
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
// 這就是“契約”本身，定義了所有數據操作必須擁有的方法
abstract class DiaryRepository {
  Future<void> addEntry(DiaryEntry entry, List<File> localImageFiles);
  Future<void> updateEntry(DiaryEntry originalEntry, DiaryEntry updatedData, List<File> newImageFiles, List<String> remainingImagePaths);
  Stream<List<DiaryEntry>> getAllEntriesSortedStream();
  Future<void> moveEntryToTrash(String diaryId);
  Stream<List<DiaryEntry>> getTrashEntriesStream();
  Future<void> restoreFromTrash(String diaryId);
  Future<void> deletePermanently(String diaryId);
  Future<void> addAnalysisToEntry(DiaryEntry entry, String newAnalysis);
// 如果需要，未來可以添加導入/導出等方法
}