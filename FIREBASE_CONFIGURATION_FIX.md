# Firebase CONFIGURATION_NOT_FOUND Error Fix

## Current Error
`CONFIGURATION_NOT_FOUND` error occurs when Firebase can't find the proper project configuration.

## Root Cause
The Firebase project `finalyearproject-45e32` either:
1. Doesn't exist
2. Doesn't have Authentication enabled
3. Has incorrect configuration

## Step-by-Step Fix

### 1. Verify Firebase Project Exists
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Check if project `finalyearproject-45e32` exists
3. If not, create a new project

### 2. Enable Authentication
1. In Firebase Console, go to **Authentication**
2. Click **Get Started**
3. Go to **Sign-in method** tab
4. Enable **Email/Password** provider
5. Enable **Google** provider (optional)

### 3. Get Correct Configuration
1. Go to **Project Settings** (gear icon)
2. Scroll to **Your apps** section
3. Click **Add app** → **Android**
4. Enter package name: `com.example.virtual_tryon_makeup`
5. Download `google-services.json`
6. Replace the current file

### 4. Regenerate Firebase Options
Run this command to regenerate Firebase configuration:
```bash
flutterfire configure --project=finalyearproject-45e32
```

### 5. Alternative: Create New Project
If the current project has issues:

1. Create new Firebase project
2. Enable Authentication
3. Add Android app with package name: `com.example.virtual_tryon_makeup`
4. Download `google-services.json`
5. Run `flutterfire configure --project=YOUR_NEW_PROJECT_ID`

## Quick Test Commands

```bash
# Clean and rebuild
flutter clean
flutter pub get

# Check Firebase connection
flutter run --verbose

# Regenerate Firebase config
flutterfire configure
```

## Expected Results
After fixing:
- No more `CONFIGURATION_NOT_FOUND` errors
- Email/password signup should work
- Users should appear in Firebase Console → Authentication → Users

## Troubleshooting
- **Error persists**: Create new Firebase project
- **Still failing**: Check internet connection
- **Auth not working**: Verify Authentication is enabled in Firebase Console
