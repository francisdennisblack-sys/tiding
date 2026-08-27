# Spot Next Steps

## Highest priority order

### 1) Authoritative user identity
- Make the Firebase Auth UID the true owner of the account.
- Keep the user document in Firestore as the canonical profile record.
- Use UID everywhere for posts, follows, saves, and moderation.

### 2) Real user profile record
- Store username, displayName, phoneNumber, profilePhotoURL, and createdAt.
- Keep one source of truth for profile data.
- Never derive the profile from local-only state.

### 3) Username uniqueness enforcement
- Normalize usernames server-side.
- Reject invalid or duplicate usernames.
- Use a usernames collection keyed by the canonical username.

### 4) Phone-number ownership and recovery
- Verify phone number before linking it to the account.
- Add ability to update phone number after verification.
- Preserve account continuity when the user changes number.

### 5) Post ownership and storage
- Every post should have ownerUID.
- Every doc should store moderationStatus, createdAt, and visibility.
- Keep post data in Firestore instead of only app-local arrays.

### 6) Real video upload and preview
- Upload selected video immediately.
- Save the storage URL to the post draft.
- Keep the selected video displayed in the composer rather than reverting to a gray placeholder.

### 7) Profile photo sync
- Upload the image to storage.
- Save the URL in the user profile.
- Display that same URL in both settings and profile.

### 8) Search users from real records
- Query real user records.
- Show avatar, username, name, and follow state.
- Use a real follow relation table or array on each user document.

### 9) Live score and trending
- Track impressions and dwell time server-side.
- Update score from actual engagement events.
- Keep the trending score engine on the backend.

### 10) Moderation gate
- Reject or quarantine racist/hateful content and explicit nudity.
- Use AI moderation on text and media before publication.
- Keep a review queue for ambiguous content.

## Immediate actions to do now

1. Finalize the auth-to-user-doc linkage.
2. Make every post use the real UID.
3. Fix the selected video upload path.
4. Fix profile photo persistence and rehydration.
5. Build user search around real Firestore user accounts.
6. Add a moderation pipeline before posts go live.

## What to avoid
- Do not trust local app state as the source of truth.
- Do not let clients decide if content is safe.
- Do not let usernames be non-unique.
- Do not allow a follow or score system to be manipulated client-side.
