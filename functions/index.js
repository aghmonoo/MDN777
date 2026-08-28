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


// ---------------------------------------------------------------------------
// Push notifications
// ---------------------------------------------------------------------------

const db = () => admin.firestore();

/** Collects push tokens, optionally skipping one username. */
async function tokensForAll(excludeUsername) {
  const snap = await db().collection("users").get();
  const tokens = [];
  snap.forEach((doc) => {
    const data = doc.data();
    if (excludeUsername && data.username === excludeUsername) return;
    (data.fcmTokens || []).forEach((t) => {
      if (t) tokens.push({token: t, uid: doc.id});
    });
  });
  return tokens;
}

/** Admins plus Management staff holding a TL or QA position. */
async function tokensForManagement(excludeUsername) {
  const snap = await db().collection("users").get();
  const tokens = [];
  snap.forEach((doc) => {
    const data = doc.data();
    const eligible = data.role === "admin" ||
      (data.department === "Management" &&
       (data.position === "TL" || data.position === "QA"));
    if (!eligible) return;
    if (excludeUsername && data.username === excludeUsername) return;
    (data.fcmTokens || []).forEach((t) => {
      if (t) tokens.push({token: t, uid: doc.id});
    });
  });
  return tokens;
}

/** Collects push tokens for a list of usernames. */
async function tokensForUsernames(usernames) {
  const wanted = [...new Set(usernames.filter(Boolean))];
  if (!wanted.length) return [];

  const tokens = [];
  for (let i = 0; i < wanted.length; i += 10) {
    const chunk = wanted.slice(i, i + 10);
    const snap = await db()
        .collection("users")
        .where("username", "in", chunk)
        .get();
    snap.forEach((doc) => {
      (doc.data().fcmTokens || []).forEach((t) => {
        if (t) tokens.push({token: t, uid: doc.id});
      });
    });
  }
  return tokens;
}

/** Sends one notification and prunes tokens the device no longer accepts. */
async function push(entries, title, body, data) {
  if (!entries.length) return;

  const tokens = entries.map((e) => e.token);
  const response = await admin.messaging().sendEachForMulticast({
    tokens: tokens,
    notification: {title: title, body: body},
    data: Object.assign({click_action: "FLUTTER_NOTIFICATION_CLICK"}, data || {}),
    android: {priority: "high", notification: {channelId: "staff_connect_high"}},
  });

  const dead = [];
  response.responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error && r.error.code;
    if (code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token") {
      dead.push(entries[i]);
    }
  });

  await Promise.all(dead.map((e) =>
    db().collection("users").doc(e.uid).update({
      fcmTokens: admin.firestore.FieldValue.arrayRemove(e.token),
    }).catch(() => null),
  ));
}

/** Shortens a message for the notification body. */
function preview(text, fallback) {
  const clean = String(text || "").replace(/\s+/g, " ").trim();
  if (!clean) return fallback;
  return clean.length > 120 ? `${clean.slice(0, 117)}...` : clean;
}

/**
 * Sends push notifications for an event the caller has just written.
 *
 * The Firestore database lives in a region without Eventarc trigger support,
 * so the app asks for the notification instead of a background trigger firing.
 * Every branch re-reads the document server-side, so the text that goes out is
 * the text that was stored.
 *
 * data: { type: "announcement" | "group" | "chat" | "payslip_batch", ... }
 */
