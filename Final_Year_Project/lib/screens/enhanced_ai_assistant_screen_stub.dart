import 'package:flutter/material.dart';

/// Web build: full skin/hair vision pipeline is not bundled in this target.
class EnhancedAIAssistantScreen extends StatelessWidget {
  const EnhancedAIAssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skin & Hair AI'),
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF111111),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'The enhanced skin and hair vision assistant runs in the '
            'iOS/Android app with camera and file analysis. '
            'Use the mobile build for this feature.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ),
      ),
    );
  }
}
