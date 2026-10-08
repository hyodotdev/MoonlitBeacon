class_name Journey
extends RefCounted

## The saved journey: where the run stands, kept across launches.
##
## The game is endless, so quitting must not throw the run away. After every
## safe moment — crossing a moon gate, or carrying the guardian's reward into
## the next cycle — the arena writes a segment-entry checkpoint: cycle, zone,
## deterministic route and seed, hero, held relic stacks, combat growth,
## score counters and reward-settlement bookkeeping. Dying seals the journey
## with a terminal `ended` marker instead; the title's Continue only resumes
## a run that is still alive, and a fresh expedition starts a new journey.
##
## Checkpoints are segment entries on purpose. Nothing mid-frame is
## serialized: no projectiles, enemies or physics state. Restore rebuilds the
## field through the same production methods a fresh segment uses, then feeds
## the saved relic stacks through the real pick path. What is transient
## (moonfire charge, combos, skill cooldowns, floor loot) starts empty; what
## is growth (relics, level, missile power, score counters) comes back whole.
##
## Settlement rules, so retries can never farm:
##
## - Earned shards settle as Vault receipts keyed by `(journey, checkpoint)`
##   with a cumulative target (`Vault.settle_journey_receipt`). The Vault's
##   durable ledger — not this file's echo — is the grant authority, so a
##   successful Vault save plus a failed journey write or a crash still
##   grants exactly once: the redelivery reads `DUPLICATE` and pays 0.
## - A checkpoint records `shards_awarded` and `settled_score` as an echo of
##   the ledger, and gate/cycle checkpoints settle before writing. Death
##   settles the final live score once and seals it into the terminal
##   marker's echo, so repeated exits, restores or relaunches grant nothing
##   more: the redelivery reads `DUPLICATE` and pays 0.
## - Settlement failure seals nothing as settled: the checkpoint keeps its
##   old echo and the next seal's cumulative target carries the value.
## - A paid continue journals its debit and exact revive seal in the Vault
##   before the alive checkpoint is written, so a crash can only strand a
##   paid seal — recovered without another charge — never an unpaid alive
##   checkpoint. Entry points settle the journal before reading.
## - The very first checkpoint settles nothing. Banking a shard for merely
##   starting would pay out on every fresh start without playing.
## - Records submit the final score on death. A repeat submit of the same
##   total reads `NOT_BEST`; only further progress saves anew.
## - Only a paid continue coin revives a sealed defeat, in place, and only
##   the live arena's `continue_run` may clear the marker by sealing a new
##   alive checkpoint. No title, backup or cloud path resumes a sealed run.
##
## Safety rules:
##
## - Verified bytes stage in a temp file and install by rename only; the
##   main save is never deleted, and any failure keeps a playable prior save.
## - The previous valid save rotates into the backup through the same atomic
##   install. A corrupt main falls back to it; an invalid file must never
##   overwrite a good backup. A terminal marker instead mirrors into both
##   files, backup first: no older alive backup survives the seal, so a
##   later corrupt main still reads terminal. A main that validates ended
##   also converges a stale alive backup forward on read, which migrates
##   pairs sealed before the mirror; a live main with a same-journey ended
##   backup at no older seal is a seal whose main write never finished, and
##   reads terminal too. Alive pairs with no seal anywhere still recover
##   from the backup exactly as before.
## - Reads are length-gated before a byte is kept. Loading validates every
##   field: non-integer or future schemas, oversized or truncated files, and
##   resource paths outside the hero/relic allowlists are refused as a
##   whole: no partial state, no arbitrary `load()`.
## - Journey state never touches the Vault's purchase ledger. A refused save
##   cannot erase paid heroes, coins or boons.
## - Only a human run writes. The title arms writes when leaving for the
##   arena; tests, debug boards and capture harnesses never arm and their
##   arena instances neither write nor restore. Backgrounding the app writes
##   nothing: the file already holds the last known-valid checkpoint.

## A title entry that has not chosen yet, a fresh journey, or a resume.
enum Pending { NONE, FRESH, RESUME }

## Fault injection for the main install, test-only. `SKIP_DIRECT` forces
## the rotate fallback to prove it installs; `FAIL_TEMP_INSTALL` fails the
## rotated install to prove the aside copy restores; `FAIL_ALL` fails
## rotation before anything moves to prove the abort keeps the main save.
## The nested backup refresh always runs unfaulted (its own failure is
## injected for real by occupying its temp path). Production runs `NONE`.
enum InstallFault { NONE, SKIP_DIRECT, FAIL_TEMP_INSTALL, FAIL_ALL }

