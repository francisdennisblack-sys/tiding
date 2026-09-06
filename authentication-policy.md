# Firebase Authentication Policy (No Rules File)

Firebase Authentication does not use a `rules` file like Firestore or Storage.
Use this policy in Firebase Console and server checks.

## 1) Providers

Enable only providers your app actually uses:
- Email/Password
- Anonymous (optional; required if your app allows guest usage)
- Phone (only if used)

Disable all unused providers.

## 2) User settings

- Disable account creation from unknown providers.
- Require email verification for sensitive actions (recommended).
- Enable reCAPTCHA/App Check where available.

## 3) Blocking and abuse controls

Use Firebase Auth blocking functions to enforce:
- Allowed email domains (if needed)
- Disposable-email rejection (optional)
- IP/rate abuse heuristics (optional)

## 4) Server-side authorization requirements

In Cloud Functions (callable/HTTP), always verify:
- `context.auth != null`
- `context.auth.uid` matches the owner UID being modified
- Never trust client-sent owner IDs without auth checks

## 5) App-level sign-in state policy

- On sign-out, clear local persisted credentials and signed-in flags.
- Do not auto-restore account sessions when signed-in flag is false.
- Only perform account restore with explicit user intent.

## 6) Optional custom claims

If you need admin moderation tools, add custom claims (for example `admin: true`) and gate privileged operations in backend code.
