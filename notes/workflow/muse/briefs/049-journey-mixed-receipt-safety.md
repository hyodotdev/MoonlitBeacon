# Brief 049: Correct the independently reproduced mixed receipt error

## The ask
Continue the journey foundation. The director needs a genuinely clean failure/replay suite before acceptance.

## Confirmed evidence
The director ran `pnpm godot:isolated --timeout 180 res://tests/test_journey.tscn`. It prints 381 passing cases, but also a SCRIPT ERROR at vault.gd:344: `Invalid operands 'int' and 'String' in operator '=='`, from _evict_one_settled_journey during _test_receipt_retirement, then one leaked ObjectDB instance. The success line is not clean evidence. Mixed issued integer and fallback string receipts need type-aware equality everywhere, including eviction/keep comparisons. Ensure regressions really fail on the prior implementation; fix any affected cleanup.

MAX_SAFE_INT currently allows 2^53, and _is_int_in compares integers after converting them to float. Integer 9007199254740993 rounds to the accepted limit. _is_journey_id accepts any positive int without its upper bound. Use exact safe JSON integer bounds and comparisons appropriate to the original type; test both in-memory integer and parsed JSON edge cases. Reject out-of-range values before write or restore. Do not invent a claim that parsing can recover precision already lost in externally supplied JSON.

The director repeats the exact blocked-checkpoint payout probe. Keep its repaired 0 -> 15 -> 15 behavior and all neighboring settlement behavior.

## Do
Fix these confirmed defects, harden the test result so an engine error cannot masquerade as a green receipt where feasible, and repeat the focused suites. Keep the changes scoped. This newly reproduced mixed-type defect is not three attempts at the original duplicated payout.

## Do not
Do not change identity/cloud/art/UI/version/presets/guards/credentials. No new delivery features; keep previous acceptance contracts and paid purchase ledgers intact.

## Acceptance and judgment
The director's exact journey scene has all assertions passing and no SCRIPT ERROR, ERROR, leaked object/resource cleanup warnings. Mixed receipts survive settlement, eviction and reload with bounded ledger size and no duplicated grants. Out-of-range integer validation fails and the intended JSON boundary succeeds. The director repeats the independent replay probe and a negative control before acceptance.
