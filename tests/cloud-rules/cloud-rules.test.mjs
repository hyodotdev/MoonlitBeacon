// Real Firestore rules-emulator tests for legacy + 4.0.0 owned cloud.
//
// Runs ONLY against the Firebase rules emulator supplied by the director
// (firebase-tools + Java + `firebase` and `@firebase/rules-unit-testing`
// packages). This file proves enforcement by execution; the splice check in
// build-combined-rules.mjs is source-only and is not evidence of enforcement.
//
// Run (from the repo root, after the director installs the dependencies):
//   firebase emulators:exec --only firestore \
//     "node --test tests/cloud-rules/cloud-rules.test.mjs"
//
// The combined ruleset is built in memory from firestore.rules (legacy,
// untouched) plus firestore.cloud.addition.rules, so the forbidden
// firestore.rules file is never edited.

import assert from 'node:assert/strict';
import test, { after, before, beforeEach, describe } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';
import { buildCombinedRules } from './build-combined-rules.mjs';

const PROJECT_ID = 'moonlitbeacon-778ee';
const ALICE = 'uid-alice-cloud-001';
const BOB = 'uid-bob-cloud-002';
const CAROL = 'uid-carol-cloud-003';
const DAVE = 'uid-dave-cloud-004';
const ALICE_ID = `MB-${'a'.repeat(32)}`;
const BOB_ID = `MB-${'b'.repeat(32)}`;
const CAROL_ID = `MB-${'c'.repeat(32)}`;
const DAVE_ID = `MB-${'d'.repeat(32)}`;
const HERO = 'res://resources/heroes/warden.tres';

function emulatorHostPort() {
  const raw = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
  const [host, port] = raw.split(':');
  return { host, port: Number(port) };
}

function profileData(uid, publicId) {
  const now = Timestamp.now();
  return {
    uid,
    public_id: publicId,
    schema: 1,
    created_at: now,
    updated_at: now,
  };
}

function reservationData(uid, publicId) {
  return {
    public_id: publicId,
    uid,
    schema: 1,
    created_at: Timestamp.now(),
  };
}

function checkpointData(uid, revision, payload) {
  return {
    uid,
    revision,
    payload,
    schema: 1,
    updated_at: Timestamp.now(),
  };
}

function hallData(publicId, score, hero = HERO) {
  return {
    public_id: publicId,
    hero,
    score,
    cycles: 3,
    release: '4.0.0',
    schema: 1,
    updated_at: Timestamp.now(),
  };
}

function authedFirestore(testEnv, uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

// Atomic registration, the only contract the rules accept: each half
// requires the other after the commit, so sequential half-registration is
// denied on both sides.
async function registerPair(db, uid, publicId) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'mb_profiles_v1', uid), profileData(uid, publicId));
  batch.set(doc(db, 'mb_reservations_v1', publicId),
    reservationData(uid, publicId));
  await assertSucceeds(batch.commit());
}

// Atomic account deletion in plan order: Hall, checkpoint, reservation,
// profile. Missing rows are no-ops, so repeats are idempotent.
async function deleteAccount(db, uid, publicId) {
  const batch = writeBatch(db);
  batch.delete(doc(db, 'mb_hall_v1', publicId));
  batch.delete(doc(db, 'mb_checkpoints_v1', uid));
  batch.delete(doc(db, 'mb_attendance_v1', publicId));
  batch.delete(doc(db, 'mb_reservations_v1', publicId));
  batch.delete(doc(db, 'mb_profiles_v1', uid));
  await assertSucceeds(batch.commit());
}

function adventurerData(uid, publicId, key, display, intro = false) {
  const now = Timestamp.now();
  return {
    public_id: publicId,
    uid,
    name_key: key,
    display,
    intro_complete: intro,
    schema: 1,
    created_at: now,
    updated_at: now,
  };
}

function nameData(key, display, publicId) {
  return {
    name_key: key,
    display,
    public_id: publicId,
    schema: 1,
    created_at: Timestamp.now(),
  };
}

// Atomic name claim, the only contract the rules accept: each half
// requires the other after the commit, exactly like registration.
async function claimName(db, uid, publicId, display) {
  const key = display.toLowerCase();
  const batch = writeBatch(db);
  batch.set(doc(db, 'mb_adventurers_v1', publicId),
    adventurerData(uid, publicId, key, display));
  batch.set(doc(db, 'mb_names_v1', key),
    nameData(key, display, publicId));
  await assertSucceeds(batch.commit());
}

// Atomic named-account deletion in plan order: Hall, name, adventurer,
// checkpoint, reservation, profile.
async function deleteNamedAccount(db, uid, publicId, key) {
  const batch = writeBatch(db);
  batch.delete(doc(db, 'mb_hall_v1', publicId));
  batch.delete(doc(db, 'mb_names_v1', key));
  batch.delete(doc(db, 'mb_adventurers_v1', publicId));
  batch.delete(doc(db, 'mb_checkpoints_v1', uid));
  batch.delete(doc(db, 'mb_attendance_v1', publicId));
  batch.delete(doc(db, 'mb_reservations_v1', publicId));
  batch.delete(doc(db, 'mb_profiles_v1', uid));
  await assertSucceeds(batch.commit());
}

function attendanceData(uid, publicId, install, stamp) {
  return {
    public_id: publicId,
    uid,
    install_id: install,
    last_claim_at: stamp,
    schema: 1,
  };
}

// Seed an old server record without waiting twelve hours. Rules stay
// enforced for every other write; only this setup bypasses them. An
// optional carried pair seeds a chained row; omitting it seeds the
// legacy five-field shape.
async function seedAttendance(publicId, uid, install, date,
    prevDate = null, prevInstall = '') {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const row = attendanceData(uid, publicId, install,
      Timestamp.fromDate(date));
    if (prevDate !== null && prevInstall !== '') {
      row.prev_claim_at = Timestamp.fromDate(prevDate);
      row.prev_install_id = prevInstall;
    }
    await setDoc(doc(db, 'mb_attendance_v1', publicId), row);
  });
}

let testEnv;

