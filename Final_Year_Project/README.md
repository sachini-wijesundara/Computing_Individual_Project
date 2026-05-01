# La Vogue Vista — Virtual Try‑On & Beauty AI

La Vogue Vista is a Flutter application that combines **live lipstick/makeup try‑on**, **hair & skin analysis**, and an **AI beauty assistant chatbot**.

This document explains how the AI parts work in the current project so you can understand what is “real model inference” vs “pixel‑based heuristics”.

## API keys & environment (submission / markers)

**`.env` is not part of the submission.** It is listed in `.gitignore` so real secrets are never committed. That is intentional and correct for security and for coursework hand‑in.

**What you do submit:** the tracked file **`.env.example`**, which documents every variable with no real values.

**How markers (or a new machine) run the app with AI features:**

1. Copy the template and add keys locally (this file stays only on their machine):
   ```bash
   cd Final_Year_Project
   cp .env.example .env
   ```
2. Edit `.env` and set:
   - **`GEMINI_API_KEY`** — from [Google AI Studio](https://aistudio.google.com/app/apikey) (Lumi chat + Skin & Hair vision in `TFLiteAnalysisService` / `GeminiChatService`).
   - **`OPENROUTER_API_KEY`** — from [OpenRouter](https://openrouter.ai/keys) (Hair **Style Match** screen only).
3. Install and run on a device/simulator using a **full** build so `--dart-define` is applied, e.g.:
   ```bash
   ./ios_quick_run.sh
   ```
   or:
   ```bash
   flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY --dart-define=OPENROUTER_API_KEY=YOUR_KEY
   ```
   Hot reload does **not** refresh API keys; change `.env` and run **`flutter run` again** (or the script above).

**If markers run without any keys:** the app still runs; features fall back or show setup hints (e.g. offline chat text, pixel/TFLite fallbacks for analysis, Style Match asks for OpenRouter). Live try‑on and most shopping flows do not need these keys.

**For your report / Viva:** state that secrets are supplied via `.env` (from `.env.example`) or `--dart-define`, and are excluded from version control by design.

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
