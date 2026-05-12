import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/delivery_staff_service.dart';
import 'delivery_staff_proof_screen.dart';
import '../../utils/price_format.dart';

class DeliveryStaffOrderDetailScreen extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> orderDoc;
  const DeliveryStaffOrderDetailScreen({super.key, required this.orderDoc});

  @override
  State<DeliveryStaffOrderDetailScreen> createState() =>
      _DeliveryStaffOrderDetailScreenState();
}

class _DeliveryStaffOrderDetailScreenState
    extends State<DeliveryStaffOrderDetailScreen> {
  static const _brand = Color(0xFF7C150D);
  static const _surface = Color(0xFFF6F3F2);
  static const _success = Color(0xFF1E8E4A);
  static const _successBg = Color(0xFFE8F7EC);

  String? _busyStep;

  @override
  Widget build(BuildContext context) {
    final ref = widget.orderDoc.reference;
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: Text('Order ${widget.orderDoc.id}'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E1A1A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black26,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(includeMetadataChanges: true),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Could not load order: ${snap.error}'));
          }
          final doc = snap.data;
          if (doc == null || !doc.exists) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = doc.data() ?? {};
          return _buildBody(context, d);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> d) {
    final orderId = widget.orderDoc.id;
    final customerName =
        (d['customerName'] ?? d['name'] ?? d['fullName'] ?? 'Customer')
            .toString();
    final customerPhone =
        (d['customerPhone'] ?? d['phone'] ?? d['mobile'] ?? '').toString();
    final customerEmail = (d['customerEmail'] ?? d['email'] ?? '').toString();
    final address =
        (d['shippingAddress'] ?? d['address'] ?? d['deliveryAddress'] ?? '')
            .toString();
    final ds = (d['deliveryStatus'] ?? 'assigned').toString();
    final orderCollected = d['orderCollectedFromStore'] == true;
    final orderDelivered = d['orderDeliveredByStaff'] == true;
    final cashCollected = d['cashCollectedSuccessfully'] == true;
    final payment = (d['paymentMethod'] ?? '').toString();
    final isCod = _isCashOnDelivery(payment);
    final total = _totalText(d);
    final totalAmount = _totalValue(d);
    final items = (d['items'] as List?) ?? const [];

    final acceptDone = _acceptStepDone(ds);
    final outDone = _outForDeliveryDone(ds, orderDelivered);
    final codStepCount = isCod ? 1 : 0;
    final lastWorkflowIndex = 3 + codStepCount;
    final useTwoColumns = MediaQuery.sizeOf(context).width >= 560;

    final customerCard = _customerDetailsCard(
      context,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      address: address,
    );
    final orderCard = _orderDetailsCard(
      context,
      deliveryStatus: ds,
      orderStatus: (d['status'] ?? '-').toString(),
      payment: payment,
      total: total,
      address: address,
      items: items,
      isCod: isCod,
    );

    final detailsRow =
        useTwoColumns
            ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: customerCard),
                const SizedBox(width: 12),
                Expanded(child: orderCard),
              ],
            )
            : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                customerCard,
                const SizedBox(height: 10),
                orderCard,
              ],
            );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        _orderHeaderChip(orderId, ds, d),
        const SizedBox(height: 12),
        detailsRow,
        const SizedBox(height: 12),
        _section(
          title: 'Delivery Workflow',
          subtitle:
              isCod
                  ? 'After delivery, record COD here. Hand cash to the office once from the dashboard (end of day).'
                  : 'Complete each step in order. No cash collection for this order.',
          titleTrailing:
              isCod
                  ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E5),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _brand.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      'Cash on delivery',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _brand,
                      ),
                    ),
                  )
                  : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _workflowStep(
                stepIndex: 0,
                isLast: 0 == lastWorkflowIndex,
                title: 'Accept assignment',
                subtitle: 'Confirm you are taking this delivery.',
                done: acceptDone,
                enabled: _canAccept(ds) && !acceptDone,
                busy: _busyStep == 'accept',
                onTap:
                    () => _runStep('accept', () async {
                      await DeliveryStaffService.instance.updateDeliveryStatus(
                        orderId: orderId,
                        deliveryStatus: 'accepted',
                      );
                    }, 'Assignment accepted'),
              ),
              _workflowStep(
                stepIndex: 1,
                isLast: 1 == lastWorkflowIndex,
                title: 'Order collected',
                subtitle: 'Picked up from store or warehouse.',
                done: orderCollected,
                enabled:
                    _canMarkCollected(ds, acceptDone) && !orderCollected,
                busy: _busyStep == 'collected',
                onTap:
                    () => _runStep('collected', () async {
                      await DeliveryStaffService.instance
                          .markOrderCollectedFromStore(orderId: orderId);
                    }, 'Order collected from store'),
              ),
              _workflowStep(
                stepIndex: 2,
                isLast: 2 == lastWorkflowIndex,
                title: 'Out for delivery',
                subtitle: 'You are on the way to the customer.',
                done: outDone,
                enabled: _canOutForDelivery(ds, orderCollected) && !outDone,
                busy: _busyStep == 'out',
                onTap:
                    () => _runStep('out', () async {
                      await DeliveryStaffService.instance.updateDeliveryStatus(
                        orderId: orderId,
                        deliveryStatus: 'out_for_delivery',
                      );
                    }, 'Marked out for delivery'),
              ),
              _workflowStep(
                stepIndex: 3,
                isLast: 3 == lastWorkflowIndex,
                title: 'Order delivered',
                subtitle: 'Handed to the customer.',
                done: orderDelivered,
                enabled:
                    _canMarkDelivered(ds, outDone) && !orderDelivered,
                busy: _busyStep == 'delivered',
                onTap:
                    () => _runStep('delivered', () async {
                      await DeliveryStaffService.instance
                          .markOrderDeliveredByStaff(orderId: orderId);
                    }, 'Order delivered'),
              ),
              if (isCod)
                _workflowStep(
                  stepIndex: 4,
                  isLast: 4 == lastWorkflowIndex,
                  title: 'Cash collected successfully',
                  subtitle:
                      'COD received from the customer. Hand over to the office later from the main dashboard.',
                  done: cashCollected,
                  enabled: orderDelivered && !cashCollected,
                  busy: _busyStep == 'cash',
                  onTap:
                      () => _runStep('cash', () async {
                        await DeliveryStaffService.instance
                            .markCashCollectedSuccessfully(
                              orderId: orderId,
                              amount: totalAmount,
                            );
                      }, 'Cash recorded in your wallet'),
                ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                'Other actions',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brand,
                      side: BorderSide(color: _brand.withValues(alpha: 0.35)),
                    ),
                    onPressed: () async {
                      final uploaded = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder:
                              (_) =>
                                  DeliveryStaffProofScreen(orderId: orderId),
                        ),
                      );
                      if (uploaded == true && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Proof uploaded successfully'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.photo_camera_outlined, size: 20),
                    label: const Text('Upload proof'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brand,
                      side: BorderSide(color: _brand.withValues(alpha: 0.35)),
                    ),
                    onPressed: () => _markFailed(context, orderId),
                    icon: const Icon(Icons.error_outline_rounded, size: 20),
                    label: const Text('Failed'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _brand,
                      side: BorderSide(color: _brand.withValues(alpha: 0.35)),
                    ),
                    onPressed: () => _rejectAssignment(context, orderId),
                    icon: const Icon(Icons.block_rounded, size: 20),
                    label: const Text('Reject assignment'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _acceptStepDone(String ds) {
    if (ds == 'failed_delivery') return false;
    return const {
      'accepted',
      'picked_up',
      'out_for_delivery',
      'delivered',
    }.contains(ds);
  }

  bool _outForDeliveryDone(String ds, bool orderDelivered) {
    if (orderDelivered) return true;
    return ds == 'out_for_delivery' || ds == 'delivered';
  }

  bool _canAccept(String ds) => ds == 'assigned';

  bool _canMarkCollected(String ds, bool acceptDone) {
    if (ds == 'failed_delivery') return false;
    if (_orderCollectedFromDs(ds)) return false;
    return acceptDone;
  }

  bool _orderCollectedFromDs(String ds) =>
      ds == 'picked_up' ||
      ds == 'out_for_delivery' ||
      ds == 'delivered';

  bool _canOutForDelivery(String ds, bool orderCollectedFlag) {
    if (ds == 'failed_delivery') return false;
    if (!orderCollectedFlag) return false;
    return ds == 'picked_up';
  }

  bool _canMarkDelivered(String ds, bool outDone) {
    if (ds == 'failed_delivery') return false;
    return outDone && (ds == 'out_for_delivery' || ds == 'delivered');
  }

  Future<void> _runStep(
    String key,
    Future<void> Function() action,
    String snackbar,
  ) async {
    setState(() => _busyStep = key);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(snackbar)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Something went wrong: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyStep = null);
    }
  }

  Widget _customerDetailsCard(
    BuildContext context, {
    required String customerName,
    required String customerPhone,
    required String customerEmail,
    required String address,
  }) {
    return _section(
      title: 'Customer details',
      subtitle: 'Contact the customer or open directions.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line('Name', customerName),
          _line('Phone', customerPhone.isEmpty ? '—' : customerPhone),
          _line('Email', customerEmail.isEmpty ? '—' : customerEmail),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brand,
                  side: const BorderSide(color: Color(0xFFE9DDDA)),
                ),
                onPressed:
                    customerPhone.trim().isEmpty
                        ? null
                        : () => _callCustomer(context, customerPhone),
                icon: const Icon(Icons.call_rounded, size: 20),
                label: const Text('Call'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brand,
                  side: const BorderSide(color: Color(0xFFE9DDDA)),
                ),
                onPressed:
                    address.trim().isEmpty
                        ? null
                        : () => _openMaps(context, address),
                icon: const Icon(Icons.map_rounded, size: 20),
                label: const Text('Maps'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderDetailsCard(
    BuildContext context, {
    required String deliveryStatus,
    required String orderStatus,
    required String payment,
    required String total,
    required String address,
    required List<dynamic> items,
    required bool isCod,
  }) {
    return _section(
      title: 'Order details',
      subtitle: 'Status, payment, address & items.',
      titleTrailing:
          isCod
              ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _brand.withValues(alpha: 0.2)),
                ),
                child: Text(
                  'COD',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: _brand,
                  ),
                ),
              )
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shipment & payment',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          _line('Delivery status', deliveryStatus),
          _line('Order status', orderStatus),
          _line('Payment', payment.isEmpty ? '—' : payment),
          _line('Total', total),
          _line('Address', address.isEmpty ? '—' : address),
          if (isCod) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9F0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _brand.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.payments_outlined, size: 18, color: _brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Collect ${total == '-' ? 'the order total' : total} after delivery, mark it below. When you finish your route, hand all cash in using Delivery Wallet on the dashboard.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Colors.grey.shade300),
          ),
          Text(
            'Items',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Text(
              'No items listed.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            )
          else
            Column(
              children:
                  items.map((item) {
                    if (item is! Map) return const SizedBox.shrink();
                    final name = (item['name'] ?? 'Item').toString();
                    final qty =
                        (item['quantity'] ?? item['qty'] ?? 1).toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '×$qty',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _orderHeaderChip(String orderId, String ds, Map<String, dynamic> d) {
    final statusLabel = (d['status'] ?? '—').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF3F0D0A), Color(0xFF7C150D), Color(0xFFA32A1F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order #$orderId',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Delivery: $ds · Shop: $statusLabel',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _workflowStep({
    required int stepIndex,
    required bool isLast,
    required String title,
    required String subtitle,
    required bool done,
    required bool enabled,
    required bool busy,
    required Future<void> Function() onTap,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                if (stepIndex > 0)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: const Color(0xFFE0D8D5),
                    ),
                  ),
                if (stepIndex == 0) const SizedBox(height: 14),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? _success : const Color(0xFFF0EBE9),
                    border: Border.all(
                      color: done ? _success : const Color(0xFFD4C9C4),
                      width: 2,
                    ),
                  ),
                  child:
                      done
                          ? const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Colors.white,
                          )
                          : Text(
                            '${stepIndex + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: const Color(0xFFE0D8D5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Material(
                color: Colors.transparent,
                child:
                    done
                        ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _successBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _success.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                color: _success,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF14532D),
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      'Completed',
                                      style: TextStyle(
                                        color: _success.withValues(alpha: 0.9),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                        : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFFE9DDDA),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      enabled ? _brand : Colors.grey.shade400,
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: Colors.white70,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed:
                                    enabled && !busy
                                        ? () => onTap()
                                        : null,
                                child:
                                    busy
                                        ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                        : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 18,
                                              color:
                                                  enabled
                                                      ? Colors.white
                                                      : Colors.white70,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text('Mark complete'),
                                          ],
                                        ),
                              ),
                              if (!enabled && !done)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    'Complete the previous step first.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markFailed(BuildContext context, String orderId) async {
    final reasonCtrl = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder:
              (_) => AlertDialog(
                title: const Text('Mark delivery failed'),
                content: TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Save'),
                  ),
                ],
              ),
        ) ??
        false;
    if (!ok) return;
    await DeliveryStaffService.instance.updateDeliveryStatus(
      orderId: orderId,
      deliveryStatus: 'failed_delivery',
      failedReason: reasonCtrl.text.trim(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked as failed')));
    }
  }

  Future<void> _rejectAssignment(BuildContext context, String orderId) async {
    final reasonCtrl = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder:
              (_) => AlertDialog(
                title: const Text('Reject assignment'),
                content: TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Reject'),
                  ),
                ],
              ),
        ) ??
        false;
    if (!ok) return;
    await DeliveryStaffService.instance.rejectAssignment(
      orderId: orderId,
      reason: reasonCtrl.text.trim(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Assignment rejected')));
    }
  }

  Future<void> _callCustomer(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.trim());
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open dialer')));
    }
  }

  Future<void> _openMaps(BuildContext context, String address) async {
    final query = Uri.encodeComponent(address.trim());
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open maps')));
    }
  }

  Widget _section({
    required String title,
    String? subtitle,
    Widget? titleTrailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9DDDA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (titleTrailing != null) ...[
                const SizedBox(width: 8),
                titleTrailing,
              ],
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Color(0xFF1E1A1A), fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  String _totalText(Map<String, dynamic> data) {
    for (final k in const ['total', 'orderTotal', 'grandTotal', 'amount']) {
      final v = data[k];
      if (v is num) return formatRs(v);
      if (v is String) {
        final p = double.tryParse(v);
        if (p != null) return formatRs(p);
      }
    }
    return '-';
  }

  double _totalValue(Map<String, dynamic> data) {
    for (final k in const ['total', 'orderTotal', 'grandTotal', 'amount']) {
      final v = data[k];
      if (v is num) return v.toDouble();
      if (v is String) {
        final p = double.tryParse(v);
        if (p != null) return p;
      }
    }
    return 0;
  }

  bool _isCashOnDelivery(String payment) {
    final p = payment.toLowerCase();
    return p.contains('cod') ||
        p.contains('cash on delivery') ||
        p.contains('cash');
  }
}
