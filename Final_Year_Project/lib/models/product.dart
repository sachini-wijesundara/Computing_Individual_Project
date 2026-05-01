import 'package:cloud_firestore/cloud_firestore.dart';

/// Shade selected when adding a product to the local [CartProvider] cart.
class ProductShade {
  final String name;
  const ProductShade({required this.name});
}

/// Represents a single product in the Firestore `products` collection.
class Product {
  final String id;
  final String name;
  final String brand;
  final String category;      // 'Lip Sticks' | 'Makeup' | 'Face' | 'Hair Colors'
  final String subCategory;   // 'Foundation' | 'Powder' | 'Blush' | 'Concealer' | 'Highlighter' | 'Contour & Bronzer'
  final double price;
  final double rating;
  final int reviews;
  final String imageUrl;   // https:// URL from Firebase Storage (optional)
  final String imagePath;  // assets/... local fallback (optional)
  final String colorHex;   // e.g. '#C0392B' – for AR overlay and swatches
  final String description;
  final List<Map<String, String>> shades; // Added: List of shade maps
  final Map<String, dynamic> compareData; // Added: For comparison features

  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.category,
    this.subCategory = '',
    required this.price,
    required this.rating,
    required this.reviews,
    this.imageUrl = '',
    this.imagePath = '',
    this.colorHex = '#C0392B',
    this.description = '',
    this.shades = const [],
    this.compareData = const {},
  });

  // ── Firestore ────────────────────────────────────────────────────────────────

  factory Product.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Product(
      id:          doc.id,
      name:        (d['name']        as String?)  ?? 'Unknown',
      brand:       (d['brand']       as String?)  ?? '',
      category:    (d['category']    as String?)  ?? 'Makeup',
      subCategory: (d['subCategory'] as String?)  ?? '',
      price:       _toDouble(d['price']),
      rating:      _toDouble(d['rating'],   fallback: 4.0),
      reviews:     (d['reviews']     as int?)     ?? 0,
      imageUrl:    (d['imageUrl']    as String?)  ?? '',
      imagePath:   (d['imagePath']   as String?)  ?? '',
      colorHex:    (d['colorHex']    as String?)  ?? '#C0392B',
      description: (d['description'] as String?)  ?? '',
      shades:      _toShades(d['shades']),
      compareData: (d['compare']     as Map<String, dynamic>?) ?? {},
    );
  }

  static List<Map<String, String>> _toShades(dynamic v) {
    if (v == null || v is! List) return [];
    return v.map((item) {
      if (item is Map) {
        return item.map((k, val) => MapEntry(k.toString(), val.toString()));
      }
      return <String, String>{};
    }).toList();
  }

  Map<String, dynamic> toMap() => {
    'name':        name,
    'brand':       brand,
    'category':    category,
    'subCategory': subCategory,
    'price':       price,
    'rating':      rating,
    'reviews':     reviews,
    'imageUrl':    imageUrl,
    'imagePath':   imagePath,
    'colorHex':    colorHex,
    'description': description,
    'shades':      shades,
    'compare':     compareData,
  };

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static double _toDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  @override
  String toString() => 'Product($id, $name, $category/$subCategory, Rs.$price)';
}
