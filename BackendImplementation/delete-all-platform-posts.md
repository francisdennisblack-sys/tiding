# Permanent platform delete flow

This is the production-safe way to clear all platform posts without client-side Firestore permission errors.

## Why the app cannot do this directly

The client's Firestore privileges do not allow a blanket delete of every `posts` document. When you try to do that from the app, Firebase rejects it with:

```
Missing or insufficient permissions
```

The correct fix is to move the destructive operation behind a Firebase callable function with an admin check.

## How it works

- the app calls a callable function named `deleteAllPlatformPosts`
- the function requires an authenticated user
- the function checks a server-side allowlist of admin UIDs from `ALLOWED_ADMIN_UIDS`
- if the UID is allowed, the function deletes all `posts` documents and clears user post arrays

## Deployment

```bash
npm install
firebase login
firebase use YOUR_PROJECT_ID
firebase deploy --only functions
```

Then set:

```bash
firebase functions:config:set admin.allowed_uids="UID_ONE,UID_TWO"
```

or environment variable usage is also supported by the code sample in this repo.

## Required Firebase rules

The callable function is the authority. The client should not be allowed to mass-delete documents directly.

The client-side app should only call the function.
