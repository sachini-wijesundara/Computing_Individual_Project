import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../providers/makeup_provider.dart';

class LiveTryOnScreen extends StatefulWidget {
  @override
  _LiveTryOnScreenState createState() => _LiveTryOnScreenState();
}

class _LiveTryOnScreenState extends State<LiveTryOnScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  String _selectedMakeupType = 'lipstick';
  Color _selectedColor = Colors.red;
  double _intensity = 0.5;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    if (_cameras!.isNotEmpty) {
      _controller = CameraController(
        _cameras![0],
        ResolutionPreset.high,
        enableAudio: false,
      );
      
      await _controller!.initialize();
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Live Try-On',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.switch_camera, color: Colors.white),
            onPressed: _switchCamera,
          ),
        ],
      ),
      body: _isInitialized && _controller != null
          ? Stack(
              children: [
                // Camera Preview
                Positioned.fill(
                  child: CameraPreview(_controller!),
                ),
                
                // Makeup Controls Overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.8),
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        // Makeup Type Selector
                        _buildMakeupTypeSelector(),
                        
                        // Color Picker
                        _buildColorPicker(),
                        
                        // Intensity Slider
                        _buildIntensitySlider(),
                      ],
                    ),
                  ),
                ),
                
                // Live Try-On Instructions
                Positioned(
                  top: 100,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Position your face in the center and select makeup to try on',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
    );
  }

  Widget _buildMakeupTypeSelector() {
    final makeupTypes = [
      {'name': 'Lipstick', 'icon': Icons.face_retouching_natural, 'type': 'lipstick'},
      {'name': 'Foundation', 'icon': Icons.face, 'type': 'foundation'},
      {'name': 'Eyeshadow', 'icon': Icons.visibility, 'type': 'eyeshadow'},
      {'name': 'Mascara', 'icon': Icons.visibility, 'type': 'mascara'},
      {'name': 'Blush', 'icon': Icons.circle, 'type': 'blush'},
    ];

    return Container(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: makeupTypes.length,
        itemBuilder: (context, index) {
          final type = makeupTypes[index];
          final isSelected = _selectedMakeupType == type['type'];
          
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedMakeupType = type['type'] as String;
              });
            },
            child: Container(
              width: 80,
              margin: EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.pink : Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    type['icon'] as IconData,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(height: 4),
                  Text(
                    type['name'] as String,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildColorPicker() {
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.blue,
      Colors.green,
      Colors.yellow,
      Colors.orange,
      Colors.brown,
      Colors.grey,
      Colors.black,
    ];

    return Container(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: colors.length,
        itemBuilder: (context, index) {
          final color = colors[index];
          final isSelected = _selectedColor == color;
          
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedColor = color;
              });
            },
            child: Container(
              width: 30,
              height: 30,
              margin: EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIntensitySlider() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Text(
            'Intensity',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Slider(
            value: _intensity,
            min: 0.0,
            max: 1.0,
            activeColor: Colors.pink,
            inactiveColor: Colors.white.withOpacity(0.3),
            onChanged: (value) {
              setState(() {
                _intensity = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _switchCamera() async {
    if (_cameras!.length < 2) return;

    final currentIndex = _cameras!.indexOf(_controller!.description);
    final nextIndex = (currentIndex + 1) % _cameras!.length;
    
    _controller = CameraController(
      _cameras![nextIndex],
      ResolutionPreset.high,
      enableAudio: false,
    );
    
    await _controller!.initialize();
    setState(() {});
  }
}




