double cartPromotionDiscount(double subtotal) {
  if (subtotal <= 0) return 0;
  final discount = (subtotal / 6 * 100).round() / 100;
  return discount.clamp(0.0, subtotal);
}
