import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/firebase_auth_service.dart';
import '../services/firebase_storage_service.dart';

const _bgTop = Color(0xFFF5F5F5);
const _bgMid = Color(0xFFF1ABAD);
const _bgBot = Color(0xFFF7BDBD);
const _ink = Color(0xFF121212);
const _fieldFill = Color(0xFFF2C9CC);
const _fieldBorder = Color(0xFFE5AFB4);
const _maroon = Color(0xFF9A130B);

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController(text: '************');
  final _dobCtrl = TextEditingController(text: '23/05/1995');
  final _countryCtrl = TextEditingController(text: 'Sri Lanka');
  bool _saving = false;
  bool _uploadingPhoto = false;
  /// Shown immediately after upload so the avatar refreshes even if the download URL is unchanged.
  String? _avatarUrlOverride;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameCtrl.text = (user?.displayName?.trim().isNotEmpty ?? false) ? user!.displayName!.trim() : 'Melissa Peters';
    _emailCtrl.text = user?.email ?? 'melpeters@gmail.com';
    _avatarUrlOverride = user?.photoURL;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _dobCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirebaseAuthService.updateUserProfile(displayName: _nameCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: Color(0xFF1F8A43),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showPhotoSourcePicker() async {
    if (_uploadingPhoto) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    await _uploadProfilePhoto(File(picked.path));
  }

  Future<void> _uploadProfilePhoto(File file) async {
    setState(() => _uploadingPhoto = true);
    try {
      final url = await FirebaseStorageService.uploadProfileImage(file);
      await FirebaseAuthService.updateUserProfile(photoURL: url);
      await FirebaseAuth.instance.currentUser?.reload();
      if (!mounted) return;
      setState(() {
        _avatarUrlOverride =
            FirebaseAuth.instance.currentUser?.photoURL ?? url;
        _uploadingPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo updated'),
          backgroundColor: Color(0xFF1F8A43),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload photo: $e')),
        );
      }
    }
  }

  String? get _avatarUrl {
    final u = FirebaseAuth.instance.currentUser?.photoURL;
    if (_avatarUrlOverride != null && _avatarUrlOverride!.isNotEmpty) {
      return _avatarUrlOverride;
    }
    return u;
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _avatarUrl;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgMid, _bgBot],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _ink),
                      ),
                    ),
                    const Text(
                      'Edit Profile',
                      style: TextStyle(fontSize: 40 / 2, fontWeight: FontWeight.w800, color: _ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 54,
                      backgroundColor: const Color(0xFF5C4FA1),
                      child: CircleAvatar(
                        radius: 52,
                        key: ValueKey(avatar ?? 'placeholder'),
                        backgroundColor: const Color(0xFFE8E0F5),
                        backgroundImage: avatar != null && avatar.isNotEmpty
                            ? NetworkImage(avatar)
                            : const NetworkImage(
                                'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?w=300',
                              ),
                      ),
                    ),
                    if (_uploadingPhoto)
                      Positioned.fill(
                        child: ClipOval(
                          child: Container(
                            color: Colors.black38,
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: InkWell(
                        onTap: _uploadingPhoto ? null : _showPhotoSourcePicker,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: const Color(0xFF5C4FA1),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt_rounded, size: 17, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _label('Name'),
              _editableField(_nameCtrl),
              const SizedBox(height: 12),
              _label('Email'),
              _editableField(_emailCtrl, enabled: false),
              const SizedBox(height: 12),
              _label('Password'),
              _editableField(_passwordCtrl, enabled: false),
              const SizedBox(height: 12),
              _label('Date of Birth'),
              _selectLikeField(_dobCtrl.text),
              const SizedBox(height: 12),
              _label('Country/Region'),
              _selectLikeField(_countryCtrl.text),
              const SizedBox(height: 24),
              Center(
                child: SizedBox(
                  width: 180,
                  height: 46,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _maroon,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _maroon.withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(color: Color(0xFFE06D6D), width: 1.6),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Save changes',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _label(String t) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Text(
        t,
        style: const TextStyle(fontSize: 17 / 1.1, fontWeight: FontWeight.w700, color: _ink),
      ),
    );
  }

  static Widget _editableField(TextEditingController c, {bool enabled = true}) {
    return TextField(
      controller: c,
      enabled: enabled,
      style: const TextStyle(fontSize: 17 / 1.1, fontWeight: FontWeight.w600, color: Color(0xFF4A4A4A)),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: _fieldFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _fieldBorder),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: _fieldBorder),
        ),
      ),
    );
  }

  static Widget _selectLikeField(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _fieldFill,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _fieldBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 17 / 1.1, fontWeight: FontWeight.w600, color: Color(0xFF4A4A4A)),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded, color: _ink),
        ],
      ),
    );
  }
}
