const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const firebaseConfig = functions.config ? functions.config() : {};

exports.deleteAllPlatformPosts = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "This operation requires an authenticated user."
    );
  }

  const uid = context.auth.uid;
  const allowedAdmins = (process.env.ALLOWED_ADMIN_UIDS || firebaseConfig.admin?.allowed_uids || "")
    .split(",")
    .map(v => v.trim())
    .filter(Boolean);

  if (!allowedAdmins.includes(uid)) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Missing or insufficient permissions to delete all posts on the platform."
    );
  }

  const db = admin.firestore();
  const postsSnapshot = await db.collection("posts").get();
  const userSnapshot = await db.collection("users").get();

  const postBatches = [];
  for (let i = 0; i < postsSnapshot.docs.length; i += 400) {
    postBatches.push(postsSnapshot.docs.slice(i, i + 400));
  }

  for (const chunk of postBatches) {
    const batch = db.batch();
    for (const doc of chunk) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }

  const userBatches = [];
  for (let i = 0; i < userSnapshot.docs.length; i += 400) {
    userBatches.push(userSnapshot.docs.slice(i, i + 400));
  }

  for (const chunk of userBatches) {
    const batch = db.batch();
    for (const doc of chunk) {
      batch.set(doc.ref, {
        postedPostIDs: [],
        savedPostIDs: [],
        flaggedPostIDs: [],
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
    }
    await batch.commit();
  }

  return {
    deletedPosts: postsSnapshot.docs.length,
    resetUsers: userSnapshot.docs.length,
    requestedBy: uid
  };
});
