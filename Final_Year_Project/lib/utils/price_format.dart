/// Single place to format storefront money as **Rs.** (Sri Lanka / South Asia style).
///
/// Use everywhere a product or order amount is shown so the app stays consistent.
/// Example: `formatRs(1234567)` → `"Rs. 1,234,567"`.
String formatRs(num amount, {int fractionDigits = 0}) {
  final negative = amount.isNegative;
  final v = amount.abs();
  final raw = v.toStringAsFixed(fractionDigits);
  final parts = raw.split('.');
  final intPart = parts[0];
  final grouped = intPart.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',
  );
  final dec = parts.length > 1 ? '.${parts[1]}' : '';
  final body = '$grouped$dec';
  if (negative) return '-Rs. $body';
  return 'Rs. $body';
}
