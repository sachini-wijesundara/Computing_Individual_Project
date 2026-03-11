import 'package:flutter/material.dart';

class FloatingProductBanner extends StatelessWidget {
  const FloatingProductBanner({
    super.key,
    required this.productName,
    required this.shadeName,
    required this.image,
    required this.onAddToCart,
    required this.productColorHex,
  });

  final String productName;
  final String shadeName;
  final String image;
  final String productColorHex;
  final VoidCallback onAddToCart;

  Color _hexToColor(String hex) {
    if (hex.isEmpty) return Colors.black;
    var s = hex.replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    return Color(int.parse(s, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Product Image Container
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: image.isNotEmpty
                  ? Image.asset(image, fit: BoxFit.contain)
                  : const Icon(Icons.image, color: Colors.black26),
            ),
          ),
          const SizedBox(width: 12),
          
          // Texts
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  productName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _hexToColor(productColorHex),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        shadeName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 8),

          // Favorite
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.favorite_border, color: Colors.black87, size: 24),
            onPressed: () {}, // Favorite logic 
          ),
          
          const SizedBox(width: 8),

          // Add to Cart Button
          ElevatedButton(
            onPressed: onAddToCart,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              minimumSize: const Size(0, 40),
            ),
            child: const Text(
              "ADD TO CART",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
