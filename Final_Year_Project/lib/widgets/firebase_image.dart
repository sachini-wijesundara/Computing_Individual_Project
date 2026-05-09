import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FirebaseStorageImage extends StatelessWidget {
  static final Set<String> _missingStoragePaths = <String>{};
  static final Map<String, String> _downloadUrlCache = <String, String>{};
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
    if (storagePath.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
      );
    }

    if (storagePath.startsWith('http://') || storagePath.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: storagePath,
        width: width,
        height: height,
        fit: fit,
        errorWidget: (context, url, err) => SizedBox(
          width: width,
          height: height,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    String firebasePath;
    if (storagePath.startsWith('gs://')) {
      // Convert full Firebase Storage URI to object path:
      // gs://bucket-name/path/to/object -> path/to/object
      final withoutScheme = storagePath.replaceFirst('gs://', '');
      final slashIndex = withoutScheme.indexOf('/');
      firebasePath = slashIndex >= 0 ? withoutScheme.substring(slashIndex + 1) : '';
    } else if (storagePath.startsWith('assets/')) {
      // Common format in app docs that map to Firebase Storage.
      firebasePath = storagePath.replaceFirst('assets/', '');
    } else if (storagePath.startsWith('products/')) {
      // Direct Firestore storage path.
      firebasePath = storagePath;
    } else {
      // Unknown format: try local asset fallback.
      return Image.asset(
        storagePath,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => SizedBox(
          width: width,
          height: height,
          child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
        ),
      );
    }

    if (firebasePath.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
      );
    }

    // Auto-correct folder name mismatches between local seed data and actual Firebase Storage paths!
    firebasePath = firebasePath
      .replaceAll('eye products/eyeliner/', 'eye products/eye liner/')
      .replaceAll('eye products/eyebrow/', 'eye products/eye brow/')
      .replaceAll('eye products/eyeshadow/', 'eye products/eye shadows/')
      .replaceAll('eye products/eyeshadows/', 'eye products/eye shadows/');

    if (_downloadUrlCache.containsKey(firebasePath)) {
      return CachedNetworkImage(
        imageUrl: _downloadUrlCache[firebasePath]!,
        width: width,
        height: height,
        fit: fit,
        errorWidget: (context, url, err) => SizedBox(
          width: width,
          height: height,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }

    if (_missingStoragePaths.contains(firebasePath)) {
      return SizedBox(
        width: width,
        height: height,
        child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
      );
    }

    return FutureBuilder<String?>(
      future: _resolveDownloadUrl(firebasePath),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Firebase Storage Error [$firebasePath]: ${snapshot.error}');
        }
        if (!snapshot.hasData || snapshot.data == null) {
          if (snapshot.hasError) {
            return SizedBox(
              width: width,
              height: height,
              child: const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
            );
          }
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

  Future<String?> _resolveDownloadUrl(String firebasePath) async {
    final candidates = _pathCandidates(firebasePath);
    for (final candidate in candidates) {
      if (_downloadUrlCache.containsKey(candidate)) {
        _downloadUrlCache[firebasePath] = _downloadUrlCache[candidate]!;
        return _downloadUrlCache[candidate];
      }
      if (_missingStoragePaths.contains(candidate)) continue;
      try {
        final url = await FirebaseStorage.instance.ref(candidate).getDownloadURL();
        _downloadUrlCache[candidate] = url;
        _downloadUrlCache[firebasePath] = url;
        return url;
      } catch (e) {
        final errorText = e.toString();
        if (errorText.contains('object-not-found')) {
          _missingStoragePaths.add(candidate);
          continue;
        }
        rethrow;
      }
    }
    _missingStoragePaths.add(firebasePath);
    return null;
  }

  List<String> _pathCandidates(String basePath) {
    final out = <String>{basePath};

    // Extension fallbacks (common mismatch in product docs vs storage).
    if (basePath.endsWith('.webp')) {
      out.add(basePath.replaceFirst('.webp', '.png'));
      out.add(basePath.replaceFirst('.webp', '.jpg'));
      out.add(basePath.replaceFirst('.webp', '.jpeg'));
    } else if (basePath.endsWith('.png')) {
      out.add(basePath.replaceFirst('.png', '.webp'));
      out.add(basePath.replaceFirst('.png', '.jpg'));
      out.add(basePath.replaceFirst('.png', '.jpeg'));
    } else if (basePath.endsWith('.jpg')) {
      out.add(basePath.replaceFirst('.jpg', '.png'));
      out.add(basePath.replaceFirst('.jpg', '.webp'));
      out.add(basePath.replaceFirst('.jpg', '.jpeg'));
    } else if (basePath.endsWith('.jpeg')) {
      out.add(basePath.replaceFirst('.jpeg', '.jpg'));
      out.add(basePath.replaceFirst('.jpeg', '.png'));
      out.add(basePath.replaceFirst('.jpeg', '.webp'));
    }

    // Some paths may differ by spaces/underscores/hyphens.
    out.add(basePath.replaceAll('_', ' '));
    out.add(basePath.replaceAll('-', ' '));
    out.add(basePath.replaceAll(' ', '_'));
    out.add(basePath.replaceAll(' ', '-'));

    return out.toList();
  }
}
