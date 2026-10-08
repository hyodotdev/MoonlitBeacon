import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

// Numeric proof for the shipped iOS reminder planner. This test
// compiles the production header MoonlitReminderPlanner.h — the same
// file the native schedule path includes — with the system C compiler
// and executes its pure functions. It never reimplements the math in
// JS and never settles for source-text patterns alone: the vectors
// below run the real computation. The game-side GDScript suite mirrors
// these exact fixtures (see _test_horizon_window_matrix), so native
// and game agree by construction, not by review.

const HERE = dirname(fileURLToPath(import.meta.url));
const IOS_SRC = join(
  HERE,
  '../../apps/game/addons/moonlit-identity/ios/src',
);
const PLANNER_H = join(IOS_SRC, 'MoonlitReminderPlanner.h');

const ANCHOR_MS = 1700000000000;
const REPEAT_MS = 43200000;

// Shared fixture table with the GDScript agreement test: anchor,
// now, base, expected first-future, expected remaining, holds?
// Whole-second stamps so both integer-ms sides agree bit-for-bit.
const AGREE = [
  // Exact eligibility: everything future, hold.
  ['equal', 0, 0, 0, 48, 1],
  // 9/8/7 future slots around the duplicate boundary, on-grid and
  // mid-slot (the mid-slot 8-future case is the old disagreement:
  // native held while the game side refilled).
  ['nine', 39 * 43200, 0, 39, 9, 1],
  ['eight', 40 * 43200, 0, 40, 8, 1],
  ['eight-mid', 39 * 43200 + 21600, 0, 40, 8, 1],
  ['seven', 41 * 43200, 0, 41, 7, 0],
  ['seven-mid', 40 * 43200 + 21600, 0, 41, 7, 0],
  // Day 25 on the grid: first future is slot 50, the old window is
  // exhausted, and a refilled base-50 window holds whole.
  ['day25', 50 * 43200, 0, 50, 0, 0],
  ['day25-held', 50 * 43200, 50, 50, 48, 1],
  // A base entirely ahead of now (regressed clock) refills rather
  // than holding, exactly like the shipped gate.
  ['ahead', 0, 40, 0, 48, 0],
];

function buildMain() {
  const nows = AGREE.map(
    ([, offset]) => `anchor + ${offset * 1000}LL`,
  ).join(', ');
  const bases = AGREE.map(([, , base]) => String(base)).join(', ');
  const names = AGREE.map(([name]) => `"agree_${name}"`).join(', ');
  return `#include <stdio.h>
#include "MoonlitReminderPlanner.h"

int main(void) {
  printf("const_horizon=%lld\\n", kReminderHorizonSlots);
  printf("const_min_future=%lld\\n", kReminderMinFutureSlots);
  printf("const_repeat=%lld\\n", kReminderRepeatMillis);
  long long anchor = ${ANCHOR_MS}LL;
  long long marks[] = {
    anchor - 43200000LL,
    anchor,
    anchor + 1,
    anchor + 43200000LL,
    anchor + 43200001LL,
    anchor + 2160000000LL,
    anchor + 2160000001LL,
  };
  const char *names[] = {
    "first_initial", "first_equal", "first_plus1ms",
    "first_plus1slot", "first_plus1slot1ms",
    "first_day25", "first_day25plus1ms",
  };
  for (int i = 0; i < 7; i++) {
    printf("%s=%lld\\n", names[i],
      MoonlitReminderFirstFuture(anchor, marks[i]));
  }
  // Window plans: base, count, first fire, last fire, all unique,
  // all on the 12h grid at or after now.
  long long nows[] = {
    anchor - 43200000LL, anchor, anchor + 2160000000LL,
  };
  const char *wnames[] = {"win_initial", "win_equal", "win_day25"};
  for (int w = 0; w < 3; w++) {
    long long now = nows[w];
    long long base = MoonlitReminderFirstFuture(anchor, now);
    long long count = 0;
    long long firstFire = 0;
    long long lastFire = 0;
    long long unique = 1;
    long long onGrid = 1;
    long long future = 1;
    for (long long pos = 0; pos < kReminderHorizonSlots; pos++) {
      long long slot = base + pos;
      long long fire = MoonlitReminderSlotFireMs(anchor, slot);
      // The shipped loop's skip rule: strictly elapsed stays out.
      if (fire < now) {
        continue;
      }
      if (count > 0 && fire != lastFire + kReminderRepeatMillis) {
        unique = 0;
      }
      if ((fire - anchor) % kReminderRepeatMillis != 0) {
        onGrid = 0;
      }
      if (fire < now) {
        future = 0;
      }
      if (count == 0) {
        firstFire = fire;
      }
      lastFire = fire;
      count++;
    }
    printf("%s_base=%lld\\n", wnames[w], base);
    printf("%s_count=%lld\\n", wnames[w], count);
    printf("%s_first=%lld\\n", wnames[w], firstFire);
    printf("%s_last=%lld\\n", wnames[w], lastFire);
    printf("%s_unique=%lld\\n", wnames[w], unique);
    printf("%s_ongrid=%lld\\n", wnames[w], onGrid);
    printf("%s_future=%lld\\n", wnames[w], future);
  }
  // Duplicate-gate agreement vectors (shared with GDScript).
  long long agreeNows[] = {${nows}};
  long long agreeBases[] = {${bases}};
  const char *anames[] = {${names}};
  for (int i = 0; i < ${AGREE.length}; i++) {
    long long f = MoonlitReminderFirstFuture(anchor, agreeNows[i]);
    printf("%s_first=%lld\\n", anames[i], f);
    printf("%s_remaining=%lld\\n", anames[i],
      MoonlitReminderRemaining(agreeBases[i], f));
    printf("%s_holds=%d\\n", anames[i],
      MoonlitReminderWindowHolds(agreeBases[i], f));
  }
  // The gate shape the helper replaced stays equivalent wherever the
  // old gate applied (firstFuture at or past the base).
  long long mismatched = 0;
  for (long long delta = 0; delta <= 60; delta++) {
    long long f = 7 + delta;
    int shape = (f - 7) + kReminderMinFutureSlots
      <= kReminderHorizonSlots;
    if (shape != MoonlitReminderWindowHolds(7, f)) {
      mismatched = 1;
    }
  }
  printf("gate_shape_mismatched=%lld\\n", mismatched);
  return 0;
}
`;
}