before(async () => {
  const { combined } = buildCombinedRules();
  const { host, port } = emulatorHostPort();
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: combined, host, port },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

describe('legacy 3.0.0 contracts stay intact', () => {
  test('scores stay publicly readable and writable with a valid row', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDocs(collection(db, 'scores')));
    await assertSucceeds(setDoc(doc(collection(db, 'scores')), {
      name: 'Momo',
      hero: HERO,
      score: 1200,
      rank: 'A',
      cycles: 2,
      version: '3.0.0',
      at: Timestamp.now(),
    }));
  });

  test('scores reject an invalid hero', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(collection(db, 'scores')), {
      name: 'Momo',
      hero: 'res://resources/heroes/bogus.tres',
      score: 10,
      rank: 'C',
      cycles: 1,
      at: Timestamp.now(),
    }));
  });

  test('analytics accepts a valid event and denies reads', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    const id = `e_${'c'.repeat(40)}`;
    const now = Timestamp.now();
    const expires = Timestamp.fromMillis(now.toMillis() + 86400000);
    await assertSucceeds(setDoc(doc(db, 'analytics_events_v1', id), {
      schema: 1,
      event: 'app_opened',
      client_at: now,
      client_day: '2026-10-02',
      expires_at: expires,
      session_id: 'd'.repeat(32),
      app_version: '3.0.0',
      platform: 'android',
      locale: 'en',
      properties: {},
    }));
    await assertFails(getDoc(doc(db, 'analytics_events_v1', id)));
  });

  test('unknown collections stay denied', async () => {
    const db = authedFirestore(testEnv, ALICE);
    await assertFails(getDoc(doc(db, 'nope', 'x')));
    await assertFails(setDoc(doc(db, 'nope', 'x'), { a: 1 }));
  });
});

describe('profiles: immutable UID-to-public-ID rows', () => {
  test('unauthenticated profile access is denied', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'mb_profiles_v1', ALICE)));
    await assertFails(
      setDoc(doc(db, 'mb_profiles_v1', ALICE), profileData(ALICE, ALICE_ID)),
    );
  });

  test('owner creates and reads, strangers cannot', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(getDoc(doc(alice, 'mb_profiles_v1', ALICE)));
    const bob = authedFirestore(testEnv, BOB);
    await assertFails(getDoc(doc(bob, 'mb_profiles_v1', ALICE)));
    await assertFails(setDoc(
      doc(bob, 'mb_profiles_v1', ALICE), profileData(ALICE, ALICE_ID)));
    await assertFails(getDocs(collection(bob, 'mb_profiles_v1')));
  });

  test('profile ID can never be reassigned or rewritten', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertFails(updateDoc(doc(alice, 'mb_profiles_v1', ALICE),
      { public_id: BOB_ID }));
    await assertFails(setDoc(
      doc(alice, 'mb_profiles_v1', ALICE), profileData(ALICE, BOB_ID)));
  });

  test('owner deletes their profile only with its pair half', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const bob = authedFirestore(testEnv, BOB);
    await assertFails(deleteDoc(doc(bob, 'mb_profiles_v1', ALICE)));
    await assertFails(deleteDoc(doc(alice, 'mb_profiles_v1', ALICE)));
    const batch = writeBatch(alice);
    batch.delete(doc(alice, 'mb_reservations_v1', ALICE_ID));
    batch.delete(doc(alice, 'mb_profiles_v1', ALICE));
    await assertSucceeds(batch.commit());
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_profiles_v1', ALICE)));
    assert.equal(snap.exists(), false);
  });
});

describe('reservations: first claim wins, no takeover', () => {
  test('owner creates, strangers cannot read or take', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const bob = authedFirestore(testEnv, BOB);
    await assertFails(getDoc(doc(bob, 'mb_reservations_v1', ALICE_ID)));
    await assertFails(setDoc(doc(bob, 'mb_reservations_v1', ALICE_ID),
      reservationData(BOB, ALICE_ID)));
    await assertFails(updateDoc(doc(bob, 'mb_reservations_v1', ALICE_ID),
      { uid: BOB }));
  });

  test('reservation rows are immutable and never go alone', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertFails(updateDoc(doc(alice, 'mb_reservations_v1', ALICE_ID),
      { schema: 2 }));
    await assertFails(deleteDoc(doc(alice, 'mb_reservations_v1', ALICE_ID)));
  });
});

describe('checkpoints: private versioned saves', () => {
  test('unauthenticated and cross-owner access denied', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await assertSucceeds(setDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 1, '{"gate":1}')));
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'mb_checkpoints_v1', ALICE)));
    await assertFails(setDoc(doc(anon, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 1, '{"gate":1}')));
    const bob = authedFirestore(testEnv, BOB);
    await assertFails(getDoc(doc(bob, 'mb_checkpoints_v1', ALICE)));
    await assertFails(updateDoc(doc(bob, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 2, '{"gate":2}')));
  });

  test('revisions advance by exactly one', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await assertFails(setDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 2, '{"gate":2}')));
    await assertSucceeds(setDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 1, '{"gate":1}')));
    await assertSucceeds(updateDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 2, '{"gate":2}')));
    await assertFails(updateDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 2, '{"gate":9}')));
    await assertFails(updateDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 4, '{"gate":9}')));
  });

  test('oversized, non-brace, and extra-field payloads denied', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await assertFails(setDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 1, `{"pad":"${'x'.repeat(40000)}"}`)));
    await assertFails(setDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 1, 'not json')));
    await assertFails(setDoc(doc(alice, 'mb_checkpoints_v1', ALICE), {
      ...checkpointData(ALICE, 1, '{"gate":1}'),
      email: 'a@example.com',
    }));
  });

  test('brace-shaped but invalid JSON passes the rules; the client stops it', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    // The server bounds size and brace shape only: it cannot parse JSON, so
    // '{bad}' clears the rules here. Upload and queue paths reject it
    // client-side instead (see test_cloud_checkpoint), and downloads still
    // need the Journey validator before anything is applied.
    await assertSucceeds(setDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 1, '{bad}')));
  });

  test('owner deletes their checkpoint', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await assertSucceeds(setDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 1, '{"gate":1}')));
    await assertSucceeds(deleteDoc(doc(alice, 'mb_checkpoints_v1', ALICE)));
  });
});

