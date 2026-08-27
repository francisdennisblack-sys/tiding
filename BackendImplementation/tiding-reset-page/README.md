# Tiding password reset page

This is the branded reset page for the Tiding password reset flow.

## Purpose

The Firebase default password reset page is generic and it can show the wrong project name or app branding. This custom page makes the reset experience match Tiding more closely and enforces the same password rules used by the app:

- minimum 8 characters
- at least one uppercase letter
- at least one lowercase letter
- at least one number

## Required setup

1. Create a Firebase Web app config and replace the placeholders in `index.html`.
2. Host this page using Firebase Hosting or another static host.
3. Set the reset link to use your hosted page, for example:

```text
https://your-domain.com/reset-password.html?mode=reset&oobCode=YOUR_OOB_CODE
```

4. Configure your Firebase Auth email action to use that hosted URL as the continue URL.
5. Update the email template in Firebase Authentication or your email provider so it links to the hosted page and shows Tiding branding instead of the project name.

## Notes

- This page uses the Firebase Web SDK and validates the reset code before allowing a new password.
- The page intentionally uses Tiding branding and not the generic project name.
- The link should be a true hyperlink in your email template, not plain text.

## Example Firebase Hosting deploy

```bash
firebase init hosting
firebase deploy --only hosting
```

Then place the generated static files in the hosting public directory and update the reset email URL.
