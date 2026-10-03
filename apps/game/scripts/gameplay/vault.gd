extends Node

## Moon vault — what survives a run.
##
## `Records` knows only a high score. This holds **what makes the next run
## start better.** Collect shards, raise boons.
##
## Split from `Records`. The repo already keeps `settings.cfg` and
## `records.cfg` apart — "records are play results, settings are taste." The
## vault is the third: **not play results, wealth built by playing.** Wipe
## records and wealth must stay, and the reverse.

signal changed

const SAVE_PATH: String = "user://vault.cfg"
const TEMP_SAVE_PATH: String = SAVE_PATH + ".tmp"
const BACKUP_SAVE_PATH: String = SAVE_PATH + ".bak"
const BACKUP_TEMP_SAVE_PATH: String = BACKUP_SAVE_PATH + ".tmp"
const SECTION: String = "vault"
## 4 added `continue_coins` (arcade continue coins), 5 added
## `continue_coin_grants` that store payment transaction keys and balance in
## one file. Old saves have no ledger, so migrate to an empty ledger and keep
## the existing coin balance.
const SCHEMA_VERSION: int = 5
const HERO_SOURCE_SHARDS: String = "shards"
const HERO_SOURCE_IAP_BUNDLE: String = "iap:hero_bundle"
const HERO_SOURCE_IAP_PREFIX: String = "iap:hero:"

enum PurchaseResult {
	OK,
	INVALID,
	INSUFFICIENT,
	OWNED,
	MAXED,
	STALE,
	SAVE_FAILED,
}

enum RunSettlementStatus {
	APPLIED,
	NO_CHANGE,
	SAVE_FAILED,
}

## One journey receipt's fate. `DUPLICATE` and `RETIRED` grant nothing and
## save nothing: they are pure reads, so crashing around them is harmless.
## `FLOORED` records a remote floor without granting its historical value.
enum JourneyReceipt {
	SETTLED,
	DUPLICATE,
	RETIRED,
	SAVE_FAILED,
	FLOORED,
}

## Every boon that can be bought. One `.tres` is one boon.
const POOL: Array[String] = [
	"res://resources/boons/steady_heart.tres",
	"res://resources/boons/keen_edge.tres",
	"res://resources/boons/light_foot.tres",
	"res://resources/boons/first_gift.tres",
	"res://resources/boons/dew_sense.tres",
	"res://resources/boons/shard_sense.tres",
]

## Settled journey receipts remembered for exactly-once grants. Bounded: at
## most this many journeys are retained. Older sequence ids past the bound
## read as retired and grant nothing, so bounding the ledger can never turn
## a forgotten receipt into fresh money.
const MAX_SETTLED_JOURNEYS: int = 16
## Largest cumulative receipt target the ledger accepts: 2^53 - 1, the
## largest integer JSON carries exactly.
const JOURNEY_TARGET_CAP: int = 9007199254740991
## Largest checkpoint id the ledger accepts. Seals tick far slower than
## frames; a billion is thousands of years of gates.
const JOURNEY_CHECKPOINT_CAP: int = 1000000000
## Unsettled fallback ids remembered per session. One entry per failed issue,
## removed on its first successful settle; bounding it can only strand an
## absurd backlog, never mint, and the coordinator floors the active journey
## from its checkpoint echo anyway.
const MAX_ISSUED_FALLBACKS: int = 64

## Slope of the shard curve. Smaller gives more.
##
## **Do not grant in proportion to score.** First pass was one per 500 points,
## and real scores made the gap between runs too wide:
##
## | Run | Total | Proportional | Now (sqrt) |
## | --- | --- | --- | --- |
## | 2 min | 6,180 | 12 | 12 |
## | 6 min | 24,600 | 49 | 24 |
## | 15 min | 70,380 | 140 | 41 |
## | 30 min | 159,480 | **318** | 63 |
##
## Proportional makes a 15-minute run 11× a 2-minute run. A skilled player
## buys every boon in two or three runs and **meta growth vanishes from then
## on.** It becomes a device that exists only for the unskilled.
##
## Square-root compresses the gap to 5×. Skill still pays more, but even a
## weak run visibly stacks each time.
const SHARD_SCALE: float = 40.0

## Characters that can be picked. The first costs 0, so it is open from the start.
const HEROES: Array[String] = [
	"res://resources/heroes/warden.tres",
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/eclipse.tres",
	"res://resources/heroes/sage.tres",
]

## Individual non-consumable IAP heroes that a new install cannot open with
## shards. A save that already opened Dancer/Keeper with shards in an old
## version still reads `HERO_SOURCE_SHARDS` and keeps the right, but this list
## is not shown in future shard goals or buy candidates.
const PAID_HEROES: Array[String] = [
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/keeper.tres",
	"res://resources/heroes/knight.tres",
	"res://resources/heroes/eclipse.tres",
	"res://resources/heroes/sage.tres",
]
const LEGACY_BUNDLE_HEROES: Array[String] = [
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/keeper.tres",
]

var shards: int = 0
## Boon path → raised rank.
var ranks: Dictionary = {}
## Opened character paths.
var opened: Array[String] = []
## Character path → unlock sources. Shard unlock and IAP unlock must be told
## apart so stripping a later-refunded IAP source does not take a hero earned
## by play.
var hero_sources: Dictionary = {}
## Currently picked character. Empty uses the first.
var chosen: String = ""
## Journey sequence ids issued so far. Fresh journeys take the next one.
var journey_seq_issued: int = 0
## Settled receipts: `[journey_id, checkpoint, target]` triples. The id is an
## int sequence, or a random String when its issue save failed.
var settled_journeys: Array = []
## Fallback string ids this session issued through `begin_journey()` that
## have not settled yet. A string with no ledger record settles only from
## this set; evicted or never-issued strings retire instead of minting.
## Memory-only on purpose, and kept across `load_vault()`: an in-flight
## fallback must still settle after a reload, and a restart reconciles the
## active journey through its floor instead of re-issuing it.
var _issued_fallback_ids: Dictionary = {}