describe('hall: public board, owned rows, monotonic scores', () => {
  async function registeredAlice() {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    return alice;
  }

  test('anyone reads, nobody anonymous writes', async () => {
    const alice = await registeredAlice();
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 500)));
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(anon, 'mb_hall_v1', ALICE_ID)));
    await assertSucceeds(getDocs(query(
      collection(anon, 'mb_hall_v1'), orderBy('score', 'desc'), limit(20))));
    await assertFails(setDoc(doc(anon, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
    await assertFails(deleteDoc(doc(anon, 'mb_hall_v1', ALICE_ID)));
  });

  test('writes need the matching pair and valid fields', async () => {
    const bob = authedFirestore(testEnv, BOB);
    await assertFails(setDoc(doc(bob, 'mb_hall_v1', BOB_ID),
      hallData(BOB_ID, 100)));
    await registerPair(bob, BOB, BOB_ID);
    await assertSucceeds(setDoc(doc(bob, 'mb_hall_v1', BOB_ID),
      hallData(BOB_ID, 100)));
    await assertFails(setDoc(doc(bob, 'mb_hall_v1', BOB_ID),
      hallData(BOB_ID, 200, 'res://resources/heroes/bogus.tres')));
    await assertFails(setDoc(doc(bob, 'mb_hall_v1', BOB_ID), {
      ...hallData(BOB_ID, 200),
      email: 'b@example.com',
    }));
  });

  test('scores never decrease, equal retries succeed', async () => {
    const alice = await registeredAlice();
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 500)));
    await assertSucceeds(updateDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 500)));
    await assertSucceeds(updateDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 800)));
    await assertFails(updateDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 799)));
  });

  test('cross-owner writes and deletes denied, owner delete allowed', async () => {
    const alice = await registeredAlice();
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 500)));
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    await assertFails(updateDoc(doc(bob, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 9999)));
    await assertFails(setDoc(doc(bob, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 9999)));
    await assertFails(deleteDoc(doc(bob, 'mb_hall_v1', ALICE_ID)));
    await assertSucceeds(deleteDoc(doc(alice, 'mb_hall_v1', ALICE_ID)));
  });

  test('public rows expose no private fields', async () => {
    const alice = await registeredAlice();
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 500)));
    const anon = testEnv.unauthenticatedContext().firestore();
    const snap = await assertSucceeds(getDoc(doc(anon, 'mb_hall_v1', ALICE_ID)));
    const keys = Object.keys(snap.data() ?? {}).sort();
    assert.deepEqual(keys, [
      'cycles', 'hero', 'public_id', 'release', 'schema', 'score',
      'updated_at',
    ]);
  });

  test('negative control: invalid writes always fail', async () => {
    const alice = await registeredAlice();
    await assertFails(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, -1)));
  });

  test('cycles bound matches the Journey cap (99999)', async () => {
    const alice = await registeredAlice();
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      { ...hallData(ALICE_ID, 500), cycles: 10000 }));
    await assertSucceeds(updateDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      { ...hallData(ALICE_ID, 500), cycles: 99999 }));
    await assertFails(updateDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      { ...hallData(ALICE_ID, 500), cycles: 100000 }));
    await assertFails(updateDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      { ...hallData(ALICE_ID, 2000000001), cycles: 3 }));
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_hall_v1', ALICE_ID)));
    assert.equal(snap.data().cycles, 99999);
    assert.equal(snap.data().score, 500);
  });
});

describe('takeover: reserved IDs cannot be stolen', () => {
  test("director probe: impostor profile and Hall overwrite denied", async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
    const bob = authedFirestore(testEnv, BOB);
    // Probe step 2: a private profile pointing at the owner's reserved ID.
    await assertFails(setDoc(doc(bob, 'mb_profiles_v1', BOB),
      profileData(BOB, ALICE_ID)));
    // Probe step 3: overwriting or deleting the owner's Hall row.
    await assertFails(updateDoc(doc(bob, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 11)));
    await assertFails(setDoc(doc(bob, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 11)));
    await assertFails(deleteDoc(doc(bob, 'mb_hall_v1', ALICE_ID)));
    const anon = testEnv.unauthenticatedContext().firestore();
    const snap = await assertSucceeds(
      getDoc(doc(anon, 'mb_hall_v1', ALICE_ID)));
    assert.equal(snap.data().score, 10);
  });

  test('even a planted impostor profile grants no Hall access', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
    // Simulate a bad row from before the fix: plant it with rules disabled.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const admin = context.firestore();
      await setDoc(doc(admin, 'mb_profiles_v1', BOB),
        profileData(BOB, ALICE_ID));
    });
    const bob = authedFirestore(testEnv, BOB);
    await assertFails(updateDoc(doc(bob, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 11)));
    await assertFails(deleteDoc(doc(bob, 'mb_hall_v1', ALICE_ID)));
  });

  test('orphaned profile with no reservation grants no Hall access', async () => {
    // A profile stranded without its reservation half (the crash state the
    // atomic pair rules exist to prevent) owns nothing until repaired.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const admin = context.firestore();
      await setDoc(doc(admin, 'mb_profiles_v1', CAROL),
        profileData(CAROL, CAROL_ID));
    });
    const carol = authedFirestore(testEnv, CAROL);
    await assertFails(setDoc(doc(carol, 'mb_hall_v1', CAROL_ID),
      hallData(CAROL_ID, 5)));
  });
});