const DEFAULT_PATH: String = "user://journey.json"
const DEFAULT_BACKUP_PATH: String = "user://journey.json.bak"
const SCHEMA_VERSION: int = 1
## A checkpoint is a few hundred bytes of numbers and paths. Anything past
## this is not a checkpoint and is refused before a single byte is kept.
const MAX_FILE_BYTES: int = 65536
## Highest playable cycle. The run is endless, so this bound must never stop
## continuation: at any human pace 99999 cycles is centuries of gates, while
## scores and telemetry derived from it stay inside 64-bit integers and the
## exactly representable JSON range. Authored content ends long before; past
## it the endless episode carries on.
const MAX_CYCLE: int = 99999
const MAX_LEVEL: int = 9999
const MAX_STACKS: int = 999
const MAX_STACK_ENTRIES: int = 64
## Largest integer JSON carries exactly: 2^53 - 1. In-memory ints compare
## against it exactly, so 2^53 already fails. A parsed integral float at or
## past 2^53 (`JSON_INT_LIMIT`) fails too: it may be a rounded stranger like
## 9007199254740993, and parsing cannot recover precision already lost.
const MAX_SAFE_INT: int = 9007199254740991
## Exclusive float envelope for JSON integers: 2^53, exactly representable.
const JSON_INT_LIMIT: float = 9007199254740992.0
const HERO_DIR: String = "res://resources/heroes/"
const RELIC_DIR: String = "res://resources/relics/"
const RESOURCE_SUFFIX: String = ".tres"

## Where to read and write. Tests point these at temp files.
static var path: String = DEFAULT_PATH
static var backup_path: String = DEFAULT_BACKUP_PATH
## True once a human run started from the title (or an explicit fresh
## restart). The arena writes checkpoints only while this is on.
static var armed: bool = false
## What the next arena `_ready` must do. Consumed once.
static var pending: int = Pending.NONE
## Why the last read or write failed, in one line for the UI. Empty when the
## last operation succeeded.
static var last_error: String = ""
## Active install fault for failure-injection tests. Always `NONE` in play.
static var install_fault: int = InstallFault.NONE
## Account partition in use: the public ID (or the requested guest ID while
## the account is still unregistered) whose slot `path`/`backup_path` point
## at. Empty means the legacy single save for players who never sign in.
static var active_account: String = ""
## Stable-checkpoint subscribers, called once per verified local write with
## `{text, path, backup_path}`. The cloud coordinator subscribes to queue
## uploads; gameplay never waits on them.
static var _stable_hooks: Array[Callable] = []


## A human run starts over. Arms writes; the arena clears any old save.
static func begin_fresh() -> void:
	pending = Pending.FRESH
	armed = true
	last_error = ""


## A human run steps back through its last gate. Arms writes; the arena
## restores the checkpoint or falls back to a fresh run, visibly.
static func begin_resume() -> void:
	pending = Pending.RESUME
	armed = true
	last_error = ""


## Take the pending title action, resetting it to `NONE`. Arming stays.
static func consume_pending() -> int:
	var action: int = pending
	pending = Pending.NONE
	return action


## Leaving the arena for the title. The file stays; writes stop.
static func disarm() -> void:
	armed = false
	pending = Pending.NONE


## Subscribe to stable checkpoints. The hook fires once per verified local
## write with `{text, path, backup_path}`; failed writes never notify.
static func subscribe_stable_checkpoint(hook: Callable) -> void:
	if hook.is_valid() and not _stable_hooks.has(hook):
		_stable_hooks.append(hook)


## Drop one stable-checkpoint subscription. Switching accounts or tearing
## down must unsubscribe so late callbacks cannot queue under a new account.
static func unsubscribe_stable_checkpoint(hook: Callable) -> void:
	_stable_hooks.erase(hook)


## Drop every stable-checkpoint subscription. For tests only.
static func clear_stable_hooks() -> void:
	_stable_hooks.clear()


## Account ids are never trusted as path text. Public `MB-` ids are safe
## already; anything else becomes a stable hash token.
static func safe_account_token(account_id: String) -> String:
	if account_id.is_empty():
		return "empty"
	var plain: bool = account_id.length() <= 64
	if plain:
		for code in account_id.to_utf8_buffer():
			var ok: bool = (code >= 48 and code <= 57) \
				or (code >= 65 and code <= 90) \
				or (code >= 97 and code <= 122) \
				or code == 45 or code == 95
			if not ok:
				plain = false
				break
	if plain:
		return account_id
	return "h_" + account_id.sha256_text().substr(0, 32)


## Partitioned slot for one account: main, backup, cloud revision metadata,
## and the last rejected local/remote payloads kept for recovery. Each
## account's journey lives in its own files; switching accounts only repoints
## `path`/`backup_path` and never copies one journey over another.
static func account_main_path(account_id: String) -> String:
	return "user://journey." + safe_account_token(account_id) + ".json"


static func account_backup_path(account_id: String) -> String:
	return account_main_path(account_id) + ".bak"


