import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared helpers for customer order list + tracking UI (mirrors admin status logic).

String displayOrderStatus(Map<String, dynamic> d) {
  final raw = (d['status'] ?? d['orderStatus'] ?? '').toString().trim();
  if (raw.isEmpty) return 'Pending';
  final lower = raw.toLowerCase();
  if (lower.contains('cancel')) return 'Cancelled';
  if (lower.contains('deliver')) return 'Delivered';
  if (lower.contains('ship')) return 'Shipped';
  if (lower.contains('process')) return 'Processing';
  if (lower.contains('place') || lower.contains('pend')) return 'Pending';
  return raw[0].toUpperCase() + raw.substring(1);
}

int orderCreatedAtMs(Map<String, dynamic> d) {
  final v = d['createdAt'];
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is int) return v;
  return 0;
}

int? orderUpdatedAtMs(Map<String, dynamic> d) {
  final v = d['updatedAt'];
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is int) return v;
  return null;
}

double orderTotalAmount(Map<String, dynamic> d) {
  for (final key in const ['total', 'orderTotal', 'grandTotal', 'amount', 'totalAmount']) {
    final value = d[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.replaceAll(RegExp(r'[^\d.]'), ''));
      if (parsed != null) return parsed;
    }
  }
  return 0;
}

class TrackingStepUi {
  final String title;
  final String subtitle;
  final bool isComplete;
  final bool isCurrent;

  const TrackingStepUi({
    required this.title,
    required this.subtitle,
    required this.isComplete,
    required this.isCurrent,
  });
}

/// Build the 4-step fulfilment timeline for the current status.
List<TrackingStepUi> buildFulfilmentSteps(String status) {
  const steps = [
    ('Order placed', 'We received your order'),
    ('Processing', 'Preparing your items'),
    ('Shipped', 'On the way to you'),
    ('Delivered', 'Enjoy your purchase'),
  ];
  if (status == 'Cancelled') {
    return [
      const TrackingStepUi(
        title: 'Order cancelled',
        subtitle: 'This order was cancelled. Contact support if this is a mistake.',
        isComplete: true,
        isCurrent: true,
      ),
    ];
  }
  const order = ['Pending', 'Processing', 'Shipped', 'Delivered'];
  var idx = order.indexOf(status);
  if (idx < 0) idx = 0;
  return List.generate(steps.length, (i) {
    final isComplete = i < idx;
    final isCurrent = i == idx;
    return TrackingStepUi(
      title: steps[i].$1,
      subtitle: steps[i].$2,
      isComplete: isComplete,
      isCurrent: isCurrent,
    );
  });
}