func _ready() -> void:
	load_vault()


## Total shards a cumulative score should grant.
##
## **Something must remain even on death.** Score 0 or negative still targets
## at least 1 shard. Boons are applied, so settling again in the same run
## with the same cumulative score yields the same target.
func shard_target_for_score(score: int) -> int:
	var target: int = maxi(int(sqrt(maxf(float(score), 0.0) / SHARD_SCALE)), 1)
	return int(round(float(target) * (1.0 + grace(Boon.Grace.SHARD_YIELD))))


## Settle this run's cumulative score. Add only the difference between the
## score-based shard target and shards already granted. The return carries
## `status` and `awarded` so the caller can tell a real extra grant of 0 from
## a save failure.
##
## Continue after a loss settlement keeps the same run. Granting the full
## target again would duplicate shards from the earlier loss. The caller
## passes shards already received this run as `already_awarded` to block that.
##
## Save failure rolls the in-memory balance back. A zero-delta re-settle
## skips save and `changed` and returns `NO_CHANGE`.
func settle_run_score(total_score: int, already_awarded: int) -> Dictionary:
	var target: int = shard_target_for_score(total_score)
	var earned: int = maxi(target - maxi(already_awarded, 0), 0)
	if earned <= 0:
		return {
			"status": RunSettlementStatus.NO_CHANGE,
			"awarded": 0,
		}
	var before: int = shards
	shards += earned
	if save_vault() != OK:
		shards = before
		return {
			"status": RunSettlementStatus.SAVE_FAILED,
			"awarded": 0,
		}
	changed.emit()
	return {
		"status": RunSettlementStatus.APPLIED,
		"awarded": earned,
	}


## Compat for existing callers. Grants the full target like the old one-shot
## settle. Callers with continue must use `settle_run_score()`.
func award(score: int) -> int:
	var result: Dictionary = settle_run_score(score, 0)
	return int(result.get("awarded", 0)) \
		if int(result.get("status", RunSettlementStatus.SAVE_FAILED)) \
		== RunSettlementStatus.APPLIED else 0


## Issue the next journey sequence id, durably. A fresh journey settles its
## earned shards against this id, so a retried receipt grants exactly once
## even across a crash between the Vault save and the journey write.
##
## When the counter save fails, fall back to a random string id instead of
## reusing a sequence: retries still dedup while the entry is retained, and
## no two journeys ever share an id. The fallback is remembered for its
## first settle; any other unknown string retires instead of minting.
func begin_journey() -> Variant:
	journey_seq_issued += 1
	var seq: int = journey_seq_issued
	if save_vault() != OK:
		journey_seq_issued = seq - 1
		var fallback: String = "r%x%x" % [
			int(Time.get_unix_time_from_system()) % 0xffffff, abs(randi())]
		_issued_fallback_ids[fallback] = true
		while _issued_fallback_ids.size() > MAX_ISSUED_FALLBACKS:
			_issued_fallback_ids.erase(_issued_fallback_ids.keys()[0])
		return fallback
	return seq


## Settle one journey receipt exactly once: `(journey, checkpoint)` with a
## cumulative shard `target`. Returns `status`, `granted`, and
## `settled_target` (the cumulative granted total the caller echoes).
##
## The grant is `target` minus the journey's settled base. A redelivery of
## the same receipt pays 0 without saving — unless the live score advanced
## past the sealed one, in which case only the new delta pays, immediately,
## so value is never stranded behind a crash. An older checkpoint of a
## settled journey (a retired receipt, e.g. from a restored backup) always
## pays 0 even revalued upward: its value was superseded already. So does a
## sequence id evicted past the bounded ledger or never issued, and so does
## an unusable id that normalizes to null.
##
## Save failure rolls the balance and the ledger back and returns
## `SAVE_FAILED` with 0 granted, so a retry grants the full delta. Callers
## seal the checkpoint unsettled on failure; the next seal's cumulative
## target carries the value, which keeps retries available across restart.
##
## Unknown strings retire: a string with no ledger record settles only when
## this session issued it through `begin_journey()` and it has not settled
## yet. A replay of an evicted fallback, or a string that was never issued,
## mints nothing. Remote history never arrives here: the coordinator floors
## it first through `initialize_remote_receipt_floor()`.
func settle_journey_receipt(
	journey: Variant, checkpoint_id: int, target: int
) -> Dictionary:
	var receipt_id: Variant = _normalize_journey_id(journey)
	var cid: int = clampi(checkpoint_id, 0, JOURNEY_CHECKPOINT_CAP)
	var want: int = clampi(target, 0, JOURNEY_TARGET_CAP)
	if receipt_id == null \
			or (receipt_id is int and _journey_seq_retired(int(receipt_id))) \
			or (receipt_id is String \
				and _journey_string_retired(str(receipt_id))):
		return {
			"status": JourneyReceipt.RETIRED,
			"granted": 0,
			"settled_target": 0,
		}
	var record: Array = _find_settled_journey(receipt_id)
	if not record.is_empty() \
			and (cid < int(record[1]) or want <= int(record[2])):
		return {
			"status": JourneyReceipt.DUPLICATE,
			"granted": 0,
			"settled_target": int(record[2]),
		}
	var base: int = int(record[2]) if not record.is_empty() else 0
	var grant: int = maxi(want - base, 0)
	var before_shards: int = shards
	var before_ledger: Array = settled_journeys.duplicate(true)
	_upsert_settled_journey(receipt_id, cid, want)
	shards += grant
	if save_vault() != OK:
		shards = before_shards
		settled_journeys = before_ledger
		return {
			"status": JourneyReceipt.SAVE_FAILED,
			"granted": 0,
			"settled_target": base,
		}
	# The first settle consumes the issuance: a later eviction leaves no
	# record and no issuance, so the replay retires instead of paying again.
	_issued_fallback_ids.erase(receipt_id)
	if grant > 0:
		changed.emit()
	return {
		"status": JourneyReceipt.SETTLED,
		"granted": grant,
		"settled_target": want,
	}


