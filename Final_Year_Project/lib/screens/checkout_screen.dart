import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/emailjs_config.dart';
import '../providers/cart_provider.dart';
import '../services/emailjs_service.dart';
import '../utils/cart_pricing.dart';
import '../utils/price_format.dart';
import '../widgets/firebase_image.dart';
import 'order_detail_screen.dart';

const Color _kMaroon = Color(0xFF7B1B11);
const Color _kSuccess = Color(0xFF1F8A43);
const Color _kTitle = Color(0xFF1A1A1A);
const Color _kMuted = Color(0xFF888888);
const Color _kFieldFill = Color(0xFFF5F5F5);

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _cardNumberCtrl = TextEditingController();
  final _cardExpiryCtrl = TextEditingController();
  final _cardCvcCtrl = TextEditingController();

  int _paymentMethod = 0; // 0 COD, 1 card demo
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final em = u.email;
    if (em != null && em.trim().isNotEmpty) {
      _emailCtrl.text = em.trim();
    }
    final dn = u.displayName?.trim();
    if (dn != null && dn.isNotEmpty) {
      _nameCtrl.text = dn;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _cardNumberCtrl.dispose();
    _cardExpiryCtrl.dispose();
    _cardCvcCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: _kFieldFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kMaroon, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  bool _isValidDemoCard() {
    final number = _cardNumberCtrl.text.replaceAll(RegExp(r'\D'), '');
    final expiry = _cardExpiryCtrl.text.trim();
    final cvc = _cardCvcCtrl.text.replaceAll(RegExp(r'\D'), '');
    return number.length >= 15 &&
        number.length <= 19 &&
        RegExp(r'^\d{2}/\d{2}$').hasMatch(expiry) &&
        RegExp(r'^\d{3,4}$').hasMatch(cvc);
  }

  Map<String, String> _buildEmailParams(
    List<CartItem> items,
    double total,
    String paymentLabel,
  ) {
    final now = DateTime.now();
    final orderId = 'LVV-${now.millisecondsSinceEpoch}';
    final orderDate =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final itemsSummary = items.map((item) {
      final shade = item.selectedShade?.name;
      final line = item.product.price * item.quantity;
      final shadeText = shade == null ? '' : ' ($shade)';
      return '- ${item.product.name}$shadeText x${item.quantity} - ${formatRs(line)}';
    }).join('\n');

    return {
      'customer_name': _nameCtrl.text.trim(),
      'customer_email': _emailCtrl.text.trim(),
      'customer_phone': _phoneCtrl.text.trim(),
      'order_id': orderId,
      'order_date': orderDate,
      'payment_method': paymentLabel,
      'order_total': formatRs(total, fractionDigits: 2),
      'delivery_address': '${_addressCtrl.text.trim()}\n${_cityCtrl.text.trim()}',
      // Keep both keys so EmailJS template can use either {{order_items_html}}
      // or {{order_items_text}} without rendering raw HTML tags.
      'order_items_html': itemsSummary.replaceAll('\n', '<br>'),
      'order_items_text': itemsSummary,
    };
  }

  Future<DocumentReference<Map<String, dynamic>>> _saveOrderToFirestore({
    required String userId,
    required List<CartItem> items,
    required double subtotal,
    required double discount,
    required double total,
    required String paymentMethod,
  }) async {
    final now = DateTime.now();
    final orderId = 'LVV-${now.millisecondsSinceEpoch}';
    final emailTrim = _emailCtrl.text.trim();

    final payload = <String, dynamic>{
      'orderId': orderId,
      'userId': userId,
      'customerName': _nameCtrl.text.trim(),
      'customerEmail': emailTrim,
      'customerEmailLower': emailTrim.toLowerCase(),
      'customerPhone': _phoneCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'paymentMethod': paymentMethod,
      'subtotal': subtotal,
      'discount': discount,
      'total': total,
      'status': 'placed',
      'createdAt': FieldValue.serverTimestamp(),
      'items': items
          .map((item) => {
                'productId': item.product.id,
                'name': item.product.name,
                'category': item.product.category,
                'subCategory': item.product.subCategory,
                'price': item.product.price,
                'quantity': item.quantity,
                'shade': item.selectedShade?.name,
              })
          .toList(),
    };

    return FirebaseFirestore.instance.collection('orders').add(payload);
  }

  /// Remember delivery/contact email so "My orders" works when it differs from Firebase Auth email.
  Future<void> _rememberCheckoutEmailForAccount(String uid, String checkoutEmail) async {
    final lower = checkoutEmail.trim().toLowerCase();
    if (lower.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
            {'checkoutEmails': FieldValue.arrayUnion([lower])},
            SetOptions(merge: true),
          );
    } catch (_) {
      // Non-fatal; order still placed.
    }
  }

  Future<void> _placeOrder(CartProvider cart) async {
    if (!_formKey.currentState!.validate()) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to place an order.')),
      );
      return;
    }
    if (_paymentMethod == 1 && !_isValidDemoCard()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid card number, expiry and CVC.')),
      );
      return;
    }

    final discount = cartPromotionDiscount(cart.subtotal);
    final total = cart.subtotal - discount;
    final paymentLabel = _paymentMethod == 0 ? 'Cash on delivery' : 'Card (demo)';
    final snapshot = List<CartItem>.from(cart.items);
    final customerEmail = _emailCtrl.text.trim();
    final customerPhone = _phoneCtrl.text.trim();

    setState(() => _busy = true);
    var emailSent = false;
    String? emailError;
    DocumentReference<Map<String, dynamic>>? savedOrderRef;

    if (EmailJsConfig.isConfigured) {
      try {
        await EmailJsService.sendOrderConfirmation(
          templateParams: _buildEmailParams(snapshot, total, paymentLabel),
        );
        emailSent = true;
      } catch (e) {
        emailError = e.toString();
      }
    } else {
      emailError = 'Email service is not configured.';
    }

    try {
      savedOrderRef = await _saveOrderToFirestore(
        userId: uid,
        items: snapshot,
        subtotal: cart.subtotal,
        discount: discount,
        total: total,
        paymentMethod: paymentLabel,
      );
      await _rememberCheckoutEmailForAccount(uid, customerEmail);
    } catch (e) {
      emailError = '${emailError ?? ''}\nFailed to persist order to database: $e'.trim();
    }

    cart.clearCart();

    if (!mounted) return;
    setState(() => _busy = false);
    final orderRef = savedOrderRef;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _kSuccess.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: _kSuccess,
                  size: 38,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Order Confirmed',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _kSuccess,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Total: ${formatRs(total, fractionDigits: 2)}\nPayment: $paymentLabel',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: Colors.black87,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: emailSent ? const Color(0xFFEAF8EF) : const Color(0xFFFFF1F1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: emailSent ? const Color(0xFFB8E3C4) : const Color(0xFFFFD1D1),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      emailSent ? Icons.mark_email_read_rounded : Icons.error_outline_rounded,
                      color: emailSent ? const Color(0xFF1F8A43) : const Color(0xFFB3261E),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        emailSent
                            ? 'Confirmation email sent to $customerEmail'
                            : 'Order placed, but email was not sent.\n${emailError ?? ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: emailSent ? const Color(0xFF1F6A36) : const Color(0xFF8B1D18),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'We will contact you at $customerPhone to confirm delivery.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: _kMuted, height: 1.4),
              ),
              const SizedBox(height: 18),
              if (orderRef != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OrderDetailScreen(orderDocId: orderRef.id),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kMaroon,
                      side: const BorderSide(color: _kMaroon),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Track order',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _kSuccess,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    if (cart.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _kTitle,
          title: const Text('Checkout'),
        ),
        body: const Center(child: Text('Your cart is empty')),
      );
    }

    final discount = cartPromotionDiscount(cart.subtotal);
    final total = cart.subtotal - discount;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kTitle,
        title: const Text('Checkout'),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  const Text('Order summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  ...cart.items.map((item) => _SummaryLine(item: item)),
                  const SizedBox(height: 8),
                  _totalsCard(cart.items.length, cart.subtotal, discount, total),
                  const SizedBox(height: 24),
                  const Text('Delivery details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: _dec('Full name'),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: _dec('Phone', hint: '07…'),
                    validator: (v) => (v == null || v.trim().length < 9) ? 'Enter valid phone' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _dec('Email', hint: 'for confirmation'),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Enter valid email' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    maxLines: 2,
                    decoration: _dec('Address'),
                    validator: (v) => (v == null || v.trim().length < 5) ? 'Enter address' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cityCtrl,
                    decoration: _dec('City'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter city' : null,
                  ),
                  const SizedBox(height: 24),
                  const Text('Payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _PayChip(
                          label: 'Cash on delivery',
                          icon: Icons.payments_outlined,
                          selected: _paymentMethod == 0,
                          onTap: () => setState(() => _paymentMethod = 0),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _PayChip(
                          label: 'Card',
                          icon: Icons.credit_card_rounded,
                          selected: _paymentMethod == 1,
                          onTap: () => setState(() => _paymentMethod = 1),
                        ),
                      ),
                    ],
                  ),
                  if (_paymentMethod == 1) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cardNumberCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _dec('Card number', hint: '4242 4242 4242 4242'),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(19),
                        _CardNumberFormatter(),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cardExpiryCtrl,
                            keyboardType: TextInputType.number,
                            decoration: _dec('Expiry', hint: 'MM/YY'),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                              _CardExpiryFormatter(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _cardCvcCtrl,
                            keyboardType: TextInputType.number,
                            decoration: _dec('CVC'),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
            _BottomBar(
              total: total,
              isBusy: _busy,
              onPlaceOrder: () => _placeOrder(cart),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalsCard(int lineCount, double subtotal, double discount, double total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kFieldFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _totRow('Subtotal ($lineCount)', formatRs(subtotal, fractionDigits: 2)),
          const SizedBox(height: 8),
          _totRow('Discount', formatRs(-discount, fractionDigits: 2)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
          _totRow('Total', formatRs(total, fractionDigits: 2), emphasize: true),
        ],
      ),
    );
  }

  Widget _totRow(String label, String value, {bool emphasize = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: emphasize ? 17 : 15,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            color: emphasize ? _kTitle : _kMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 18 : 15,
            fontWeight: FontWeight.w800,
            color: emphasize ? _kMaroon : _kTitle,
          ),
        ),
      ],
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      final isBoundary = (i + 1) % 4 == 0 && i + 1 != digits.length;
      if (isBoundary) buffer.write(' ');
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _CardExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    var mm = digits.length >= 2 ? digits.substring(0, 2) : digits;
    if (mm.length == 2) {
      final month = int.tryParse(mm) ?? 0;
      if (month <= 0) mm = '01';
      if (month > 12) mm = '12';
    }
    final yy = digits.length > 2 ? digits.substring(2) : '';
    final formatted = yy.isEmpty ? mm : '$mm/$yy';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final CartItem item;
  const _SummaryLine({required this.item});

  @override
  Widget build(BuildContext context) {
    final line = item.product.price * item.quantity;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: FirebaseStorageImage(storagePath: item.product.imagePath, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${item.product.name} x${item.quantity}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            formatRs(line),
            style: const TextStyle(fontWeight: FontWeight.w800, color: _kMaroon),
          ),
        ],
      ),
    );
  }
}

class _PayChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PayChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _kMaroon.withValues(alpha: 0.12) : _kFieldFill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _kMaroon : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? _kMaroon : _kMuted, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? _kMaroon : _kTitle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final double total;
  final bool isBusy;
  final VoidCallback onPlaceOrder;

  const _BottomBar({
    required this.total,
    required this.isBusy,
    required this.onPlaceOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      shadowColor: Colors.black26,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kMuted.withValues(alpha: 0.9))),
                    const SizedBox(height: 2),
                    Text(
                      formatRs(total, fractionDigits: 2),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _kMaroon),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: isBusy ? null : onPlaceOrder,
                style: FilledButton.styleFrom(
                  backgroundColor: _kMaroon,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _kMaroon.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: isBusy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Place order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