describe('registration pairs: atomic, matched, complete', () => {
  test('atomic batch registration then Hall submit succeeds', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'mb_profiles_v1', ALICE),
      profileData(ALICE, ALICE_ID));
    batch.set(doc(alice, 'mb_reservations_v1', ALICE_ID),
      reservationData(ALICE, ALICE_ID));
    await assertSucceeds(batch.commit());
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
  });

  test('mismatched batch pairs acquire nothing, both directions', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    for (const [profileId, reservationId] of [
      [ALICE_ID, BOB_ID],
      [BOB_ID, ALICE_ID],
    ]) {
      const batch = writeBatch(alice);
      batch.set(doc(alice, 'mb_profiles_v1', ALICE),
        profileData(ALICE, profileId));
      batch.set(doc(alice, 'mb_reservations_v1', reservationId),
        reservationData(ALICE, reservationId));
      await assertFails(batch.commit());
    }
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_profiles_v1', ALICE)));
    assert.equal(snap.exists(), false);
  });

  test('lone halves denied on both sides; atomic pair then Hall works', async () => {
    const carol = authedFirestore(testEnv, CAROL);
    await assertFails(setDoc(doc(carol, 'mb_profiles_v1', CAROL),
      profileData(CAROL, CAROL_ID)));
    await assertFails(setDoc(doc(carol, 'mb_reservations_v1', CAROL_ID),
      reservationData(CAROL, CAROL_ID)));
    await registerPair(carol, CAROL, CAROL_ID);
    await assertSucceeds(setDoc(doc(carol, 'mb_hall_v1', CAROL_ID),
      hallData(CAROL_ID, 5)));
  });

  test('same-batch reservation delete cannot smuggle a profile', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'mb_profiles_v1', ALICE),
      profileData(ALICE, ALICE_ID));
    batch.set(doc(alice, 'mb_reservations_v1', ALICE_ID),
      reservationData(ALICE, ALICE_ID));
    batch.delete(doc(alice, 'mb_reservations_v1', ALICE_ID));
    await assertFails(batch.commit());
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_profiles_v1', ALICE)));
    assert.equal(snap.exists(), false);
  });

  test('harmless set/delete no-op leaves no new document', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    // Setting then deleting the same previously absent profile nets to a
    // missing-row no-op, which the deletion contract permits. The batch
    // succeeds and creates nothing.
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'mb_profiles_v1', ALICE),
      profileData(ALICE, ALICE_ID));
    batch.delete(doc(alice, 'mb_profiles_v1', ALICE));
    await assertSucceeds(batch.commit());
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_profiles_v1', ALICE)));
    assert.equal(snap.exists(), false);
  });

  test('cloud restore: same UID reads back its canonical ID', async () => {
    const first = authedFirestore(testEnv, ALICE);
    await registerPair(first, ALICE, ALICE_ID);
    const second = authedFirestore(testEnv, ALICE);
    const snap = await assertSucceeds(
      getDoc(doc(second, 'mb_profiles_v1', ALICE)));
    assert.equal(snap.data().public_id, ALICE_ID);
  });
});

describe('deletion guards and complete deletion', () => {
  test('pair halves cannot go while the Hall row lives', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
    await assertFails(deleteDoc(doc(alice, 'mb_reservations_v1', ALICE_ID)));
    await assertFails(deleteDoc(doc(alice, 'mb_profiles_v1', ALICE)));
  });

  test('living pair halves go only together, even with no Hall row', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertFails(deleteDoc(doc(alice, 'mb_reservations_v1', ALICE_ID)));
    await assertFails(deleteDoc(doc(alice, 'mb_profiles_v1', ALICE)));
    const batch = writeBatch(alice);
    batch.delete(doc(alice, 'mb_reservations_v1', ALICE_ID));
    batch.delete(doc(alice, 'mb_profiles_v1', ALICE));
    await assertSucceeds(batch.commit());
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_profiles_v1', ALICE)));
    assert.equal(snap.exists(), false);
  });

  test('complete account deletion is one atomic commit', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 1, '{"gate":1}')));
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
    await deleteAccount(alice, ALICE, ALICE_ID);
    for (const [collectionId, id] of [
      ['mb_hall_v1', ALICE_ID],
      ['mb_checkpoints_v1', ALICE],
      ['mb_profiles_v1', ALICE],
    ]) {
      const snap = await assertSucceeds(getDoc(doc(alice, collectionId, id)));
      assert.equal(snap.exists(), false);
    }
    // The freed ID re-registers cleanly: nothing orphaned, nothing stuck.
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 12)));
  });

  test('repeated deletion is idempotent', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
    await deleteAccount(alice, ALICE, ALICE_ID);
    // A second run over already-missing rows still succeeds, so an
    // interrupted deletion resumes instead of wedging on a 403.
    await deleteAccount(alice, ALICE, ALICE_ID);
  });

  test('hall cannot be rewritten while its pair is deleted', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
    const batch = writeBatch(alice);
    batch.update(doc(alice, 'mb_hall_v1', ALICE_ID), hallData(ALICE_ID, 11));
    batch.delete(doc(alice, 'mb_profiles_v1', ALICE));
    batch.delete(doc(alice, 'mb_reservations_v1', ALICE_ID));
    await assertFails(batch.commit());
    const hall = await assertSucceeds(
      getDoc(doc(alice, 'mb_hall_v1', ALICE_ID)));
    assert.equal(hall.data().score, 10);
    const profile = await assertSucceeds(
      getDoc(doc(alice, 'mb_profiles_v1', ALICE)));
    assert.equal(profile.exists(), true);
  });
});

describe('negative control: takeover works only without enforcement', () => {
  test('rules-disabled impostor writes succeed, proving the scenario', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const admin = context.firestore();
      await setDoc(doc(admin, 'mb_profiles_v1', BOB),
        profileData(BOB, ALICE_ID));
      await updateDoc(doc(admin, 'mb_hall_v1', ALICE_ID),
        hallData(ALICE_ID, 11));
    });
    // Without enforcement the attack flips the score, so the takeover
    // suite above can fail: its denials come from the rules, not the setup.
    const anon = testEnv.unauthenticatedContext().firestore();
    const snap = await assertSucceeds(
      getDoc(doc(anon, 'mb_hall_v1', ALICE_ID)));
    assert.equal(snap.data().score, 11);
  });

  test('control: each ownership leg decides identical Hall writes', async () => {
    // Profile half only: the identical Hall write fails for want of the
    // reservation leg. Planting uses disabled rules because lone halves can
    // no longer be created through them.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const admin = context.firestore();
      await setDoc(doc(admin, 'mb_profiles_v1', CAROL),
        profileData(CAROL, CAROL_ID));
      await setDoc(doc(admin, 'mb_reservations_v1', DAVE_ID),
        reservationData(DAVE, DAVE_ID));
    });
    const carol = authedFirestore(testEnv, CAROL);
    await assertFails(setDoc(doc(carol, 'mb_hall_v1', CAROL_ID),
      hallData(CAROL_ID, 5)));
    const dave = authedFirestore(testEnv, DAVE);
    await assertFails(setDoc(doc(dave, 'mb_hall_v1', DAVE_ID),
      hallData(DAVE_ID, 5)));
    // Completing each pair with only the missing half flips both identical
    // writes to allowed, proving each leg of the guard fires.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const admin = context.firestore();
      await setDoc(doc(admin, 'mb_reservations_v1', CAROL_ID),
        reservationData(CAROL, CAROL_ID));
      await setDoc(doc(admin, 'mb_profiles_v1', DAVE),
        profileData(DAVE, DAVE_ID));
    });
    await assertSucceeds(setDoc(doc(carol, 'mb_hall_v1', CAROL_ID),
      hallData(CAROL_ID, 5)));
    await assertSucceeds(setDoc(doc(dave, 'mb_hall_v1', DAVE_ID),
      hallData(DAVE_ID, 5)));
  });
});

