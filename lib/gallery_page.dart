// file: libs/gallery_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

class GalleryPage extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;

  const GalleryPage({
    super.key,
    required this.imagePaths,
    this.initialIndex = 0,
  });

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late int currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void onPageChanged(int index) {
    setState(() {
      currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        // 在标题处显示 "当前页 / 总页数"
        title: Text(
          '${currentIndex + 1} / ${widget.imagePaths.length}',
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: PhotoViewGallery.builder(
        pageController: _pageController,
        itemCount: widget.imagePaths.length,
        builder: (context, index) {
          final imagePath = widget.imagePaths[index];
          return PhotoViewGalleryPageOptions(
            imageProvider: FileImage(File(imagePath)),
            initialScale: PhotoViewComputedScale.contained,
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 2.0,
            heroAttributes: PhotoViewHeroAttributes(tag: imagePath),
          );
        },
        onPageChanged: onPageChanged,
        // 设置背景为黑色
        backgroundDecoration: const BoxDecoration(
          color: Colors.black,
        ),
        // 允许在所有图片间循环滑动
        scrollPhysics: const BouncingScrollPhysics(),
      ),
    );
  }
}