## Record a downloaded checkpoint's cumulative target as this device's floor
## without granting its historical value. New play above the floor still
## settles exactly once through `settle_journey_receipt()`; the history
## itself pays 0. An int floor also advances the issue watermark so a later
## local `begin_journey()` never reuses the remote id. A higher floor only
## ever rises, never pays. Save failure rolls everything back for a retry.
## Paid entitlements and the coin ledger are untouched: only the journey
## receipt ledger and the sequence watermark move.
func initialize_remote_receipt_floor(
	journey: Variant, checkpoint_id: int, target: int
) -> Dictionary:
	var receipt_id: Variant = _normalize_journey_id(journey)
	var cid: int = clampi(checkpoint_id, 0, JOURNEY_CHECKPOINT_CAP)
	var want: int = clampi(target, 0, JOURNEY_TARGET_CAP)
	if receipt_id == null:
		return {
			"status": JourneyReceipt.RETIRED,
			"granted": 0,
			"settled_target": 0,
		}
	var record: Array = _find_settled_journey(receipt_id)
	if not record.is_empty():
		var floor_target: int = maxi(int(record[2]), want)
		var floor_cid: int = maxi(int(record[1]), cid)
		if floor_target == int(record[2]) and floor_cid == int(record[1]):
			return {
				"status": JourneyReceipt.DUPLICATE,
				"granted": 0,
				"settled_target": int(record[2]),
			}
		var before_ledger: Array = settled_journeys.duplicate(true)
		_upsert_settled_journey(receipt_id, floor_cid, floor_target)
		if save_vault() != OK:
			settled_journeys = before_ledger
			return {
				"status": JourneyReceipt.SAVE_FAILED,
				"granted": 0,
				"settled_target": int(record[2]),
			}
		return {
			"status": JourneyReceipt.FLOORED,
			"granted": 0,
			"settled_target": floor_target,
		}
	var before_seq: int = journey_seq_issued
	var before_fresh: Array = settled_journeys.duplicate(true)
	if receipt_id is int:
		journey_seq_issued = maxi(journey_seq_issued, int(receipt_id))
	_upsert_settled_journey(receipt_id, cid, want)
	if save_vault() != OK:
		journey_seq_issued = before_seq
		settled_journeys = before_fresh
		return {
			"status": JourneyReceipt.SAVE_FAILED,
			"granted": 0,
			"settled_target": 0,
		}
	return {
		"status": JourneyReceipt.FLOORED,
		"granted": 0,
		"settled_target": want,
	}


## Receipt ids that survive a ConfigFile round trip: int sequences
## (retired downstream when never issued), their integral floats below
## 2^53, or the random fallback strings. Anything else normalizes to null
## and settles as retired: it was never issued, so it must never mint.
func _normalize_journey_id(journey: Variant) -> Variant:
	if journey is int:
		return journey
	if journey is float and journey == floorf(journey) \
			and journey > -Journey.JSON_INT_LIMIT \
			and journey < Journey.JSON_INT_LIMIT:
		return int(journey)
	if journey is String and Journey.is_safe_id(str(journey)):
		return str(journey)
	return null


## A ledger id from disk: an int sequence in range, an integral float of
## one below 2^53, or a random fallback string. Anything else is null
## (dropped on load).
func _normalize_loaded_journey_id(raw: Variant) -> Variant:
	if raw is int and int(raw) >= 1 and int(raw) <= Journey.MAX_SAFE_INT:
		return int(raw)
	if raw is float and raw >= 1.0 and raw < Journey.JSON_INT_LIMIT \
			and raw == floorf(raw):
		return int(raw)
	if raw is String and Journey.is_safe_id(str(raw)):
		return str(raw)
	return null


## Receipt equality across the mixed int/string ledger. GDScript errors on
## `7 == "r1"`, so ids compare equal only within one type.
func _same_receipt_id(left: Variant, right: Variant) -> bool:
	return typeof(left) == typeof(right) and left == right


func _find_settled_journey(receipt_id: Variant) -> Array:
	for entry in settled_journeys:
		if entry is Array and (entry as Array).size() == 3 \
				and _same_receipt_id((entry as Array)[0], receipt_id):
			return (entry as Array).duplicate()
	return []


## Decide what a locally-present checkpoint echo means for the receipt
## ledger, without granting anything. This is the restart-recovery path:
## a locally-issued integer, or a session-issued fallback, with no record
## may still be owed its failed settlement, so it is left strictly alone
## (`local-pending`) and the next `settle_journey_receipt` retry pays it
## exactly once. Only unknown ids — never issued here and never recorded,
## including evicted history and garbage — are floored with zero granted,
## which can never mint. Existing records are never raised from an echo:
## the echo may carry an unsettled retry delta that flooring would steal.
## Returns `{status, code, granted: 0, settled_target}` with code one of
## `local-pending`, `duplicate`, `floored`, `floor-save-failed`,
## `floor-retired`.
func reconcile_local_receipt(journey: Variant, checkpoint_id: int,
		target: int) -> Dictionary:
	var receipt_id: Variant = _normalize_journey_id(journey)
	if receipt_id == null:
		return {
			"status": JourneyReceipt.RETIRED,
			"code": "floor-retired",
			"granted": 0,
			"settled_target": 0,
		}
	if not _find_settled_journey(receipt_id).is_empty():
		return {
			"status": JourneyReceipt.DUPLICATE,
			"code": "duplicate",
			"granted": 0,
			"settled_target": int(
				_find_settled_journey(receipt_id)[2]),
		}
	if receipt_id is int and int(receipt_id) <= journey_seq_issued:
		return {
			"status": JourneyReceipt.DUPLICATE,
			"code": "local-pending",
			"granted": 0,
			"settled_target": 0,
		}
	if receipt_id is String \
			and _issued_fallback_ids.has(str(receipt_id)):
		return {
			"status": JourneyReceipt.DUPLICATE,
			"code": "local-pending",
			"granted": 0,
			"settled_target": 0,
		}
	var floored: Dictionary = initialize_remote_receipt_floor(
		receipt_id, checkpoint_id, target)
	var code: String = "floor-retired"
	if int(floored.get("status", -1)) == JourneyReceipt.FLOORED:
		code = "floored"
	elif int(floored.get("status", -1)) == JourneyReceipt.SAVE_FAILED:
		code = "floor-save-failed"
	elif int(floored.get("status", -1)) == JourneyReceipt.DUPLICATE:
		code = "duplicate"
	floored["code"] = code
	return floored