describe('adventurer names: atomic claim, one winner', () => {
  test('registered owner claims via one atomic batch, reads own row', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_adventurers_v1', ALICE_ID)));
    assert.equal(snap.data().display, 'Luna');
    assert.equal(snap.data().name_key, 'luna');
    assert.equal(snap.data().intro_complete, false);
    const index = await assertSucceeds(getDoc(doc(alice, 'mb_names_v1', 'luna')));
    assert.equal(index.data().public_id, ALICE_ID);
  });

  test('fresh owner reads an authoritative missing row', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_adventurers_v1', ALICE_ID)));
    assert.equal(snap.exists(), false);
  });

  test('missing-row reads stay denied for others and the unregistered', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    await assertFails(getDoc(doc(bob, 'mb_adventurers_v1', ALICE_ID)));
    const dave = authedFirestore(testEnv, DAVE);
    await assertFails(getDoc(doc(dave, 'mb_adventurers_v1', DAVE_ID)));
    await assertFails(getDocs(collection(alice, 'mb_adventurers_v1')));
  });

  test('claim needs a registered pair first', async () => {
    const bob = authedFirestore(testEnv, BOB);
    const batch = writeBatch(bob);
    batch.set(doc(bob, 'mb_adventurers_v1', BOB_ID),
      adventurerData(BOB, BOB_ID, 'luna', 'Luna'));
    batch.set(doc(bob, 'mb_names_v1', 'luna'),
      nameData('luna', 'Luna', BOB_ID));
    await assertFails(batch.commit());
  });

  test('lone halves denied on both sides', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertFails(setDoc(doc(alice, 'mb_adventurers_v1', ALICE_ID),
      adventurerData(ALICE, ALICE_ID, 'luna', 'Luna')));
    await assertFails(setDoc(doc(alice, 'mb_names_v1', 'luna'),
      nameData('luna', 'Luna', ALICE_ID)));
  });

  test('mismatched pair halves acquire nothing', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const batch = writeBatch(alice);
    batch.set(doc(alice, 'mb_adventurers_v1', ALICE_ID),
      adventurerData(ALICE, ALICE_ID, 'luna', 'Luna'));
    batch.set(doc(alice, 'mb_names_v1', 'luna'),
      nameData('luna', 'Luna', BOB_ID));
    await assertFails(batch.commit());
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_adventurers_v1', ALICE_ID)));
    assert.equal(snap.exists(), false);
  });

  test('two owners racing for one name yield exactly one winner', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    const batchA = writeBatch(alice);
    batchA.set(doc(alice, 'mb_adventurers_v1', ALICE_ID),
      adventurerData(ALICE, ALICE_ID, 'luna', 'Luna'));
    batchA.set(doc(alice, 'mb_names_v1', 'luna'),
      nameData('luna', 'Luna', ALICE_ID));
    const batchB = writeBatch(bob);
    batchB.set(doc(bob, 'mb_adventurers_v1', BOB_ID),
      adventurerData(BOB, BOB_ID, 'luna', 'Luna'));
    batchB.set(doc(bob, 'mb_names_v1', 'luna'),
      nameData('luna', 'Luna', BOB_ID));
    const [a, b] = await Promise.allSettled([
      batchA.commit(), batchB.commit(),
    ]);
    const wins = [a, b].filter((r) => r.status === 'fulfilled').length;
    assert.equal(wins, 1);
    const index = await assertSucceeds(getDoc(doc(alice, 'mb_names_v1', 'luna')));
    const winnerId = index.data().public_id;
    assert.ok(winnerId === ALICE_ID || winnerId === BOB_ID);
    const loserId = winnerId === ALICE_ID ? BOB_ID : ALICE_ID;
    const loserDb = winnerId === ALICE_ID ? bob : alice;
    const loserSnap = await assertSucceeds(
      getDoc(doc(loserDb, 'mb_adventurers_v1', loserId)));
    assert.equal(loserSnap.exists(), false);
  });

  test('mixed-case Latin variants collide on one key', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    const batch = writeBatch(bob);
    batch.set(doc(bob, 'mb_adventurers_v1', BOB_ID),
      adventurerData(BOB, BOB_ID, 'luna', 'LUNA'));
    batch.set(doc(bob, 'mb_names_v1', 'luna'),
      nameData('luna', 'LUNA', BOB_ID));
    await assertFails(batch.commit());
  });

  test('valid Korean and Japanese names round-trip raw', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, '루나');
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    await claimName(bob, BOB, BOB_ID, 'ルミー');
    for (const [db, key, display] of [
      [alice, '루나', '루나'],
      [bob, 'ルミー', 'ルミー'],
    ]) {
      const snap = await assertSucceeds(getDoc(doc(db, 'mb_names_v1', key)));
      assert.equal(snap.data().display, display);
    }
  });

  test('invalid names fail at the boundary', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const nbsp = '\u00A0';
    const bad = [
      '', 'a', 'abcdefghijklm', ' A', 'A ', 'A  B', 'a/b', 'a\\b',
      'a.b', 'a-b', 'a\tb', 'a\nb', '\u00E9', 'e\u0301',
      '\u314E\u314E', '\uD83D\uDE00ab', '\uFF21\uFF22',
      '\u30FBab', nbsp + 'Moon', 'Moon' + nbsp, 'Mo' + nbsp + 'on',
    ];
    let i = 0;
    for (const display of bad) {
      const key = `probe${i++}`;
      const batch = writeBatch(alice);
      batch.set(doc(alice, 'mb_adventurers_v1', ALICE_ID),
        adventurerData(ALICE, ALICE_ID, key, display));
      batch.set(doc(alice, 'mb_names_v1', key),
        nameData(key, display, ALICE_ID));
      await assertFails(batch.commit());
    }
  });

  test('another owner cannot read, write, or delete the private row', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    await assertFails(getDoc(doc(bob, 'mb_adventurers_v1', ALICE_ID)));
    await assertFails(getDocs(collection(bob, 'mb_adventurers_v1')));
    await assertFails(updateDoc(doc(bob, 'mb_adventurers_v1', ALICE_ID),
      { intro_complete: true }));
    await assertFails(deleteDoc(doc(bob, 'mb_adventurers_v1', ALICE_ID)));
    await assertFails(deleteDoc(doc(bob, 'mb_names_v1', 'luna')));
  });

  test('name index exposes handle and public ID only', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    const bob = authedFirestore(testEnv, BOB);
    const snap = await assertSucceeds(getDoc(doc(bob, 'mb_names_v1', 'luna')));
    assert.deepEqual(Object.keys(snap.data() ?? {}).sort(), [
      'created_at', 'display', 'name_key', 'public_id', 'schema',
    ]);
    await assertFails(getDocs(collection(bob, 'mb_names_v1')));
  });

  test('unauthenticated claim and index reads denied', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'mb_names_v1', 'luna')));
    await assertFails(getDoc(doc(anon, 'mb_adventurers_v1', ALICE_ID)));
    const batch = writeBatch(anon);
    batch.set(doc(anon, 'mb_adventurers_v1', ALICE_ID),
      adventurerData(ALICE, ALICE_ID, 'anon', 'Anon'));
    batch.set(doc(anon, 'mb_names_v1', 'anon'),
      nameData('anon', 'Anon', ALICE_ID));
    await assertFails(batch.commit());
  });
});