function runPlanner() {
  const dir = mkdtempSync(join(tmpdir(), 'moonlit-planner-'));
  try {
    const main = join(dir, 'planner_main.c');
    const bin = join(dir, 'planner');
    writeFileSync(main, buildMain());
    let compiled = null;
    try {
      compiled = execFileSync(
        'cc',
        ['-std=c99', '-Wall', '-Werror', '-I', IOS_SRC, main, '-o', bin],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
      );
    } catch (error) {
      const detail = String(
        (error !== null && typeof error === 'object' && 'stderr' in error
          ? error.stderr
          : null) ?? error,
      );
      assert.fail(`planner header does not compile cleanly:\n${detail}`);
    }
    void compiled;
    const out = execFileSync(bin, { encoding: 'utf8' });
    const values = new Map();
    for (const line of out.split('\n')) {
      const trimmed = line.trim();
      if (trimmed === '') {
        continue;
      }
      const at = trimmed.indexOf('=');
      assert.ok(at > 0, `planner prints name=value lines, saw ${trimmed}`);
      values.set(trimmed.slice(0, at), Number(trimmed.slice(at + 1)));
    }
    return values;
  } finally {
    rmSync(dir, { force: true, recursive: true });
  }
}

test('planner constants pin the shipped window', () => {
  const v = runPlanner();
  assert.equal(v.get('const_horizon'), 48);
  assert.equal(v.get('const_min_future'), 8);
  assert.equal(v.get('const_repeat'), 43200000);
});

test('planner first-future is exact at every boundary', () => {
  const v = runPlanner();
  assert.equal(v.get('first_initial'), 0);
  assert.equal(v.get('first_equal'), 0);
  assert.equal(v.get('first_plus1ms'), 1);
  assert.equal(v.get('first_plus1slot'), 1);
  assert.equal(v.get('first_plus1slot1ms'), 2);
  assert.equal(v.get('first_day25'), 50);
  assert.equal(v.get('first_day25plus1ms'), 51);
});

test('planner windows hold 48 unique future grid slots', () => {
  const v = runPlanner();
  const cases = [
    ['win_initial', 0, ANCHOR_MS],
    ['win_equal', 0, ANCHOR_MS],
    ['win_day25', 50, ANCHOR_MS + 50 * REPEAT_MS],
  ];
  for (const [name, base, first] of cases) {
    assert.equal(v.get(`${name}_base`), base);
    assert.equal(v.get(`${name}_count`), 48);
    assert.equal(v.get(`${name}_first`), first);
    assert.equal(v.get(`${name}_last`), first + 47 * REPEAT_MS);
    assert.equal(v.get(`${name}_unique`), 1);
    assert.equal(v.get(`${name}_ongrid`), 1);
    assert.equal(v.get(`${name}_future`), 1);
  }
});

test('planner duplicate gate agrees on the shared vectors', () => {
  const v = runPlanner();
  for (const [name, , base, first, remaining, holds] of AGREE) {
    void base;
    assert.equal(v.get(`agree_${name}_first`), first);
    assert.equal(v.get(`agree_${name}_remaining`), remaining);
    assert.equal(v.get(`agree_${name}_holds`), holds);
  }
  assert.equal(v.get('gate_shape_mismatched'), 0);
});
