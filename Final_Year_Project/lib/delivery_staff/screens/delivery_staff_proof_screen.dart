import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

import '../services/delivery_staff_service.dart';

class DeliveryStaffProofScreen extends StatefulWidget {
  final String orderId;
  const DeliveryStaffProofScreen({super.key, required this.orderId});

  @override
  State<DeliveryStaffProofScreen> createState() =>
      _DeliveryStaffProofScreenState();
}

class _DeliveryStaffProofScreenState extends State<DeliveryStaffProofScreen> {
  final _picker = ImagePicker();
  final _noteCtrl = TextEditingController();
  XFile? _file;
  bool _saving = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final f = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (f == null) return;
    setState(() => _file = f);
  }

  Future<void> _upload() async {
    if (_file == null) return;
    setState(() => _saving = true);
    try {
      await DeliveryStaffService.instance.attachDeliveryProof(
        orderId: widget.orderId,
        localFilePath: _file!.path,
        note: _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Proof uploaded')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Proof of Delivery')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE9DDDA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Upload delivery proof photo',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 10),
                if (_file == null)
                  const Text('No image selected yet.')
                else
                  Text('Selected: ${_file!.name}'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickImage,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('Take Photo'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Optional note',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving || _file == null ? null : _upload,
                  child:
                      _saving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('Upload Proof'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
