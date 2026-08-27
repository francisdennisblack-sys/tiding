# Tiding branded first-signup email

This setup sends a custom welcome email the moment a new Firebase Auth user is created.

## What it does

- triggers on `functions.auth.user().onCreate`
- sends a branded email with your logo
- displays exactly: `Welcome to Tiding.`
- keeps the standard Firebase email verification flow in place
- adds a callable function `sendBrandedPasswordResetEmail` to send a Tiding-branded reset email with a real reset hyperlink

## Required setup

1. Create a Firebase project and enable Email/Password authentication.
2. Install the Firebase CLI if needed.
3. Add a SendGrid API key.
4. Verify the sender email in SendGrid.
5. Set your logo URL as a public image URL.
6. Set `RESET_PAGE_URL` to your hosted Tiding reset page (for example the page in `BackendImplementation/tiding-reset-page`).

## Local env example

Copy `.env.example` to `.env` and fill in real values.

```bash
cp .env.example .env
```

## Deploy

```bash
npm install
firebase login
firebase use YOUR_PROJECT_ID
firebase deploy --only functions
```

## Notes

- The app already sends the standard Firebase verification email on signup.
- This function adds the branded welcome email as a second, custom message.
- The body is intentionally minimal: the logo is displayed above the exact text `Welcome to Tiding.`
- For password resets, the correct production pattern is Firebase Auth reset emails with `ActionCodeSettings` and `handleCodeInApp = true`, plus a branded custom email template or a SendGrid/Resend template if you want the logo in the reset email.

## Reset-email strategy

The app now calls the callable function `sendBrandedPasswordResetEmail` first. That function:

- generates a secure Firebase reset link with Admin SDK
- extracts the `oobCode`
- builds a hyperlink to your branded reset page
- sends the email through SendGrid using Tiding branding

If the function is unavailable, the iOS app falls back to Firebase default reset email to keep account recovery working.

### Branded reset deploy checklist

1. Set function env vars (`SENDGRID_API_KEY`, `FROM_EMAIL`, `APP_LOGO_URL`, `RESET_PAGE_URL`).
2. Deploy functions from this folder.
3. Verify sender domain in SendGrid.
4. Make sure `RESET_PAGE_URL` is publicly reachable.

Use this fallback-safe client call:

```swift
let mode = try await FirebaseSpotService.shared.sendPasswordReset(email: email)
```

This lets the link reopen the app when the user taps it, which is the best iOS strategy for a password-reset flow. If you want the logo in the actual reset email itself, use a branded template in Firebase or a provider like SendGrid/Resend behind a secure function.

## Minimal email content

The message text is intentionally just:

```
Welcome to Tiding.
```

The HTML version includes the logo image above that text.