describe('adventurer metadata: immutable except the intro bit', () => {
  test('display, key, uid, and public ID never change', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    const row = doc(alice, 'mb_adventurers_v1', ALICE_ID);
    await assertFails(updateDoc(row, { display: 'Sol' }));
    await assertFails(updateDoc(row, { name_key: 'sol' }));
    await assertFails(updateDoc(row, { uid: BOB }));
    await assertFails(updateDoc(row, { public_id: BOB_ID }));
    await assertFails(setDoc(row,
      adventurerData(ALICE, ALICE_ID, 'sol', 'Sol')));
  });

  test('intro bit moves false to true only', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    const row = doc(alice, 'mb_adventurers_v1', ALICE_ID);
    await assertSucceeds(updateDoc(row, { intro_complete: true }));
    await assertFails(updateDoc(row, { intro_complete: false }));
    const snap = await assertSucceeds(getDoc(row));
    assert.equal(snap.data().intro_complete, true);
  });

  test('arbitrary field additions denied', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    await assertFails(updateDoc(doc(alice, 'mb_adventurers_v1', ALICE_ID),
      { intro_complete: true, email: 'a@example.com' }));
    await assertFails(setDoc(doc(alice, 'mb_names_v1', 'luna'),
      nameData('luna', 'Luna', ALICE_ID)));
  });
});

describe('hall display: verified handles only', () => {
  test('named submit carries the claimed handle', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      { ...hallData(ALICE_ID, 500), display: 'Luna' }));
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_hall_v1', ALICE_ID)));
    assert.equal(snap.data().display, 'Luna');
  });

  test('forged, unclaimed, and malformed displays denied', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    await assertFails(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      { ...hallData(ALICE_ID, 500), display: 'Sol' }));
    await assertFails(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      { ...hallData(ALICE_ID, 500), display: 'a/b' }));
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    await assertFails(setDoc(doc(bob, 'mb_hall_v1', BOB_ID),
      { ...hallData(BOB_ID, 500), display: 'Luna' }));
  });

  test("another player's handle denied on write", async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    await claimName(bob, BOB, BOB_ID, 'Sol');
    await assertSucceeds(setDoc(doc(bob, 'mb_hall_v1', BOB_ID),
      { ...hallData(BOB_ID, 500), display: 'Sol' }));
    await assertFails(updateDoc(doc(bob, 'mb_hall_v1', BOB_ID),
      { ...hallData(BOB_ID, 500), display: 'Luna' }));
  });

  test('backfill attaches at the same score, downgrades still denied', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 500)));
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    await assertSucceeds(updateDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      { ...hallData(ALICE_ID, 500), display: 'Luna' }));
    await assertFails(updateDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      { ...hallData(ALICE_ID, 499), display: 'Luna' }));
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_hall_v1', ALICE_ID)));
    assert.equal(snap.data().score, 500);
    assert.equal(snap.data().display, 'Luna');
  });

  test('unnamed legacy rows keep working', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 500)));
    await assertSucceeds(updateDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 800)));
  });
});

describe('name deletion: pair halves go with the account', () => {
  test('lone name or adventurer delete denied', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    await assertFails(deleteDoc(doc(alice, 'mb_names_v1', 'luna')));
    await assertFails(deleteDoc(doc(alice, 'mb_adventurers_v1', ALICE_ID)));
  });

  test('pair halves cannot go under a living Hall row', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
    const batch = writeBatch(alice);
    batch.delete(doc(alice, 'mb_names_v1', 'luna'));
    batch.delete(doc(alice, 'mb_adventurers_v1', ALICE_ID));
    await assertFails(batch.commit());
  });

  test('name-only pair cannot release under a living canonical pair', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    const batch = writeBatch(alice);
    batch.delete(doc(alice, 'mb_names_v1', 'luna'));
    batch.delete(doc(alice, 'mb_adventurers_v1', ALICE_ID));
    await assertFails(batch.commit());
    const index = await assertSucceeds(getDoc(doc(alice, 'mb_names_v1', 'luna')));
    assert.equal(index.exists(), true);
    const row = await assertSucceeds(
      getDoc(doc(alice, 'mb_adventurers_v1', ALICE_ID)));
    assert.equal(row.data().display, 'Luna');
  });

  test('name halves cannot go with the Hall but without the pair', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
    const batch = writeBatch(alice);
    batch.delete(doc(alice, 'mb_hall_v1', ALICE_ID));
    batch.delete(doc(alice, 'mb_names_v1', 'luna'));
    batch.delete(doc(alice, 'mb_adventurers_v1', ALICE_ID));
    await assertFails(batch.commit());
  });

  test('canonical halves cannot go while the name pair stays', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    const batch = writeBatch(alice);
    batch.delete(doc(alice, 'mb_profiles_v1', ALICE));
    batch.delete(doc(alice, 'mb_reservations_v1', ALICE_ID));
    await assertFails(batch.commit());
    const index = await assertSucceeds(getDoc(doc(alice, 'mb_names_v1', 'luna')));
    assert.equal(index.exists(), true);
  });

  test('no-op missing-row name deletes stay allowed', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const batch = writeBatch(alice);
    batch.delete(doc(alice, 'mb_names_v1', 'never-claimed'));
    batch.delete(doc(alice, 'mb_adventurers_v1', ALICE_ID));
    await assertSucceeds(batch.commit());
  });

  test('named deletion without a Hall row still completes', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    await deleteNamedAccount(alice, ALICE, ALICE_ID, 'luna');
    const gone = await assertSucceeds(getDoc(doc(alice, 'mb_names_v1', 'luna')));
    assert.equal(gone.exists(), false);
  });

  test('named account deletion frees the name exactly once', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      { ...hallData(ALICE_ID, 10), display: 'Luna' }));
    await deleteNamedAccount(alice, ALICE, ALICE_ID, 'luna');
    const gone = await assertSucceeds(getDoc(doc(alice, 'mb_names_v1', 'luna')));
    assert.equal(gone.exists(), false);
    await deleteNamedAccount(alice, ALICE, ALICE_ID, 'luna');
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    await claimName(bob, BOB, BOB_ID, 'Luna');
  });

  test('pair halves cannot be deleted by another owner', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    const batch = writeBatch(bob);
    batch.delete(doc(bob, 'mb_names_v1', 'luna'));
    batch.delete(doc(bob, 'mb_adventurers_v1', ALICE_ID));
    await assertFails(batch.commit());
  });

  test('legacy four-write deletion strands nothing new on unnamed rows', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_checkpoints_v1', ALICE),
      checkpointData(ALICE, 1, '{"gate":1}')));
    await assertSucceeds(setDoc(doc(alice, 'mb_hall_v1', ALICE_ID),
      hallData(ALICE_ID, 10)));
    await deleteAccount(alice, ALICE, ALICE_ID);
  });
});