exports.notify = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const me = String(auth.token.email || "").split("@")[0];
  const type = String(request.data.type || "");

  const isAdmin = async () => {
    const snap = await db().collection("users").doc(auth.uid).get();
    return snap.exists && snap.data().role === "admin";
  };

  if (type === "announcement") {
    if (!(await isAdmin())) {
      throw new HttpsError("permission-denied", "Admin only.");
    }
    const id = String(request.data.announcementId || "");
    const doc = await db().collection("announcements").doc(id).get();
    if (!doc.exists) throw new HttpsError("not-found", "Announcement missing.");
    const data = doc.data();

    await push(
        await tokensForAll(me),
        data.title || "New announcement",
        preview(data.body, "New announcement"),
        {type: "announcement", id: id},
    );
    return {ok: true};
  }

  if (type === "group") {
    const groupId = String(request.data.groupId || "general");
    const msgId = String(request.data.msgId || "");
    const doc = await db()
        .collection("groups").doc(groupId)
        .collection("messages").doc(msgId)
        .get();
    if (!doc.exists) throw new HttpsError("not-found", "Message missing.");

    const data = doc.data();
    if (data.senderId !== me) {
      throw new HttpsError("permission-denied", "Not your message.");
    }

    const audience = groupId === "management" ?
      await tokensForManagement(me) :
      await tokensForAll(me);

    const label = groupId === "management" ? "Management" : "group chat";

    await push(
        audience,
        `${data.senderName || me} - ${label}`,
        preview(data.text, "Sent an attachment"),
        {type: "group", groupId: groupId},
    );
    return {ok: true};
  }

  if (type === "chat") {
    const chatId = String(request.data.chatId || "");
    const msgId = String(request.data.msgId || "");

    const chat = await db().collection("chats").doc(chatId).get();
    if (!chat.exists) throw new HttpsError("not-found", "Chat missing.");

    const participants = chat.data().participants || [];
    if (!participants.includes(me)) {
      throw new HttpsError("permission-denied", "Not in this chat.");
    }

    const doc = await db()
        .collection("chats").doc(chatId)
        .collection("messages").doc(msgId)
        .get();
    if (!doc.exists) throw new HttpsError("not-found", "Message missing.");

    const data = doc.data();
    if (data.senderId !== me) {
      throw new HttpsError("permission-denied", "Not your message.");
    }

    const others = participants.filter((p) => p && p !== me);
    await push(
        await tokensForUsernames(others),
        data.senderName || me,
        preview(data.text, "Sent an attachment"),
        {type: "chat", chatId: chatId},
    );
    return {ok: true};
  }

  if (type === "payslip_batch") {
    if (!(await isAdmin())) {
      throw new HttpsError("permission-denied", "Admin only.");
    }
    const id = String(request.data.batchId || "");
    const doc = await db().collection("payslip_batches").doc(id).get();
    if (!doc.exists) throw new HttpsError("not-found", "Batch missing.");

    await push(
        await tokensForAll(me),
        "Payslips available",
        `Your payslip for ${doc.data().month || "this period"} is ready.`,
        {type: "payslip", id: id},
    );
    return {ok: true};
  }

  throw new HttpsError("invalid-argument", `Unknown type: ${type}`);
});


/** True when the profile may use the management group. */
function isManagementProfile(data) {
  return data.role === "admin" ||
    (data.department === "Management" &&
     (data.position === "TL" || data.position === "QA"));
}

/**
 * Lists the members of a group.
 *
 * Employees cannot read other staff profiles directly, so the roster is
 * assembled server-side and trimmed to the fields the chat UI needs.
 *
 * data: { groupId: "general" | "management" }
 */
exports.listGroupMembers = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const groupId = String(request.data.groupId || "general");

  const meSnap = await db().collection("users").doc(auth.uid).get();
  if (!meSnap.exists) {
    throw new HttpsError("permission-denied", "No staff profile.");
  }

  if (groupId === "management" && !isManagementProfile(meSnap.data())) {
    throw new HttpsError("permission-denied", "Not a member of this group.");
  }

  const snap = await db().collection("users").get();
  const members = [];
  snap.forEach((doc) => {
    const d = doc.data();
    if (!d.username) return;
    if (groupId === "management" && !isManagementProfile(d)) return;
    members.push({
      username: d.username,
      displayName: d.displayName || d.username,
      role: d.role || "employee",
      department: d.department || "",
      position: d.position || "",
    });
  });

  members.sort((a, b) => a.displayName.localeCompare(b.displayName));
  return {members: members};
});
