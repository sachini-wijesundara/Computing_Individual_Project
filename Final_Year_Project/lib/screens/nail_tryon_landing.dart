import 'package:flutter/material.dart';

import 'nail_tryon_screen.dart';

const _maroon = Color(0xFF7C150D);

Future<void> _openNailTryOnInline(BuildContext context, {required bool liveMode}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.black,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    clipBehavior: Clip.hardEdge,
    builder: (sheetCtx) {
      final screenHeight = MediaQuery.of(sheetCtx).size.height;
      return SizedBox(
        height: screenHeight,
        child: NailTryOnScreen(
          liveMode: liveMode,
          embedded: true,
          onClose: () => Navigator.of(sheetCtx).pop(),
        ),
      );
    },
  );
}

/// Bottom sheet: Try live (MediaPipe + back camera) or Add photo.
void showNailTryOnEntry(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'NAIL TRY-ON',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _maroon,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Use your camera with automatic hand tracking, or a hand photo from your gallery.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openNailTryOnInline(context, liveMode: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _maroon,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_rounded, size: 22),
                      SizedBox(width: 10),
                      Text('Try live', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openNailTryOnInline(context, liveMode: false);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _maroon,
                    side: const BorderSide(color: _maroon, width: 1.8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 22),
                      SizedBox(width: 10),
                      Text('Add photo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Live mode uses the back camera so you can film your hand.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Popup entry used from dashboard before opening mode selection.
void showNailTryOnPopup(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Nail Try-On',
          style: TextStyle(
            color: _maroon,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        content: const Text(
          'Try nail colours and art in live camera mode or using a hand photo.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              showNailTryOnEntry(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _maroon,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      );
    },
  );
}
