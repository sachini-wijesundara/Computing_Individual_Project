import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../firebase/firebase_config.dart';

class FirebaseStorageService {
  static final FirebaseStorage _storage = FirebaseConfig.storage;
  static final FirebaseAuth _auth = FirebaseConfig.auth;

  // Upload user profile image
  static Future<String> uploadProfileImage(File imageFile) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final ref = _storage
          .ref()
          .child('users')
          .child(user.uid)
          .child('profile')
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print('Upload profile image error: $e');
      rethrow;
    }
  }

  // Upload try-on result image
  static Future<String> uploadTryOnResult(File imageFile, {
    required String productId,
    required String productType,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final ref = _storage
          .ref()
          .child('users')
          .child(user.uid)
          .child('try_on_results')
          .child(productType)
          .child('${productId}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print('Upload try-on result error: $e');
      rethrow;
    }
  }

  // Upload makeup style image
  static Future<String> uploadMakeupStyle(File imageFile, {
    required String styleName,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final ref = _storage
          .ref()
          .child('users')
          .child(user.uid)
          .child('makeup_styles')
          .child('${styleName}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print('Upload makeup style error: $e');
      rethrow;
    }
  }

  // Upload model training data
  static Future<String> uploadTrainingData(File dataFile, {
    required String dataType,
  }) async {
    try {
      final ref = _storage
          .ref()
          .child('training_data')
          .child(dataType)
          .child('${DateTime.now().millisecondsSinceEpoch}.${dataFile.path.split('.').last}');

      final uploadTask = ref.putFile(dataFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print('Upload training data error: $e');
      rethrow;
    }
  }

  // Download model files
  static Future<String> downloadModelFile(String modelPath) async {
    try {
      final ref = _storage.ref().child('models').child(modelPath);
      final downloadUrl = await ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('Download model file error: $e');
      rethrow;
    }
  }

  // Get user's uploaded images
  static Future<List<String>> getUserImages(String folder) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final ref = _storage
          .ref()
          .child('users')
          .child(user.uid)
          .child(folder);

      final listResult = await ref.listAll();
      final downloadUrls = <String>[];

      for (final item in listResult.items) {
        final downloadUrl = await item.getDownloadURL();
        downloadUrls.add(downloadUrl);
      }

      return downloadUrls;
    } catch (e) {
      print('Get user images error: $e');
      return [];
    }
  }

  // Delete image
  static Future<void> deleteImage(String imageUrl) async {
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      print('Delete image error: $e');
      rethrow;
    }
  }

  // Get storage usage
  static Future<int> getStorageUsage() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 0;

      final ref = _storage.ref().child('users').child(user.uid);
      final listResult = await ref.listAll();
      
      int totalSize = 0;
      for (final item in listResult.items) {
        final metadata = await item.getMetadata();
        totalSize += metadata.size ?? 0;
      }

      return totalSize;
    } catch (e) {
      print('Get storage usage error: $e');
      return 0;
    }
  }

  // Clean up old files
  static Future<void> cleanupOldFiles(String folder, {int daysOld = 30}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final ref = _storage
          .ref()
          .child('users')
          .child(user.uid)
          .child(folder);

      final listResult = await ref.listAll();
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));

      for (final item in listResult.items) {
        final metadata = await item.getMetadata();
        final createdDate = metadata.timeCreated;
        
        if (createdDate != null && createdDate.isBefore(cutoffDate)) {
          await item.delete();
        }
      }
    } catch (e) {
      print('Cleanup old files error: $e');
    }
  }
}




