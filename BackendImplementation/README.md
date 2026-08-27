# Backend Implementation Plan

This file covers the backend work that is feasible to start immediately with the current Firebase setup.

## 1) User identity must be authoritative

The real identity should be:
- Firebase Auth UID
- linked to a user document in Firestore
- attached to every created post, media item, and action

The current app already has a strong foundation in FirebaseService.swift for:
- uid-based user creation
- phone sign-in linking
- username validation
- user profile save
- post save reference

Continue in this direction and make every single user action use the auth UID instead of a local-only device ID.

## 2) Use Auth UID as the post owner

Every post record should contain:
- ownerUID
- postID
- contentType
- createdAt
- location
- moderationStatus
- visibility

This is already partly represented in FirebasePostPayload and saveUserPostReference, so the next step is to make all post creation flow use the authenticated UID universally.

## 3) Store a canonical user record

Create a document per user under:
- users/{uid}

Fields should include:
- uid
- username
- displayName
- bio
- profilePhotoURL
- phoneNumber
- createdAt
- updatedAt
- savedPostIDs
- flaggedPostIDs
- postedPostIDs
- areaHistory

This is already in FirebaseUserAccountRecord and the saveUserProfile flow.

## 4) Enforce username uniqueness server-side

The app already has:
- normalizeUsername
- isValidUsername
- checkUsernameAvailability
- reserveUsername

This is the correct approach. Keep using this and do not allow the client to be the only source of truth.

## 5) Build phone-number ownership logic

The current code already supports:
- sendPhoneCode(to:)
- linkOrSignInPhoneNumber(...)

This should be treated as the first version of a real account recovery and account ownership system.

Next steps:
- verify old and new phone numbers
- permit number change only after re-verification
- persist phoneNumber on the user doc
- require the same account to stay linked across sign-ins

## 6) Attach phone account to the same user profile

When a user signs in or verifies a phone number:
- use the same Auth UID
- update the user document with the phone number
- keep the account history in a verification log if the number changes

This is necessary for long-term account continuity.

## 7) Add actual live engagement tracking

The app needs server-side counters for:
- impressionCount
- viewCount
- dwellTimeSeconds
- uniqueViewers
- likeCount
- saveCount
- shareCount
- videoWatchPercentage

These counters should update on post documents, not just client state.

## 8) Create a trending score pipeline

Define a post score from:
- unique view count
- dwell time
- watch completion
- saves/shares
- recency

A good base formula is:
- score = weightedViews + weightedDwell + weightedCompletion + weightedSaves + weightedShares - penalties

Keep score updates on the backend so they cannot be manipulated by a client.

## 9) Fix the video-specific save flow

The current app has a valid selected-video state, but the real requirement is:
- pick video
- upload to storage
- save video URL to draft/post
- show the actual selected video in the create-video section
- prevent it from falling back to a gray placeholder

This requires a backend-aware flow where the uploaded URL is attached immediately to the draft and final post document.

## 10) Finish profile photo persistence

The app already has profile photo caching and a profile photo picker, but the real requirement is:
- upload photo
- save URL to user doc
- fetch from user doc on app launch
- update both the settings page and profile view from the same stored URL
- keep the same photo in all user-related references

## 11) Search users should use real user records

The search UX should query a real user list from Firestore, not only mock profiles.

Each result should include:
- userID
- username
- displayName
- profilePhotoURL
- followerCount
- followingCount
- followRelation

Then render:
- avatar
- username
- name
- follow button

## 12) Moderation should be the backend gate

Before a post is public:
- text is checked
- media is checked
- links are checked
- audio transcripts are checked
- result becomes approved, rejected, or needs_review

This is the correct system for:
- racism
- hate speech
- nudity
- sexual content
- harassment
- threats

## 13) Start building the production sequence

The next real work order should be:
1. finish the auth-to-user-record link
2. make the user doc authoritative
3. make every post attach ownerUID
4. fix real video upload and preview
5. fix profile photo sync
6. implement search users with real records
7. add score tracking and trend pipeline
8. add moderation gate to post publish

## 14) Validation checklist

Before launch, verify:
- same user can sign back in with same account
- every post has ownerUID
- usernames are unique
- profile photo updates everywhere
- selected video persists and shows in post composer
- score increases from real views
- moderation rejects unsafe content
- search shows real users with follow states

This is the next chunk of work that can be built now without waiting for the whole product to be finished.
