# Implementation Notes

## Current baseline

The project already has the right foundation in FirebaseService.swift for:
- Firebase Auth
- username normalization
- unique username reservation
- user profile save
- phone-number linking
- post save references

## What can be done now in code

### A) Use auth UID everywhere
- Replace any local or device-generated user ID in content creation.
- When a post is created, include the current authenticated user UID.
- Add a server-side check that the post author matches the signed-in user.

### B) Keep the selected video URL live in the composer state
- When a video is picked, upload it and store the URL immediately.
- Keep the selected draft video URL in memory and in the final post payload.
- Remove gray placeholder logic if a valid video URL exists.

### C) Save profile photo to the user document
- Upload the profile image to Firebase Storage.
- Save the returned URL to the user record.
- Update the UI from the Firestore user data instead of local-only state.

### D) Turn search users into real-user queries
- Build query fields for username, displayName, and profilePhotoURL.
- Query Firestore users by prefix or normalized username.
- Keep the display consistent with the follow state.

### E) Add moderation status to each post
- Add moderationStatus: pending | approved | rejected | flagged
- Do not publish posts with unsafe or ambiguous result.
- Keep a moderation review list for flagged content.

## Suggested next code tickets

1. Auth-to-user-record binding
2. Post ownerUID enforcement
3. Real video save pipeline
4. Profile photo persistence
5. Search users from Firestore
6. Live score counters
7. Moderation status + review queue

## Recommended sequence

1. User identity and account continuity
2. Post ownership and save flow
3. Video upload and preview
4. Profile photo and account data sync
5. Search + follow + usernames
6. Score + engagement
7. Moderation

This keeps the work buildable in layers without breaking the app.
