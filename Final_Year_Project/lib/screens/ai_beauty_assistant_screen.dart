// lib/screens/ai_beauty_assistant_screen.dart
//
// Gemini chatbot — dark theme to match the Beauty AI screenshot.
// Header: "< Beauty AI" · camera icon
// Dark bubbles, quick suggestion chips, camera+text input bar.

import 'package:flutter/material.dart';
import 'enhanced_ai_assistant_screen.dart';
import '../services/gemini_chat_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _bg        = Color(0xFF111111);
const _surface   = Color(0xFF1C1C1C);
const _bubbleClr = Color(0xFF242424);
const _red       = Color(0xFFC41E3A);

// ═════════════════════════════════════════════════════════════════════════════
class AIBeautyAssistantScreen extends StatefulWidget {
  const AIBeautyAssistantScreen({super.key});
  // ignore: annotate_overrides
  State<AIBeautyAssistantScreen> createState() =>
      _AIBeautyAssistantScreenState();
}

class _AIBeautyAssistantScreenState extends State<AIBeautyAssistantScreen>
    with SingleTickerProviderStateMixin {

  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final _gemini = GeminiChatService();
  final List<ChatMessage> _msgs = [];
  bool _typing = false;

  late final AnimationController _dotCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  @override
  void initState() {
    super.initState();
    // Welcome message
    _msgs.add(ChatMessage(
      text: '👋 Hi! I\'m your **La Vogue Vista AI Beauty Assistant**.\n\n'
          'Tap **Scan My Beauty Profile** to take a selfie — I\'ll use my '
          'trained AI models to analyse your:\n'
          '• Skin tone & undertone\n'
          '• Hair type & colour\n\n'
          'Then ask me anything — foundation shades, lipstick picks, '
          'hair care routines — and I\'ll answer based on *your* actual profile! 💄',
      isUser: false,
    ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _ctrl.text).trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    setState(() { _msgs.add(ChatMessage(text: text, isUser: true)); _typing = true; });
    _scrollDown();
    final reply = await _gemini.sendMessage(text);
    if (!mounted) return;
    setState(() { _msgs.add(ChatMessage(text: reply, isUser: false)); _typing = false; });
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).maybePop()),
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Beauty AI',
            style: TextStyle(color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.w800)),
          const Text('Powered by trained TFLite models',
            style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 11)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_camera_outlined,
                color: Colors.white54, size: 22),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const EnhancedAIAssistantScreen()))),
        ],
      ),

      body: Column(children: [
        // ── Chat list ────────────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            itemCount: _msgs.length + (_typing ? 1 : 0),
            itemBuilder: (_, i) {
              if (_typing && i == _msgs.length) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: _typingBubble(),
                  ),
                );
              }
              return _msgBubble(_msgs[i]);
            },
          ),
        ),

        // ── Quick suggestions ────────────────────────────────────────────
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _chip('Scan my beauty profile 📷',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const EnhancedAIAssistantScreen()))),
              _chip('Lipstick colours 💄'),
              _chip('Hair care routine 💇'),
              _chip('Foundation shade 🎨'),
              _chip('Skincare tips ✨'),
            ],
          ),
        ),

        // ── Input bar ────────────────────────────────────────────────────
        SafeArea(
          top: false,
          child: Container(
            color: _surface,
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(children: [
              // Camera shortcut
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const EnhancedAIAssistantScreen())),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: _red, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Ask about makeup, skincare, hair…',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send_rounded, color: _red, size: 22),
                onPressed: () => _send()),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Bubble ────────────────────────────────────────────────────────────────
  Widget _msgBubble(ChatMessage m) {
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 6, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: m.isUser ? _red : _bubbleClr,
          borderRadius: BorderRadius.circular(16)),
        child: Text(m.text,
          style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45)),
      ),
    );
  }

  // ── Typing dots ───────────────────────────────────────────────────────────
  Widget _typingBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: _bubbleClr, borderRadius: BorderRadius.circular(16)),
      child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _dotCtrl,
          builder: (_, __) {
            final v = ((_dotCtrl.value * 3).floor() == i) ? 1.0 : 0.3;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: v),
                shape: BoxShape.circle));
          });
      })),
    );
  }

  // ── Suggestion chip ───────────────────────────────────────────────────────
  Widget _chip(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap ?? () => _send(label),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12)),
        child: Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  const ChatMessage({required this.text, required this.isUser});
}
