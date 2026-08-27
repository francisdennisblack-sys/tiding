const functions = require("firebase-functions");
const admin = require("firebase-admin");
const sgMail = require("@sendgrid/mail");
const { URL } = require("url");

admin.initializeApp();

if (process.env.SENDGRID_API_KEY) {
  sgMail.setApiKey(process.env.SENDGRID_API_KEY);
}

function buildBrandedResetURL(firebaseResetLink) {
  const resetPageURL = process.env.RESET_PAGE_URL || "https://tiding.app/reset-password";
  try {
    const parsedFirebaseLink = new URL(firebaseResetLink);
    const oobCode = parsedFirebaseLink.searchParams.get("oobCode");
    if (!oobCode) {
      return firebaseResetLink;
    }

    const brandedLink = new URL(resetPageURL);
    brandedLink.searchParams.set("mode", "resetPassword");
    brandedLink.searchParams.set("oobCode", oobCode);
    return brandedLink.toString();
  } catch {
    return firebaseResetLink;
  }
}

function buildPasswordResetEmailHTML({ logoUrl, resetURL }) {
  return `
    <div style="background:#f4f6fb;padding:32px 0;font-family:Arial,Helvetica,sans-serif;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;">
        <tr>
          <td style="padding:32px 32px 12px; text-align:center;">
            <img src="${logoUrl}" alt="Tiding logo" style="max-width:180px;height:auto;display:block;margin:0 auto 12px;" />
          </td>
        </tr>
        <tr>
          <td style="padding:8px 32px 16px;text-align:center;">
            <div style="font-size:24px;line-height:1.4;font-weight:700;color:#101828;">Reset your Tiding password</div>
          </td>
        </tr>
        <tr>
          <td style="padding:0 32px 18px;text-align:center;">
            <a href="${resetURL}" style="display:inline-block;padding:12px 20px;border-radius:10px;background:#1b4dff;color:#ffffff;text-decoration:none;font-weight:700;">Reset Password</a>
          </td>
        </tr>
      </table>
    </div>
  `;
}

exports.sendBrandedPasswordResetEmail = functions.https.onCall(async (data) => {
  const rawEmail = typeof data?.email === "string" ? data.email : "";
  const email = rawEmail.trim().toLowerCase();
  if (!email) {
    throw new functions.https.HttpsError("invalid-argument", "Email is required.");
  }

  const fromEmail = process.env.FROM_EMAIL || "welcome@tiding.app";
  const logoUrl = process.env.APP_LOGO_URL || "https://example.com/tiding-logo.png";

  try {
    const firebaseResetLink = await admin.auth().generatePasswordResetLink(email);
    const resetURL = buildBrandedResetURL(firebaseResetLink);

    const msg = {
      to: email,
      from: fromEmail,
      subject: "Reset your Tiding password",
      text: `Reset your Tiding password: ${resetURL}\n\nIf the button does not work, copy and paste this link into your browser: ${resetURL}`,
      html: `
        <div style="background:#f4f6fb;padding:32px 0;font-family:Arial,Helvetica,sans-serif;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;">
            <tr>
              <td style="padding:32px 32px 12px; text-align:center;">
                <img src="${logoUrl}" alt="Tiding logo" style="max-width:180px;height:auto;display:block;margin:0 auto 12px;" />
              </td>
            </tr>
            <tr>
              <td style="padding:8px 32px 12px;text-align:center;">
                <div style="font-size:24px;line-height:1.4;font-weight:700;color:#101828;">Reset your Tiding password</div>
              </td>
            </tr>
            <tr>
              <td style="padding:0 32px 16px;text-align:center;">
                <a href="${resetURL}" style="display:inline-block;padding:12px 20px;border-radius:10px;background:#1b4dff;color:#ffffff;text-decoration:none;font-weight:700;">Reset Password</a>
              </td>
            </tr>
            <tr>
              <td style="padding:0 32px 24px;text-align:center;">
                <a href="${resetURL}" style="color:#1b4dff;text-decoration:underline;word-break:break-all;">${resetURL}</a>
              </td>
            </tr>
          </table>
        </div>
      `
    };

    await sgMail.send(msg);
    return { status: "sent" };
  } catch (error) {
    console.error("Failed to send branded password reset email", error);
    throw new functions.https.HttpsError("internal", "Unable to send branded password reset email.");
  }
});

exports.sendWelcomeEmail = functions.auth.user().onCreate(async (user) => {
  if (!user.email) {
    console.log("No email on user record, skipping branded welcome email.");
    return null;
  }

  const fromEmail = process.env.FROM_EMAIL || "welcome@tiding.app";
  const logoUrl = process.env.APP_LOGO_URL || "https://example.com/tiding-logo.png";

  const msg = {
    to: user.email,
    from: fromEmail,
    subject: "Welcome to Tiding",
    text: "Welcome to Tiding.",
    html: `
      <div style="background:#f4f6fb;padding:32px 0;font-family:Arial,Helvetica,sans-serif;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;overflow:hidden;">
          <tr>
            <td style="padding:32px 32px 8px; text-align:center;">
              <img src="${logoUrl}" alt="Tiding logo" style="max-width:180px;height:auto;display:block;margin:0 auto 12px;" />
            </td>
          </tr>
          <tr>
            <td style="padding:8px 32px 32px;text-align:center;">
              <div style="font-size:28px;line-height:1.4;font-weight:700;color:#101828;">Welcome to Tiding.</div>
            </td>
          </tr>
        </table>
      </div>
    `
  };

  try {
    await sgMail.send(msg);
    console.log(`Welcome email sent to ${user.email}`);
    return true;
  } catch (error) {
    console.error("Failed to send welcome email:", error);
    throw error;
  }
});
