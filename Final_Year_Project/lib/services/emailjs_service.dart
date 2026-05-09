import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/emailjs_config.dart';

class EmailJsService {
  EmailJsService._();

  static const _url = 'https://api.emailjs.com/api/v1.0/email/send';

  /// All [templateParams] values must be strings (template variable names must
  /// match your EmailJS template, e.g. `customer_email`, `order_items_html`).
  static Future<void> sendOrderConfirmation({
    required Map<String, String> templateParams,
  }) async {
    if (!EmailJsConfig.isConfigured) {
      debugPrint('EmailJS: skipped (set EMAILJS_PUBLIC_KEY)');
      return;
    }

    final enrichedParams = <String, String>{
      ...templateParams,
      // Common aliases many EmailJS templates use.
      'to_email': templateParams['customer_email'] ?? '',
      'reply_to': templateParams['customer_email'] ?? '',
      'from_name': 'La Vogue Vista',
      'subject': 'Order confirmation - ${templateParams['order_id'] ?? 'LVV'}',
    };

    final payload = <String, dynamic>{
      'service_id': EmailJsConfig.serviceId,
      'template_id': EmailJsConfig.templateId,
      'user_id': EmailJsConfig.publicKey,
      'template_params': enrichedParams,
    };

    if (EmailJsConfig.accessToken.isNotEmpty) {
      payload['accessToken'] = EmailJsConfig.accessToken;
    }

    final resp = await http.post(
      Uri.parse(_url),
      headers: const {
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(payload),
    );

    if (resp.statusCode != 200) {
      final detail = resp.body.trim().isEmpty
          ? 'HTTP ${resp.statusCode}'
          : resp.body.trim();
      debugPrint('EmailJS error ${resp.statusCode}: $detail');
      throw EmailJsException(resp.statusCode, detail);
    }
  }
}

class EmailJsException implements Exception {
  EmailJsException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() {
    if (body.length > 120) {
      return 'EmailJS $statusCode: ${body.substring(0, 120)}…';
    }
    return 'EmailJS $statusCode: $body';
  }
}
