import 'package:flutter/material.dart';
import 'enhanced_ai_assistant_screen.dart';

class AIBeautyAssistantScreen extends StatefulWidget {
  @override
  _AIBeautyAssistantScreenState createState() => _AIBeautyAssistantScreenState();
}

class _AIBeautyAssistantScreenState extends State<AIBeautyAssistantScreen>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
    
    // Add welcome message
    _messages.add(ChatMessage(
      text: "Hello! I'm your AI Beauty Assistant. I can help you with:\n\n"
          "✨ Skin tone analysis\n"
          "💄 Makeup recommendations\n"
          "🎨 Color matching\n"
          "💋 Lipstick suggestions\n"
          "🌟 Beauty tips and trends\n\n"
          "What would you like to know?",
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final userMessage = _messageController.text.trim();
    _messageController.clear();

    setState(() {
      _messages.add(ChatMessage(
        text: userMessage,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
    });

    // Simulate AI response with beauty recommendations
    await Future.delayed(Duration(seconds: 2));

    final aiResponse = _generateAIResponse(userMessage);
    
    setState(() {
      _messages.add(ChatMessage(
        text: aiResponse,
        isUser: false,
        timestamp: DateTime.now(),
      ));
      _isTyping = false;
    });
  }

  String _generateAIResponse(String userMessage) {
    final message = userMessage.toLowerCase();
    
    if (message.contains('skin tone') || message.contains('skin color')) {
      return "Based on your skin tone, I recommend:\n\n"
          "🎨 **Foundation**: Warm undertones - try golden/peachy shades\n"
          "💄 **Lipstick**: Coral, warm reds, or nude with pink undertones\n"
          "👁️ **Eyeshadow**: Bronze, gold, and warm browns\n"
          "💋 **Blush**: Peach or warm pink tones\n\n"
          "Would you like specific product recommendations?";
    } else if (message.contains('lipstick') || message.contains('lip')) {
      return "Here are my lipstick recommendations:\n\n"
          "💋 **For Fair Skin**: Nude pinks, light corals, berry tones\n"
          "💋 **For Medium Skin**: Rose, mauve, warm reds\n"
          "💋 **For Dark Skin**: Deep berries, rich reds, plums\n\n"
          "💡 **Pro Tip**: Match your lipstick to your skin's undertone for the best results!";
    } else if (message.contains('makeup') || message.contains('look')) {
      return "I'd love to help you create the perfect look! Here are some suggestions:\n\n"
          "🌅 **Natural Look**: Light foundation, nude lips, subtle eyeshadow\n"
          "🌙 **Evening Look**: Bold lips, smoky eyes, defined brows\n"
          "🌸 **Spring Look**: Pastel eyeshadows, pink lips, fresh skin\n"
          "🍂 **Autumn Look**: Warm tones, berry lips, golden highlights\n\n"
          "What occasion are you getting ready for?";
    } else if (message.contains('color') || message.contains('match')) {
      return "Color matching is my specialty! Here's how to find your perfect shades:\n\n"
          "🔍 **Skin Undertone Test**:\n"
          "• Look at your veins - blue/purple = cool, green = warm\n"
          "• Gold jewelry looks better on warm skin\n"
          "• Silver jewelry looks better on cool skin\n\n"
          "🎨 **Color Recommendations**:\n"
          "• Cool undertones: Blue-based reds, cool pinks\n"
          "• Warm undertones: Orange-based reds, warm corals";
    } else {
      return "I'm here to help with all your beauty questions! I can assist with:\n\n"
          "✨ Skin analysis and recommendations\n"
          "💄 Makeup tutorials and tips\n"
          "🎨 Color matching and undertone analysis\n"
          "💋 Product suggestions\n"
          "🌟 Beauty trends and techniques\n\n"
          "Feel free to ask me anything about beauty and makeup!";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F4F0),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EnhancedAIAssistantScreen(),
            ),
          );
        },
        backgroundColor: Color(0xFFE91E63),
        icon: Icon(Icons.camera_alt, color: Colors.white),
        label: Text(
          'AI Skin Analysis',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
                      ),
                    ),
                    child: Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                  ),
                );
              },
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Beauty Assistant',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C1810),
                  ),
                ),
                Text(
                  'Your personal beauty expert',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8B7355),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline, color: Color(0xFF8B7355)),
            onPressed: () {
              _showHelpDialog();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Quick suggestions
          Container(
            height: 60,
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildQuickSuggestion('Skin Tone Analysis'),
                SizedBox(width: 8),
                _buildQuickSuggestion('Lipstick Colors'),
                SizedBox(width: 8),
                _buildQuickSuggestion('Makeup Tips'),
                SizedBox(width: 8),
                _buildQuickSuggestion('Color Matching'),
              ],
            ),
          ),
          
          // Chat messages
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isTyping) {
                  return _buildTypingIndicator();
                }
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),
          
          // Message input
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Ask me about beauty and makeup...',
                        hintStyle: TextStyle(color: Color(0xFF8B7355)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
                      ),
                    ),
                    child: Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSuggestion(String text) {
    return GestureDetector(
      onTap: () {
        _messageController.text = text;
        _sendMessage();
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Color(0xFFE91E63).withOpacity(0.3)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Color(0xFFE91E63),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: message.isUser 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
                ),
              ),
              child: Icon(Icons.auto_awesome, color: Colors.white, size: 16),
            ),
            SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: message.isUser ? Color(0xFFE91E63) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: message.isUser ? Colors.white : Color(0xFF2C1810),
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (message.isUser) ...[
            SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF8B7355),
              ),
              child: Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
              ),
            ),
            child: Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          ),
          SizedBox(width: 8),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTypingDot(0),
                SizedBox(width: 4),
                _buildTypingDot(1),
                SizedBox(width: 4),
                _buildTypingDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final delay = index * 0.2;
        final animationValue = (_pulseController.value + delay) % 1.0;
        final opacity = (1.0 - (animationValue - 0.5).abs() * 2).clamp(0.0, 1.0);
        
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFE91E63).withOpacity(opacity),
          ),
        );
      },
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('AI Beauty Assistant Help'),
        content: Text(
          'I can help you with:\n\n'
          '• Skin tone analysis and recommendations\n'
          '• Makeup color matching\n'
          '• Product suggestions\n'
          '• Beauty tips and tutorials\n'
          '• Trend analysis\n\n'
          'Just ask me anything about beauty and makeup!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it!'),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}