const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({region: "asia-southeast1", maxInstances: 10});

const LOGIN_DOMAIN = "staffconnect.app";

async function assertAdmin(request) {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const snap = await admin.firestore().collection("users").doc(auth.uid).get();
  if (!snap.exists || snap.data().role !== "admin") {
    throw new HttpsError("permission-denied", "Admin only.");
  }
  return snap.data().username || auth.token.email.split("@")[0];
}

/**
 * Sets a staff member's login password.
 * data: { username: string, newPassword: string }
 */
exports.adminSetPassword = onCall(async (request) => {
  const actor = await assertAdmin(request);

  const username = String(request.data.username || "").trim().toLowerCase();
  const newPassword = String(request.data.newPassword || "");

  if (!username) {
    throw new HttpsError("invalid-argument", "username is required.");
  }
  if (newPassword.length < 6) {
    throw new HttpsError(
        "invalid-argument", "Password must be at least 6 characters.");
  }

  const email = `${username}@${LOGIN_DOMAIN}`;

  let userRecord;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
  } catch (e) {
    throw new HttpsError("not-found", `No login account for ${email}.`);
  }

  await admin.auth().updateUser(userRecord.uid, {password: newPassword});

  await admin.firestore().collection("password_reset_logs").add({
    username: username,
    uid: userRecord.uid,
    resetBy: actor,
    resetAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {ok: true, uid: userRecord.uid, email: email};
});

/**
 * Deletes a staff member's login account (Firestore profile is handled
 * by the app's own recycle-bin flow).
 * data: { username: string }
 */
exports.adminDeleteAuthUser = onCall(async (request) => {
  await assertAdmin(request);

  const username = String(request.data.username || "").trim().toLowerCase();
  if (!username) {
    throw new HttpsError("invalid-argument", "username is required.");
  }

  const email = `${username}@${LOGIN_DOMAIN}`;
  try {
    const userRecord = await admin.auth().getUserByEmail(email);
    await admin.auth().deleteUser(userRecord.uid);
    return {ok: true, uid: userRecord.uid};
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      return {ok: true, skipped: true};
    }
    throw new HttpsError("internal", e.message);
  }
});
