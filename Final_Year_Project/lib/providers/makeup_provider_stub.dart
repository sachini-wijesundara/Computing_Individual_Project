import 'package:flutter/material.dart';

/// Web / non-IO: same surface as [MakeupProvider] on mobile without `dart:io`.
class MakeupStyle {
  final String id;
  final String name;
  final String category;
  final String imageUrl;
  final Color color;

  MakeupStyle({
    required this.id,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.color,
  });

  factory MakeupStyle.fromJson(Map<String, dynamic> json) {
    return MakeupStyle(
      id: '${json['id']}',
      name: '${json['name']}',
      imageUrl: '${json['image_url']}',
      category: '${json['category']}',
      color: Color(json['color'] as int? ?? 0xFFE91E63),
    );
  }
}

class MakeupProvider extends ChangeNotifier {
  MakeupProvider();

  dynamic get selectedImage => null;
  dynamic get processedImage => null;
  bool get isLoading => false;
  bool get isModelReady => false;
  List<MakeupStyle> get availableStyles => const [];
  String? get error => null;

  Future<void> selectImageFromCamera() async {}
  Future<void> selectImageFromGallery() async {}
  Future<void> applyMakeup(MakeupStyle style) async {}
  void clearResults() {}
  Future<void> refreshModelStatus() async {}
  void setSelectedImage(Object? image) {}
}
