import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/makeup_service.dart';

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
      id: json['id'],
      name: json['name'],
      imageUrl: json['image_url'],
      category: json['category'],
      color: Color(json['color'] ?? 0xFFE91E63),
    );
  }
}

class MakeupProvider extends ChangeNotifier {
  File? _selectedImage;
  File? _processedImage;
  bool _isLoading = false;
  bool _isModelReady = false;
  List<MakeupStyle> _availableStyles = [];
  String? _error;

  // Getters
  File? get selectedImage => _selectedImage;
  File? get processedImage => _processedImage;
  bool get isLoading => _isLoading;
  bool get isModelReady => _isModelReady;
  List<MakeupStyle> get availableStyles => _availableStyles;
  String? get error => _error;

  MakeupProvider() {
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    try {
      // Check if model is ready
      _isModelReady = await _checkModelStatus();
      notifyListeners();
      
      if (_isModelReady) {
        await _loadMakeupStyles();
      }
    } catch (e) {
      _error = 'Failed to initialize model: $e';
      notifyListeners();
    }
  }

  Future<bool> _checkModelStatus() async {
    // In a real implementation, this would check with the API
    // For now, we'll simulate checking
    await Future.delayed(Duration(seconds: 2));
    return true; // Assume model is ready
  }

  Future<void> _loadMakeupStyles() async {
    try {
      _availableStyles = await MakeupService.getMakeupStyles();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load makeup styles: $e';
      notifyListeners();
    }
  }

  Future<void> selectImageFromCamera() async {
    try {
      _setLoading(true);
      _clearError();
      
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        _selectedImage = File(pickedFile.path);
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to capture image: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> selectImageFromGallery() async {
    try {
      _setLoading(true);
      _clearError();
      
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        _selectedImage = File(pickedFile.path);
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to select image: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> applyMakeup(MakeupStyle style) async {
    if (_selectedImage == null) {
      _error = 'No image selected';
      notifyListeners();
      return;
    }

    try {
      _setLoading(true);
      _clearError();

      // Preprocess the selected image
      final processedFaceImage = await MakeupService.preprocessImage(_selectedImage!);
      
      // Apply makeup
      final result = await MakeupService.applyMakeup(
        faceImage: processedFaceImage,
        makeupStyle: File(style.imageUrl), // This would need to be a local file
        makeupType: style.category,
      );

      if (result != null) {
        _processedImage = result;
        notifyListeners();
      } else {
        _error = 'Failed to apply makeup';
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to apply makeup: $e';
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  void clearResults() {
    _selectedImage = null;
    _processedImage = null;
    _clearError();
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> refreshModelStatus() async {
    _isModelReady = await _checkModelStatus();
    if (_isModelReady) {
      await _loadMakeupStyles();
    }
    notifyListeners();
  }

  void setSelectedImage(File image) {
    _selectedImage = image;
    notifyListeners();
  }
}
