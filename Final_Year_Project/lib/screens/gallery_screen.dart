import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../providers/makeup_provider.dart';

class GalleryScreen extends StatefulWidget {
  @override
  _GalleryScreenState createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Photo Gallery'),
        backgroundColor: Color(0xFFE91E63),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F8F8),
              Color(0xFFF0F0F0),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 100,
                color: Colors.grey.shade400,
              ),
              SizedBox(height: 20),
              Text(
                'Select a Photo',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Choose a photo from your gallery to try on makeup',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _pickImage,
                icon: Icon(Icons.photo_library),
                label: Text('Choose Photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFE91E63),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        final makeupProvider = Provider.of<MakeupProvider>(context, listen: false);
        makeupProvider.setSelectedImage(File(image.path));
        
        Navigator.pushNamed(context, '/makeup');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}




