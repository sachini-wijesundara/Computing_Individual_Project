import 'package:flutter/material.dart';
import '../models/product.dart';

class CartItem {
  final Product product;
  final ProductShade? selectedShade; // Nullable because some non-lip products might not have shades
  int quantity;

  CartItem({
    required this.product,
    this.selectedShade,
    this.quantity = 1,
  });

  double get totalPrice => product.price * quantity;

  // Used for identifying if an item is already in the cart with the same shade
  String get id => '${product.id}_${selectedShade?.name ?? 'no_shade'}';
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  void addToCart(Product product, {ProductShade? shade, int quantity = 1}) {
    final newItemId = '${product.id}_${shade?.name ?? 'no_shade'}';
    final existingIndex = _items.indexWhere((item) => item.id == newItemId);

    if (existingIndex >= 0) {
      _items[existingIndex].quantity += quantity;
    } else {
      _items.add(CartItem(
        product: product,
        selectedShade: shade,
        quantity: quantity,
      ));
    }
    notifyListeners();
  }

  CartItem? _lastRemovedItem;
  int? _lastRemovedIndex;

  void removeFromCart(CartItem cartItem) {
    final index = _items.indexWhere((item) => item.id == cartItem.id);
    if (index >= 0) {
      _lastRemovedItem = _items[index];
      _lastRemovedIndex = index;
      _items.removeAt(index);
      notifyListeners();
    }
  }

  void undoDelete() {
    if (_lastRemovedItem != null && _lastRemovedIndex != null) {
      _items.insert(_lastRemovedIndex!, _lastRemovedItem!);
      _lastRemovedItem = null;
      _lastRemovedIndex = null;
      notifyListeners();
    }
  }

  void updateQuantity(CartItem cartItem, int newQuantity) {
    if (newQuantity <= 0) {
      removeFromCart(cartItem);
    } else {
      final index = _items.indexWhere((item) => item.id == cartItem.id);
      if (index >= 0) {
        _items[index].quantity = newQuantity;
        notifyListeners();
      }
    }
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}