## A string id with no ledger record settles only when this session
## issued it and it has not settled yet. Anything else — an evicted
## fallback replayed, or a string that was never issued — retires and
## mints nothing.
func _journey_string_retired(candidate: String) -> bool:
	if not _find_settled_journey(candidate).is_empty():
		return false
	return not _issued_fallback_ids.has(candidate)


## A sequence id with no record is retired when it sits below every retained
## one (evicted past the bound), or was never issued at all. The live
## sequence may not have sealed yet, so it is never retired.
func _journey_seq_retired(seq: int) -> bool:
	if seq < 1 or seq > journey_seq_issued:
		return true
	if seq == journey_seq_issued or not _find_settled_journey(seq).is_empty():
		return false
	var floor: int = journey_seq_issued + 1
	for entry in settled_journeys:
		if entry is Array and (entry as Array).size() == 3 \
				and (entry as Array)[0] is int:
			floor = mini(floor, int((entry as Array)[0]))
	return seq < floor


func _upsert_settled_journey(
	receipt_id: Variant, checkpoint_id: int, target: int
) -> void:
	for i in settled_journeys.size():
		var entry: Array = settled_journeys[i]
		if entry.size() == 3 \
				and _same_receipt_id(entry[0], receipt_id):
			settled_journeys[i] = [receipt_id, checkpoint_id, target]
			return
	settled_journeys.append([receipt_id, checkpoint_id, target])
	while settled_journeys.size() > MAX_SETTLED_JOURNEYS:
		if not _evict_one_settled_journey(receipt_id):
			break


## Shrink the ledger past its bound. Lowest sequence first, so retirement
## (below every retained id) stays sound; random fallbacks oldest-first.
## Never the just-written entry.
func _evict_one_settled_journey(keep: Variant) -> bool:
	var victim: int = -1
	var victim_seq: int = -1
	for i in settled_journeys.size():
		var entry: Array = settled_journeys[i]
		if entry.size() != 3 or _same_receipt_id(entry[0], keep):
			continue
		if entry[0] is int \
				and (victim_seq < 0 or int(entry[0]) < victim_seq):
			victim = i
			victim_seq = int(entry[0])
	if victim >= 0:
		settled_journeys.remove_at(victim)
		return true
	for i in settled_journeys.size():
		var entry: Array = settled_journeys[i]
		if entry.size() == 3 and not _same_receipt_id(entry[0], keep):
			settled_journeys.remove_at(i)
			return true
	return false


func rank_of(path: String) -> int:
	return int(ranks.get(path, 0))


## Can this boon be raised one more rank.
func can_raise(boon: Boon, path: String) -> bool:
	var rank: int = rank_of(path)
	return rank < boon.max_rank and shards >= boon.cost_at(rank + 1)


## Even if the value changed after the button was drawn, do not process the
## same buy twice.
##
## `expected_rank` is the rank that was on screen. To stop a fast double-tap
## from buying the next rank too, compare to the real rank again just before
## deducting.
func purchase_boon(boon: Boon, path: String, expected_rank: int) -> int:
	if boon == null or path not in POOL:
		return PurchaseResult.INVALID
	# Price and max rank are re-read from the list original, not trusted from
	# the button's resource. A stale UI or a wrong resource still leaves
	# grant authority with Vault.
	var catalog_boon: Boon = load(path) as Boon
	if catalog_boon == null or boon.resource_path != catalog_boon.resource_path:
		return PurchaseResult.INVALID
	boon = catalog_boon
	var rank: int = rank_of(path)
	if rank != expected_rank:
		return PurchaseResult.STALE
	if rank >= boon.max_rank:
		return PurchaseResult.MAXED
	var cost: int = boon.cost_at(rank + 1)
	if shards < cost:
		return PurchaseResult.INSUFFICIENT
	var before_shards: int = shards
	shards -= cost
	ranks[path] = rank + 1
	if save_vault() != OK:
		shards = before_shards
		if rank <= 0:
			ranks.erase(path)
		else:
			ranks[path] = rank
		return PurchaseResult.SAVE_FAILED
	changed.emit()
	return PurchaseResult.OK


## Short form existing callers use. New UI calls `purchase_boon()` directly
## to show a failure reason.
func raise(boon: Boon, path: String) -> bool:
	return purchase_boon(boon, path, rank_of(path)) == PurchaseResult.OK


## How much of this kind of boon is currently raised. The arena reads this
## when opening a run.
##
## Path is the key, so adding one `.tres` grows boons — this code does not.
func grace(kind: int) -> float:
	var sum: float = 0.0
	for path in POOL:
		var rank: int = rank_of(path)
		if rank <= 0:
			continue
		var boon: Boon = load(path) as Boon
		if boon != null and boon.grace == kind:
			sum += boon.amount_at(rank)
	return sum


## Currently picked character. A bad saved value falls back to the first —
## delete a `.tres` while the save still points at it and the run cannot open.
func hero() -> Hero:
	var found: Hero = load(hero_path()) as Hero
	return found if found != null else load(HEROES[0]) as Hero


## Path of the character actually in use.
##
## **Do not use `chosen` as-is.** It starts empty and fills only when a
## character is tapped at the shrine. Meanwhile the run plays `HEROES[0]`
## (Moon Warden) — saved value and used value differ.
##
## Put that on the board and anyone who never entered the shrine always had
## `-` in the character cell. The half of the board `ladder.gd` comments call
## "who scored it on which character" vanished for every default user.
func hero_path() -> String:
	return chosen if chosen in HEROES else HEROES[0]


