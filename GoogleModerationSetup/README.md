# Google Moderation Setup Plan

This is the direct setup plan for getting moderation working for text, images, video, audio, and links using Google services.

## 1) Open the main Google Cloud page

Open:
https://console.cloud.google.com/

This is the main dashboard where you create the project, enable APIs, and manage billing.

## 2) Create a new Google Cloud project

Create a project named something like:
- Spot-Moderation
- Spot-Production
- Spot-Content-Moderation

Keep this project separate from your app’s general Firebase project if you want cleaner billing and moderation isolation.

## 3) Open the Google Cloud billing page

Open:
https://console.cloud.google.com/billing

You need a billing account connected to the project before enabling many Google AI and moderation services.

## 4) Open the Firebase console

Open:
https://console.firebase.google.com/

Use the same Google account that owns your app project, and make sure your iOS app is linked to Firebase.

## 5) Open the Firebase project settings page

Open:
https://console.firebase.google.com/project/<your-project-id>/settings/general

You will need these values:
- iOS bundle identifier
- App nickname
- Firebase SDK config
- Google-services info

## 6) Confirm your iOS bundle identifier

Your app bundle identifier is:
- Lane-Apps.Spot

Use this in Firebase and Google Cloud setup when asked for the iOS app bundle identifier.

## 7) Open the Firebase iOS app registration page

Open:
https://console.firebase.google.com/project/<your-project-id>/settings/general

Then register the app with:
- iOS bundle ID: Lane-Apps.Spot
- App nickname: Spot

This is the app identity Firebase uses for your iOS project.

## 8) Open the Google Cloud APIs page

Open:
https://console.cloud.google.com/apis/dashboard

Enable these APIs for moderation:
- Cloud Vision API
- Video Intelligence API
- Cloud Translation API (optional, useful for transcript checks)
- Firebase Admin SDK / Firebase services (if you use Firebase functions)
- Cloud Functions API (if your moderation runs server-side)

## 9) Open the Google Cloud AI / Vertex AI page

Open:
https://console.cloud.google.com/vertex-ai

If you want text moderation for captions and transcripts, set up Vertex AI and use a moderation or safety model. This is for:
- hate speech
- racism
- slurs
- sexual content
- harassment
- unsafe text

## 10) Open the Google Cloud IAM / service accounts page

Open:
https://console.cloud.google.com/iam-admin/serviceaccounts

Create a service account for the backend moderation service. You will want:
- Cloud Vision User
- Video Intelligence User
- Firebase Admin privileges
- Storage access if the moderation backend reads uploaded files

Create a JSON key and save it somewhere secure.

## 11) Open the Google Cloud Storage page

Open:
https://console.cloud.google.com/storage

Create a bucket for:
- uploaded media
- processed moderation results
- flagged content logs
- temporary moderation artifacts

This is where post media can live before it is approved.

## 12) Open your Firebase project’s iOS config page

Open:
https://console.firebase.google.com/project/<your-project-id>/settings/general

Download the iOS config file if needed:
- GoogleService-Info.plist

You will also want:
- project ID
- API key
- app ID
- client ID
- bundle ID

## 13) Open the Google Cloud project settings page

Open:
https://console.cloud.google.com/projectselector2/home/dashboard

You’ll need the following information later:
- project ID
- project number
- billing status
- service account email
- API enablement status

## 14) Open the Firebase Auth page

Open:
https://console.firebase.google.com/project/<your-project-id>/authentication

Turn on:
- Email/Password auth if you use it
- or whichever auth method you want

Moderation should be tied to authenticated users so you can flag and track unsafe posts by user.

## 15) Open the Firebase Firestore page

Open:
https://console.firebase.google.com/project/<your-project-id>/firestore

Create the collections for moderation:
- posts
- moderationQueue
- reports
- users
- flaggedContent

Each post should store moderation status like:
- pending
- approved
- rejected
- flagged
- needs_review

## 16) Open the Firebase Storage page

Open:
https://console.firebase.google.com/project/<your-project-id>/storage

Configure storage rules for:
- authenticated uploads only
- restricted access to private or moderated content
- clear separation between approved and rejected media

## 17) Open the Cloud Functions page

Open:
https://console.cloud.google.com/functions

Set up a moderation function that is triggered when a post is created.

This function should:
- read the post text
- check image/video/audio uploads
- call Google moderation APIs
- set the moderation status
- reject unsafe posts
- move questionable content into a review queue

## 18) Open your project’s app settings in Xcode

Open the app target in Xcode and check:
- Bundle Identifier: Lane-Apps.Spot
- Team
- Signing & Capabilities
- Firebase app configuration

This ensures your app can connect to Firebase and Google services correctly.

## Required settings and app info

Use these values:

- Bundle Identifier: Lane-Apps.Spot
- App Name: Spot
- Firebase Project ID: your Firebase project ID
- Google Cloud Project ID: your Google Cloud project ID
- Firebase App ID: from Firebase General settings
- Google Cloud service account JSON: generated from IAM service account
- Storage bucket: your Firebase storage bucket
- Firestore database: your project Firestore database

## Minimum moderation checklist

You should set up these before launch:
- text moderation
- image moderation
- video moderation
- audio moderation via transcript scan
- link/domain checks
- human review queue
- user reporting
- rejection logic
- approved-only publishing

## Quick note about the actual Google links

These are the main pages you need to open in order:

1. Google Cloud Console: https://console.cloud.google.com/
2. Google Cloud Billing: https://console.cloud.google.com/billing
3. Google Cloud APIs: https://console.cloud.google.com/apis/dashboard
4. Vertex AI: https://console.cloud.google.com/vertex-ai
5. Service Accounts: https://console.cloud.google.com/iam-admin/serviceaccounts
6. Storage: https://console.cloud.google.com/storage
7. Firebase Console: https://console.firebase.google.com/
8. Firebase Project Settings: https://console.firebase.google.com/project/<your-project-id>/settings/general
9. Firebase Authentication: https://console.firebase.google.com/project/<your-project-id>/authentication
10. Firebase Firestore: https://console.firebase.google.com/project/<your-project-id>/firestore
11. Firebase Storage: https://console.firebase.google.com/project/<your-project-id>/storage
12. Cloud Functions: https://console.cloud.google.com/functions

## Final instruction

When you’re ready, do this in order:
1. Create the Google Cloud project
2. Enable billing
3. Enable the required APIs
4. Create the service account
5. Connect Firebase to the same app
6. Add moderation logic in backend functions
7. Test with real content samples
8. Launch with restrictive rejection rules

This is the path I would follow to get moderation working for racism, hate speech, nudity, and explicit content.
