import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FirebaseStorageImage extends StatelessWidget {
  final String storagePath;
  final double? width;
  final double? height;
  final BoxFit fit;

  const FirebaseStorageImage({
    Key? key,
    required this.storagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (storagePath.isEmpty || !storagePath.startsWith('assets/')) {
        // Fallback for non-storage paths or static assets
        return Image.asset(storagePath, width: width, height: height, fit: fit);
    }
    
    // Strip the 'assets/' prefix since Firebase Storage root likely starts with 'products/'
    String firebasePath = storagePath.replaceFirst('assets/', '');
    
    // Auto-correct folder name mismatches between local seed data and actual Firebase Storage paths!
    firebasePath = firebasePath
      .replaceAll('eye products/eyeliner/', 'eye products/eye liner/')
      .replaceAll('eye products/eyebrow/', 'eye products/eye brow/')
      .replaceAll('eye products/eyeshadow/', 'eye products/eye shadows/')
      .replaceAll('eye products/eyeshadows/', 'eye products/eye shadows/');

    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(firebasePath).getDownloadURL(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Firebase Storage Error [$firebasePath]: ${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return SizedBox(
            width: width,
            height: height,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return CachedNetworkImage(
          imageUrl: snapshot.data!,
          width: width,
          height: height,
          fit: fit,
          errorWidget: (context, url, err) => SizedBox(
            width: width, height: height,
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      },
    );
  }
}