## Debug-build switch that opens every hero for this session only. **Does not
## save** — vault.cfg opened/hero_sources are untouched, so relaunch restores
## the original lock and purchase-source checks stay. Release
## debug_open_all_heroes() always returns false, so there is no way to turn
## it on. Debug builds start with it on. Checking a new sprite on all six
## without tapping a button every time. Release blocks both functions below.
##
## **Do not turn it on in a regression-test session.** Lock and purchase-path
## checks all assume "only the default hero is open," so shrine layout and
## IAP-disabled checks go red with no real bug. Isolated-root env vars
## identify tests.
var _debug_heroes_open: bool = OS.is_debug_build() \
	and OS.get_environment("MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").is_empty()


func debug_open_all_heroes() -> bool:
	if not OS.is_debug_build():
		return false
	_debug_heroes_open = not _debug_heroes_open
	return _debug_heroes_open


## Actually owned hero. **Ignores the debug bypass.**
##
## `hero_open()` means "may this hero be played," so in debug it is always true.
## If the shop uses that to decide "already owned," a debug-build review image
## shows "Already unlocked" instead of a price — the image must show what an
## unpurchased player sees. Ownership checks use this function.
func hero_earned(path: String) -> bool:
	if path not in HEROES:
		return false
	return path == HEROES[0] or path in opened


func hero_open(path: String) -> bool:
	if path not in HEROES:
		return false
	var found: Hero = load(path) as Hero
	if found == null:
		return false
	# Test-only bypass that opens all six heroes to check a new sprite.
	if OS.is_debug_build() and _debug_heroes_open:
		return true
	# Letting the price resource decide free status lets one misconfigured paid
	# `.tres` bypass payment. The free hero is fixed as the first Warden in the list.
	return path == HEROES[0] or path in opened


func hero_iap_source(path: String) -> String:
	if path not in PAID_HEROES:
		return ""
	return HERO_SOURCE_IAP_PREFIX + path.get_file().get_basename()


func _hero_source_is_valid(path: String, source: String) -> bool:
	if source == HERO_SOURCE_SHARDS:
		# Grandfather shard sources only for the two heroes that could actually
		# unlock with shards in 1.0.0. Reject saves or bad internal calls that
		# inject a shard source onto a new paid hero to bypass payment.
		return path in LEGACY_BUNDLE_HEROES
	if source == HERO_SOURCE_IAP_BUNDLE:
		return path in LEGACY_BUNDLE_HEROES
	return source == hero_iap_source(path) and not source.is_empty()


func any_hero_has_source(paths: Array[String], source: String) -> bool:
	for path in paths:
		if path in HEROES and _hero_source_is_valid(path, source) \
				and source in hero_sources.get(path, []):
			return true
	return false


func purchase_hero(path: String) -> int:
	if path not in HEROES:
		return PurchaseResult.INVALID
	var found: Hero = load(path) as Hero
	if found == null:
		return PurchaseResult.INVALID
	if hero_open(path):
		return PurchaseResult.OWNED
	if path in PAID_HEROES:
		return PurchaseResult.INVALID
	if shards < found.unlock_cost:
		return PurchaseResult.INSUFFICIENT
	var before_shards: int = shards
	shards -= found.unlock_cost
	opened.append(path)
	hero_sources[path] = [HERO_SOURCE_SHARDS]
	if save_vault() != OK:
		shards = before_shards
		opened.erase(path)
		hero_sources.erase(path)
		return PurchaseResult.SAVE_FAILED
	changed.emit()
	return PurchaseResult.OK


func open_hero(path: String) -> bool:
	return purchase_hero(path) == PurchaseResult.OK


## Open several heroes at once, as with a store hero bundle.
##
## Uses no shards and leaves already-open heroes alone. Saving each hero
## separately can grant only half the bundle if the app exits after the first
## save, so this writes once. On save failure, roll back only what this call opened.
func grant_heroes(
		paths: Array[String], source: String = HERO_SOURCE_IAP_BUNDLE) -> bool:
	for path in paths:
		if path not in HEROES or not _hero_source_is_valid(path, source):
			return false
		var candidate: Hero = load(path) as Hero
		if candidate == null:
			return false
	var before_opened: Array[String] = opened.duplicate()
	var before_sources: Dictionary = hero_sources.duplicate(true)
	var changed_any: bool = false
	for path in paths:
		var sources: Array = hero_sources.get(path, [])
		if source not in sources:
			sources.append(source)
			hero_sources[path] = sources
			changed_any = true
		if path not in opened:
			opened.append(path)
			changed_any = true
	if not changed_any:
		return true
	if save_vault() != OK:
		opened = before_opened
		hero_sources = before_sources
		return false
	changed.emit()
	return true


## Strip one source when applying a confirmed refund. The current client does
## not call this just because the store catalog is empty. This is the boundary
## used when the server/store confirms a refund.
func revoke_heroes(paths: Array[String], source: String) -> bool:
	for path in paths:
		if path not in HEROES or not _hero_source_is_valid(path, source) \
				or source == HERO_SOURCE_SHARDS:
			return false
	var before_opened: Array[String] = opened.duplicate()
	var before_sources: Dictionary = hero_sources.duplicate(true)
	var before_chosen: String = chosen
	var changed_any: bool = false
	for path in paths:
		var sources: Array = hero_sources.get(path, [])
		if source in sources:
			sources.erase(source)
			changed_any = true
		if sources.is_empty():
			hero_sources.erase(path)
			opened.erase(path)
		else:
			hero_sources[path] = sources
	if not changed_any:
		return true
	if chosen not in opened and chosen != HEROES[0]:
		chosen = ""
	if save_vault() != OK:
		opened = before_opened
		hero_sources = before_sources
		chosen = before_chosen
		return false
	changed.emit()
	return true


