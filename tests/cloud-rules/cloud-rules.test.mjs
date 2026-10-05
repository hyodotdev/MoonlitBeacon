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
  batch.delete(doc(db, 'mb_reservations_v1', publicId));
  batch.delete(doc(db, 'mb_profiles_v1', uid));
  await assertSucceeds(batch.commit());
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