describe('attendance: server-time cooldown claims', () => {
  test('owner first claim with a server stamp succeeds', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      attendanceData(ALICE, ALICE_ID, 'install-a', serverTimestamp())));
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_attendance_v1', ALICE_ID)));
    assert.equal(snap.data().install_id, 'install-a');
  });

  test('owner reads an authoritative missing row', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_attendance_v1', ALICE_ID)));
    assert.equal(snap.exists(), false);
  });

  test('attendance stays private: strangers, unregistered, lists denied', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      attendanceData(ALICE, ALICE_ID, 'install-a', serverTimestamp())));
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    await assertFails(getDoc(doc(bob, 'mb_attendance_v1', ALICE_ID)));
    const dave = authedFirestore(testEnv, DAVE);
    await assertFails(getDoc(doc(dave, 'mb_attendance_v1', DAVE_ID)));
    await assertFails(getDocs(collection(alice, 'mb_attendance_v1')));
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'mb_attendance_v1', ALICE_ID)));
    await assertFails(setDoc(doc(anon, 'mb_attendance_v1', DAVE_ID),
      attendanceData(DAVE, DAVE_ID, 'install-x', serverTimestamp())));
  });

  test('forged timestamps die in the rules', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const past = Timestamp.fromDate(new Date(Date.now() - 3600 * 1000));
    await assertFails(setDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      attendanceData(ALICE, ALICE_ID, 'install-a', past)));
    const future = Timestamp.fromDate(
      new Date(Date.now() + 3600 * 1000));
    await assertFails(setDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      attendanceData(ALICE, ALICE_ID, 'install-a', future)));
    const missing = { ...attendanceData(ALICE, ALICE_ID, 'install-a',
      serverTimestamp()) };
    delete missing.last_claim_at;
    await assertFails(setDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      missing));
  });

  test('unregistered and stranger claims denied', async () => {
    const dave = authedFirestore(testEnv, DAVE);
    await assertFails(setDoc(doc(dave, 'mb_attendance_v1', DAVE_ID),
      attendanceData(DAVE, DAVE_ID, 'install-x', serverTimestamp())));
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const bob = authedFirestore(testEnv, BOB);
    await registerPair(bob, BOB, BOB_ID);
    await assertFails(setDoc(doc(bob, 'mb_attendance_v1', ALICE_ID),
      attendanceData(ALICE, ALICE_ID, 'install-b', serverTimestamp())));
    await assertSucceeds(setDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      attendanceData(ALICE, ALICE_ID, 'install-a', serverTimestamp())));
    const seedDate = new Date(Date.now() - 13 * 3600 * 1000);
    await seedAttendance(ALICE_ID, ALICE, 'install-a', seedDate);
    await assertFails(updateDoc(doc(bob, 'mb_attendance_v1', ALICE_ID), {
      install_id: 'install-b',
      last_claim_at: serverTimestamp(),
      prev_claim_at: Timestamp.fromDate(seedDate),
      prev_install_id: 'install-a',
    }));
  });

  test('thirteen-hour-old record claims for a new install', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const seedDate = new Date(Date.now() - 13 * 3600 * 1000);
    await seedAttendance(ALICE_ID, ALICE, 'install-a', seedDate);
    await assertSucceeds(updateDoc(doc(alice, 'mb_attendance_v1', ALICE_ID), {
      install_id: 'install-b',
      last_claim_at: serverTimestamp(),
      prev_claim_at: Timestamp.fromDate(seedDate),
      prev_install_id: 'install-a',
    }));
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_attendance_v1', ALICE_ID)));
    assert.equal(snap.data().install_id, 'install-b');
    assert.equal(snap.data().prev_install_id, 'install-a');
    assert.equal(snap.data().prev_claim_at.toMillis(),
      seedDate.getTime());
  });

  test('eleven-hour-old record holds its cooldown', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const seedDate = new Date(Date.now() - 11 * 3600 * 1000);
    await seedAttendance(ALICE_ID, ALICE, 'install-a', seedDate);
    await assertFails(updateDoc(doc(alice, 'mb_attendance_v1', ALICE_ID), {
      install_id: 'install-a',
      last_claim_at: serverTimestamp(),
      prev_claim_at: Timestamp.fromDate(seedDate),
      prev_install_id: 'install-a',
    }));
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_attendance_v1', ALICE_ID)));
    assert.equal(snap.data().install_id, 'install-a');
  });

  test('exactly twelve hours is eligible', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const seedDate = new Date(Date.now() - 43200 * 1000);
    await seedAttendance(ALICE_ID, ALICE, 'install-a', seedDate);
    await assertSucceeds(updateDoc(doc(alice, 'mb_attendance_v1', ALICE_ID), {
      install_id: 'install-a',
      last_claim_at: serverTimestamp(),
      prev_claim_at: Timestamp.fromDate(seedDate),
      prev_install_id: 'install-a',
    }));
  });

  test('advance without the carried pair is denied', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await seedAttendance(ALICE_ID, ALICE, 'install-a',
      new Date(Date.now() - 13 * 3600 * 1000));
    await assertFails(updateDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      { install_id: 'install-b', last_claim_at: serverTimestamp() }));
  });

  test('advance with a forged carried pair is denied', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const seedDate = new Date(Date.now() - 13 * 3600 * 1000);
    await seedAttendance(ALICE_ID, ALICE, 'install-a', seedDate);
    const wrongStamp = Timestamp.fromDate(
      new Date(seedDate.getTime() - 3600 * 1000));
    await assertFails(updateDoc(doc(alice, 'mb_attendance_v1', ALICE_ID), {
      install_id: 'install-b',
      last_claim_at: serverTimestamp(),
      prev_claim_at: wrongStamp,
      prev_install_id: 'install-a',
    }));
    await assertFails(updateDoc(doc(alice, 'mb_attendance_v1', ALICE_ID), {
      install_id: 'install-b',
      last_claim_at: serverTimestamp(),
      prev_claim_at: Timestamp.fromDate(seedDate),
      prev_install_id: 'install-forged',
    }));
  });

  test('first claim carrying a previous pair is denied', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const carried = {
      ...attendanceData(ALICE, ALICE_ID, 'install-a', serverTimestamp()),
      prev_claim_at: Timestamp.fromDate(new Date(Date.now() - 1000)),
      prev_install_id: 'install-a',
    };
    await assertFails(setDoc(
      doc(alice, 'mb_attendance_v1', ALICE_ID), carried));
  });

  test('the carried pair overwrites each advance', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const seedDate = new Date(Date.now() - 13 * 3600 * 1000);
    const olderDate = new Date(Date.now() - 26 * 3600 * 1000);
    await seedAttendance(ALICE_ID, ALICE, 'install-a', seedDate,
      olderDate, 'install-older');
    await assertSucceeds(updateDoc(doc(alice, 'mb_attendance_v1', ALICE_ID), {
      install_id: 'install-b',
      last_claim_at: serverTimestamp(),
      prev_claim_at: Timestamp.fromDate(seedDate),
      prev_install_id: 'install-a',
    }));
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_attendance_v1', ALICE_ID)));
    assert.equal(snap.data().prev_claim_at.toMillis(),
      seedDate.getTime());
    assert.equal(snap.data().prev_install_id, 'install-a');
  });

  test('canonical halves never move on update', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const seedDate = new Date(Date.now() - 13 * 3600 * 1000);
    await seedAttendance(ALICE_ID, ALICE, 'install-a', seedDate);
    const carry = {
      last_claim_at: serverTimestamp(),
      prev_claim_at: Timestamp.fromDate(seedDate),
      prev_install_id: 'install-a',
    };
    await assertFails(updateDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      { ...carry, uid: BOB }));
    await assertFails(updateDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      { ...carry, public_id: BOB_ID }));
  });

  test('concurrent conditional claims yield one new receipt', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const seedDate = new Date(Date.now() - 13 * 3600 * 1000);
    await seedAttendance(ALICE_ID, ALICE, 'install-a', seedDate);
    const racer = () => updateDoc(doc(alice, 'mb_attendance_v1', ALICE_ID), {
      install_id: 'install-a',
      last_claim_at: serverTimestamp(),
      prev_claim_at: Timestamp.fromDate(seedDate),
      prev_install_id: 'install-a',
    });
    const attempts = await Promise.allSettled([racer(), racer()]);
    const wins = attempts.filter((a) => a.status === 'fulfilled');
    assert.equal(wins.length, 1);
  });

  test('concurrent first claims yield one row', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    const attempts = await Promise.allSettled([
      setDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
        attendanceData(ALICE, ALICE_ID, 'install-a', serverTimestamp())),
      setDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
        attendanceData(ALICE, ALICE_ID, 'install-a', serverTimestamp())),
    ]);
    const wins = attempts.filter((a) => a.status === 'fulfilled');
    assert.equal(wins.length, 1);
  });

  test('living attendance never deletes alone', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      attendanceData(ALICE, ALICE_ID, 'install-a', serverTimestamp())));
    await assertFails(deleteDoc(doc(alice, 'mb_attendance_v1', ALICE_ID)));
    const snap = await assertSucceeds(
      getDoc(doc(alice, 'mb_attendance_v1', ALICE_ID)));
    assert.equal(snap.exists(), true);
  });

  test('pair halves cannot go while attendance stays', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await assertSucceeds(setDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      attendanceData(ALICE, ALICE_ID, 'install-a', serverTimestamp())));
    const batch = writeBatch(alice);
    batch.delete(doc(alice, 'mb_hall_v1', ALICE_ID));
    batch.delete(doc(alice, 'mb_checkpoints_v1', ALICE));
    batch.delete(doc(alice, 'mb_reservations_v1', ALICE_ID));
    batch.delete(doc(alice, 'mb_profiles_v1', ALICE));
    await assertFails(batch.commit());
  });

  test('full deletion removes an attended account', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await claimName(alice, ALICE, ALICE_ID, 'Luna');
    await assertSucceeds(setDoc(doc(alice, 'mb_attendance_v1', ALICE_ID),
      attendanceData(ALICE, ALICE_ID, 'install-a', serverTimestamp())));
    await deleteNamedAccount(alice, ALICE, ALICE_ID, 'luna');
    // The former owner reads denied either way; only an admin read
    // proves the row itself is gone.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const gone = await getDoc(doc(db, 'mb_attendance_v1', ALICE_ID));
      assert.equal(gone.exists(), false);
    });
  });

  test('full deletion keeps working never-attended', async () => {
    const alice = authedFirestore(testEnv, ALICE);
    await registerPair(alice, ALICE, ALICE_ID);
    await deleteAccount(alice, ALICE, ALICE_ID);
  });
});