func choose_hero(path: String) -> bool:
	if not hero_open(path):
		return false
	if chosen == path:
		return true
	var before: String = chosen
	chosen = path
	if save_vault() != OK:
		chosen = before
		return false
	changed.emit()
	return true


## How many **next ranks / locked heroes** can be bought right now.
##
## Even if one boon line can buy several ranks, the badge counts one line.
## Walking in on "3 available" that also tallied the same boon's next ranks
## would break the promise against the screen.
func affordable_purchase_count() -> int:
	var count: int = 0
	for path in POOL:
		var boon: Boon = load(path) as Boon
		if boon == null:
			continue
		var rank: int = rank_of(path)
		if rank < boon.max_rank and boon.cost_at(rank + 1) <= shards:
			count += 1
	for path in HEROES:
		if path in PAID_HEROES:
			continue
		var candidate: Hero = load(path) as Hero
		if candidate != null and not hero_open(path) and candidate.unlock_cost <= shards:
			count += 1
	return count


## Purchase candidates shared by the shrine and the result screen.
##
## Product knowledge lives in Vault alone. If the result screen copies the
## boon price formula, the day prices change the "available" badge and the
## real button disagree.
func purchase_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for path in POOL:
		var boon: Boon = load(path) as Boon
		if boon == null:
			continue
		var rank: int = rank_of(path)
		if rank >= boon.max_rank:
			continue
		options.append({
			"kind": &"boon",
			"path": path,
			"name": tr(boon.display_name),
			"description": boon.describe(rank),
			"cost": boon.cost_at(rank + 1),
			"rank": rank,
			"accent": boon.accent,
		})
	for path in HEROES:
		if path in PAID_HEROES:
			continue
		var candidate: Hero = load(path) as Hero
		if candidate == null or hero_open(path):
			continue
		options.append({
			"kind": &"hero",
			"path": path,
			"name": tr(candidate.display_name),
			"description": tr(candidate.description),
			"cost": candidate.unlock_cost,
			"rank": 0,
			"accent": candidate.accent,
		})
	return options


## Recommend the cheapest buyable option, or if none, the one short by the least.
##
## No timers or fake discounts — only a **nearby real goal.**
func next_purchase() -> Dictionary:
	var best: Dictionary = {}
	for option in purchase_options():
		if best.is_empty() or _purchase_precedes(option, best):
			best = option
	return best


func _purchase_precedes(candidate: Dictionary, current: Dictionary) -> bool:
	var candidate_cost: int = int(candidate.get("cost", 0))
	var current_cost: int = int(current.get("cost", 0))
	var candidate_ready: bool = candidate_cost <= shards
	var current_ready: bool = current_cost <= shards
	if candidate_ready != current_ready:
		return candidate_ready
	if candidate_ready:
		return candidate_cost < current_cost
	var candidate_short: int = maxi(candidate_cost - shards, 0)
	var current_short: int = maxi(current_cost - shards, 0)
	if candidate_short != current_short:
		return candidate_short < current_short
	return candidate_cost < current_cost


## Arcade continue coins. Real-money consumables — keep them out of the shard pool.
##
## **Shards are earned by play; coins are bought with money.** Even in one save
## file the two must not convert, or players think "farm shards for free
## continues" or "spending money grants shards."
## Free continues granted at first launch.
##
## **Players must try continues before they will buy them.** Arcades start the
## first credit in the machine. Two is enough to feel that continue keeps the
## run going; after that they buy.
const STARTING_COINS: int = 2
## Largest pack currently sold. Vault also blocks grants larger than the catalog.
const MAX_CONTINUE_COIN_GRANT: int = 10

var continue_coins: int = STARTING_COINS
## Grant count per transaction key. Atomic with the balance in one file so crashes neither double nor drop grants.
var continue_coin_grants: Dictionary = {}


## Grant coins. Only `Shop` calls this after a real payment is verified.
##
## Balance and transaction key land in one atomic save. Whether the app dies
## before or after that write, both are absent or both are present, so the same
## transaction can be retried safely.
func grant_continue_coins(count: int, transaction_key: String) -> bool:
	var clean_key: String = transaction_key.strip_edges()
	if count <= 0 or count > MAX_CONTINUE_COIN_GRANT or clean_key.is_empty():
		return false
	if continue_coin_grants.has(clean_key):
		return int(continue_coin_grants[clean_key]) == count
	continue_coins += count
	continue_coin_grants[clean_key] = count
	if save_vault() != OK:
		continue_coins -= count
		continue_coin_grants.erase(clean_key)
		return false
	changed.emit()
	return true


## Schema 4 IAP ledgers had grant transaction keys; Vault did not.
## Those old ledgers already point at the granted balance, so on upgrade move
## only the idempotency keys into the same atomic save — do not raise the balance.
func adopt_continue_coin_grant(count: int, transaction_key: String) -> bool:
	var clean_key: String = transaction_key.strip_edges()
	if count <= 0 or count > MAX_CONTINUE_COIN_GRANT or clean_key.is_empty():
		return false
	if continue_coin_grants.has(clean_key):
		return int(continue_coin_grants[clean_key]) == count
	continue_coin_grants[clean_key] = count
	if save_vault() != OK:
		continue_coin_grants.erase(clean_key)
		return false
	return true


## Continue one run. If the balance is empty, spend nothing and return false.
func spend_continue_coin() -> bool:
	if continue_coins <= 0:
		return false
	continue_coins -= 1
	if save_vault() != OK:
		continue_coins += 1
		return false
	changed.emit()
	return true


