# La Vogue Vista — Virtual Try‑On & Beauty AI

La Vogue Vista is a Flutter application that combines **live lipstick/makeup try‑on**, **hair & skin analysis**, and an **AI beauty assistant chatbot**.

This document explains how the AI parts work in the current project so you can understand what is “real model inference” vs “pixel‑based heuristics”.

## API keys & environment (submission / markers)

**`.env` is not part of the submission.** It is listed in `.gitignore` so real secrets are never committed. That is intentional and correct for security and for coursework hand‑in.

**What you do submit:** the tracked file **`.env.example`**, which documents every variable with no real values.

**How markers (or a new machine) run the app with AI features:**

If an **IDE or agent status panel** shows `OPENROUTER_API_KEY` / `OPENROUTER_MODEL` as missing while other keys pass, that panel is usually reading the **Git workspace root** (the parent of this folder). Use the repo file **`../.env.example`** there: copy it to **`../.env`** and add the same OpenRouter values, or define those variables in **Cursor → Settings → Environment** (or wherever `OPENAI_API_KEY` is set).

1. Copy the template and add keys locally (this file stays only on their machine):
   ```bash
   cd Final_Year_Project
   cp .env.example .env
   ```
2. Edit `.env` and set:
   - **`GEMINI_API_KEY`** — from [Google AI Studio](https://aistudio.google.com/app/apikey) (Lumi chat + Skin & Hair vision in `TFLiteAnalysisService` / `GeminiChatService`).
   - **`OPENROUTER_API_KEY`** — from [OpenRouter](https://openrouter.ai/keys) (Hair **Style Match** screen only).

3. **Option A — IDE / plain `flutter run`:** keep keys in **`.env`** next to `pubspec.yaml` (same variables as above). It is declared as a Flutter **asset**, so it is copied into the app when you build; **stop and run `flutter run` again** after editing. If the file is missing, run `cp .env.example .env` first or the build can fail on the missing asset.
4. **Optional fallbacks:** `assets/env/local_keys.env` (tracked, empty defaults) is merged after `.env` for keys you only set there. **`--dart-define`** overrides both when set.
5. **Option B — shell / CI:** use `--dart-define` so keys never sit in tracked files, e.g.:
   ```bash
   ./ios_quick_run.sh
   ```
   or:
   ```bash
   flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY --dart-define=OPENROUTER_API_KEY=YOUR_KEY
   ```
   `--dart-define` overrides bundled env files when set.

   Hot reload does **not** refresh API keys; after editing `.env` run **`flutter run` again** (or the script above).

**If markers run without any keys:** the app still runs; features fall back or show setup hints (e.g. offline chat text, pixel/TFLite fallbacks for analysis, Style Match asks for OpenRouter). Live try‑on and most shopping flows do not need these keys.

**For your report / Viva:** state that secrets are supplied via bundled **`.env`** (from `.env.example`), optional `assets/env/local_keys.env`, `ios_quick_run.sh`, or `--dart-define`, and that `.env` is excluded from version control by design.

**Manual QA:** use `docs/QA_CHECKLIST.md` (session template + device checks). Automated: `flutter pub get`, then `./scripts/qa_automated.sh` (runs analyze with non-fatal infos/warnings + `flutter test`).

**If `flutter run` fails on a physical iPhone:** (1) **Wrong iOS support in Xcode** — if the error says `iOS XX.X is not installed` for your phone’s OS, open **Xcode → Settings → Platforms** (or **Settings → Components** in older Xcode), download that **iOS version** support, restart Xcode, then `flutter run` again. Updating **Xcode** from the App Store can also bring newer device support. (2) **Wireless debugging** — use a **USB** cable, unlock the phone, trust the computer. (3) Other build issues — open `ios/Runner.xcworkspace`, **Product → Run** once; or `flutter clean`, then `cd ios && pod install && cd ..`, then `flutter run`. Retraining only changes `assets/models/*.tflite`; it does not install Xcode platforms.

**Web hosting (Firebase — admin + delivery only):** `docs/HOSTING.md` — `./scripts/setup_firebase_hosting_sites.sh`, then `./scripts/deploy_firebase_hosting.sh`. **iOS (TestFlight / App Store, not Firebase):** same doc — app icon + splash use `assets/logo.png` (regenerate with `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create` after changing the logo). Build an IPA with `./scripts/build_ios_ipa.sh` after code signing is set in Xcode.

## Live Try‑On (Lipsticks & Makeup)

- Implemented fully on‑device using:
  - `assets/models/face_landmarker.task` (MediaPipe face landmarks).
  - Custom GLSL shader `assets/shaders/lipstick.frag`.
  - Lip mask asset `assets/masks/lip_oval.png`.
- The live try‑on effect does **not** depend on the Python training scripts or datasets. It is driven by landmarks + shader blending, so it works as long as the assets above are bundled and the camera permissions are granted.

## Skin & Hair Analysis

- **Saved beauty profile (signed-in users):** After **Beauty Analysis** runs, results merge into Firestore `users/{uid}.beautyProfile` (keeps the more reliable inference tier: Gemini Vision > TFLite > server > pixel). A **deterministic lip hex** is stored for **live try-on**. **Profile** shows the summary and **Try my lip shade live**; the analysis screen has **TRY RECOMMENDED LIP LIVE**. Sign in so saves apply; guests still get on-screen results only.
- **On-device (Flutter):** `TFLiteAnalysisService` loads `hair_type_classifier.tflite` and `hair_color_classifier.tflite` plus their `*_labels.json` files. Each model’s **output size must match** the label list (4 hair types, 5 colours). If you see “outputs 1001 classes”, replace the `.tflite` files. Requires `pip install tensorflow`.
  - **Train from your `datasets/` tree (canonical scripts live in `datasets/train/`):**  
    `cd datasets/train` → `python3 prepare_hair_training_from_datasets.py --max_per_class 2000` →  
    `python3 train_hair_classifiers_tflite.py --type_dir ./hair_type_flutter --color_dir ./hair_color_flutter --epochs 20`  
    Run from **`datasets/train/`** (see **`datasets/train/README_TRAINING.md`**). Use `--max_per_class 800` if training is slow. **Red** is a **proxy** class unless you add real red-hair photos under `hair_color_flutter/Red/`.
  - **Quick synthetic models:** `cd datasets/train` then `python3 train_hair_classifiers_tflite.py --demo`
- **Optional Python API** (`datasets/api/app.py` if present in your tree) may expose `POST /analyze_skin` and `POST /analyze_hair` with server-side TFLite or pixel modes.
- **Fallbacks:** Gemini vision and pixel heuristics still apply when TFLite is skipped or fails.

## AI Beauty Chatbot

- The chat UI (`AIBeautyAssistantScreen`) talks to the Python API via `AIChatService`:
  - `POST /chat` — knowledge‑base‑driven responses implemented in `datasets/api/beauty_knowledge_base.py`.
  - If the server is unavailable, the app switches to **offline scripted replies** that still feel intelligent but do not query the backend.
- The chatbot logic is **text/knowledge‑base based**, not image‑model based, so it works independently of the training scripts.

## Summary for the Project Report

- **Live Try‑On**: real‑time graphics pipeline (MediaPipe + shaders), independent of ML training.
- **Skin & Hair Matching:** Flutter uses **TFLite** hair classifiers when output sizes match `*_labels.json`; otherwise **Gemini** / **pixel** fallbacks apply. Regenerate models from **`datasets/train/train_hair_classifiers_tflite.py`** (see **Skin & Hair Analysis** and `datasets/train/README_TRAINING.md`).
- **AI Bot**: uses a curated beauty knowledge base with optional backend server; has graceful offline fallbacks in the Flutter app.

Heavy CNN training is therefore an **optional enhancement**. The app as delivered can be built and demonstrated end‑to‑end using the existing assets and pixel‑analysis logic.
