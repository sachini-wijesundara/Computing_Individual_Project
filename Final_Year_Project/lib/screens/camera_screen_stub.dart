import 'package:flutter/material.dart';

/// Web / unsupported: camera stack is mobile-only in this project.
class CameraScreen extends StatelessWidget {
  CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Camera preview is not available in this build. Use the iOS or Android app.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