func load_vault() -> void:
	shards = 0
	continue_coins = STARTING_COINS
	continue_coin_grants.clear()
	ranks.clear()
	opened.clear()
	hero_sources.clear()
	chosen = ""
	journey_seq_issued = 0
	settled_journeys.clear()
	var file: ConfigFile = _load_saved_config()
	if file == null:
		return                                   # First launch. An empty vault is normal
	shards = maxi(int(file.get_value(SECTION, "shards", 0)), 0)
	continue_coins = maxi(
		int(file.get_value(SECTION, "continue_coins", STARTING_COINS)), 0)
	var saved_version: int = int(file.get_value(SECTION, "schema_version", 0))
	if saved_version >= 5:
		var saved_grants: Variant = file.get_value(
			SECTION, "continue_coin_grants", {})
		if saved_grants is Dictionary:
			for raw_key in saved_grants:
				var transaction_key: String = str(raw_key).strip_edges()
				var count: int = int(saved_grants[raw_key])
				if not transaction_key.is_empty() \
						and count > 0 and count <= MAX_CONTINUE_COIN_GRANT:
					continue_coin_grants[transaction_key] = count
	if saved_version >= 3:
		var saved_sources: Variant = file.get_value(SECTION, "hero_sources", {})
		if saved_sources is Dictionary:
			for raw_path in saved_sources:
				var candidate: String = str(raw_path)
				if candidate not in HEROES:
					continue
				var clean_sources: Array[String] = []
				var source_values: Variant = saved_sources[raw_path]
				if source_values is Array:
					for raw_source in source_values:
						var source: String = str(raw_source)
						if _hero_source_is_valid(candidate, source) \
								and source not in clean_sources:
							clean_sources.append(source)
				if not clean_sources.is_empty():
					hero_sources[candidate] = clean_sources
					opened.append(candidate)
	else:
		# Old saves have no source. Safer to migrate conservatively as play-earned
		# than to guess they were bought with money and strip them.
		var saved_opened: Variant = file.get_value(SECTION, "opened", [])
		if saved_opened is Array:
			for path in saved_opened:
				var candidate: String = str(path)
				# Only these two shard heroes could legally appear in a 1.0.0 save.
				# Injecting a paid-hero path added in 1.0.1 into old-schema `opened`
				# must not promote it to grandfather rights.
				if candidate in LEGACY_BUNDLE_HEROES and candidate not in opened:
					opened.append(candidate)
					hero_sources[candidate] = [HERO_SOURCE_SHARDS]
	for path in POOL:
		var boon: Boon = load(path) as Boon
		if boon == null:
			continue
		var rank: int = clampi(int(file.get_value(SECTION, path, 0)), 0, boon.max_rank)
		if rank > 0:
			ranks[path] = rank
	var saved_hero: String = str(file.get_value(SECTION, "hero", ""))
	if saved_hero in HEROES and hero_open(saved_hero):
		chosen = saved_hero
	# Journey receipts are optional in every schema: old saves predate them
	# and load with an empty ledger. Entries that fail shape are dropped, so
	# a hand-edited ledger can only lose history, never mint from it.
	journey_seq_issued = maxi(int(file.get_value(
		SECTION, "journey_seq_issued", 0)), 0)
	var saved_settled: Variant = file.get_value(SECTION, "settled_journeys", [])
	if saved_settled is Array:
		var seen: Dictionary = {}
		for raw in saved_settled:
			if not raw is Array or (raw as Array).size() != 3:
				continue
			var loaded_id: Variant = _normalize_loaded_journey_id(
				(raw as Array)[0])
			var loaded_cid: Variant = (raw as Array)[1]
			var loaded_target: Variant = (raw as Array)[2]
			if loaded_id == null or not loaded_cid is int \
					or not loaded_target is int:
				continue
			if int(loaded_cid) < 0 or int(loaded_cid) > JOURNEY_CHECKPOINT_CAP:
				continue
			if int(loaded_target) < 0 \
					or int(loaded_target) > JOURNEY_TARGET_CAP:
				continue
			var slot: String = "%s:%s" % [
				typeof(loaded_id), str(loaded_id)]
			if seen.has(slot):
				continue
			seen[slot] = true
			settled_journeys.append(
				[loaded_id, int(loaded_cid), int(loaded_target)])
		while settled_journeys.size() > MAX_SETTLED_JOURNEYS:
			if not _evict_one_settled_journey(null):
				break


func save_vault() -> Error:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION, "schema_version", SCHEMA_VERSION)
	file.set_value(SECTION, "shards", shards)
	file.set_value(SECTION, "continue_coins", continue_coins)
	file.set_value(SECTION, "continue_coin_grants", continue_coin_grants)
	file.set_value(SECTION, "hero", chosen)
	file.set_value(SECTION, "opened", opened)
	file.set_value(SECTION, "hero_sources", hero_sources)
	file.set_value(SECTION, "journey_seq_issued", journey_seq_issued)
	file.set_value(SECTION, "settled_journeys", settled_journeys)
	for path in POOL:
		file.set_value(SECTION, path, rank_of(path))
	var encoded: String = file.encode_to_text()
	var write_error: Error = _write_verified_text(encoded, TEMP_SAVE_PATH)
	if write_error != OK:
		_discard_file(TEMP_SAVE_PATH)
		return write_error
	var backup_error: Error = _backup_current_save()
	if backup_error != OK:
		_discard_file(TEMP_SAVE_PATH)
		return backup_error

	# Same-folder rename swaps the primary file in one step. Before the swap the
	# previous primary is visible; after it the verified temp is. No half-written
	# middle state is exposed if the app exits.
	var replace_error: Error = _replace_save(TEMP_SAVE_PATH, SAVE_PATH)
	if replace_error != OK:
		_discard_file(TEMP_SAVE_PATH)
	return replace_error


