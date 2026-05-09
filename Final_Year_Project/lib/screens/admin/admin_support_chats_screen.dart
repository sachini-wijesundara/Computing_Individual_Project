import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminSupportChatsScreen extends StatelessWidget {
  const AdminSupportChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('support_chats')
        .orderBy('updatedAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F2F1),
      appBar: AppBar(
        title: const Text('Customer Chats'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F1A1A),
        elevation: 0.2,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEADBD7)),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.forum_outlined, color: Color(0xFF7C150D), size: 34),
                    SizedBox(height: 10),
                    Text(
                      'No customer chats yet',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Messages from app users will appear here in real time.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            );
          }
          final unreadCount = docs.where((d) => d.data()['unreadForAdmin'] == true).length;
          return Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE9DDDA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mark_chat_unread_rounded, color: Color(0xFF7C150D)),
                    const SizedBox(width: 8),
                    Text(
                      unreadCount > 0
                          ? '$unreadCount unread conversation(s)'
                          : 'All chats are up to date',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final d = doc.data();
              final name = (d['userName'] ?? '').toString();
              final email = (d['userEmail'] ?? '').toString();
              final last = (d['lastMessage'] ?? '').toString();
              final unread = d['unreadForAdmin'] == true;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AdminSupportChatDetailScreen(
                        chatId: doc.id,
                        chatTitle: name.isEmpty ? email : name,
                      ),
                    ),
                  ),
                  child: Ink(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: unread ? const Color(0xFFE9B9A8) : const Color(0xFFE9DDDA),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: unread ? const Color(0xFF7C150D) : Colors.grey.shade300,
                          child: Icon(Icons.person, color: unread ? Colors.white : Colors.black54),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isEmpty ? email : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                last.isEmpty ? 'No messages yet' : last,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: unread ? const Color(0xFF3C2320) : Colors.black54,
                                  fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        unread
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C150D),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: const Text(
                                  'New',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded, color: Colors.black45),
                      ],
                    ),
                  ),
                ),
              );
            },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class AdminSupportChatDetailScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  const AdminSupportChatDetailScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
  });

  @override
  State<AdminSupportChatDetailScreen> createState() => _AdminSupportChatDetailScreenState();
}

class _AdminSupportChatDetailScreenState extends State<AdminSupportChatDetailScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  bool _markingSeen = false;
  Timer? _typingDebounce;

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance.collection('support_chats').doc(widget.chatId).set({
      'unreadForAdmin': false,
    }, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _setTypingForAdmin(false);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    _msgCtrl.clear();

    try {
      final chatRef = FirebaseFirestore.instance.collection('support_chats').doc(widget.chatId);
      final nowServer = FieldValue.serverTimestamp();
      final nowLocal = Timestamp.now();

      await chatRef.collection('messages').add({
        'senderId': 'admin',
        'senderRole': 'admin',
        'text': text,
        'createdAt': nowLocal,
        'createdAtServer': nowServer,
        'seenByAdmin': true,
        'seenByUser': false,
      });

      await chatRef.set({
        'lastMessage': text,
        'lastMessageAt': nowServer,
        'updatedAt': nowServer,
        'unreadForAdmin': false,
        'unreadForUser': true,
        'typingByAdmin': false,
      }, SetOptions(merge: true));

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

  Future<void> _setTypingForAdmin(bool value) async {
    try {
      await FirebaseFirestore.instance.collection('support_chats').doc(widget.chatId).set({
        'typingByAdmin': value,
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
      _setTypingForAdmin(true);
      _typingDebounce = Timer(const Duration(milliseconds: 1100), () {
        _setTypingForAdmin(false);
      });
    } else {
      _setTypingForAdmin(false);
    }
  }

  Future<void> _markUserMessagesSeen(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (_markingSeen) return;
    final unseen = docs.where((m) {
      final d = m.data();
      return d['senderRole'] == 'user' && d['seenByAdmin'] != true;
    }).toList();
    if (unseen.isEmpty) return;
    _markingSeen = true;
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final chatRef = db.collection('support_chats').doc(widget.chatId);
      for (final m in unseen) {
        batch.update(m.reference, {'seenByAdmin': true});
      }
      batch.set(chatRef, {
        'unreadForAdmin': false,
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
    final stream = FirebaseFirestore.instance
        .collection('support_chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: Text(widget.chatTitle)),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('support_chats').doc(widget.chatId).snapshots(),
            builder: (context, snap) {
              final typing = snap.data?.data()?['typingByUser'] == true;
              if (!typing) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                child: const Text(
                  'Customer is typing...',
                  style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No messages yet.'));
                }
                _markUserMessagesSeen(docs);
                _scrollToBottom();
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final isAdmin = d['senderRole'] == 'admin';
                    final seenByUser = d['seenByUser'] == true;
                    return Align(
                      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isAdmin ? const Color(0xFF7C150D) : const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              (d['text'] ?? '').toString(),
                              style: TextStyle(color: isAdmin ? Colors.white : Colors.black87),
                            ),
                            if (isAdmin) ...[
                              const SizedBox(height: 3),
                              Text(
                                seenByUser ? 'Seen' : 'Delivered',
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
                        hintText: 'Reply to customer...',
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
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFF7C150D)),
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