static func account_revision_path(account_id: String) -> String:
	return "user://journey." + safe_account_token(account_id) + ".rev.json"


static func account_rejected_path(account_id: String, side: String) -> String:
	var clean_side: String = "remote" if side == "remote" else "local"
	return "user://journey." + safe_account_token(account_id) \
		+ ".rejected-" + clean_side + ".json"


## Point reads and writes at one account's slot. An empty id returns to the
## legacy single save.
static func use_account(account_id: String) -> void:
	active_account = account_id
	if account_id.is_empty():
		path = DEFAULT_PATH
		backup_path = DEFAULT_BACKUP_PATH
		return
	path = account_main_path(account_id)
	backup_path = account_backup_path(account_id)


## Move the legacy single save into `account_id`'s slot once, byte for byte,
## without losing bytes. Only files the slot is missing are moved; existing
## slot files are never overwritten. Each moved file is verified byte-equal
## after install before its legacy original is removed, so a failed move
## keeps the legacy file. Removing the original is what makes the migration
## run once: the next account finds no legacy file left to claim.
static func migrate_legacy_to_account(account_id: String) -> Dictionary:
	var result: Dictionary = {
		"moved_main": false, "moved_backup": false, "ok": true,
	}
	if account_id.is_empty():
		result["ok"] = false
		return result
	var main_outcome: String = _move_one_file(
		DEFAULT_PATH, account_main_path(account_id))
	if main_outcome == "moved":
		result["moved_main"] = true
	elif main_outcome == "failed":
		result["ok"] = false
	var backup_outcome: String = _move_one_file(
		DEFAULT_BACKUP_PATH, account_backup_path(account_id))
	if backup_outcome == "moved":
		result["moved_backup"] = true
	elif backup_outcome == "failed":
		result["ok"] = false
	return result


## Move one account slot's files (main, backup, revision, rejected copies)
## into another slot, byte for byte. Used when an offline guest slot learns
## its canonical id. Existing target files are never overwritten; sources
## that moved are removed only after verification.
static func move_account_slot(from_account: String, to_account: String) -> Dictionary:
	var moved: Array[String] = []
	var ok: bool = true
	if from_account.is_empty() or to_account.is_empty() \
			or from_account == to_account:
		return {"moved": moved, "ok": false}
	var pairs: Array = [
		[account_main_path(from_account), account_main_path(to_account)],
		[account_backup_path(from_account), account_backup_path(to_account)],
		[account_revision_path(from_account), account_revision_path(to_account)],
		[account_rejected_path(from_account, "local"),
			account_rejected_path(to_account, "local")],
		[account_rejected_path(from_account, "remote"),
			account_rejected_path(to_account, "remote")],
	]
	for pair in pairs:
		var outcome: String = _move_one_file(
			str((pair as Array)[0]), str((pair as Array)[1]))
		if outcome == "moved":
			moved.append(str((pair as Array)[1]))
		elif outcome == "failed":
			ok = false
	return {"moved": moved, "ok": ok}


## Write one checkpoint atomically, keeping the previous valid save as the
## backup. Returns `OK` only when the new file verified on disk.
##
## Nothing here ever deletes the main save: verified bytes stage in a temp
## file, the current main (when valid) rotates into the backup through the
## same atomic install, and only then does the staged file replace the main.
## Any failure — temp write, backup refresh, or replace — leaves a playable
## prior save behind and reports `last_error`.
static func write_checkpoint(data: Dictionary) -> Error:
	if not validate(data):
		last_error = "refused to write an invalid checkpoint"
		return ERR_INVALID_DATA
	var text: String = JSON.stringify(data)
	if text.is_empty() or text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		last_error = "checkpoint too large to save"
		return ERR_INVALID_DATA
	if is_ended(data):
		return _install_ended_pair(text)
	# Refresh the backup first, like the Vault: a backup that cannot install
	# aborts the write rather than replacing the main behind a stale backup.
	if not _refresh_backup_from_main():
		last_error = "could not save the journey"
		return ERR_CANT_OPEN
	var installed: Error = _install_verified(path, text, backup_path)
	if installed == OK:
		_notify_stable_checkpoint(text)
	return installed


## Install a terminal marker to both files, backup first, without rotation:
## the previous alive main is superseded by the seal, and rotating it into
## the backup would leave a stale alive copy able to revive the ended
## journey if the main ever corrupts. Either ordering of a crash stays
## terminal: a failed backup mirror leaves the main untouched (the seal
## never started), while a failed main install still leaves the mirrored
## backup the reads treat as terminal. Callers retry until the pair
## converges; stable hooks fire only once the main lands.
static func _install_ended_pair(text: String) -> Error:
	var backup_error: Error = _install_verified(backup_path, text)
	if backup_error != OK:
		last_error = "could not save the journey"
		return backup_error
	var installed: Error = _install_verified(path, text)
	if installed == OK:
		_notify_stable_checkpoint(text)
		return OK
	last_error = "could not save the journey"
	return installed


