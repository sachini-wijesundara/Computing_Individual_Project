import 'package:flutter/material.dart';

/// Web / unsupported: gallery flow is mobile-only in this project.
class GalleryScreen extends StatelessWidget {
  GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gallery')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Gallery selection is not available in this build. Use the iOS or Android app.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
