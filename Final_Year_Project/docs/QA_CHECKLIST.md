# La Vogue Vista — QA checklist

Use this for **manual regression** before demos, submissions, or releases. Tick `[ ]` → `[x]` as you go.  
Record **device**, **OS**, **commit SHA**, and **debug vs release** at the top of each run.

## Session header

| Field        | Value |
|-------------|--------|
| Date        |       |
| Tester      |       |
| Device / OS |       |
| Build       |       |

## Automated (run first)

```bash
cd Final_Year_Project
./scripts/qa_automated.sh
```

Or manually:

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

- [ ] `flutter analyze` — **no errors** (infos/warnings are non-fatal with flags above; fix any `error •` lines if they appear)
- [ ] `flutter test` — all green

## A. Cold start & auth

- [ ] First launch after install: no red-screen crash
- [ ] Sign in with valid user → lands on dashboard
- [ ] Wrong password → clear error, no crash
- [ ] Sign out → returns to login / guest flow as designed

## B. Dashboard & navigation

- [ ] Main sections open from dashboard / drawer / tabs (your actual UX)
- [ ] Android **back** / iOS **swipe back** does not trap user on blank screen

## C. Live try-on (native camera)

- [ ] Grant camera → preview visible, not black
- [ ] Lip / makeup effect visible and tracks face
- [ ] Change shade / intensity → updates live
- [ ] **Hair colour** mode: effect visible; change colour; leave screen → camera stops / no duplicate session
- [ ] **Hair style** mode: same as above if applicable
- [ ] **Nails** (if enabled on this build): no crash; boxes align roughly with fingers
- [ ] Deny camera → user sees rationale + path to Settings (if implemented)

## D. Photo / gallery try-on

- [ ] Pick JPEG from gallery → preview + effect
- [ ] iOS: HEIC / “Most Compatible” photo if users use that path
- [ ] **Android:** photo path: export / save still works if you expose it
- [ ] Compare / split UI (if any): slider or mode toggles correctly

## E. Style Match (OpenRouter)

- [ ] With `OPENROUTER_API_KEY` set: upload face photo → recommendations appear
- [ ] Airplane mode ON → graceful error, no uncaught exception
- [ ] Key missing / invalid: banner or error text matches current product copy

## F. AI assistant & analysis (Gemini / TFLite)

- [ ] Chat or analysis screen opens
- [ ] With Gemini key: at least one successful completion (or documented fallback)
- [ ] Without key: offline / fallback message, app stable

## G. Shop & payments (if in scope)

- [ ] Browse products, open detail, add to cart
- [ ] Checkout / Stripe **test** path completes or fails with readable message
- [ ] Order confirmation / EmailJS: only if wired in this build

## H. Non-functional

- [ ] **5 min** live try-on: no obvious freeze or memory blow-up
- [ ] Rotate device (if supported): layout acceptable or locked orientation behaves
- [ ] Kill app from task switcher → relaunch → no corrupted persisted state

## I. Release build smoke (optional)

```bash
flutter build apk   # or ios when signing is ready
```

- [ ] Release build completes
- [ ] Install artifact on device → cold start + one live try-on pass

## Bug log (append rows)

| ID | Area | Steps | Expected | Actual | Severity |
|----|------|-------|----------|--------|----------|
| 1  |      |       |          |        |          |

---

**Severity:** Blocker / Major / Minor / Cosmetic.