## Install already-serialized checkpoint text — a cloud download that passed
## validation — keeping its exact bytes. Parses and strictly validates
## first; oversized, malformed, or invalid payloads are refused without
## touching any file. Notifies stable hooks on success like `write_checkpoint`.
static func write_checkpoint_text(text: String) -> Error:
	if text.is_empty() or text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		last_error = "checkpoint too large to save"
		return ERR_INVALID_DATA
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK or not validate(parser.data):
		last_error = "refused to write an invalid checkpoint"
		return ERR_INVALID_DATA
	if is_ended(parser.data):
		return _install_ended_pair(text)
	if not _refresh_backup_from_main():
		last_error = "could not save the journey"
		return ERR_CANT_OPEN
	var installed: Error = _install_verified(path, text, backup_path)
	if installed == OK:
		_notify_stable_checkpoint(text)
	return installed


## Read the newest valid checkpoint: the main file first, then the backup.
## Returns `{}` when neither validates. A recovered backup is copied back to
## the main path so the next read is direct. A valid terminal marker reads
## back like any valid checkpoint — callers gate resume on `is_ended()` or
## `has_valid_checkpoint()` — and no older alive backup of the same journey
## may revive it: an ended main converges a stale alive backup forward on
## read, and a live main with a same-journey ended backup at no older seal
## (a seal whose main write never finished) reads terminal too.
static func read_checkpoint() -> Dictionary:
	last_error = ""
	var main: Dictionary = _read_candidate(path)
	if main.is_empty():
		return _read_fallback_backup()
	if is_ended(main):
		_converge_ended_backup(main)
		return main
	var backup: Dictionary = _read_candidate(backup_path)
	if backup.is_empty() or not is_ended(backup) \
			or not _same_journey(main, backup) \
			or _seal_id(main) > _seal_id(backup):
		return main
	# The backup proves a seal the main write never finished. Heal the
	# marker forward so the pair converges, then read terminal.
	var read: Dictionary = _read_bounded(backup_path)
	if bool(read.get("ok", false)):
		_install_verified(path, str(read.get("text", "")))
	last_error = ""
	return backup


## The main file is missing or invalid: fall back to the backup, if any.
## A recovered backup is installed forward atomically, without rotating
## (the corrupt main must never overwrite the backup). Even if the install
## fails, the returned data is valid and the backup stays.
static func _read_fallback_backup() -> Dictionary:
	var main_error: String = last_error
	var backup: Dictionary = _read_candidate(backup_path)
	if backup.is_empty():
		if not main_error.is_empty():
			last_error = main_error
		elif last_error.is_empty():
			last_error = "no saved journey"
		return {}
	var read: Dictionary = _read_bounded(backup_path)
	if bool(read.get("ok", false)):
		_install_verified(path, str(read.get("text", "")))
	last_error = ""
	return backup


## Converge a stale alive backup behind an ended main: mirror the marker's
## exact bytes forward (best effort) so pairs sealed before the mirror end
## up redundant too. Only same-journey backups converge — a different
## journey's alive backup is pre-install lineage, never this seal's stale
## shadow, and a corrupt main may still legitimately recover from it.
static func _converge_ended_backup(main: Dictionary) -> void:
	var backup: Dictionary = _read_candidate(backup_path)
	if backup.is_empty() or is_ended(backup) \
			or not _same_journey(main, backup):
		return
	var read: Dictionary = _read_bounded(path)
	if bool(read.get("ok", false)):
		_install_verified(backup_path, str(read.get("text", "")))


## Journey identity across int, float and string forms: Vault sequences
## stay in the `i` namespace (JSON floats count whole, like the validator),
## random fallbacks in the `s` namespace, so id `5` never aliases `"5"`.
static func _journey_key(journey_id: Variant) -> String:
	if journey_id is int:
		return "i%d" % int(journey_id)
	if journey_id is float and journey_id == floorf(journey_id):
		return "i%d" % int(journey_id)
	if journey_id is String and is_safe_id(str(journey_id)):
		return "s%s" % str(journey_id)
	return ""


## True when both checkpoints name the same journey.
static func _same_journey(first: Dictionary, second: Dictionary) -> bool:
	var left: String = _journey_key(first.get("journey_id"))
	var right: String = _journey_key(second.get("journey_id"))
	return not left.is_empty() and left == right


## Seal id of a validated checkpoint for ordering comparisons.
static func _seal_id(data: Dictionary) -> int:
	return int(data.get("checkpoint_id", -1))


