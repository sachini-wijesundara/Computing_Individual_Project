import 'package:flutter/material.dart';

class LiveTryOnOverlay extends StatelessWidget {
  final String productName;
  final String productCategory;
  final String productHexValue;
  final VoidCallback onAddToCart; 

  const LiveTryOnOverlay({
    Key? key,
    required this.productName,
    required this.productCategory,
    required this.productHexValue,
    required this.onAddToCart,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
