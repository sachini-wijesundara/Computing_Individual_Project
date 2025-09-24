# Firebase Google Sign-In Fix Guide

## Current Issue
Google Sign-In is failing with error code 10, which means the OAuth client configuration is missing or incorrect.

## Steps to Fix

### 1. Get Your Actual OAuth Client IDs from Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: `finalyearproject-45e32`
3. Go to **Project Settings** (gear icon)
4. Scroll down to **Your apps** section
5. Click on your Android app: `com.example.virtual_tryon_makeup`
6. Click **Download google-services.json** - this will have the correct OAuth client IDs

### 2. Enable Google Sign-In Authentication

1. In Firebase Console, go to **Authentication** > **Sign-in method**
2. Enable **Google** provider
3. Add your project's **Web SDK configuration**:
   - Go to **Project Settings** > **General** tab
   - Scroll to **Your apps** section
   - Find the **Web app** (or create one if it doesn't exist)
   - Copy the **Web API key** and **Project ID**

### 3. Update google-services.json

Replace the current `android/app/google-services.json` with the one downloaded from Firebase Console. The file should contain:

```json
{
  "project_info": {
    "project_number": "694949898753",
    "firebase_url": "https://finalyearproject-45e32.firebaseio.com",
    "project_id": "finalyearproject-45e32",
    "storage_bucket": "finalyearproject-45e32.firebasestorage.app"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:694949898753:android:0259add168620ba92dae00",
        "android_client_info": {
          "package_name": "com.example.virtual_tryon_makeup"
        }
      },
      "oauth_client": [
        {
          "client_id": "YOUR_ACTUAL_ANDROID_CLIENT_ID.apps.googleusercontent.com",
          "client_type": 1,
          "android_info": {
            "package_name": "com.example.virtual_tryon_makeup",
            "certificate_hash": "YOUR_ACTUAL_CERTIFICATE_HASH"
          }
        },
        {
          "client_id": "YOUR_ACTUAL_WEB_CLIENT_ID.apps.googleusercontent.com",
          "client_type": 3
        }
      ],
      "api_key": [
        {
          "current_key": "AIzaSyBRcKSKNQBr-LYuaMHSufhg3xJ3UuQMo2c"
        }
      ],
      "services": {
        "appinvite_service": {
          "other_platform_oauth_client": [
            {
              "client_id": "YOUR_ACTUAL_WEB_CLIENT_ID.apps.googleusercontent.com",
              "client_type": 3
            }
          ]
        }
      }
    }
  ],
  "configuration_version": "1"
}
```

### 4. Test Email/Password Authentication First

Before fixing Google Sign-In, test if email/password authentication works:

1. Run the app: `flutter run`
2. Try to create an account with email/password
3. Check Firebase Console > Authentication > Users to see if the user was created

### 5. Alternative: Disable Google Sign-In Temporarily

If you want to test the app without Google Sign-In, you can comment out the Google Sign-In button in the UI:

```dart
// Comment out the Google Sign-In button temporarily
// Container(
//   width: double.infinity,
//   height: 52,
//   child: OutlinedButton(
//     // ... Google Sign-In button code
//   ),
// ),
```

## Quick Test Commands

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run

# Check if Firebase is properly configured
flutter doctor
```

## Expected Results

After fixing:
- Email/password sign-up should work
- Email/password sign-in should work
- Google Sign-In should work (after proper OAuth setup)
- Users should appear in Firebase Console > Authentication > Users

## Troubleshooting

1. **Error Code 10**: OAuth client not configured properly
2. **Error Code 7**: Network error - check internet connection
3. **Error Code 12501**: User cancelled the sign-in
4. **Error Code 8**: Internal error - check Firebase configuration

## Next Steps

1. Download the correct `google-services.json` from Firebase Console
2. Replace the current file
3. Enable Google Sign-In in Firebase Console
4. Test the authentication flow
5. Check Firebase Console for user creation