## True when a checkpoint would load. Title calls this to offer Continue.
## A sealed defeat is valid but not resumable, so it reads false.
static func has_valid_checkpoint() -> bool:
	var data: Dictionary = read_checkpoint()
	return not data.is_empty() and not is_ended(data)


## True when the checkpoint carries the defeat marker: a sealed run that no
## title, backup or cloud path may resume. Strictly a bool `true`; anything
## else (absent, false, or a non-bool a hostile file smuggled in) is alive.
static func is_ended(data: Dictionary) -> bool:
	var marker: Variant = data.get("ended", false)
	return marker is bool and bool(marker)


## Settle one Vault continue transaction against the journey files: the
## journaled seal is paid, so materialize it when the files still hold the
## defeat it revives. Returns `recovered` (the paid seal landed),
## `delivered` (the paid seal is already on disk), `stale` (nothing to
## deliver — the caller clears the journal), `none` (no transaction),
## `deferred` (another scope owns the receipt — nothing is touched), or
## `failed` (the materialize write failed — the caller keeps the journal
## and retries later). Only ever revives the transaction's own journey
## past its own defeat: a different journey, an alive seal at no older
## id, or a defeat at no older id clears the journal instead of writing.
static func settle_continue_txn(txn: Dictionary) -> String:
	if txn.is_empty():
		return "none"
	if str(txn.get("owner", active_account)) != active_account:
		return "deferred"
	var journey: Variant = txn.get("journey_id", null)
	var attempt: Variant = txn.get("checkpoint_id", null)
	var seal_text: String = str(txn.get("seal", ""))
	if _journey_key(journey).is_empty() or not attempt is int \
			or seal_text.is_empty():
		return "stale"
	var parser: JSON = JSON.new()
	if parser.parse(seal_text) != OK or not validate(parser.data):
		return "stale"
	var seal: Dictionary = parser.data
	if is_ended(seal) \
			or _journey_key(seal.get("journey_id")) != _journey_key(journey) \
			or int(seal.get("checkpoint_id", -1)) != int(attempt):
		return "stale"
	var file: Dictionary = read_checkpoint()
	if file.is_empty():
		return "recovered" \
			if write_checkpoint(seal) == OK else "failed"
	if not _same_journey(file, seal):
		return "stale"
	if not is_ended(file):
		if _seal_id(file) >= int(attempt):
			return "delivered"
		return "recovered" \
			if write_checkpoint(seal) == OK else "failed"
	if _seal_id(file) < int(attempt):
		return "recovered" \
			if write_checkpoint(seal) == OK else "failed"
	return "stale"


## Forget the journey: main, backup and temp files. Best effort.
static func clear() -> void:
	_remove_regular_file(path)
	_remove_regular_file(backup_path)
	_remove_regular_file(path + ".tmp")
	_remove_regular_file(backup_path + ".tmp")
	last_error = ""


## Small display summary for the title's Continue row. Empty when invalid
## or when the journey sealed its defeat: there is no gate left to resume.
static func summary(data: Dictionary) -> Dictionary:
	if not validate(data) or is_ended(data):
		return {}
	var cycle: int = int(data["cycle"])
	var zone: int = int(data["zone_index"])
	var route: Array = data["route"]
	var terrain: int = int(route[zone])
	if terrain < 0:
		var classic: Array[int] = Expedition.classic_route(cycle)
		terrain = classic[clampi(zone, 0, classic.size() - 1)]
	return {
		"cycle": cycle,
		"zone_index": zone,
		"terrain": terrain,
		"hero_path": str(data["hero_path"]),
		"level": int(data["level"]),
		"journey_id": str(data["journey_id"]),
		"checkpoint_id": int(data["checkpoint_id"]),
	}


