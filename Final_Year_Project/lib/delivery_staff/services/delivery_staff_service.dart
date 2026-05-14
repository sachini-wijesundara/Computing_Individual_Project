import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cross_file/cross_file.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class DeliveryStaffService {
  DeliveryStaffService._();
  static final instance = DeliveryStaffService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  String? get uid => _auth.currentUser?.uid;
  String get emailLower =>
      (_auth.currentUser?.email ?? '').trim().toLowerCase();

  /// If [forUid] is set, that document is watched (avoids relying on
  /// [currentUser] lagging behind [authStateChanges] on web after sign-in).
  Stream<DocumentSnapshot<Map<String, dynamic>>> currentProfileStream({
    String? forUid,
  }) {
    final id = (forUid ?? uid)?.trim();
    if (id == null || id.isEmpty) {
      return const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();
    }
    return _db.collection('users').doc(id).snapshots();
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  assignedOrdersStream() {
    final id = uid;
    final mail = emailLower;
    if (id == null || id.isEmpty) return const Stream.empty();

    final byIdStream = _db
        .collection('orders')
        .where('deliveryStaffId', isEqualTo: id)
        .snapshots(includeMetadataChanges: true);
    final byUidStream = _db
        .collection('orders')
        .where('deliveryStaffUid', isEqualTo: id)
        .snapshots(includeMetadataChanges: true);
    final byEmailStream =
        mail.isEmpty
            ? const Stream<QuerySnapshot<Map<String, dynamic>>>.empty()
            : _db
                .collection('orders')
                .where('deliveryStaffEmailLower', isEqualTo: mail)
                .snapshots(includeMetadataChanges: true);

    final controller =
        StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>();
    QuerySnapshot<Map<String, dynamic>>? a;
    QuerySnapshot<Map<String, dynamic>>? b;
    QuerySnapshot<Map<String, dynamic>>? c;

    void emit() {
      final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final snap in [a, b, c]) {
        if (snap == null) continue;
        for (final doc in snap.docs) {
          map[doc.id] = doc;
        }
      }
      final docs =
          map.values.toList()..sort(
            (x, y) => _orderMillis(y.data()).compareTo(_orderMillis(x.data())),
          );
      if (!controller.isClosed) controller.add(docs);
    }

    final s1 = byIdStream.listen((snap) {
      a = snap;
      emit();
    }, onError: controller.addError);
    final s2 = byUidStream.listen((snap) {
      b = snap;
      emit();
    }, onError: controller.addError);
    final s3 = byEmailStream.listen((snap) {
      c = snap;
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await s1.cancel();
      await s2.cancel();
      await s3.cancel();
    };
    return controller.stream;
  }

  Future<void> updateDeliveryStatus({
    required String orderId,
    required String deliveryStatus,
    String? failedReason,
  }) async {
    final ref = _db.collection('orders').doc(orderId);
    final payload = <String, dynamic>{
      'deliveryStatus': deliveryStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (deliveryStatus == 'accepted') {
      payload['deliveryAcceptedAt'] = FieldValue.serverTimestamp();
      payload['status'] = 'Processing';
      payload['failedReason'] = FieldValue.delete();
    } else if (deliveryStatus == 'picked_up') {
      payload['pickedUpAt'] = FieldValue.serverTimestamp();
      payload['status'] = 'Shipped';
    } else if (deliveryStatus == 'out_for_delivery') {
      payload['outForDeliveryAt'] = FieldValue.serverTimestamp();
      payload['status'] = 'Shipped';
    } else if (deliveryStatus == 'delivered') {
      payload['deliveredAt'] = FieldValue.serverTimestamp();
      payload['status'] = 'Delivered';
      payload['failedReason'] = FieldValue.delete();
    } else if (deliveryStatus == 'failed_delivery') {
      payload['failedAt'] = FieldValue.serverTimestamp();
      payload['status'] = 'Delivery Failed';
      payload['failedReason'] = (failedReason ?? '').trim();
    }
    await ref.set(payload, SetOptions(merge: true));
  }

  Future<void> markOrderCollectedFromStore({required String orderId}) async {
    await _db.collection('orders').doc(orderId).set({
      'deliveryStatus': 'picked_up',
      'orderCollectedFromStore': true,
      'orderCollectedAt': FieldValue.serverTimestamp(),
      'status': 'Shipped',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markOrderDeliveredByStaff({required String orderId}) async {
    await _db.collection('orders').doc(orderId).set({
      'deliveryStatus': 'delivered',
      'orderDeliveredByStaff': true,
      'orderDeliveredByStaffAt': FieldValue.serverTimestamp(),
      'deliveredAt': FieldValue.serverTimestamp(),
      'status': 'Delivered',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markCashCollectedSuccessfully({
    required String orderId,
    required double amount,
  }) async {
    final id = uid;
    if (id == null || id.isEmpty) {
      throw Exception('No signed-in delivery staff.');
    }
    final orderRef = _db.collection('orders').doc(orderId);
    final userRef = _db.collection('users').doc(id);
    await _db.runTransaction((tx) async {
      final orderSnap = await tx.get(orderRef);
      final orderData = orderSnap.data() ?? const <String, dynamic>{};
      if (orderData['cashCollectedSuccessfully'] == true) return;
      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? const <String, dynamic>{};
      final wallet = _toDouble(userData['deliveryWalletBalance']);
      final pending = _toDouble(userData['deliveryPendingCash']);
      tx.set(orderRef, {
        'cashCollectedSuccessfully': true,
        'cashCollectedAt': FieldValue.serverTimestamp(),
        'cashCollectedAmount': amount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(userRef, {
        'deliveryWalletBalance': wallet + amount,
        'deliveryPendingCash': pending + amount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Per-order handover (legacy). Prefer [markEndOfDayCashHandover] for riders
  /// who settle many COD orders once at the end of the day.
  Future<void> markCashHandover({
    required String orderId,
    required double amount,
  }) async {
    final id = uid;
    if (id == null || id.isEmpty) {
      throw Exception('No signed-in delivery staff.');
    }
    final orderRef = _db.collection('orders').doc(orderId);
    final userRef = _db.collection('users').doc(id);
    await _db.runTransaction((tx) async {
      final orderSnap = await tx.get(orderRef);
      final orderData = orderSnap.data() ?? const <String, dynamic>{};
      if (orderData['cashHandoverDone'] == true) return;
      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? const <String, dynamic>{};
      final wallet = _toDouble(userData['deliveryWalletBalance']);
      final pending = _toDouble(userData['deliveryPendingCash']);
      final handed = _toDouble(userData['deliveryCashHandoverTotal']);
      tx.set(orderRef, {
        'cashHandoverDone': true,
        'cashHandoverAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(userRef, {
        'deliveryWalletBalance': (wallet - amount) < 0 ? 0 : wallet - amount,
        'deliveryPendingCash': (pending - amount) < 0 ? 0 : pending - amount,
        'deliveryCashHandoverTotal': handed + amount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Settle cash with the office once (e.g. end of day). Caps at current
  /// [deliveryPendingCash]. Does not modify individual order documents.
  Future<double> markEndOfDayCashHandover({required double amount}) async {
    final id = uid;
    if (id == null || id.isEmpty) {
      throw Exception('No signed-in delivery staff.');
    }
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }
    final userRef = _db.collection('users').doc(id);
    double settled = 0;
    await _db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? const <String, dynamic>{};
      final wallet = _toDouble(userData['deliveryWalletBalance']);
      final pending = _toDouble(userData['deliveryPendingCash']);
      final handed = _toDouble(userData['deliveryCashHandoverTotal']);
      final pay = amount > pending ? pending : amount;
      if (pay <= 0) return;
      settled = pay;
      tx.set(userRef, {
        'deliveryWalletBalance': (wallet - pay) < 0 ? 0 : wallet - pay,
        'deliveryPendingCash': (pending - pay) < 0 ? 0 : pending - pay,
        'deliveryCashHandoverTotal': handed + pay,
        'deliveryLastHandoverAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    return settled;
  }

  Future<void> rejectAssignment({
    required String orderId,
    String? reason,
  }) async {
    await updateDeliveryStatus(
      orderId: orderId,
      deliveryStatus: 'failed_delivery',
      failedReason:
          (reason ?? '').trim().isEmpty
              ? 'Assignment rejected by delivery staff'
              : reason,
    );
  }

  Future<void> attachDeliveryProof({
    required String orderId,
    required XFile image,
    String? note,
  }) async {
    final id = uid;
    if (id == null || id.isEmpty) {
      throw Exception('No signed-in delivery staff.');
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'delivery_proofs/$id/$orderId/$ts.jpg';
    final bytes = await image.readAsBytes();
    await _storage.ref(storagePath).putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
    final url = await _storage.ref(storagePath).getDownloadURL();
    await _db.collection('orders').doc(orderId).set({
      'proofImageUrl': url,
      'proofImagePath': storagePath,
      'proofNote': (note ?? '').trim(),
      'proofUploadedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  int deliveredTodayCount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return docs.where((doc) {
      final data = doc.data();
      if (_deliveryStatus(data) != 'delivered') return false;
      final ts = data['deliveredAt'];
      if (ts is! Timestamp) return false;
      final dt = ts.toDate();
      return dt.isAfter(dayStart) && dt.isBefore(dayEnd);
    }).length;
  }

  static int _orderMillis(Map<String, dynamic> data) {
    final v = data['updatedAt'] ?? data['createdAt'] ?? data['createdAtServer'];
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is int) return v;
    return 0;
  }

  static String _deliveryStatus(Map<String, dynamic> data) {
    final s = (data['deliveryStatus'] ?? '').toString().trim();
    if (s.isNotEmpty) return s;
    final hasAssignee =
        (data['deliveryStaffId'] ??
                data['deliveryStaffUid'] ??
                data['deliveryStaffEmailLower'] ??
                '')
            .toString()
            .trim()
            .isNotEmpty;
    if (hasAssignee) return 'assigned';
    final order = (data['status'] ?? '').toString().toLowerCase();
    if (order.contains('deliver')) return 'delivered';
    if (order.contains('ship')) return 'out_for_delivery';
    return 'assigned';
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
