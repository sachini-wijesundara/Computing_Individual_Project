import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../firebase/firebase_config.dart';
import '../utils/beauty_profile_shades.dart';
import 'tflite_analysis_service.dart';

/// Persists merged beauty analysis on `users/{uid}.beautyProfile` for consistent
/// recommendations and live try-on shades.
class BeautyProfileService {
  BeautyProfileService._();
  static final BeautyProfileService instance = BeautyProfileService._();

  static FirebaseFirestore get _db => FirebaseConfig.firestore;

  static int _inferenceRank(String? mode) {
    switch (mode) {
      case 'gemini_vision':
        return 4;
      case 'tflite_ondevice':
        return 3;
      case 'server':
        return 2;
      case 'pixel_analysis':
        return 1;
      default:
        return 0;
    }
  }

  static Map<String, dynamic> _merge(
    Map<String, dynamic>? existing,
    Map<String, dynamic> incoming,
  ) {
    if (existing == null || existing.isEmpty) {
      return Map<String, dynamic>.from(incoming);
    }
    final out = Map<String, dynamic>.from(existing);

    final newSkin = _inferenceRank(incoming['skinInference'] as String?);
    final oldSkin = _inferenceRank(out['skinInference'] as String?);
    if (newSkin >= oldSkin) {
      out['skinTone'] = incoming['skinTone'];
      out['undertone'] = incoming['undertone'];
      out['skinInference'] = incoming['skinInference'];
      out['skinConfidence'] = incoming['skinConfidence'];
      out['makeupRecommendations'] = incoming['makeupRecommendations'];
    }

    final newHair = _inferenceRank(incoming['hairInference'] as String?);
    final oldHair = _inferenceRank(out['hairInference'] as String?);
    if (newHair >= oldHair) {
      out['hairType'] = incoming['hairType'];
      out['hairColor'] = incoming['hairColor'];
      out['hairInference'] = incoming['hairInference'];
      out['hairConfidence'] = incoming['hairConfidence'];
      out['recommendedStyles'] = incoming['recommendedStyles'];
      out['hairProductRecommendations'] = incoming['hairProductRecommendations'];
    }

    return out;
  }

  /// Call after a successful [analyzeSkin] + [analyzeHair] pass. No-op if logged out.
  /// Returns the merged profile map (in-memory) so callers can refresh Gemini context.
  Future<Map<String, dynamic>?> saveAfterAnalysis({
    required SkinToneResult skin,
    required HairResult hair,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final incoming = <String, dynamic>{
      'skinTone': skin.skinTone,
      'undertone': skin.undertone,
      'skinInference': skin.inferenceMode,
      'skinConfidence': skin.confidence,
      'makeupRecommendations': skin.makeupRecommendations,
      'hairType': hair.hairType,
      'hairColor': hair.hairColor,
      'hairInference': hair.inferenceMode,
      'hairConfidence': hair.confidence,
      'recommendedStyles': hair.recommendedStyles,
      'hairProductRecommendations': hair.productRecommendations,
    };

    final ref = _db.collection('users').doc(uid);
    final snap = await ref.get();
    final data = snap.data();
    final existing = data?['beautyProfile'] is Map
        ? Map<String, dynamic>.from(data!['beautyProfile'] as Map)
        : null;

    final merged = _merge(existing, incoming);
    final tone = merged['skinTone'] as String? ?? skin.skinTone;
    final under = merged['undertone'] as String? ?? skin.undertone;
    final lip = BeautyProfileShades.lipPrimaryForProfile(tone, under);
    final lipAlt = BeautyProfileShades.lipAltForProfile(tone, under);
    merged['lipTryOnHex'] = BeautyProfileShades.hexRgb(lip);
    merged['lipTryOnHexAlt'] = BeautyProfileShades.hexRgb(lipAlt);

    final toWrite = Map<String, dynamic>.from(merged);
    toWrite['updatedAt'] = FieldValue.serverTimestamp();
    toWrite['lastScanAt'] = FieldValue.serverTimestamp();

    await ref.set(
      {
        'beautyProfile': toWrite,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return merged;
  }

  /// Live try-on colour from stored profile map (after merge).
  static Color? lipColorFromProfileMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final hex = m['lipTryOnHex'] as String?;
    if (hex == null || hex.length < 7) return null;
    try {
      final h = hex.replaceFirst('#', '');
      return Color(int.parse(h, radix: 16) + 0xFF000000);
    } catch (_) {
      return null;
    }
  }
}
