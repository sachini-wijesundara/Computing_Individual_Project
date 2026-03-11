import 'package:flutter/material.dart';
import 'virtual_tryon_popup.dart';

class ProductShowcaseScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Loreal VogueVista'),
        backgroundColor: Color(0xFFE91E63),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F8F8),
              Color(0xFFF0F0F0),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE91E63), Color(0xFFFF4081)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    Text(
                      'L\'ORÉAL PARIS',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'VIRTUAL TRY-ON',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Try any makeup, before buying',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 24),
              
              // Featured Products
              Text(
                'Featured Products',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 16),
              
              // Lipstick Products
              _buildProductSection(
                context,
                'Lipstick Collection',
                [
                  Product(
                    name: 'Colour Riche Satin Lipstick',
                    price: '\$10.99',
                    color: Colors.red,
                    image: 'assets/lipstick_red.png',
                    category: 'Lip Sticks',
                    shades: [
                      {'name': 'Rouge', 'hex': '#FF0000'},
                      {'name': 'Muted Red', 'hex': '#B22222'},
                    ],
                  ),
                  Product(
                    name: 'Infallible Pro Matte Lipstick',
                    price: '\$12.99',
                    color: Colors.pink,
                    image: 'assets/lipstick_pink.png',
                    category: 'Lip Sticks',
                    shades: [
                      {'name': 'Candy Pink', 'hex': '#FF69B4'},
                      {'name': 'Fuschia', 'hex': '#FF00FF'},
                    ],
                  ),
                  Product(
                    name: 'Colour Riche Nude Lipstick',
                    price: '\$10.99',
                    color: Color(0xFFD4AF8C),
                    image: 'assets/lipstick_nude.png',
                    category: 'Lip Sticks',
                    shades: [
                      {'name': 'Nude', 'hex': '#D4AF8C'},
                    ],
                  ),
                ],
              ),
              
              SizedBox(height: 24),
              
              // Foundation Products
              _buildProductSection(
                context,
                'Foundation Collection',
                [
                  Product(
                    name: 'True Match Foundation',
                    price: '\$14.99',
                    color: Color(0xFFF4C2A1),
                    image: 'assets/foundation_light.png',
                    category: 'Makeup',
                  ),
                  Product(
                    name: 'Infallible Pro Glow',
                    price: '\$16.99',
                    color: Color(0xFFE6B8A2),
                    image: 'assets/foundation_medium.png',
                    category: 'Makeup',
                  ),
                  Product(
                    name: 'True Match Lumi',
                    price: '\$15.99',
                    color: Color(0xFFD4A574),
                    image: 'assets/foundation_dark.png',
                    category: 'Makeup',
                  ),
                ],
              ),
              
              SizedBox(height: 24),
              
              // Eye Makeup Products
              _buildProductSection(
                context,
                'Eye Makeup Collection',
                [
                  Product(
                    name: 'Telescopic Mascara',
                    price: '\$9.99',
                    color: Colors.black,
                    image: 'assets/mascara_black.png',
                    category: 'Mascara',
                    shades: [
                      {'name': 'Blackest Black', 'hex': '#000000'},
                    ],
                  ),
                  Product(
                    name: 'Infallible Eyeshadow',
                    price: '\$8.99',
                    color: Colors.purple,
                    image: 'assets/eyshadow_purple.png',
                    category: 'Makeup',
                    shades: [
                      {'name': 'Majestic Purple', 'hex': '#800080'},
                      {'name': 'Lavender', 'hex': '#E6E6FA'},
                    ],
                  ),
                  Product(
                    name: 'Voluminous Eyeliner',
                    price: '\$7.99',
                    color: Colors.brown,
                    image: 'assets/eyeliner_brown.png',
                    category: 'Makeup',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductSection(BuildContext context, String title, List<Product> products) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: 12),
        Container(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            itemBuilder: (context, index) {
              return _buildProductCard(context, products[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(BuildContext context, Product product) {
    return Container(
      width: 160,
      margin: EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Product Image
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(15),
                  topRight: Radius.circular(15),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFF5E6E8),
                    Color(0xFFE8D5D8),
                  ],
                ),
              ),
              child: Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: product.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: product.color.withOpacity(0.3),
                        blurRadius: 15,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.face_retouching_natural,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ),
          ),
          
          // Product Info
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    product.price,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE91E63),
                    ),
                  ),
                  SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _showVirtualTryOn(context, product),
                    child: Container(
                      width: double.infinity,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(0xFFE91E63),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          'Try On',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVirtualTryOn(BuildContext context, Product product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const VirtualTryOnLandingPage(),
      ),
    );
  }
}

class Product {
  final String name;
  final String price;
  final Color color;
  final String image;
  final String category;
  final List<Map<String, String>> shades; // Added

  Product({
    required this.name,
    required this.price,
    required this.color,
    required this.image,
    required this.category,
    this.shades = const [], // Added
  });
}



