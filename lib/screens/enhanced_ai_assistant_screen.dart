import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:math';

class EnhancedAIAssistantScreen extends StatefulWidget {
  @override
  _EnhancedAIAssistantScreenState createState() => _EnhancedAIAssistantScreenState();
}

class _EnhancedAIAssistantScreenState extends State<EnhancedAIAssistantScreen>
    with TickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  bool _isAnalyzing = false;
  SkinToneAnalysis? _analysis;
  
  late AnimationController _pulseController;
  late AnimationController _scanController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _scanController = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );
    
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        _isAnalyzing = true;
      });
      
      // Simulate AI analysis
      await _analyzeSkinTone();
    }
  }

  Future<void> _takePhoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        _isAnalyzing = true;
      });
      
      // Simulate AI analysis
      await _analyzeSkinTone();
    }
  }

  Future<void> _analyzeSkinTone() async {
    // Simulate AI processing time
    await Future.delayed(Duration(seconds: 3));
    
    // Simulate trained model analysis
    final analysis = _simulateSkinToneAnalysis();
    
    setState(() {
      _analysis = analysis;
      _isAnalyzing = false;
    });
  }

  SkinToneAnalysis _simulateSkinToneAnalysis() {
    // Simulate AI model results
    final skinTones = ['Fair', 'Light', 'Medium', 'Tan', 'Deep'];
    final undertones = ['Cool', 'Warm', 'Neutral'];
    final selectedTone = skinTones[Random().nextInt(skinTones.length)];
    final selectedUndertone = undertones[Random().nextInt(undertones.length)];
    
    return SkinToneAnalysis(
      skinTone: selectedTone,
      undertone: selectedUndertone,
      confidence: 0.85 + Random().nextDouble() * 0.15,
      recommendations: _generateRecommendations(selectedTone, selectedUndertone),
    );
  }

  List<MakeupRecommendation> _generateRecommendations(String skinTone, String undertone) {
    List<MakeupRecommendation> recommendations = [];
    
    // Foundation recommendations
    recommendations.add(MakeupRecommendation(
      category: 'Foundation',
      product: _getFoundationRecommendation(skinTone, undertone),
      color: _getFoundationColor(skinTone, undertone),
      brand: 'L\'Oréal Paris',
      price: '\$${25 + Random().nextInt(30)}',
      confidence: 0.9,
    ));
    
    // Blush recommendations
    recommendations.add(MakeupRecommendation(
      category: 'Blush',
      product: _getBlushRecommendation(skinTone, undertone),
      color: _getBlushColor(skinTone, undertone),
      brand: 'Maybelline',
      price: '\$${8 + Random().nextInt(12)}',
      confidence: 0.85,
    ));
    
    // Lipstick recommendations
    recommendations.add(MakeupRecommendation(
      category: 'Lipstick',
      product: _getLipstickRecommendation(skinTone, undertone),
      color: _getLipstickColor(skinTone, undertone),
      brand: 'Revlon',
      price: '\$${12 + Random().nextInt(18)}',
      confidence: 0.88,
    ));
    
    // Eyeshadow recommendations
    recommendations.add(MakeupRecommendation(
      category: 'Eyeshadow',
      product: _getEyeshadowRecommendation(skinTone, undertone),
      color: _getEyeshadowColor(skinTone, undertone),
      brand: 'Urban Decay',
      price: '\$${20 + Random().nextInt(25)}',
      confidence: 0.82,
    ));
    
    return recommendations;
  }

  String _getFoundationRecommendation(String skinTone, String undertone) {
    if (skinTone == 'Fair' && undertone == 'Cool') return 'True Match Foundation - Cool Ivory';
    if (skinTone == 'Fair' && undertone == 'Warm') return 'True Match Foundation - Warm Ivory';
    if (skinTone == 'Medium' && undertone == 'Cool') return 'True Match Foundation - Cool Beige';
    if (skinTone == 'Medium' && undertone == 'Warm') return 'True Match Foundation - Warm Beige';
    if (skinTone == 'Deep' && undertone == 'Cool') return 'True Match Foundation - Cool Deep';
    return 'True Match Foundation - Neutral';
  }

  String _getFoundationColor(String skinTone, String undertone) {
    if (skinTone == 'Fair') return undertone == 'Cool' ? 'Cool Ivory' : 'Warm Ivory';
    if (skinTone == 'Medium') return undertone == 'Cool' ? 'Cool Beige' : 'Warm Beige';
    if (skinTone == 'Deep') return undertone == 'Cool' ? 'Cool Deep' : 'Warm Deep';
    return 'Neutral Beige';
  }

  String _getBlushRecommendation(String skinTone, String undertone) {
    if (skinTone == 'Fair') return 'Fit Me Blush - Light Pink';
    if (skinTone == 'Medium') return 'Fit Me Blush - Rose';
    if (skinTone == 'Deep') return 'Fit Me Blush - Deep Rose';
    return 'Fit Me Blush - Natural';
  }

  String _getBlushColor(String skinTone, String undertone) {
    if (skinTone == 'Fair') return 'Light Pink';
    if (skinTone == 'Medium') return 'Rose';
    if (skinTone == 'Deep') return 'Deep Rose';
    return 'Natural';
  }

  String _getLipstickRecommendation(String skinTone, String undertone) {
    if (skinTone == 'Fair' && undertone == 'Cool') return 'Super Lustrous - Cool Pink';
    if (skinTone == 'Fair' && undertone == 'Warm') return 'Super Lustrous - Warm Pink';
    if (skinTone == 'Medium' && undertone == 'Cool') return 'Super Lustrous - Cool Rose';
    if (skinTone == 'Medium' && undertone == 'Warm') return 'Super Lustrous - Warm Rose';
    if (skinTone == 'Deep' && undertone == 'Cool') return 'Super Lustrous - Cool Berry';
    return 'Super Lustrous - Neutral';
  }

  String _getLipstickColor(String skinTone, String undertone) {
    if (skinTone == 'Fair') return undertone == 'Cool' ? 'Cool Pink' : 'Warm Pink';
    if (skinTone == 'Medium') return undertone == 'Cool' ? 'Cool Rose' : 'Warm Rose';
    if (skinTone == 'Deep') return undertone == 'Cool' ? 'Cool Berry' : 'Warm Berry';
    return 'Neutral';
  }

  String _getEyeshadowRecommendation(String skinTone, String undertone) {
    if (skinTone == 'Fair') return 'Naked Palette - Light Neutrals';
    if (skinTone == 'Medium') return 'Naked Palette - Medium Neutrals';
    if (skinTone == 'Deep') return 'Naked Palette - Deep Neutrals';
    return 'Naked Palette - Universal';
  }

  String _getEyeshadowColor(String skinTone, String undertone) {
    if (skinTone == 'Fair') return 'Light Neutrals';
    if (skinTone == 'Medium') return 'Medium Neutrals';
    if (skinTone == 'Deep') return 'Deep Neutrals';
    return 'Universal';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F4F0),
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
                  'AI Beauty Analysis',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C1810),
                  ),
                ),
                Text(
                  'Trained AI models for skin analysis',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8B7355),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // Image Analysis Section
            Container(
              width: double.infinity,
              height: 300,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: _selectedImage == null
                  ? _buildImagePlaceholder()
                  : _buildImageAnalysis(),
            ),
            
            SizedBox(height: 20),
            
            // Analysis Results
            if (_analysis != null) _buildAnalysisResults(),
            
            SizedBox(height: 20),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.camera_alt,
                    label: 'Take Photo',
                    onTap: _takePhoto,
                    color: Color(0xFFE91E63),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.photo_library,
                    label: 'Upload Photo',
                    onTap: _pickImage,
                    color: Color(0xFF9C27B0),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.face_retouching_natural,
          size: 80,
          color: Color(0xFFE91E63).withOpacity(0.3),
        ),
        SizedBox(height: 16),
        Text(
          'Upload or take a photo for AI analysis',
          style: TextStyle(
            fontSize: 16,
            color: Color(0xFF8B7355),
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Our trained AI will analyze your skin tone and suggest perfect makeup products',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF8B7355).withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildImageAnalysis() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.file(
            _selectedImage!,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        if (_isAnalyzing) _buildAnalysisOverlay(),
      ],
    );
  }

  Widget _buildAnalysisOverlay() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _scanAnimation,
              builder: (context, child) {
                return Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Color(0xFFE91E63),
                      width: 3,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: _scanAnimation.value * 100 - 2,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Color(0xFFE91E63),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            SizedBox(height: 20),
            Text(
              'AI Analyzing...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Detecting skin tone and undertones',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisResults() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics, color: Color(0xFFE91E63), size: 24),
              SizedBox(width: 12),
              Text(
                'AI Analysis Results',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C1810),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          
          // Skin Tone Analysis
          _buildAnalysisCard(
            'Skin Tone',
            _analysis!.skinTone,
            _analysis!.confidence,
            Icons.palette,
          ),
          _buildAnalysisCard(
            'Undertone',
            _analysis!.undertone,
            _analysis!.confidence,
            Icons.color_lens,
          ),
          
          SizedBox(height: 20),
          
          // Makeup Recommendations
          Text(
            'Recommended Products',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C1810),
            ),
          ),
          SizedBox(height: 12),
          
          ..._analysis!.recommendations.map((rec) => _buildRecommendationCard(rec)),
        ],
      ),
    );
  }

  Widget _buildAnalysisCard(String title, String value, double confidence, IconData icon) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFFF8F4F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(0xFFE91E63).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Color(0xFFE91E63), size: 20),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8B7355),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C1810),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Color(0xFFE91E63).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${(confidence * 100).toInt()}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE91E63),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(MakeupRecommendation rec) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFFE91E63).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: _getCategoryColor(rec.category).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getCategoryIcon(rec.category),
              color: _getCategoryColor(rec.category),
              size: 24,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.category,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8B7355),
                  ),
                ),
                Text(
                  rec.product,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C1810),
                  ),
                ),
                Text(
                  '${rec.brand} • ${rec.color}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8B7355),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rec.price,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE91E63),
                ),
              ),
              Text(
                '${(rec.confidence * 100).toInt()}% match',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8B7355),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.8)],
          ),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Foundation': return Color(0xFFE91E63);
      case 'Blush': return Color(0xFF9C27B0);
      case 'Lipstick': return Color(0xFFF44336);
      case 'Eyeshadow': return Color(0xFF673AB7);
      default: return Color(0xFFE91E63);
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Foundation': return Icons.face;
      case 'Blush': return Icons.brush;
      case 'Lipstick': return Icons.face;
      case 'Eyeshadow': return Icons.visibility;
      default: return Icons.auto_awesome;
    }
  }
}

class SkinToneAnalysis {
  final String skinTone;
  final String undertone;
  final double confidence;
  final List<MakeupRecommendation> recommendations;

  SkinToneAnalysis({
    required this.skinTone,
    required this.undertone,
    required this.confidence,
    required this.recommendations,
  });
}

class MakeupRecommendation {
  final String category;
  final String product;
  final String color;
  final String brand;
  final String price;
  final double confidence;

  MakeupRecommendation({
    required this.category,
    required this.product,
    required this.color,
    required this.brand,
    required this.price,
    required this.confidence,
  });
}
