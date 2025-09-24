import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../providers/makeup_provider.dart';

class MakeupService {
  static const String _baseUrl = 'http://localhost:8000'; // Change to your server URL
  
  /// Apply virtual makeup to a face image
  static Future<File?> applyMakeup({
    required File faceImage,
    required File makeupStyle,
    required String makeupType,
  }) async {
    try {
      // Prepare the request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/apply_makeup'),
      );
      
      // Add files
      request.files.add(
        await http.MultipartFile.fromPath(
          'face_image',
          faceImage.path,
        ),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath(
          'makeup_style',
          makeupStyle.path,
        ),
      );
      
      // Add parameters
      request.fields['makeup_type'] = makeupType;
      
      // Send request
      var response = await request.send();
      
      if (response.statusCode == 200) {
        // Get the response bytes
        var responseBytes = await response.stream.toBytes();
        
        // Save the result image
        final directory = await getTemporaryDirectory();
        final resultPath = '${directory.path}/makeup_result_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final resultFile = File(resultPath);
        
        await resultFile.writeAsBytes(responseBytes);
        
        return resultFile;
      } else {
        print('Error applying makeup: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception in applyMakeup: $e');
      return null;
    }
  }
  
  /// Get available makeup styles
  static Future<List<MakeupStyle>> getMakeupStyles() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/makeup_styles'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['styles'] as List)
            .map((style) => MakeupStyle.fromJson(style))
            .toList();
      }
      
      return [];
    } catch (e) {
      print('Error fetching makeup styles: $e');
      return [];
    }
  }
  
  /// Preprocess image for model input
  static Future<File> preprocessImage(File imageFile) async {
    try {
      // Read the image
      final imageBytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(imageBytes);
      
      if (image == null) {
        throw Exception('Could not decode image');
      }
      
      // Resize to 512x512 (model input size)
      image = img.copyResize(image, width: 512, height: 512);
      
      // Save processed image
      final directory = await getTemporaryDirectory();
      final processedPath = '${directory.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final processedFile = File(processedPath);
      
      await processedFile.writeAsBytes(img.encodeJpg(image));
      
      return processedFile;
    } catch (e) {
      print('Error preprocessing image: $e');
      rethrow;
    }
  }
}
