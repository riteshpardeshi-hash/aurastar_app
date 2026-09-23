#!/usr/bin/env node
// Grant or revoke the `admin: true` custom auth claim on a Firebase user.
//
// Setup (one time):
//   1. In Firebase console: Project settings → Service accounts → Generate new private key.
//   2. Save the JSON as scripts/serviceAccount.json (gitignored).
//   3. cd scripts && npm install
//
// Usage:
//   node set_admin_claim.js <email>            # grant admin
//   node set_admin_claim.js <email> --revoke   # revoke admin
//
// The target user must sign out and back in for the new token to take effect.

const path = require('path');
const admin = require('firebase-admin');

const KEY_PATH = path.resolve(__dirname, 'serviceAccount.json');

let serviceAccount;
try {
  serviceAccount = require(KEY_PATH);
} catch (e) {
  console.error(`Could not load ${KEY_PATH}.`);
  console.error('Download a service-account JSON from Firebase console and save it there.');
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

async function main() {
  const [, , email, flag] = process.argv;
  if (!email) {
    console.error('Usage: node set_admin_claim.js <email> [--revoke]');
    process.exit(1);
  }
  const grant = flag !== '--revoke';

  const user = await admin.auth().getUserByEmail(email);
  const nextClaims = grant ? { admin: true } : {};
  await admin.auth().setCustomUserClaims(user.uid, nextClaims);

  console.log(`${grant ? 'Granted' : 'Revoked'} admin for ${email} (uid=${user.uid}).`);
  console.log('User must sign out and back in for the new token to take effect.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