func _load_saved_config() -> ConfigFile:
	var primary: ConfigFile = ConfigFile.new()
	var primary_loaded: bool = primary.load(SAVE_PATH) == OK
	if primary_loaded and _config_is_current(primary):
		return primary

	var backup: ConfigFile = ConfigFile.new()
	var primary_usable: bool = primary_loaded and _config_is_usable(primary)
	var backup_usable: bool = backup.load(BACKUP_SAVE_PATH) == OK \
		and _config_is_usable(backup)
	if primary_usable and int(primary.get_value(SECTION, "schema_version", 0)) > 0:
		if not backup_usable:
			return primary
		var primary_version: int = int(primary.get_value(SECTION, "schema_version", 0))
		var backup_version: int = int(backup.get_value(SECTION, "schema_version", 0))
		# For the same version, a healthy primary is one save newer. ConfigFile can
		# still parse a truncated tail, so prefer the backup when the primary has
		# fewer known keys. A truncated file left with only a high schema line must
		# not beat a more complete older save. Use the version number as freshness
		# only when known-value counts are equal or higher.
		if primary_version >= backup_version \
				and _known_key_count(primary) >= _known_key_count(backup):
			return primary

	if backup_usable:
		# If the primary is missing or truncated mid-schema, restore the last good copy.
		# A cut before the version line can look like an old save, so a healthy backup
		# wins over an incomplete primary. Continue this run even if the restore write fails.
		var restore_error: Error = _write_verified_text(
			backup.encode_to_text(), TEMP_SAVE_PATH)
		if restore_error == OK:
			restore_error = _replace_save(TEMP_SAVE_PATH, SAVE_PATH)
		if restore_error != OK:
			_discard_file(TEMP_SAVE_PATH)
		return backup

	# Only on a first launch with no backup, migrate a versionless old save as-is.
	if primary_usable:
		return primary
	return null


func _config_is_current(file: ConfigFile) -> bool:
	return _config_is_usable(file) \
		and int(file.get_value(SECTION, "schema_version", 0)) == SCHEMA_VERSION


func _config_is_usable(file: ConfigFile) -> bool:
	if not file.has_section(SECTION):
		return false
	var version: Variant = file.get_value(SECTION, "schema_version", 0)
	if typeof(version) != TYPE_INT or int(version) < 0 or int(version) > SCHEMA_VERSION:
		return false
	if file.has_section_key(SECTION, "shards") \
			and typeof(file.get_value(SECTION, "shards")) != TYPE_INT:
		return false
	if file.has_section_key(SECTION, "continue_coins") \
			and typeof(file.get_value(SECTION, "continue_coins")) != TYPE_INT:
		return false
	if file.has_section_key(SECTION, "continue_coin_grants") \
			and typeof(file.get_value(SECTION, "continue_coin_grants")) \
			!= TYPE_DICTIONARY:
		return false
	if file.has_section_key(SECTION, "hero") \
			and typeof(file.get_value(SECTION, "hero")) != TYPE_STRING:
		return false
	if file.has_section_key(SECTION, "opened") \
			and typeof(file.get_value(SECTION, "opened")) != TYPE_ARRAY:
		return false
	if file.has_section_key(SECTION, "hero_sources") \
			and typeof(file.get_value(SECTION, "hero_sources")) != TYPE_DICTIONARY:
		return false
	if file.has_section_key(SECTION, "journey_seq_issued") \
			and typeof(file.get_value(SECTION, "journey_seq_issued")) != TYPE_INT:
		return false
	if file.has_section_key(SECTION, "settled_journeys") \
			and typeof(file.get_value(SECTION, "settled_journeys")) != TYPE_ARRAY:
		return false
	for path in POOL:
		if file.has_section_key(SECTION, path) \
				and typeof(file.get_value(SECTION, path)) != TYPE_INT:
			return false

	# Only versionless old saves fill missing core keys with defaults. A versioned
	# file must keep the minimum core keys so a truncated primary cannot overwrite
	# a healthy backup.
	if int(version) > 0:
		for key in ["shards", "hero", "opened"]:
			if not file.has_section_key(SECTION, key):
				return false
	if int(version) == SCHEMA_VERSION:
		for key in ["hero_sources", "continue_coins", "continue_coin_grants"]:
			if not file.has_section_key(SECTION, key):
				return false
		for path in POOL:
			if not file.has_section_key(SECTION, path):
				return false
	return true


func _known_key_count(file: ConfigFile) -> int:
	var count: int = 0
	for key in [
		"shards", "continue_coins", "continue_coin_grants",
		"hero", "opened", "hero_sources",
		"journey_seq_issued", "settled_journeys",
	]:
		if file.has_section_key(SECTION, key):
			count += 1
	for path in POOL:
		if file.has_section_key(SECTION, path):
			count += 1
	return count


func _backup_current_save() -> Error:
	if not FileAccess.file_exists(SAVE_PATH):
		return OK
	var current: ConfigFile = ConfigFile.new()
	if current.load(SAVE_PATH) != OK or not _config_is_usable(current):
		return OK                               # Do not overwrite a healthy backup with a corrupt copy
	var current_text: String = FileAccess.get_file_as_string(SAVE_PATH)
	var read_error: Error = FileAccess.get_open_error()
	if read_error != OK:
		return read_error
	var write_error: Error = _write_verified_text(current_text, BACKUP_TEMP_SAVE_PATH)
	if write_error != OK:
		_discard_file(BACKUP_TEMP_SAVE_PATH)
		return write_error
	var replace_error: Error = _replace_save(BACKUP_TEMP_SAVE_PATH, BACKUP_SAVE_PATH)
	if replace_error != OK:
		_discard_file(BACKUP_TEMP_SAVE_PATH)
	return replace_error


func _write_verified_text(encoded: String, path: String) -> Error:
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		return FileAccess.get_open_error()
	if not output.store_string(encoded):
		var store_error: Error = output.get_error()
		output.close()
		return store_error if store_error != OK else ERR_FILE_CANT_WRITE
	output.flush()
	var flush_error: Error = output.get_error()
	output.close()
	if flush_error != OK:
		return flush_error

	# ConfigFile.save() empties the primary first and ignores write errors.
	# Verify the temp file's bytes and syntax, then rename in the same folder so
	# if the app dies mid-write, either the previous or the new file remains intact.
	var written: String = FileAccess.get_file_as_string(path)
	var read_error: Error = FileAccess.get_open_error()
	if read_error != OK or written != encoded:
		return read_error if read_error != OK else ERR_FILE_CORRUPT
	var verified: ConfigFile = ConfigFile.new()
	return verified.load(path)


func _replace_save(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from_path),
		ProjectSettings.globalize_path(to_path))


func _discard_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
