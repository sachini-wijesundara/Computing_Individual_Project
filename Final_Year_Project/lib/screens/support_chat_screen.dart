import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const _maroon = Color(0xFF7C150D);
const _ink = Color(0xFF1F1F1F);

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  Timer? _typingDebounce;
  bool _markingSeen = false;

  User? get _user => FirebaseAuth.instance.currentUser;
  String get _chatId => _user!.uid;

  @override
  void initState() {
    super.initState();
    final user = _user;
    if (user != null) {
      FirebaseFirestore.instance.collection('support_chats').doc(user.uid).set({
        'unreadForUser': false,
        'typingByUser': false,
      }, SetOptions(merge: true));
    }
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _setTypingForUser(false);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final user = _user;
    final text = _msgCtrl.text.trim();
    if (user == null || text.isEmpty) return;

    setState(() => _sending = true);
    _msgCtrl.clear();

    try {
      final db = FirebaseFirestore.instance;
      final chatRef = db.collection('support_chats').doc(_chatId);
      final nowServer = FieldValue.serverTimestamp();
      final nowLocal = Timestamp.now();

      await chatRef.set({
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'userName': user.displayName ?? '',
        'lastMessage': text,
        'lastMessageAt': nowServer,
        'updatedAt': nowServer,
        'unreadForAdmin': true,
        'unreadForUser': false,
        'typingByUser': false,
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add({
        'senderId': user.uid,
        'senderRole': 'user',
        'text': text,
        'createdAt': nowLocal,
        'createdAtServer': nowServer,
        'seenByAdmin': false,
        'seenByUser': true,
      });

      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message failed to send: $e')),
      );
      _msgCtrl.text = text;
      _msgCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _msgCtrl.text.length),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setTypingForUser(bool value) async {
    final user = _user;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('support_chats').doc(_chatId).set({
        'typingByUser': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // typing signal failures should not block chat UX
    }
  }

  void _handleTypingChanged(String value) {
    final hasText = value.trim().isNotEmpty;
    _typingDebounce?.cancel();
    if (hasText) {
      _setTypingForUser(true);
      _typingDebounce = Timer(const Duration(milliseconds: 1100), () {
        _setTypingForUser(false);
      });
    } else {
      _setTypingForUser(false);
    }
  }

  Future<void> _markAdminMessagesSeen(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (_markingSeen) return;
    final unseen = docs.where((m) {
      final d = m.data();
      return d['senderRole'] == 'admin' && d['seenByUser'] != true;
    }).toList();
    if (unseen.isEmpty) return;
    _markingSeen = true;
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final chatRef = db.collection('support_chats').doc(_chatId);
      for (final m in unseen) {
        batch.update(m.reference, {'seenByUser': true});
      }
      batch.set(chatRef, {
        'unreadForUser': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
    } finally {
      _markingSeen = false;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 70,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Live Chat'),
          backgroundColor: Colors.white,
          foregroundColor: _ink,
        ),
        body: const Center(
          child: Text('Please sign in to chat with admin.'),
        ),
      );
    }

    final msgStream = FirebaseFirestore.instance
        .collection('support_chats')
        .doc(_chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();

    final chatDocStream = FirebaseFirestore.instance.collection('support_chats').doc(_chatId).snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Chat with Admin'),
        backgroundColor: Colors.white,
        foregroundColor: _ink,
      ),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: chatDocStream,
            builder: (context, snap) {
              final typing = snap.data?.data()?['typingByAdmin'] == true;
              if (!typing) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                child: const Text(
                  'Admin is typing...',
                  style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: msgStream,
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Send a message to start chatting with admin.'),
                  );
                }
                _markAdminMessagesSeen(docs);
                _scrollToBottom();
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final isMe = d['senderRole'] == 'user';
                    final seenByAdmin = d['seenByAdmin'] == true;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isMe ? _maroon : const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              (d['text'] ?? '').toString(),
                              style: TextStyle(color: isMe ? Colors.white : _ink),
                            ),
                            if (isMe) ...[
                              const SizedBox(height: 3),
                              Text(
                                seenByAdmin ? 'Seen' : 'Delivered',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.white.withValues(alpha: 0.82),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      onChanged: _handleTypingChanged,
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        filled: true,
                        fillColor: const Color(0xFFF6F6F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(backgroundColor: _maroon),
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
