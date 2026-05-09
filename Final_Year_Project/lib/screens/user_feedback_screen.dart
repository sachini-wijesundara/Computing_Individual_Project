import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const _bgTop = Color(0xFFF5F5F5);
const _bgMid = Color(0xFFF1ABAD);
const _bgBot = Color(0xFFF7BDBD);
const _ink = Color(0xFF171717);
const _maroon = Color(0xFF7C150D);

class UserFeedbackScreen extends StatefulWidget {
  final bool isProblemReport;
  const UserFeedbackScreen({super.key, this.isProblemReport = false});

  @override
  State<UserFeedbackScreen> createState() => _UserFeedbackScreenState();
}

class _UserFeedbackScreenState extends State<UserFeedbackScreen> {
  final _commentCtrl = TextEditingController();
  double _score = 3;
  bool _saving = false;

  static const _faces = ['😡', '😕', '😐', '🙂', '😍'];
  static const _labels = ['Very Bad', 'Bad', 'Okay', 'Good', 'Excellent'];

  int get _index => _score.round().clamp(1, 5) - 1;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in first.')),
      );
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('user_feedback').add({
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'userName': user.displayName ?? '',
        'type': widget.isProblemReport ? 'report' : 'feedback',
        'moodScore': _index + 1,
        'moodLabel': _labels[_index],
        'comment': _commentCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isProblemReport
              ? 'Report submitted. Thank you.'
              : 'Feedback submitted. Thank you.'),
          backgroundColor: const Color(0xFF1F8A43),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isProblemReport ? 'Report a Problem' : 'Feedback';
    final subtitle = widget.isProblemReport
        ? 'Tell us what went wrong and select a face that matches your experience.'
        : 'How was your experience? Move the face slider and optionally leave a note.';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        elevation: 0.2,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgMid, _bgBot],
            stops: [0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                subtitle,
                style: const TextStyle(color: Colors.black87, height: 1.4),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE9DDDA)),
                ),
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Text(
                        _faces[_index],
                        key: ValueKey(_index),
                        style: const TextStyle(fontSize: 58),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _labels[_index],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Slider(
                      value: _score,
                      min: 1,
                      max: 5,
                      divisions: 4,
                      activeColor: _maroon,
                      label: _labels[_index],
                      onChanged: (v) => setState(() => _score = v),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        _faces.length,
                        (i) => Text(_faces[i], style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentCtrl,
                minLines: 4,
                maxLines: 8,
                maxLength: 1000,
                decoration: InputDecoration(
                  hintText: widget.isProblemReport
                      ? 'Describe the problem (what happened, where, steps...)'
                      : 'Optional comment...',
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.82),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: _maroon,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(widget.isProblemReport ? 'Submit Report' : 'Submit Feedback'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

