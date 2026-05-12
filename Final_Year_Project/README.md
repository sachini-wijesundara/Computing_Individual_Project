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

**Web hosting (Firebase — admin + delivery only):** `docs/HOSTING.md`. One-time: `./scripts/setup_firebase_hosting_sites.sh`, then `./scripts/deploy_firebase_hosting.sh`. **iOS:** same doc, TestFlight / App Store section.

## Live Try‑On (Lipsticks & Makeup)

- Implemented fully on‑device using:
  - `assets/models/face_landmarker.task` (MediaPipe face landmarks).
  - Custom GLSL shader `assets/shaders/lipstick.frag`.
  - Lip mask asset `assets/masks/lip_oval.png`.
- The live try‑on effect does **not** depend on the Python training scripts or datasets. It is driven by landmarks + shader blending, so it works as long as the assets above are bundled and the camera permissions are granted.

## Skin & Hair Analysis

- The Python API in `datasets/api/app.py` exposes:
  - `POST /analyze_skin` — returns skin tone, undertone, confidence, and makeup recommendations.
  - `POST /analyze_hair` — returns hair type, colour, confidence, and product tips.
- The API has two possible inference modes:
  - **`tflite` mode** — uses TensorFlow Lite models saved under `datasets/train/models/*.tflite` and mirrored into `Final_Year_Project/assets/models/`.
  - **`pixel_analysis` / `offline` mode** — uses deterministic rules in `pixel_based_skin_analysis` and `pixel_based_hair_analysis` (plus hard‑coded fallbacks in `AIChatService`) when TFLite models are missing or the server is offline.
- In the current setup, no `.tflite` model files are present, so the system works in **pixel‑based mode**, which is sufficient for a final‑year demo but not meant as production‑grade dermatology.

## AI Beauty Chatbot

- The chat UI (`AIBeautyAssistantScreen`) talks to the Python API via `AIChatService`:
  - `POST /chat` — knowledge‑base‑driven responses implemented in `datasets/api/beauty_knowledge_base.py`.
  - If the server is unavailable, the app switches to **offline scripted replies** that still feel intelligent but do not query the backend.
- The chatbot logic is **text/knowledge‑base based**, not image‑model based, so it works independently of the training scripts.

## Summary for the Project Report

- **Live Try‑On**: real‑time graphics pipeline (MediaPipe + shaders), independent of ML training.
- **Skin & Hair Matching**: currently uses **pixel‑based analysis** with configurable upgrade path to `.tflite` classifiers from the training scripts in `datasets/train/*.py`.
- **AI Bot**: uses a curated beauty knowledge base with optional backend server; has graceful offline fallbacks in the Flutter app.

Heavy CNN training is therefore an **optional enhancement**. The app as delivered can be built and demonstrated end‑to‑end using the existing assets and pixel‑analysis logic.
