import 'package:flutter/material.dart';

const _brand = Color(0xFF7C150D);
const _ink = Color(0xFF1E1A1A);
const _muted = Color(0xFF6B6565);

/// Placeholder hub for viewing customer feedback and reports (extend with Firestore later).
class AdminUserFeedbackScreen extends StatelessWidget {
  const AdminUserFeedbackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F2F1),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0.2,
        title: const Text(
          'User feedback & reports',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Review what customers share from the app. Connect these sections to your feedback store when ready.',
            style: TextStyle(color: _muted.withValues(alpha: 0.95), height: 1.45, fontSize: 14),
          ),
          const SizedBox(height: 20),
          _sectionCard(
            icon: Icons.feedback_outlined,
            title: 'Feedback',
            subtitle:
                'Ratings, comments, and in-app feedback submissions will show here once wired to a collection or backend.',
          ),
          const SizedBox(height: 14),
          _sectionCard(
            icon: Icons.flag_outlined,
            title: 'Reports',
            subtitle:
                'Customer issue reports and flagged content can be listed here for your team to action.',
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9DDDA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1EC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _brand, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13.5, color: _muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EBEA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'No items yet',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