## Strict validation of a parsed checkpoint. Everything required must be
## present and in range; resource paths must name a real hero or relic.
static func validate(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var checkpoint: Dictionary = data
	# Strictly an integer with exactly the supported value: 1.5, "1" and
	# true must not coerce through int() into a match.
	if not _is_int_in(
			checkpoint.get("schema_version", 0), SCHEMA_VERSION, SCHEMA_VERSION):
		return false
	if not _is_journey_id(checkpoint.get("journey_id", "")):
		return false
	if not _is_int_in(checkpoint.get("checkpoint_id"), 0, MAX_SAFE_INT):
		return false
	if not _is_int_in(checkpoint.get("cycle"), 1, MAX_CYCLE):
		return false
	if not _is_int_in(checkpoint.get("zone_index"), 0, 2):
		return false
	var route: Variant = checkpoint.get("route", null)
	if not route is Array or (route as Array).size() != 3:
		return false
	var terrain_count: int = Expedition.TERRAINS.size()
	for slot: Variant in route as Array:
		if not _is_int_in(slot, -1, terrain_count - 1):
			return false
	if not _is_int_in(
			checkpoint.get("run_seed"), -MAX_SAFE_INT, MAX_SAFE_INT):
		return false
	if not _is_hero_path(str(checkpoint.get("hero_path", ""))):
		return false
	if not _are_relic_stacks(checkpoint.get("relic_stacks", null)):
		return false
	if not _is_int_in(checkpoint.get("level"), 1, MAX_LEVEL):
		return false
	if not _is_int_in(checkpoint.get("to_next"), 1, MAX_SAFE_INT):
		return false
	if not _is_int_in(checkpoint.get("level_progress"), 0, MAX_SAFE_INT):
		return false
	if not _is_int_in(
			checkpoint.get("missile_power"), 0, MissileProgression.MAX_POWER):
		return false
	if not _is_int_in(checkpoint.get("missile_progress"), 0, MAX_SAFE_INT):
		return false
	if not checkpoint.get("first_core_collected") is bool:
		return false
	if not _is_int_in(checkpoint.get("kills"), 0, MAX_SAFE_INT):
		return false
	if not _is_int_in(checkpoint.get("kill_score"), 0, MAX_SAFE_INT):
		return false
	if not _is_number_in(checkpoint.get("survived"), 0, MAX_SAFE_INT):
		return false
	if not _is_int_in(checkpoint.get("lit_count"), 0, 3):
		return false
	if not _is_int_in(checkpoint.get("overcharge_successes"), 0, 3):
		return false
	if not _are_guardian_meetings(checkpoint.get("guardian_meetings", null)):
		return false
	if not _are_places_seen(checkpoint.get("places_seen", null)):
		return false
	if not _is_int_in(checkpoint.get("shards_awarded"), 0, MAX_SAFE_INT):
		return false
	if not _is_int_in(checkpoint.get("settled_score"), 0, MAX_SAFE_INT):
		return false
	if not _is_gate_direction(checkpoint.get("gate_direction", null)):
		return false
	if not checkpoint.get("opening_played") is bool:
		return false
	if not _is_int_in(checkpoint.get("saved_at_unix"), 0, MAX_SAFE_INT):
		return false
	# Additive terminal marker: absent on every checkpoint sealed before the
	# defeat rules, `true` once the journey ends. Present but non-bool
	# refuses the whole save like any other mistyped field.
	if checkpoint.has("ended") and not checkpoint.get("ended") is bool:
		return false
	return true


# --- internals ----------------------------------------------------------------

static func _read_candidate(candidate: String) -> Dictionary:
	if not FileAccess.file_exists(candidate):
		return {}
	var read: Dictionary = _read_bounded(candidate)
	if not bool(read.get("ok", false)):
		last_error = str(read.get("error", "saved journey is unreadable"))
		return {}
	# Parsed through the instance API: the static `JSON.parse_string` prints
	# an engine ERROR on a truncated file, while `JSON.new().parse()` just
	# returns an error code. A half-written save is ordinary (the app was
	# killed mid-write), not something to report.
	var parser: JSON = JSON.new()
	if parser.parse(str(read.get("text", ""))) != OK:
		last_error = "saved journey is unreadable"
		return {}
	var data: Variant = parser.data
	if not data is Dictionary:
		last_error = "saved journey is unreadable"
		return {}
	# Strict before anything loads: a fractional, string or bool schema is
	# unreadable, not a version. Only an integral newer version asks for a
	# newer game.
	var version: Variant = (data as Dictionary).get("schema_version", 0)
	if not _is_int_in(version, SCHEMA_VERSION, SCHEMA_VERSION):
		if _is_int_in(version, SCHEMA_VERSION + 1, MAX_SAFE_INT):
			last_error = "saved journey needs a newer game"
		else:
			last_error = "saved journey is unreadable"
		return {}
	if not validate(data):
		last_error = "saved journey failed its safety check"
		return {}
	return data


## One bounded read: the length gate runs before any byte is kept, so an
## oversized file is refused without allocating or parsing it. Returns
## `{ok, text}` or `{ok: false, error}`.
static func _read_bounded(candidate: String) -> Dictionary:
	var handle: FileAccess = FileAccess.open(candidate, FileAccess.READ)
	if handle == null:
		return {"ok": false, "error": "saved journey is unreadable"}
	var length: int = int(handle.get_length())
	if length > MAX_FILE_BYTES:
		handle.close()
		return {"ok": false, "error": "saved journey is too large to load"}
	var text: String = handle.get_as_text()
	handle.close()
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return {"ok": false, "error": "saved journey is too large to load"}
	return {"ok": true, "text": text}


## Install verified text at `target` through a staged temp file. The staged
## bytes are re-read (bounded) and validated before any rename; renames are
## the only thing that ever touches `target`.
##
## When `rotate_with` names the backup and the direct install fails, the
## current target rotates aside into it, the staged file installs, and any
## failure reinstalls the aside copy back — the backup stays behind the
## restored main. The target is never deleted: a failed replacement keeps
## the previous playable save.
static func _install_verified(
	target: String, text: String, rotate_with: String = ""
) -> Error:
	var temp: String = target + ".tmp"
	var handle: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if handle == null:
		last_error = "could not save the journey"
		return ERR_CANT_CREATE
	handle.store_string(text)
	handle.flush()
	handle.close()
	if not _staged_validates(temp):
		_remove_regular_file(temp)
		last_error = "could not save the journey"
		return ERR_FILE_CORRUPT
	if install_fault == InstallFault.NONE \
			and _rename_file(temp, target) == OK:
		last_error = ""
		return OK
	if rotate_with.is_empty() or not FileAccess.file_exists(target):
		_remove_regular_file(temp)
		last_error = "could not save the journey"
		return ERR_CANT_OPEN
	if install_fault == InstallFault.FAIL_ALL \
			or _rename_file(target, rotate_with) != OK:
		_remove_regular_file(temp)
		last_error = "could not save the journey"
		return ERR_CANT_OPEN
	var temp_failed: bool = install_fault == InstallFault.FAIL_TEMP_INSTALL \
		or install_fault == InstallFault.FAIL_ALL
	if not temp_failed:
		temp_failed = _rename_file(temp, target) != OK
	if not temp_failed:
		last_error = ""
		return OK
	# Reinstall the aside copy instead of moving it back, so the backup
	# stays behind the restored main. Unfaulted: a restore must use real
	# operations. If even this fails, the aside copy still reads.
	var saved_fault: int = install_fault
	install_fault = InstallFault.NONE
	var aside: Dictionary = _read_bounded(rotate_with)
	if bool(aside.get("ok", false)):
		_install_verified(target, str(aside.get("text", "")))
	install_fault = saved_fault
	_remove_regular_file(temp)
	last_error = "could not save the journey"
	return ERR_CANT_OPEN


static func _rename_file(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(from_path),
		ProjectSettings.globalize_path(to_path))


static func _staged_validates(temp: String) -> bool:
	if not FileAccess.file_exists(temp):
		return false
	var read: Dictionary = _read_bounded(temp)
	if not bool(read.get("ok", false)):
		return false
	var parser: JSON = JSON.new()
	if parser.parse(str(read.get("text", ""))) != OK:
		return false
	return validate(parser.data)


## Rotate the current main file into the backup path, but only when it still
## validates, and only through the same atomic install. An invalid main must
## never overwrite a good backup. Returns false when the refresh cannot
## install, which aborts the write rather than replacing the main behind a
## stale backup.
static func _refresh_backup_from_main() -> bool:
	if not FileAccess.file_exists(path):
		return true
	var read: Dictionary = _read_bounded(path)
	if not bool(read.get("ok", false)):
		return true
	var parser: JSON = JSON.new()
	if parser.parse(str(read.get("text", ""))) != OK:
		return true
	if not validate(parser.data):
		return true
	# Unfaulted: install faults target the outer main install only, so the
	# rotate paths stay reachable under injection.
	var saved_fault: int = install_fault
	install_fault = InstallFault.NONE
	var installed: bool = _install_verified(
		backup_path, str(read.get("text", ""))) == OK
	install_fault = saved_fault
	return installed


static func _remove_regular_file(candidate: String) -> void:
	# Failure-injection tests may occupy a path as a directory. Delete only a
	# regular file we could have created; never touch a directory.
	if FileAccess.file_exists(candidate):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


## Tell stable-checkpoint subscribers about one verified write. Only called
## on the success path, so a failed write never queues a cloud upload.
static func _notify_stable_checkpoint(text: String) -> void:
	if _stable_hooks.is_empty():
		return
	var info: Dictionary = {
		"text": text, "path": path, "backup_path": backup_path,
	}
	for hook in _stable_hooks.duplicate():
		if (hook as Callable).is_valid():
			(hook as Callable).call(info)


## Move one file's exact bytes to a target that must not exist yet. Stages
## through a temp file and verifies twice: the staged bytes, then the
## installed bytes. The source is removed only after both verifications, so
## a failed move loses nothing. Returns `moved`, `skipped` (no source, or a
## target that must be preserved), or `failed`.
static func _move_one_file(source: String, target: String) -> String:
	if not FileAccess.file_exists(source) or FileAccess.file_exists(target):
		return "skipped"
	var reader: FileAccess = FileAccess.open(source, FileAccess.READ)
	if reader == null:
		return "failed"
	var length: int = int(reader.get_length())
	var bytes: PackedByteArray = reader.get_buffer(length)
	reader.close()
	if bytes.size() != length:
		return "failed"
	var staged: String = target + ".tmp"
	var writer: FileAccess = FileAccess.open(staged, FileAccess.WRITE)
	if writer == null:
		return "failed"
	writer.store_buffer(bytes)
	writer.flush()
	var write_error: Error = writer.get_error()
	writer.close()
	if write_error != OK:
		_remove_regular_file(staged)
		return "failed"
	if _read_raw_bytes(staged) != bytes:
		_remove_regular_file(staged)
		return "failed"
	if _rename_file(staged, target) != OK:
		_remove_regular_file(staged)
		return "failed"
	if _read_raw_bytes(target) != bytes:
		return "failed"
	_remove_regular_file(source)
	return "moved"


## Raw bytes of one file for byte-equality checks. Empty when unreadable.
static func _read_raw_bytes(candidate: String) -> PackedByteArray:
	var reader: FileAccess = FileAccess.open(candidate, FileAccess.READ)
	if reader == null:
		return PackedByteArray()
	var bytes: PackedByteArray = reader.get_buffer(int(reader.get_length()))
	reader.close()
	return bytes


## Journey identity: a Vault-issued sequence (a positive int inside the
## safe JSON range, or its integral float after a JSON round trip), or a
## random fallback string from a failed issue save. Legacy random ids keep
## validating.
static func _is_journey_id(value: Variant) -> bool:
	if value is int:
		return int(value) >= 1 and int(value) <= MAX_SAFE_INT
	if value is float:
		return value >= 1.0 and value < JSON_INT_LIMIT \
			and value == floorf(value)
	return value is String and is_safe_id(str(value))


## Random journey ids: letters, digits, `_` and `-`, at most 64 chars.
## Shared with the Vault's receipt ledger, which stores the same ids.
static func is_safe_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for character: String in value:
		if character not in \
				"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true


## An integer inside the inclusive range, compared in its own type. Ints
## never convert through float (9007199254740993 would round into the
## bound); JSON floats must sit strictly below 2^53 past which they may
## already be rounded, hold an integral value, and land in range.
static func _is_int_in(value: Variant, minimum: int, maximum: int) -> bool:
	if value is int:
		return int(value) >= minimum and int(value) <= maximum
	if value is float:
		return value == floorf(value) \
			and value > -JSON_INT_LIMIT and value < JSON_INT_LIMIT \
			and value >= float(minimum) and value <= float(maximum)
	return false


## A JSON number inside the inclusive range: an int compares exactly, a
## float must sit strictly below 2^53 in magnitude and land in range.
static func _is_number_in(value: Variant, minimum: int, maximum: int) -> bool:
	if value is int:
		return int(value) >= minimum and int(value) <= maximum
	if value is float:
		return value > -JSON_INT_LIMIT and value < JSON_INT_LIMIT \
			and value >= float(minimum) and value <= float(maximum)
	return false


## Heroes come only from the Vault's fixed roster. A save pointing anywhere
## else is refused before anything is loaded from it.
static func _is_hero_path(value: String) -> bool:
	return value in Vault.HEROES


## Relic stacks map a relic path to its held count. Every key must stay
## inside the relic resource folder, name a `.tres` that exists, and load as
## a `Relic` — anything else refuses the whole save.
static func _are_relic_stacks(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var stacks: Dictionary = value
	if stacks.size() > MAX_STACK_ENTRIES:
		return false
	for key: Variant in stacks:
		if not key is String:
			return false
		var entry_path: String = key
		if not entry_path.begins_with(RELIC_DIR) \
				or not entry_path.ends_with(RESOURCE_SUFFIX) \
				or entry_path.contains("..") \
				or entry_path.length() > 128:
			return false
		if not _is_int_in(stacks[key], 1, MAX_STACKS):
			return false
		if not ResourceLoader.exists(entry_path):
			return false
		if not load(entry_path) is Relic:
			return false
	return true


## Terrain index (as JSON string keys) to meeting counts.
static func _are_guardian_meetings(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var meetings: Dictionary = value
	if meetings.size() > Expedition.TERRAINS.size():
		return false
	for key: Variant in meetings:
		if not key is String or not (key as String).is_valid_int():
			return false
		var terrain: int = int(key)
		if terrain < 0 or terrain >= Expedition.TERRAINS.size():
			return false
		if not _is_int_in(meetings[key], 0, MAX_SAFE_INT):
			return false
	return true


## Terrain ids whose place memory already played this journey.
static func _are_places_seen(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Array = value
	if seen.size() > Expedition.TERRAINS.size():
		return false
	for entry: Variant in seen:
		if not entry is String:
			return false
		if not PlaceMemory.TERRAIN_IDS.has(entry):
			return false
	return true


static func _is_gate_direction(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	for axis: Variant in value as Array:
		if not _is_number_in(axis, -1, 1):
			return false
	return true
