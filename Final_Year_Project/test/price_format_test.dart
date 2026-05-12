import 'package:flutter_test/flutter_test.dart';

import 'package:la_vogue_vista/utils/price_format.dart';

void main() {
  group('formatRs', () {
    test('zero and small integers', () {
      expect(formatRs(0), 'Rs. 0');
      expect(formatRs(42), 'Rs. 42');
    });

    test('thousands grouping', () {
      expect(formatRs(1234567), 'Rs. 1,234,567');
    });

    test('negative amounts', () {
      expect(formatRs(-99), '-Rs. 99');
      expect(formatRs(-1234), '-Rs. 1,234');
    });

    test('fraction digits', () {
      expect(formatRs(12.3, fractionDigits: 1), 'Rs. 12.3');
      expect(formatRs(1234.56, fractionDigits: 2), 'Rs. 1,234.56');
    });
  });
}
