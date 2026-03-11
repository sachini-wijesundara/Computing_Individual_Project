// lib/utils/fix_shades.dart
//
// One-time utility to patch any existing products in Firestore
// that were seeded without a proper colorHex value.
// Called from the "FIX SHADES NOW" button in main.dart's MainScreen.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Updates every product document in Firestore that has a missing or
/// placeholder colorHex.  Safe to call multiple times — it only patches
/// documents that actually need it.
Future<void> fixAllProductShades() async {
  final db = FirebaseFirestore.instance;
  final snap = await db.collection('products').get();

  // Default shade per product id (matches seed_products.dart)
  const shades = <String, String>{
    'lip_satin':              '#C0392B',
    'lip_hyaluron_oil':       '#E87D7D',
    'lip_intense_matte':      '#8B1A1A',
    'lip_matte_resistance':   '#C94040',
    'lip_balm_in':            '#D46A6A',
    'lip_8hr_gloss':          '#F4A0A0',
    'lip_less_nus':           '#D4B4B4',
    'lip_reds_worth':         '#A00000',
    'lip_balm_gloss':         '#F7C5C5',
    'lip_liner':              '#7B1C1C',
    'mas_big_deal':           '#1C1C1C',
    'mas_extensionist':       '#1C1C1C',
    'mas_extensionist_washable': '#1C1C1C',
    'mas_original_washable':  '#1C1C1C',
    'mas_panorama_wp':        '#1C1C1C',
    'mas_superstar_wp':       '#1C1C1C',
    'mas_superstar':          '#1C1C1C',
    'mas_big_deal_buildable': '#1C1C1C',
    'el_grip_gel':            '#000000',
    'el_grip_felt':           '#000000',
    'el_matematic':           '#2C2C2C',
    'el_new_fail':            '#1A1A1A',
    'el_prolast_wp':          '#000000',
    'el_smoldering':          '#111111',
    'el_super_slim':          '#000000',
    'el_superstar':           '#000000',
    'es_24hr':                '#8B6F47',
    'es_le_shadow':           '#C9A96E',
    'es_metallic':            '#C0A060',
    'es_monos':               '#A0856A',
    'es_shimmer_liquid':      '#D4AF37',
    'eb_24hr_lamination':     '#6B4226',
    'eb_brow_gloss':          '#7A5C3C',
    'eb_definer':             '#5C3D1E',
    'eb_shape_fill':          '#6B4C2A',
    'eb_volumizing':          '#7A5530',
  };

  var fixed = 0;
  for (final doc in snap.docs) {
    final data = doc.data();
    final current = (data['colorHex'] as String?) ?? '';
    final correct = shades[doc.id];
    if (correct != null && current != correct) {
      try {
        await doc.reference.update({'colorHex': correct});
        fixed++;
      } catch (e) {
        debugPrint('fixShades: could not update ${doc.id} — $e');
      }
    }
  }
  debugPrint('✅ Fixed shades on $fixed product(s)');
}
