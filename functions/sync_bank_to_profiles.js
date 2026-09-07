// One-off: copy bank details from the payslips onto the staff profiles.
//
// Run from the functions folder, which already has firebase-admin:
//   cd functions
//   node sync_bank_to_profiles.js            (dry run)
//   node sync_bank_to_profiles.js --apply    (write)
//   node sync_bank_to_profiles.js --apply --only-empty
//
// Needs a service account key at functions/serviceAccount.json
// (Firebase Console -> Project settings -> Service accounts -> Generate key).

const path = require('path');
const admin = require('firebase-admin');

const apply = process.argv.includes('--apply');
const onlyEmpty = process.argv.includes('--only-empty');

admin.initializeApp({
  credential: admin.credential.cert(
      require(path.join(__dirname, 'serviceAccount.json'))),
});

const db = admin.firestore();

function clean(v) {
  return (v === null || v === undefined) ? '' : String(v).trim();
}

(async () => {
  const [payslips, users] = await Promise.all([
    db.collection('payslips').get(),
    db.collection('users').get(),
  ]);

  // Newest payslip wins when someone has several.
  const bank = new Map();
  const issuedAt = new Map();

  payslips.forEach((doc) => {
    const d = doc.data();
    const username = clean(d.username);
    if (!username) return;

    const details = {
      bankName: clean(d.bankName),
      accountNumber: clean(d.accountNumber),
      accountHolderName: clean(d.accountHolderName),
    };
    if (!details.bankName && !details.accountNumber &&
        !details.accountHolderName) {
      return;
    }

    const when = d.issuedDate && d.issuedDate.toMillis ?
      d.issuedDate.toMillis() : 0;
    if (!bank.has(username) || when >= (issuedAt.get(username) || 0)) {
      bank.set(username, details);
      issuedAt.set(username, when);
    }
  });

  const profiles = new Map();
  users.forEach((doc) => {
    const username = clean(doc.data().username);
    if (username) profiles.set(username, doc);
  });

  let updated = 0;
  let unchanged = 0;
  const noProfile = [];

  for (const [username, details] of bank) {
    const doc = profiles.get(username);
    if (!doc) {
      noProfile.push(username);
      continue;
    }

    const current = doc.data();
    const changes = {};

    for (const field of
      ['bankName', 'accountNumber', 'accountHolderName']) {
      const value = details[field];
      if (!value) continue;
      const existing = clean(current[field]);
      if (onlyEmpty && existing) continue;
      if (existing === value) continue;
      changes[field] = value;
    }

    if (Object.keys(changes).length === 0) {
      unchanged++;
      continue;
    }

    console.log(`${apply ? 'UPDATE' : 'would update'}  @${username}`,
        JSON.stringify(changes));
    if (apply) await doc.ref.update(changes);
    updated++;
  }

  console.log('');
  console.log(`payslip accounts : ${bank.size}`);
  console.log(`${apply ? 'updated' : 'to update'}      : ${updated}`);
  console.log(`already correct  : ${unchanged}`);
  if (noProfile.length) {
    console.log(`no profile for   : ${noProfile.join(', ')}`);
  }
  if (!apply) console.log('\nDry run. Re-run with --apply to write.');

  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
