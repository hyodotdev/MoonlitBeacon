extends Node

## Owned-journey cloud coordinator: the game-facing bridge between the local
## Journey/Vault and the owned Firestore rows (profile, reservation,
## checkpoint, Hall).
##
## The host (a future native layer) injects the Firebase UID, the durable
## pre-play guest public ID, an ID-token supplier, an HTTP sender, and the
## Vault, then receives the canonical public ID to persist. The coordinator
## owns nothing else: no UI, no native calls, no autoloads, no scene files.
##
## Local first, cloud follows. Journey checkpoints always land in the
## account's partitioned local files before anything is queued, uploads run
## async off the gameplay path, and no gameplay or authentication step ever
## waits on network. A stable checkpoint notifies once per verified local
## write; failed writes never queue.
##
## Safety rules:
##
## - The supplied guest ID is reserved verbatim for a new UID and never
##   silently replaced on a collision; an existing UID returns its canonical
##   ID explicitly. Offline work claims nothing global.
## - Conflicts are shown, never auto-chosen. The loaded remote is compared
##   against the durable sync baseline before any commit, because
##   compare-and-swap alone cannot see another device's progress made
##   before the guard read; a miss at either layer carries safe local and
##   remote summaries (sizes and digests, never payloads or credentials).
##   The host picks local or remote explicitly, and the rejected version is
##   preserved to a recovery file first — the actually overwritten remote
##   bytes when it advanced again mid-choice. The one automatic rule is
##   same-journey defeat precedence: a sealed defeat outranks a stale alive
##   payload of the same journey without a dialog, reported explicitly as
##   `defeat-kept` or `defeat-adopted`, so no sync path silently resumes a
##   run that already ended. Different journeys still choose explicitly.
## - Downloads validate completely through `Journey.validate()` before any
##   install. Malformed, oversized, or ledger-carrying payloads are refused
##   with the local files untouched.
## - A restore never mints historical currency on this device. The remote
##   cumulative target lands as a durable Vault floor with zero granted; new
##   play above the floor settles exactly once. Imported integer journey ids
##   are remapped into this device's receipt namespace at install, so they
##   can never alias a local receipt; locally-issued ids with no record are
##   left alone so a failed settlement's retry still pays exactly once.
## - Hall rows carry only the public ID, checkpoint-derived hero/score/
##   cycles, release, schema, and stamp: no UID, token, save, or credential.
##   Rank refresh is throttled globally and every read labels its source as
##   live, cache, throttled, stale, offline, or unregistered.
## - Switching accounts repoints the Journey slot and retires in-flight
##   work. Late replies for an old account report cancelled and change
##   nothing. Each account's local journey bytes are preserved untouched.
## - Nothing here serializes per frame or writes mid-frame in the
##   background. Checkpoints queue on segment seals; everything else runs on
##   explicit host calls.

signal account_changed(snapshot: Dictionary)
signal save_changed(snapshot: Dictionary)
signal conflict_found(info: Dictionary)
signal hall_changed(snapshot: Dictionary)
signal rank_changed(snapshot: Dictionary)
signal attendance_changed(snapshot: Dictionary)

const CloudSchema: Script = preload("res://scripts/cloud/cloud_schema.gd")
const TransportScript: Script = preload(
	"res://scripts/cloud/cloud_transport.gd")
const IdentityScript: Script = preload(
	"res://scripts/cloud/cloud_identity.gd")
const CheckpointScript: Script = preload(
	"res://scripts/cloud/cloud_checkpoint.gd")
const HallScript: Script = preload("res://scripts/cloud/cloud_hall.gd")
const NameScript: Script = preload("res://scripts/cloud/cloud_name.gd")
const AttendanceScript: Script = preload(
	"res://scripts/cloud/cloud_attendance.gd")
const VaultScript: Script = preload("res://scripts/gameplay/vault.gd")

## Upload attempts per flush for retryable failures. Conflicts, offline,
## unconfigured, and cancelled states never loop: they keep the pending
## payload and return for an explicit later flush.
const MAX_FLUSH_ATTEMPTS: int = 3
const REVISION_FILE_VERSION: int = 2
const DEFAULT_RELEASE: String = "4.0.0"

var _transport: RefCounted
var _identity: RefCounted
var _checkpoint: RefCounted
var _hall: RefCounted
var _names: RefCounted
var _attendance: RefCounted

var _generation: int = 0
var _closed: bool = false
var _configured: bool = false
var _uid: String = ""
var _requested_guest_id: String = ""
var _canonical_id: String = ""
var _partition_key: String = ""
var _vault: Node = null
var _release: String = DEFAULT_RELEASE
var _auto_flush: bool = true
var _now_override: int = -1
var _installing_remote: bool = false

var _account_state: String = "unconfigured"
var _account_code: String = ""
var _save_state: String = "idle"
var _save_code: String = ""
var _conflict: Dictionary = {}
var _acked_revision: int = 0
var _known_remote_revision: int = 0
## Durable sync baseline: the last revision + payload digest both sides
## agreed on. A remote that differs from it is foreign progress and
## conflicts before any commit; compare-and-swap alone cannot see progress
## that landed before the guard read. `-1` means no baseline yet.
var _baseline_revision: int = -1
var _baseline_digest: String = ""
## Single flush owner: one upload runs at a time and chained follow-ups run
## only while newer work is actually queued. The lock is a ticket, not a
## flag: only the holder may release it, so a late completion from a retired
## generation can never unlock a newer account's outstanding upload.
var _flush_owner: int = 0
var _flush_seq: int = 0
## Checkpoint-read epoch. Every `restore_from_cloud` claims the next value
## at start, and `cancel_pending_restore` spends one without reading, so a
## reply that lands after its attempt was superseded reports cancelled and
## installs nothing. Monotonic like `_flush_seq`: never reset, so an older
## attempt can never match a newer one.
var _restore_epoch: int = 0
var _last_migration: Dictionary = {}
var _floor_code: String = ""
var _revision_error: String = ""
var _hall_snapshot: Dictionary = {}
var _rank_snapshot: Dictionary = {}
var _attendance_snapshot: Dictionary = {}


func _init() -> void:
	_transport = TransportScript.new()
	_identity = IdentityScript.new()
	_checkpoint = CheckpointScript.new()
	_hall = HallScript.new()
	_names = NameScript.new()
	_attendance = AttendanceScript.new()
	_hall_snapshot = {
		"state": "unregistered", "source": "unregistered", "rows": [],
		"last_submit": {},
	}
	_rank_snapshot = {
		"state": "unregistered", "source": "unregistered", "rank": 0,
		"greater": 0, "score": 0, "hero": "", "cycles": 0,
		"public_id": "", "requested_score": 0, "row_source": "unregistered",
		"rank_source": "unregistered", "fetched_msec": 0,
		"row_fetched_msec": 0, "rank_fetched_msec": 0, "live_error": "",
	}


func _exit_tree() -> void:
	close()


## Retire every in-flight request and subscription. Late replies report
## cancelled and change nothing. The host owns the sender lifecycle.
func close() -> void:
	if _closed:
		return
	_closed = true
	_generation += 1
	_flush_owner = 0
	_unsubscribe_hook()
	if _transport != null and _transport.has_method("cancel_all"):
		_transport.call("cancel_all")
	_account_state = "closed"
	_save_state = "closed"
	account_changed.emit(account_snapshot())
	save_changed.emit(save_snapshot())


## Inject the host account and services. Synchronous and local-only: it
## validates, partitions the Journey slot, migrates the legacy save once,
## floors the active receipt, and starts reservation in the background. The
## reservation result arrives via `account_changed`; nothing here waits on
## network. Re-configuring switches accounts: the old slot's bytes stay
## untouched and its in-flight work retires.
##
## Config keys: `uid` (Firebase UID), `guest_public_id` (durable pre-play
## `MB-` id), `token_supplier` (Callable () -> String), `sender` (Callable
## (method, url, headers, body) -> Dictionary, may be async), `vault` (the
## Vault node), `release` (Hall release tag, default `4.0.0`), `project_id`
## (default the owned project), `web_api_key` (default empty).
func configure_host(config: Dictionary) -> Dictionary:
	if _closed:
		return {"status": "failure", "code": "coordinator-closed",
			"retryable": false}
	var uid: String = str(config.get("uid", ""))
	if not CloudSchema.is_valid_uid(uid):
		return {"status": "failure", "code": "invalid-uid",
			"retryable": false}
	var guest_id: String = str(config.get("guest_public_id", ""))
	if not CloudSchema.is_valid_public_id(guest_id):
		return {"status": "failure", "code": "invalid-guest-id",
			"retryable": false}
	var token_supplier: Callable = config.get("token_supplier", Callable())
	if not token_supplier.is_valid():
		return {"status": "failure", "code": "missing-token-supplier",
			"retryable": false}
	var sender: Callable = config.get("sender", Callable())
	if not sender.is_valid():
		return {"status": "failure", "code": "missing-sender",
			"retryable": false}
	var vault: Variant = config.get("vault", null)
	if vault == null or not (vault as Object).has_method(
			"initialize_remote_receipt_floor"):
		return {"status": "failure", "code": "missing-vault",
			"retryable": false}
	var project_id: String = str(config.get(
		"project_id", CloudSchema.PROJECT_ID))
	if project_id.is_empty():
		return {"status": "failure", "code": "invalid-project",
			"retryable": false}
	var release: String = str(config.get("release", DEFAULT_RELEASE))
	if release.is_empty() or release.length() > CloudSchema.MAX_RELEASE_LENGTH:
		return {"status": "failure", "code": "invalid-release",
			"retryable": false}
	_generation += 1
	_configured = true
	_uid = uid
	_requested_guest_id = guest_id
	_canonical_id = ""
	_vault = vault as Node
	_release = release
	_transport.call("configure", project_id,
		str(config.get("web_api_key", "")), token_supplier, sender)
	_identity.call("switch_account", _transport, uid)
	_hall.call("set_account", "")
	_checkpoint.call("switch_account", uid)
	_conflict = {}
	_acked_revision = 0
	_known_remote_revision = 0
	_baseline_revision = -1
	_baseline_digest = ""
	# Free the retired generation's ticket: the new account acquires its own,
	# and late old completions no longer match so they cannot unlock it.
	_flush_owner = 0
	_revision_error = ""
	_floor_code = ""
	_hall_snapshot = {
		"state": "unregistered", "source": "unregistered", "rows": [],
		"last_submit": {},
	}
	_rank_snapshot = {
		"state": "unregistered", "source": "unregistered", "rank": 0,
		"greater": 0, "score": 0, "hero": "", "cycles": 0,
		"public_id": "", "requested_score": 0, "row_source": "unregistered",
		"rank_source": "unregistered", "fetched_msec": 0,
		"row_fetched_msec": 0, "rank_fetched_msec": 0, "live_error": "",
	}
	_partition_key = guest_id
	Journey.use_account(guest_id)
	_last_migration = _vault.call("adopt_legacy_slot", guest_id) as Dictionary
	_load_revision_file()
	_reconcile_active_receipt_floor()
	_subscribe_hook()
	_account_state = "reserving"
	_account_code = ""
	_save_state = "unregistered"
	_save_code = ""
	account_changed.emit(account_snapshot())
	save_changed.emit(save_snapshot())
	hall_changed.emit(hall_snapshot())
	rank_changed.emit(rank_snapshot())
	_reserve_async(_generation)
	return {"status": "ok", "code": "account-reserving",
		"partition": _partition_key, "migration": _last_migration.duplicate()}


## True once the account owns its canonical public ID.
func account_ready() -> bool:
	return _configured and not _canonical_id.is_empty() \
		and _account_state == "ready"


## Queue uploads automatically after each stable checkpoint (default on).
## Tests switch it off to drive `flush()` explicitly against scripted fakes.
func set_auto_flush(enabled: bool) -> void:
	_auto_flush = enabled


func account_snapshot() -> Dictionary:
	return {
		"state": _account_state,
		"code": _account_code,
		"uid": _uid,
		"requested_guest_id": _requested_guest_id,
		"public_id": _canonical_id,
		"partition": _partition_key,
		"migration": _last_migration.duplicate(),
	}


func save_snapshot() -> Dictionary:
	return {
		"state": _save_state,
		"code": _save_code,
		"pending_coalesced": int(
			_checkpoint.call("pending_coalesced_count")),
		"acked_revision": _acked_revision,
		"known_remote_revision": _known_remote_revision,
		"baseline_revision": _baseline_revision,
		"has_conflict": not _conflict.is_empty(),
		"floor_code": _floor_code,
		"revision_error": _revision_error,
	}


## Safe conflict view for the host: summaries only, never full payloads and
## never credentials. Empty when no conflict is open.
func conflict_snapshot() -> Dictionary:
	if _conflict.is_empty():
		return {}
	return {
		"local_summary": (_conflict.get("local_summary", {}) as Dictionary
			).duplicate(true),
		"remote_summary": (_conflict.get("remote_summary", {}) as Dictionary
			).duplicate(true),
		"local_revision": int(_conflict.get("local_revision", 0)),
		"remote_revision": int(_conflict.get("remote_revision", 0)),
		"baseline_revision": int(_conflict.get("baseline_revision", -1)),
	}


func hall_snapshot() -> Dictionary:
	return _hall_snapshot.duplicate(true)


func rank_snapshot() -> Dictionary:
	return _rank_snapshot.duplicate(true)


func state_snapshot() -> Dictionary:
	return {
		"account": account_snapshot(),
		"save": save_snapshot(),
		"conflict": conflict_snapshot(),
		"hall": hall_snapshot(),
		"rank": rank_snapshot(),
	}


## Upload the coalesced pending payload, if any. Compares the loaded
## remote against the durable sync baseline before any commit: a differing
## remote is foreign progress and conflicts without sending, and a missing
## remote with acknowledged history conflicts instead of silently
## re-creating. Acknowledges only an actual server success; anything else
## keeps the payload queued for an explicit later flush. One flush owns the
## upload at a time; a second caller reports `flush-already-running` and a
## chained follow-up runs only while newer work is actually queued.
func flush() -> Dictionary:
	return await _flush_async(_generation)


## Resolve the open conflict explicitly. `local` preserves the freshly
## read remote to recovery (and the actually overwritten bytes when the
## remote advanced again mid-choice), then rebases and saves ours; `remote`
## validates the complete download through `Journey`, preserves ours,
## installs theirs — remapping an imported integer journey id into this
## device's receipt namespace — and floors its receipt with zero granted.
## Anything else is refused and the conflict stays open. A choice that would
## silently resume a sealed same-journey run is likewise refused (as
## `defeat-kept`), as is a choice committing or installing a death its
## journey already revived past (as `stale-ended-retired`), with the
## conflict left open. Reports busy while a flush owns the upload.
func resolve_conflict(choice: String) -> Dictionary:
	var captured: int = _generation
	if _closed:
		return {"status": "cancelled", "code": "coordinator-closed",
			"retryable": false}
	if not _configured or _canonical_id.is_empty():
		return {"status": "unregistered", "code": "account-not-ready",
			"retryable": false}
	if _conflict.is_empty():
		return {"status": "failure", "code": "no-conflict",
			"retryable": false}
	if choice != "local" and choice != "remote":
		return {"status": "failure", "code": "invalid-choice",
			"retryable": false}
	if _flush_locked():
		return {"status": "failure", "code": "flush-in-flight",
			"retryable": true}
	if choice == "local":
		return await _resolve_keep_local(captured)
	return await _resolve_keep_remote(captured)


## Retire the in-flight checkpoint read, if any. The host calls this when
## the initial restore's wait elapses: the orphaned read keeps its claimed
## epoch, so when its reply lands it reports cancelled and installs
## nothing, floors nothing, and opens no conflict. Flushes, profile work,
## rank, and settlement are untouched — only a restore holding a stale
## epoch is discarded.
func cancel_pending_restore() -> void:
	_restore_epoch += 1


## Pull the cloud checkpoint down safely. Installs only into an empty or
## install-identical slot; a differing local journey becomes an explicit
## conflict instead of a silent overwrite — except a same-journey defeat,
## which wins outright (`defeat-kept` locally, `defeat-adopted` from the
## server) so a stale payload can never resurrect a sealed run. A fresh
## install floors its receipt with zero granted — remapping an imported
## integer journey id first, so history never mints and never aliases a
## local receipt — and adopts the remote as the new sync baseline. Reports
## busy while a flush owns the upload. Each call claims the next restore
## epoch at start, so a newer read preempts any older attempt still in
## flight.
func restore_from_cloud() -> Dictionary:
	var captured: int = _generation
	if _closed:
		return {"status": "cancelled", "code": "coordinator-closed",
			"retryable": false}
	if not _configured:
		return {"status": "failure", "code": "coordinator-unconfigured",
			"retryable": false}
	if _flush_locked():
		return {"status": "failure", "code": "flush-in-flight",
			"retryable": true}
	# Claim the read before the first await: a newer restore — or an
	# explicit cancel — preempts any older attempt still in flight.
	_restore_epoch += 1
	var restore_epoch: int = _restore_epoch
	var remote: Dictionary = await _checkpoint.call(
		"load_remote", _transport, _uid)
	if _stale(captured) or restore_epoch != _restore_epoch:
		return _cancelled_stale()
	if str(remote.get("status", "")) != "ok":
		return remote
	var remote_text: String = str(remote.get("payload", ""))
	var checked: Dictionary = _validate_remote_payload(remote_text)
	if not bool(checked.get("ok", false)):
		return {"status": "failure",
			"code": str(checked.get("error", "invalid-remote-payload")),
			"retryable": false}
	var prepared: Dictionary = _prepare_install(
		checked.get("data", {}) as Dictionary, remote_text)
	if not bool(prepared.get("ok", false)):
		return {"status": "failure",
			"code": str(prepared.get("error", "invalid-remote-payload")),
			"retryable": false}
	var install_text: String = str(prepared.get("install_text", ""))
	var install_data: Dictionary = prepared.get("install_data", {})
	var local_text: String = _read_local_main_bytes()
	var effective_text: String = _read_effective_bytes()
	if not effective_text.is_empty() and effective_text == install_text:
		_floor_from_checkpoint(install_data, "restore")
		_adopt_baseline(int(remote.get("revision", 0)), remote_text)
		_save_state = "acked"
		_save_code = ""
		save_changed.emit(save_snapshot())
		return {"status": "ok", "code": "already-in-sync",
			"revision": int(remote.get("revision", 0))}
	if not effective_text.is_empty():
		var settled: Dictionary = _settle_defeat_download(
			captured, restore_epoch, effective_text, remote,
			remote_text, install_text, install_data)
		if not settled.is_empty():
			return settled
		_open_download_conflict(effective_text, remote)
		return {"status": "conflict", "code": "restore-differs",
			"retryable": false,
			"local_revision": int(_conflict.get("local_revision", 0)),
			"remote_revision": int(_conflict.get("remote_revision", 0)),
			"baseline_revision": int(_conflict.get("baseline_revision", -1)),
			"local_summary": (_conflict.get("local_summary", {})
				as Dictionary).duplicate(true),
			"remote_summary": (_conflict.get("remote_summary", {})
				as Dictionary).duplicate(true)}
	if not local_text.is_empty():
		if not _write_rejected("local", local_text):
			return {"status": "failure", "code": "recovery-save-failed",
				"retryable": false}
	if bool(prepared.get("remapped", false)) \
			and not _write_rejected("remote", remote_text):
		return {"status": "failure", "code": "recovery-save-failed",
			"retryable": false}
	# Pre-mutation recheck: a read retired after its reply landed must
	# not write, floor, or adopt anything on its way out.
	if _stale(captured) or restore_epoch != _restore_epoch:
		return _cancelled_stale()
	_installing_remote = true
	var installed: Error = Journey.write_checkpoint_text(install_text)
	_installing_remote = false
	if _stale(captured) or restore_epoch != _restore_epoch:
		return _cancelled_stale()
	if installed != OK:
		_save_state = "error"
		_save_code = "restore-install-failed"
		save_changed.emit(save_snapshot())
		return {"status": "failure", "code": "restore-install-failed",
			"retryable": false}
	var floored: Dictionary = _floor_from_checkpoint(install_data, "restore")
	if str(floored.get("code", "")) == "floor-save-failed":
		_save_state = "error"
		_save_code = "floor-save-failed"
		save_changed.emit(save_snapshot())
		return {"status": "failure", "code": "floor-save-failed",
			"retryable": true}
	_adopt_baseline(int(remote.get("revision", 0)), remote_text)
	_save_state = "acked"
	_save_code = ""
	save_changed.emit(save_snapshot())
	return {"status": "ok", "code": "restored",
		"revision": _known_remote_revision,
		"remapped": bool(prepared.get("remapped", false))}


## Same-journey defeat precedence for a download that differs from the local
## journey. Returns `{}` when the normal explicit conflict must open (both
## sides alive, both sealed, different journeys, or a seal strictly newer
## than the other side's defeat without an acknowledged baseline — genuine
## concurrent progress). Otherwise the terminal state wins without a dialog:
## a local seal keeps `defeat-kept` with the files untouched, a remote seal
## installs as `defeat-adopted` with the superseded alive bytes preserved
## to recovery first, and a stale remote seal against our acknowledged
## newer alive seal retires as `stale-ended-retired` with the files
## untouched. Journey identity compares the downloaded bytes before
## receipt-namespace remapping, so one device's own lineage always matches;
## a cross-device sequence collision resolves to the defeat and the
## surviving journey stays on the server for an explicit fresh-start
## conflict afterwards.
func _settle_defeat_download(captured: int, restore_epoch: int,
		effective_text: String, remote: Dictionary, remote_text: String,
		install_text: String, install_data: Dictionary) -> Dictionary:
	var local_meta: Dictionary = _defeat_meta(effective_text)
	var remote_meta: Dictionary = _defeat_meta(remote_text)
	if local_meta.is_empty() or remote_meta.is_empty():
		return {}
	if str(local_meta.get("journey", "")) != str(remote_meta.get("journey", "")):
		return {}
	var local_ended: bool = bool(local_meta.get("ended", false))
	var remote_ended: bool = bool(remote_meta.get("ended", false))
	if local_ended == remote_ended:
		return {}
	var local_cid: int = int(local_meta.get("checkpoint_id", 0))
	var remote_cid: int = int(remote_meta.get("checkpoint_id", 0))
	if local_ended and remote_cid > local_cid:
		return {}
	if remote_ended and local_cid > remote_cid:
		# Our alive seal is strictly newer than the downloaded death. Only
		# an acknowledged seal retires it outright: an unflushed revive
		# still opens the explicit dialog, where the guarded resolve
		# refuses the stale death and rebases the live seal instead.
		if _baseline_revision >= 1 \
				and _baseline_digest == effective_text.sha256_text():
			return {"status": "ok", "code": "stale-ended-retired",
				"remote_revision": int(remote.get("revision", 0))}
		return {}
	if local_ended:
		return {"status": "ok", "code": "defeat-kept",
			"remote_revision": int(remote.get("revision", 0))}
	return _adopt_remote_defeat(captured, restore_epoch, effective_text,
		remote, remote_text, install_text, install_data)


## Install a same-journey remote defeat over stale local alive bytes. Mirrors
## the empty-slot install: the superseded bytes are preserved first, a
## retired read installs nothing, and the receipt floors with zero granted.
func _adopt_remote_defeat(captured: int, restore_epoch: int,
		effective_text: String, remote: Dictionary, remote_text: String,
		install_text: String, install_data: Dictionary) -> Dictionary:
	if not effective_text.is_empty() and not _write_rejected(
			"local", effective_text):
		return {"status": "failure", "code": "recovery-save-failed",
			"retryable": false}
	if install_text != remote_text and not _write_rejected(
			"remote", remote_text):
		return {"status": "failure", "code": "recovery-save-failed",
			"retryable": false}
	if _stale(captured) or restore_epoch != _restore_epoch:
		return _cancelled_stale()
	_installing_remote = true
	var installed: Error = Journey.write_checkpoint_text(install_text)
	_installing_remote = false
	if _stale(captured) or restore_epoch != _restore_epoch:
		return _cancelled_stale()
	if installed != OK:
		_save_state = "error"
		_save_code = "restore-install-failed"
		save_changed.emit(save_snapshot())
		return {"status": "failure", "code": "restore-install-failed",
			"retryable": false}
	var floored: Dictionary = _floor_from_checkpoint(install_data, "restore")
	if str(floored.get("code", "")) == "floor-save-failed":
		_save_state = "error"
		_save_code = "floor-save-failed"
		save_changed.emit(save_snapshot())
		return {"status": "failure", "code": "floor-save-failed",
			"retryable": true}
	_adopt_baseline(int(remote.get("revision", 0)), remote_text)
	_save_state = "acked"
	_save_code = ""
	save_changed.emit(save_snapshot())
	return {"status": "ok", "code": "defeat-adopted",
		"revision": _known_remote_revision,
		"remapped": install_text != remote_text,
		"local_preserved": not effective_text.is_empty()}


## Journey identity, checkpoint id and defeat marker of one checkpoint
## payload, or `{}` when the bytes are not a checkpoint at all. Parsed
## numbers arrive as floats, so whole floats count as integers exactly like
## the Journey validator counts them; the journey key keeps ints and strings
## in separate namespaces so id `5` never aliases id `"5"`.
func _defeat_meta(text: String) -> Dictionary:
	var decoded: Dictionary = CloudSchema.parse_json_value(text)
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = decoded.get("value")
	var journey: Variant = data.get("journey_id", null)
	var key: String = ""
	if journey is int:
		key = "i%d" % int(journey)
	elif journey is float and journey == floor(journey):
		key = "i%d" % int(journey)
	elif journey is String and not str(journey).is_empty():
		key = "s%s" % str(journey)
	else:
		return {}
	var cid: Variant = data.get("checkpoint_id", null)
	var checkpoint_id: int = -1
	if cid is int:
		checkpoint_id = int(cid)
	elif cid is float and cid == floor(cid):
		checkpoint_id = int(cid)
	else:
		return {}
	var marker: Variant = data.get("ended", false)
	return {
		"journey": key,
		"checkpoint_id": checkpoint_id,
		"ended": marker is bool and bool(marker),
	}


## True when installing the download would silently resume a sealed run: the
## current local bytes hold the same journey's defeat and the download is
## that journey alive at no newer seal.
func _download_resurrects(local_text: String, remote_text: String) -> bool:
	var local_meta: Dictionary = _defeat_meta(local_text)
	var remote_meta: Dictionary = _defeat_meta(remote_text)
	if local_meta.is_empty() or remote_meta.is_empty():
		return false
	if str(local_meta.get("journey", "")) != str(remote_meta.get("journey", "")):
		return false
	return bool(local_meta.get("ended", false)) \
		and not bool(remote_meta.get("ended", false)) \
		and int(remote_meta.get("checkpoint_id", 0)) \
			<= int(local_meta.get("checkpoint_id", 0))


## True when uploading the local bytes would silently resurrect a sealed run
## on the server: the fresh remote holds the same journey's defeat and the
## local bytes are that journey alive at no newer seal.
func _upload_resurrects(local_text: String, remote_text: String) -> bool:
	var local_meta: Dictionary = _defeat_meta(local_text)
	var remote_meta: Dictionary = _defeat_meta(remote_text)
	if local_meta.is_empty() or remote_meta.is_empty():
		return false
	if str(local_meta.get("journey", "")) != str(remote_meta.get("journey", "")):
		return false
	return not bool(local_meta.get("ended", false)) \
		and bool(remote_meta.get("ended", false)) \
		and int(local_meta.get("checkpoint_id", 0)) \
			<= int(remote_meta.get("checkpoint_id", 0))


## True when uploading the local bytes would commit a stale death over the
## journey's acknowledged newer seal: the payload is ended, the fresh
## remote is that journey alive at a strictly newer seal (the paid revive
## already landed there), so the ended candidate retires instead.
func _upload_commits_stale_death(payload: String,
		fresh_text: String) -> bool:
	var local_meta: Dictionary = _defeat_meta(payload)
	var remote_meta: Dictionary = _defeat_meta(fresh_text)
	if local_meta.is_empty() or remote_meta.is_empty():
		return false
	if str(local_meta.get("journey", "")) != str(remote_meta.get("journey", "")):
		return false
	return bool(local_meta.get("ended", false)) \
		and not bool(remote_meta.get("ended", false)) \
		and int(remote_meta.get("checkpoint_id", 0)) \
			> int(local_meta.get("checkpoint_id", 0))


## True when installing the download would lay a stale death over the
## journey's newer alive seal: the download is ended, the current local
## bytes are that journey alive at a strictly newer seal, so the ended
## candidate retires instead.
func _download_installs_stale_death(local_text: String,
		remote_text: String) -> bool:
	var local_meta: Dictionary = _defeat_meta(local_text)
	var remote_meta: Dictionary = _defeat_meta(remote_text)
	if local_meta.is_empty() or remote_meta.is_empty():
		return false
	if str(local_meta.get("journey", "")) != str(remote_meta.get("journey", "")):
		return false
	return not bool(local_meta.get("ended", false)) \
		and bool(remote_meta.get("ended", false)) \
		and int(local_meta.get("checkpoint_id", 0)) \
			> int(remote_meta.get("checkpoint_id", 0))


## Submit the active checkpoint's actual hero, score, and cycles as our
## single best Hall row. Reads the local checkpoint only; the row is the
## one document our public ID owns, so retries overwrite it idempotently.
func submit_current_best() -> Dictionary:
	var captured: int = _generation
	if _closed:
		return {"status": "cancelled", "code": "coordinator-closed",
			"retryable": false}
	if not account_ready():
		_hall_snapshot["state"] = "unregistered"
		_hall_snapshot["source"] = "unregistered"
		hall_changed.emit(hall_snapshot())
		return {"status": "unregistered", "code": "account-not-ready",
			"retryable": false}
	var checkpoint: Dictionary = Journey.read_checkpoint()
	if checkpoint.is_empty():
		return {"status": "failure", "code": "no-checkpoint",
			"retryable": false}
	var derived: Dictionary = _derive_hall_row(checkpoint)
	var row_check: Dictionary = CloudSchema.validate_hall_row(
		str(derived.get("hero", "")), int(derived.get("score", 0)),
		int(derived.get("cycles", 0)), _release)
	if not bool(row_check.get("ok", false)):
		return {"status": "failure",
			"code": str(row_check.get("error", "invalid-row")),
			"retryable": false}
	var display: String = ""
	if _vault != null:
		display = str((_vault.call("verified_name_for_account",
			_canonical_id) as Dictionary).get("display", ""))
	var result: Dictionary = await _hall.call("submit_best", _transport,
		_canonical_id, str(derived.get("hero", "")),
		int(derived.get("score", 0)), int(derived.get("cycles", 0)),
		_release, display)
	if _stale(captured):
		return _cancelled_stale()
	if str(result.get("status", "")) == "ok":
		_hall_snapshot["state"] = "ready"
		_hall_snapshot["source"] = "live"
		_hall_snapshot["last_submit"] = {
			"score": int(derived.get("score", 0)),
			"code": "ok",
		}
		if not (_hall_snapshot.get("rows", []) as Array).is_empty():
			_hall_snapshot["source"] = "stale"
	elif str(result.get("code", "")) == "not-best":
		_hall_snapshot["state"] = "ready"
		_hall_snapshot["last_submit"] = {
			"score": int(derived.get("score", 0)),
			"code": "not-best",
			"best": int(result.get("best", 0)),
		}
	elif str(result.get("status", "")) == "offline":
		_hall_snapshot["state"] = "offline"
	else:
		_hall_snapshot["state"] = "error"
	hall_changed.emit(hall_snapshot())
	return result


## Claim an adventurer name for the ready account, or restore the one it
## already owns. A verified claim is cached for offline use and attached
## to the existing best row at its own score; the claim stands even when
## the cache write or the backfill fails, and the result says which leg
## did not land (`cached`, `backfilled`, `backfill_code`) so the lodge
## can retry exactly that leg.
func claim_adventurer_name(raw_display: String) -> Dictionary:
	var captured: int = _generation
	if _closed:
		return {"status": "cancelled", "code": "coordinator-closed",
			"retryable": false}
	if not account_ready():
		return {"status": "unregistered", "code": "account-not-ready",
			"retryable": false}
	var claimed: Dictionary = await _names.call("claim_name", _transport,
		_uid, _canonical_id, raw_display)
	if _stale(captured):
		return _cancelled_stale()
	if str(claimed.get("status", "")) != "ok":
		return claimed
	claimed["cached"] = _cache_verified_name(claimed)
	var backfilled: Dictionary = await _hall.call("backfill_display",
		_transport, _canonical_id, str(claimed.get("display", "")))
	if _stale(captured):
		return _cancelled_stale()
	claimed["backfilled"] = bool(backfilled.get("backfilled", false))
	claimed["backfill_code"] = str(backfilled.get("code",
		backfilled.get("status", "")))
	return claimed


## Reload the ready account's claimed name and refresh its offline cache.
## A recovered row never adopts another account: fetching names the exact
## UID and public ID, and a mismatched row reports instead of applying.
func fetch_adventurer_name() -> Dictionary:
	var captured: int = _generation
	if _closed:
		return {"status": "cancelled", "code": "coordinator-closed",
			"retryable": false}
	if not account_ready():
		return {"status": "unregistered", "code": "account-not-ready",
			"retryable": false}
	var loaded: Dictionary = await _names.call("fetch_adventurer",
		_transport, _uid, _canonical_id)
	if _stale(captured):
		return _cancelled_stale()
	if str(loaded.get("status", "")) != "ok":
		return loaded
	loaded["cached"] = _cache_verified_name(loaded)
	return loaded


## Flip the tutorial bit on the ready account's claimed name. Idempotent:
## double taps and uncertain acknowledgements converge on one row.
func complete_intro() -> Dictionary:
	var captured: int = _generation
	if _closed:
		return {"status": "cancelled", "code": "coordinator-closed",
			"retryable": false}
	if not account_ready():
		return {"status": "unregistered", "code": "account-not-ready",
			"retryable": false}
	var done: Dictionary = await _names.call("mark_intro_complete",
		_transport, _uid, _canonical_id)
	if _stale(captured):
		return _cancelled_stale()
	if str(done.get("status", "")) != "ok":
		return done
	done["cached"] = _cache_verified_name(done)
	return done


## Attach the ready account's verified handle to its existing best row at
## the row's own score. Resolves a cold cache from the server once; writes
## nothing when no best row exists yet.
func backfill_hall_name() -> Dictionary:
	var captured: int = _generation
	if _closed:
		return {"status": "cancelled", "code": "coordinator-closed",
			"retryable": false}
	if not account_ready():
		return {"status": "unregistered", "code": "account-not-ready",
			"retryable": false}
	var display: String = ""
	if _vault != null:
		display = str((_vault.call("verified_name_for_account",
			_canonical_id) as Dictionary).get("display", ""))
	if display.is_empty():
		var loaded: Dictionary = await fetch_adventurer_name()
		if _stale(captured):
			return _cancelled_stale()
		if str(loaded.get("status", "")) != "ok":
			return loaded
		display = str(loaded.get("display", ""))
	return await _hall.call("backfill_display", _transport,
		_canonical_id, display)


## Claim this attendance period: one server-conditional claim, then exactly
## one local grant of two coins under the stable derived receipt key.
##
## Returns `granted` with `{receipt, coins, next_eligible_utc,
## remaining_seconds}` for a new claim, `already-claimed` when this install
## already received the current period (topping up a missing local grant
## after an uncertain ack or a failed wallet write), or `cooldown` when
## another install holds the period. An eligible advance first backfills
## every owned still-unapplied reward named by the read row, then commits
## carrying the row; results name any backfill in `backfilled` plus
## `backfilled_receipt`. Offline, denied, and conflict-race replies pass
## through honestly and grant nothing; a failed local wallet write after
## a server ack returns `local-grant-failed` with `server_claimed` so the
## next trigger recovers without loss or replay.
func claim_attendance() -> Dictionary:
	var captured: int = _generation
	if _closed:
		return {"status": "cancelled", "code": "coordinator-closed",
			"retryable": false}
	if not account_ready():
		return {"status": "unregistered", "code": "account-not-ready",
			"retryable": false}
	var install_id: String = ""
	if _vault != null:
		install_id = str(_vault.call("ensure_install_id"))
	if install_id.is_empty():
		return {"status": "failure", "code": "attendance-no-install",
			"retryable": true}
	var claimed: Dictionary = await _attendance.call("claim_attendance",
		_transport, _uid, _canonical_id, install_id)
	if _stale(captured):
		return _cancelled_stale()
	var state: String = str(claimed.get("status", ""))
	if state == "ok":
		return _grant_attendance_claim(claimed, install_id, captured)
	if state == "already-claimed":
		return _settle_attendance_hold(claimed, install_id, captured)
	if state == "eligible":
		return await _advance_attendance_claim(
			claimed, install_id, captured)
	if _stale(captured):
		return _cancelled_stale()
	_serve_attendance_offline()
	return claimed


## Advance one eligible period: backfill every owned still-unapplied
## reward on the read row first, then commit carrying the row. A failed
## wallet save stops before the commit so the server row keeps the
## recoverable receipt; an ambiguous forgotten receipt is skipped (named,
## never repaid) while the genuine new claim still progresses. The wallet
## already holds every backfilled coin.
func _advance_attendance_claim(row: Dictionary, install_id: String,
		captured: int) -> Dictionary:
	var backfill: Dictionary = _backfill_attendance_claims(
		row, install_id, true)
	if _stale(captured):
		return _cancelled_stale()
	if str(backfill.get("status", "")) == "failure":
		return _pending_attendance_receipt(row, backfill)
	var advanced: Dictionary = await _attendance.call("commit_advance",
		_transport, _uid, _canonical_id, install_id,
		str(row.get("update_time", "")),
		str(row.get("last_claim_rfc", "")),
		str(row.get("install_id", "")))
	if _stale(captured):
		return _cancelled_stale()
	var settled: Dictionary = advanced
	if str(advanced.get("status", "")) != "ok":
		_serve_attendance_offline()
	else:
		settled = _grant_attendance_claim(
			advanced, install_id, captured)
	if str(settled.get("status", "")) != "cancelled":
		settled["backfilled"] = bool(backfill.get("backfilled", false))
		settled["backfilled_receipt"] = str(
			backfill.get("receipt", ""))
		settled["backfill_skipped"] = bool(
			backfill.get("skipped", false))
		settled["skipped_receipt"] = str(
			backfill.get("skipped_receipt", ""))
	return settled


## Apply owned still-unapplied rewards named by a read row: its current
## stamp when this install received it (`include_last`), plus any carried
## previous stamp from this install. Each grant is strict (a re-read
## carries no fresh proof), so a replay past the eviction floor refuses
## instead of paying twice. A refused old receipt is SKIPPED, never
## repaid, and the caller still proceeds: bounded retired history must
## not freeze genuinely new rewards. Only a failed wallet save stops the
## caller (the row keeps the recoverable receipt). Returns `{backfilled,
## receipt, skipped, skipped_receipt}` naming the newest landed backfill
## and the newest skipped old receipt, or `{status: failure, code,
## receipt, retryable}` when a save fails.
func _backfill_attendance_claims(row: Dictionary, install_id: String,
		include_last: bool) -> Dictionary:
	var summary: Dictionary = {"backfilled": false, "receipt": "",
		"skipped": false, "skipped_receipt": ""}
	var candidates: Array = []
	if include_last \
			and str(row.get("install_id", "")) == install_id \
			and not install_id.is_empty():
		candidates.append(int(row.get("last_claim_at", 0)))
	if str(row.get("prev_install_id", "")) == install_id \
			and not install_id.is_empty():
		candidates.append(int(row.get("prev_claim_at", 0)))
	var pending: Array = []
	for seconds in candidates:
		if int(seconds) <= 0:
			continue
		if _vault != null and bool(_vault.call(
				"attendance_receipt_applied", _canonical_id,
				int(seconds), install_id)):
			continue
		pending.append(int(seconds))
	if pending.is_empty():
		return summary
	if _vault == null:
		return {"status": "failure", "code": "attendance-no-vault",
			"receipt": "", "retryable": false}
	for seconds in pending:
		var receipt: String = CloudSchema.attendance_receipt_key(
			_canonical_id, seconds, install_id)
		var granted: Dictionary = _vault.call("grant_attendance_coins",
			_canonical_id, seconds, install_id, false)
		if str(granted.get("status", "")) != "ok":
			if str(granted.get("code", "")) \
					== "attendance-replay-ambiguous":
				summary["skipped"] = true
				summary["skipped_receipt"] = receipt
				continue
			var mapped: Dictionary = _vault_grant_failure(granted)
			return {"status": "failure",
				"code": str(mapped.get("code", "")),
				"receipt": receipt,
				"retryable": bool(mapped.get("retryable", false))}
		if bool(granted.get("granted", false)):
			summary["backfilled"] = true
			summary["receipt"] = receipt
	return summary


## Publish the live snapshot for a pending earned receipt the wallet
## could not take yet, and report it honestly: the server row already
## acknowledged these coins, the deadline is eligible now, and retry may
## recover them (a failed save) or never can (an eviction ambiguity).
func _pending_attendance_receipt(row: Dictionary,
		backfill: Dictionary) -> Dictionary:
	var last_seconds: int = int(row.get("last_claim_at", 0))
	var receipt: String = str(backfill.get("receipt", ""))
	var pending: Dictionary = {
		"next_eligible_utc": CloudSchema.rfc3339_from_unix(
			last_seconds + CloudSchema.ATTENDANCE_COOLDOWN_SECONDS),
		"remaining_seconds": 0,
		"server_now": int(row.get("server_now", last_seconds)),
	}
	_cache_attendance_deadline(pending)
	_publish_attendance_snapshot(pending, receipt, last_seconds)
	return {"status": "failure", "code": str(backfill.get("code", "")),
		"server_claimed": true, "receipt": receipt,
		"next_eligible_utc": str(pending.get("next_eligible_utc", "")),
		"remaining_seconds": 0,
		"retryable": bool(backfill.get("retryable", false))}


## Map a vault grant failure to its honest caller code. An eviction-floor
## ambiguity is terminal (no retry can resolve forgotten history); a
## failed save stays retryable under the established code.
static func _vault_grant_failure(granted: Dictionary) -> Dictionary:
	if str(granted.get("code", "")) == "attendance-replay-ambiguous":
		return {"code": "attendance-replay-ambiguous",
			"retryable": false}
	return {"code": "local-grant-failed", "retryable": true}


## Apply a landed server claim to the local wallet exactly once, then
## publish the confirmed deadline. The just-landed commit is fresh proof,
## so same-second cross-owner ties still grant; a failed wallet write
## keeps the server truth and reports recovery-by-retry, never a loss.
func _grant_attendance_claim(claimed: Dictionary, install_id: String,
		captured: int) -> Dictionary:
	var claim_seconds: int = int(claimed.get("claim_seconds", 0))
	var receipt: String = CloudSchema.attendance_receipt_key(
		_canonical_id, claim_seconds, install_id)
	var granted: Dictionary = {"status": "failure",
		"code": "attendance-no-vault", "granted": false,
		"duplicate": false}
	if _vault != null:
		granted = _vault.call("grant_attendance_coins", _canonical_id,
			claim_seconds, install_id, true)
	if _stale(captured):
		return _cancelled_stale()
	_cache_attendance_deadline(claimed)
	_publish_attendance_snapshot(claimed, receipt, claim_seconds)
	if str(granted.get("status", "")) != "ok":
		var mapped: Dictionary = _vault_grant_failure(granted)
		return {"status": "failure",
			"code": str(mapped.get("code", "")),
			"server_claimed": true, "receipt": receipt,
			"claim_seconds": claim_seconds,
			"next_eligible_utc": str(claimed.get(
				"next_eligible_utc", "")),
			"remaining_seconds": int(claimed.get(
				"remaining_seconds", 0)),
			"retryable": bool(mapped.get("retryable", false))}
	return {"status": "granted", "receipt": receipt,
		"coins": CloudSchema.ATTENDANCE_GRANT_COINS,
		"granted": bool(granted.get("granted", false)),
		"duplicate": bool(granted.get("duplicate", false)),
		"next_eligible_utc": str(claimed.get("next_eligible_utc", "")),
		"remaining_seconds": int(claimed.get("remaining_seconds", 0))}


## Settle a held period. Ours (double tap, uncertain ack, recovery):
## ensure the local grant under the row's own key, idempotently.
## Another install's: deadline only, never a grant into this wallet.
## Either way, a carried previous stamp from this install backfills
## first, so another install's advance never strands our reward.
func _settle_attendance_hold(claimed: Dictionary, install_id: String,
		captured: int) -> Dictionary:
	_cache_attendance_deadline(claimed)
	var backfill: Dictionary = _backfill_attendance_claims(
		claimed, install_id, false)
	if _stale(captured):
		return _cancelled_stale()
	if str(backfill.get("status", "")) == "failure":
		claimed["status"] = "failure"
		claimed["code"] = str(backfill.get("code", ""))
		claimed["server_claimed"] = true
		claimed["receipt"] = str(backfill.get("receipt", ""))
		claimed["retryable"] = bool(backfill.get("retryable", false))
		_publish_attendance_snapshot(claimed,
			str(backfill.get("receipt", "")),
			int(claimed.get("last_claim_at", 0)))
		return claimed
	claimed["backfilled"] = bool(backfill.get("backfilled", false))
	claimed["backfilled_receipt"] = str(backfill.get("receipt", ""))
	claimed["backfill_skipped"] = bool(backfill.get("skipped", false))
	claimed["skipped_receipt"] = str(
		backfill.get("skipped_receipt", ""))
	if not bool(claimed.get("mine", false)):
		_publish_attendance_snapshot(claimed,
			str(backfill.get("receipt", "")),
			int(claimed.get("last_claim_at", 0)))
		claimed["status"] = "cooldown"
		return claimed
	var claim_seconds: int = int(claimed.get("last_claim_at", 0))
	var receipt: String = CloudSchema.attendance_receipt_key(
		_canonical_id, claim_seconds, install_id)
	var granted: Dictionary = {"status": "failure",
		"code": "attendance-no-vault", "granted": false,
		"duplicate": false}
	if _vault != null:
		granted = _vault.call("grant_attendance_coins", _canonical_id,
			claim_seconds, install_id)
	if _stale(captured):
		return _cancelled_stale()
	_publish_attendance_snapshot(claimed, receipt, claim_seconds)
	if str(granted.get("status", "")) != "ok":
		var mapped: Dictionary = _vault_grant_failure(granted)
		claimed["status"] = "failure"
		claimed["code"] = str(mapped.get("code", ""))
		claimed["server_claimed"] = true
		claimed["receipt"] = receipt
		claimed["retryable"] = bool(mapped.get("retryable", false))
		return claimed
	claimed["receipt"] = receipt
	claimed["coins"] = CloudSchema.ATTENDANCE_GRANT_COINS
	claimed["granted"] = bool(granted.get("granted", false))
	return claimed


## Best-effort deadline cache for display and reminder scheduling. The
## claim path never reads it back: only a live server read grants.
func _cache_attendance_deadline(claimed: Dictionary) -> void:
	if _vault == null:
		return
	_vault.call("cache_attendance_next", _canonical_id,
		str(claimed.get("next_eligible_utc", "")),
		int(claimed.get("remaining_seconds", 0)),
		int(claimed.get("server_now",
			claimed.get("claim_seconds",
				claimed.get("last_claim_at", 0)))))


## Publish the live attendance snapshot for the reminder controller and
## any deadline display. Absolute server-confirmed UTC plus bounded
## server-derived remaining: no grant capability rides along.
func _publish_attendance_snapshot(claimed: Dictionary, receipt: String,
		claim_seconds: int) -> void:
	var last_utc: String = ""
	if claim_seconds > 0:
		last_utc = CloudSchema.rfc3339_from_unix(claim_seconds)
	_attendance_snapshot = {"state": "ready", "source": "live",
		"public_id": _canonical_id, "receipt": receipt,
		"last_claim_utc": last_utc,
		"next_eligible_utc": str(claimed.get("next_eligible_utc", "")),
		"remaining_seconds": int(claimed.get("remaining_seconds", -1))}
	attendance_changed.emit(_attendance_snapshot.duplicate())


## Offline or errored reads keep the last live snapshot when one exists;
## otherwise they serve the cached deadline labeled as cache, which can
## schedule a reminder but never mint coins.
func _serve_attendance_offline() -> void:
	if str(_attendance_snapshot.get("source", "")) == "live":
		return
	var cached: Dictionary = {}
	if _vault != null:
		cached = _vault.call("attendance_next_for_account",
			_canonical_id)
	if cached.is_empty():
		_attendance_snapshot = {"state": "offline", "source": "none",
			"public_id": _canonical_id, "receipt": "",
			"last_claim_utc": "",
			"next_eligible_utc": "", "remaining_seconds": -1}
	else:
		_attendance_snapshot = {"state": "offline", "source": "cache",
			"public_id": _canonical_id, "receipt": "",
			"last_claim_utc": "",
			"next_eligible_utc": str(cached.get("next_utc", "")),
			"remaining_seconds": int(cached.get("remaining", -1))}
	attendance_changed.emit(_attendance_snapshot.duplicate())


## Current attendance view for the reminder controller. Live values win;
## cached deadlines arrive labeled and grant nothing.
func attendance_snapshot() -> Dictionary:
	if _attendance_snapshot.is_empty():
		return {"state": "unregistered", "source": "none",
			"public_id": _canonical_id, "receipt": "",
			"last_claim_utc": "",
			"next_eligible_utc": "", "remaining_seconds": -1}
	return _attendance_snapshot.duplicate()


## Remember one verified claim result in the account-partitioned durable
## cache. Best effort: the server already acknowledged the name, so a
## failed local write only skips the offline copy, which the next load
## restores from the server.
func _cache_verified_name(claimed: Dictionary) -> bool:
	if _vault == null:
		return false
	return bool(_vault.call("cache_verified_name", _canonical_id,
		str(claimed.get("display", "")), str(claimed.get("key", "")),
		bool(claimed.get("intro_complete", false))))


## Refresh the public top board. Results label their source; failures keep
## the last known rows labeled instead of inventing new ones.
func refresh_board(limit: int = 20) -> Dictionary:
	var captured: int = _generation
	if _closed:
		return {"status": "cancelled", "code": "coordinator-closed",
			"retryable": false}
	var result: Dictionary = await _hall.call("fetch_top", _transport,
		limit, _now_msec())
	if _stale(captured):
		return _cancelled_stale()
	if str(result.get("status", "")) == "ok":
		_hall_snapshot["state"] = "ready"
		_hall_snapshot["source"] = str(result.get("source", "live"))
		_hall_snapshot["rows"] = (result.get("rows", []) as Array
			).duplicate(true)
		_hall_snapshot["live_error"] = str(result.get("live_error", ""))
	elif str(result.get("status", "")) == "offline":
		_hall_snapshot["state"] = "offline"
	else:
		_hall_snapshot["state"] = "error"
	hall_changed.emit(hall_snapshot())
	return result


## Refresh our actual Hall standing: the owned `mb_hall_v1` best row for
## our canonical ID, ranked against the Hall. The result and snapshot carry
## that row's hero, score, cycles, and public ID with the rank, so the HUD
## never pairs a rank with a different hero or score — not even while the
## local journey holds a fresh low score under a newly selected hero. A
## missing own row is genuinely unranked (state `unranked`, rank 0): no
## invented #1 and no submission is ever started here. Ranking reads only:
## it never rewrites or floors the local journey. The Hall throttles the
## complete row-plus-rank refresh globally, so rapid calls reuse the
## labeled last known pair instead of firing requests each.
func refresh_rank() -> Dictionary:
	var captured: int = _generation
	if _closed:
		return {"status": "cancelled", "code": "coordinator-closed",
			"retryable": false}
	if not account_ready():
		_rank_snapshot["state"] = "unregistered"
		_rank_snapshot["source"] = "unregistered"
		rank_changed.emit(rank_snapshot())
		return {"status": "unregistered", "code": "account-not-ready",
			"retryable": false}
	var result: Dictionary = await _hall.call("fetch_self_rank",
		_transport, _canonical_id, _now_msec())
	if _stale(captured):
		return _cancelled_stale()
	if str(result.get("status", "")) == "ok":
		_rank_snapshot["state"] = "ready"
		_rank_snapshot["source"] = str(result.get("source", "live"))
		_rank_snapshot["rank"] = int(result.get("rank", 0))
		_rank_snapshot["greater"] = int(result.get("greater", 0))
		_rank_snapshot["score"] = int(result.get("score", 0))
		_rank_snapshot["hero"] = str(result.get("hero", ""))
		_rank_snapshot["cycles"] = int(result.get("cycles", 0))
		_rank_snapshot["public_id"] = str(result.get("public_id", ""))
		_rank_snapshot["requested_score"] = int(result.get("score", 0))
		_rank_snapshot["row_source"] = str(result.get("row_source", "live"))
		_rank_snapshot["rank_source"] = str(
			result.get("rank_source", "live"))
		_rank_snapshot["fetched_msec"] = int(
			result.get("fetched_msec", 0))
		_rank_snapshot["row_fetched_msec"] = int(
			result.get("row_fetched_msec", 0))
		_rank_snapshot["rank_fetched_msec"] = int(
			result.get("rank_fetched_msec", 0))
		_rank_snapshot["live_error"] = str(result.get("live_error", ""))
	elif str(result.get("status", "")) == "unranked":
		_rank_snapshot["state"] = "unranked"
		_rank_snapshot["source"] = str(result.get("source", "live"))
		_rank_snapshot["rank"] = 0
		_rank_snapshot["greater"] = 0
		_rank_snapshot["score"] = 0
		_rank_snapshot["hero"] = ""
		_rank_snapshot["cycles"] = 0
		_rank_snapshot["public_id"] = str(
			result.get("public_id", _canonical_id))
		_rank_snapshot["requested_score"] = 0
		_rank_snapshot["row_source"] = str(
			result.get("row_source", result.get("source", "live")))
		_rank_snapshot["rank_source"] = str(result.get("rank_source", ""))
		_rank_snapshot["fetched_msec"] = int(
			result.get("fetched_msec", 0))
		_rank_snapshot["row_fetched_msec"] = int(
			result.get("row_fetched_msec",
				result.get("fetched_msec", 0)))
		_rank_snapshot["rank_fetched_msec"] = int(
			result.get("rank_fetched_msec", 0))
		_rank_snapshot["live_error"] = ""
	elif str(result.get("status", "")) == "offline":
		_rank_snapshot["state"] = "offline"
		_rank_snapshot["live_error"] = "offline"
	elif str(result.get("status", "")) == "cancelled":
		# A retired Hall ticket: the snapshot keeps its newer pair (or
		# its unranked state) and the stale result is dropped silently,
		# exactly like a retired generation. Never publish it.
		return result
	else:
		_rank_snapshot["state"] = "error"
		_rank_snapshot["live_error"] = str(result.get("code", "failure"))
	rank_changed.emit(rank_snapshot())
	return result


## Read back one preserved rejected payload for recovery tooling. Returns
## `{ok, text}` or `{ok: false, error}`; never executes or installs it.
func recovery_payload(side: String) -> Dictionary:
	if _partition_key.is_empty():
		return {"ok": false, "error": "coordinator-unconfigured"}
	var candidate: String = Journey.account_rejected_path(
		_partition_key, side)
	if not FileAccess.file_exists(candidate):
		return {"ok": false, "error": "not-found"}
	var reader: FileAccess = FileAccess.open(candidate, FileAccess.READ)
	if reader == null:
		return {"ok": false, "error": "read-failed"}
	var length: int = int(reader.get_length())
	if length > Journey.MAX_FILE_BYTES:
		reader.close()
		return {"ok": false, "error": "payload-too-large"}
	var text: String = reader.get_as_text()
	reader.close()
	if text.to_utf8_buffer().size() > Journey.MAX_FILE_BYTES:
		return {"ok": false, "error": "payload-too-large"}
	return {"ok": true, "text": text}


## Test hook: pin the clock `fetch` calls throttle against. Negative
## restores the real clock.
func _test_set_now(now_msec: int) -> void:
	_now_override = now_msec


## Test hook: internal state no snapshot carries. Memory only.
func _test_state() -> Dictionary:
	return {
		"generation": _generation,
		"partition": _partition_key,
		"canonical": _canonical_id,
		"acked": _acked_revision,
		"known_remote": _known_remote_revision,
		"baseline_revision": _baseline_revision,
		"baseline_digest": _baseline_digest,
		"flush_running": _flush_owner != 0,
		"has_pending": bool(_checkpoint.call("has_pending")),
		"has_failed": not bool((_checkpoint.call("failed_save")
			as Dictionary).is_empty()),
		"has_conflict": not _conflict.is_empty(),
		"installing_remote": _installing_remote,
		"hof_account": str(_hall.get("_account_public_id")),
		"rank_cache": int(_hall.call("rank_cache_size")),
		"own_cache": int(_hall.call("own_cache_size")),
	}


## Map an imported (remote) journey id into this device's receipt
## namespace. Integers are device-local sequence namespaces that collide
## across devices, so every imported int becomes a deterministic
## per-account string: `c` plus 31 hex of `sha256(uid + ":" + journey)`.
## Strings pass through: they are already globally unique random or mapped
## ids. Never interpret a remote int as a local receipt — that would alias
## unrelated journeys or corrupt an existing record. Host contract: the
## coordinator applies this mapping at every remote install; hosts must
## never settle a foreign int directly. No checkpoint schema change: mapped
## ids are ordinary safe strings that old validators already accept.
func map_remote_journey_id(uid: String, journey: Variant) -> Variant:
	var journey_int: int = -1
	if journey is int:
		journey_int = int(journey)
	elif journey is float and (journey as float) == floor(journey as float) \
			and journey >= 1.0 \
			and journey <= float(Journey.JSON_INT_LIMIT):
		journey_int = int(journey)
	if journey_int < 0:
		return journey
	var digest: String = (uid + ":" + str(journey_int)
		).sha256_text().substr(0, 31)
	return "c" + digest


# --- internals ----------------------------------------------------------------

func _now_msec() -> int:
	if _now_override >= 0:
		return _now_override
	return int(Time.get_ticks_msec())


func _stale(captured: int) -> bool:
	return _closed or captured != _generation


func _flush_locked() -> bool:
	return _flush_owner != 0


func _release_flush(ticket: int) -> void:
	if _flush_owner == ticket:
		_flush_owner = 0


func _cancelled_stale() -> Dictionary:
	return {"status": "cancelled", "code": "stale-reply",
		"retryable": false}


func _subscribe_hook() -> void:
	Journey.subscribe_stable_checkpoint(
		Callable(self, "_on_stable_checkpoint"))


func _unsubscribe_hook() -> void:
	Journey.unsubscribe_stable_checkpoint(
		Callable(self, "_on_stable_checkpoint"))


## Background reservation started by `configure_host`. Applies nothing when
## a newer configuration superseded it.
func _reserve_async(captured: int) -> void:
	var result: Dictionary = await _identity.call(
		"register_or_restore_with_guest_id", _transport, _uid,
		_requested_guest_id)
	if _stale(captured):
		return
	var status: String = str(result.get("status", "failure"))
	if status == "ok":
		_canonical_id = str(result.get("public_id", ""))
		if _canonical_id != _partition_key:
			var migration: Dictionary = _move_slot_to_canonical()
			if not bool(migration.get("ok", false)):
				_account_state = "error"
				_account_code = "slot-move-failed"
				_save_state = "error"
				_save_code = "slot-move-failed"
				account_changed.emit(account_snapshot())
				save_changed.emit(save_snapshot())
				return
		_hall.call("set_account", _canonical_id)
		_reconcile_active_receipt_floor()
		_account_state = "ready"
		_account_code = ""
		_save_state = "idle"
		_save_code = ""
		account_changed.emit(account_snapshot())
		save_changed.emit(save_snapshot())
		_catch_up_after_ready(captured)
		return
	if status == "offline":
		_account_state = "offline"
		_account_code = "offline"
		_save_state = "unregistered"
	elif status == "conflict":
		_account_state = "conflict"
		_account_code = str(result.get("code", "conflict"))
		_save_state = "unregistered"
	elif status == "unconfigured":
		_account_state = "error"
		_account_code = str(result.get("code", "unconfigured"))
		_save_state = "unregistered"
	elif status == "cancelled":
		_account_state = "error"
		_account_code = str(result.get("code", "cancelled"))
		_save_state = "unregistered"
	else:
		_account_state = "error"
		_account_code = str(result.get("code", "failure"))
		_save_state = "unregistered"
	account_changed.emit(account_snapshot())
	save_changed.emit(save_snapshot())


## Move an offline guest slot under its canonical id once known,
## rekey-first: the pending receipt rekeys onto the canonical slot BEFORE
## any file moves, so a crash between the two leaves the receipt ahead of
## its bytes and the retry completes the move. A failure holds the move —
## guest files and receipt stay jointly in place — and reports `ok: false`
## instead of adopting over a stranded receipt. Files only move into an
## empty canonical slot; a canonical slot that already holds a journey
## keeps it and the guest slot stays in place, preserved but deferred.
func _move_slot_to_canonical() -> Dictionary:
	if _canonical_id.is_empty() or _partition_key.is_empty():
		return {"ok": true, "moved": []}
	if _canonical_id == _partition_key:
		return {"ok": true, "moved": []}
	var readiness: String = str(_vault.call("prepare_receipt_move",
		_partition_key, _canonical_id))
	if readiness == "failed":
		_save_code = "slot-move-failed"
		return {"ok": false, "moved": [], "code": "slot-move-failed"}
	if readiness == "kept":
		_partition_key = _canonical_id
		Journey.use_account(_canonical_id)
		_load_revision_file()
		return {"ok": true, "moved": [], "kept": true}
	var moved: Dictionary = Journey.move_account_slot(
		_partition_key, _canonical_id)
	if not bool(moved.get("ok", false)):
		_save_code = "slot-move-failed"
		return {"ok": false, "moved": [], "code": "slot-move-failed"}
	_partition_key = _canonical_id
	Journey.use_account(_canonical_id)
	_load_revision_file()
	return {"ok": true, "moved": moved.get("moved", []), "kept": false}


## Queue the current local checkpoint once the account is ready, so offline
## progress made while unregistered uploads without a new seal. Queues the
## effective file bytes verbatim — never a re-serialization, which the JSON
## number round-trip would corrupt (parsed integers come back as floats).
func _catch_up_after_ready(captured: int) -> void:
	if _stale(captured) or _canonical_id.is_empty():
		return
	var text: String = _read_effective_bytes()
	if text.is_empty():
		return
	var queued: Dictionary = _checkpoint.call("queue_checkpoint", _uid, 1,
		text)
	if str(queued.get("status", "")) != "ok":
		_save_state = "error"
		_save_code = str(queued.get("code", "queue-failed"))
		save_changed.emit(save_snapshot())
		return
	_save_state = "queued"
	_save_code = ""
	save_changed.emit(save_snapshot())
	if _auto_flush:
		call_deferred("_flush_async", captured)


## One stable checkpoint landed locally. Queue it for upload; the flush
## runs deferred so gameplay never waits. Late or foreign callbacks — an
## old account's write, a remote install — queue nothing.
func _on_stable_checkpoint(info: Dictionary) -> void:
	if _closed or not _configured or _installing_remote:
		return
	if str(info.get("path", "")) != Journey.path:
		return
	if _canonical_id.is_empty():
		_save_state = "unregistered"
		_save_code = ""
		save_changed.emit(save_snapshot())
		return
	var queued: Dictionary = _checkpoint.call("queue_checkpoint", _uid, 1,
		str(info.get("text", "")))
	if str(queued.get("status", "")) != "ok":
		_save_state = "error"
		_save_code = str(queued.get("code", "queue-failed"))
		save_changed.emit(save_snapshot())
		return
	_save_state = "queued"
	_save_code = ""
	save_changed.emit(save_snapshot())
	if _auto_flush:
		call_deferred("_flush_async", _generation)


func _flush_async(captured: int) -> Dictionary:
	if _stale(captured):
		return _cancelled_stale()
	if not _configured or _canonical_id.is_empty():
		_save_state = "unregistered"
		_save_code = ""
		save_changed.emit(save_snapshot())
		return {"status": "unregistered", "code": "account-not-ready",
			"retryable": false}
	if _flush_locked():
		if bool(_checkpoint.call("has_pending")):
			return {"status": "queued", "code": "flush-already-running",
				"retryable": false}
		return {"status": "ok", "code": "nothing-pending"}
	var taken: Dictionary = _checkpoint.call("take_pending")
	if taken.is_empty():
		return {"status": "ok", "code": "nothing-pending"}
	_flush_seq += 1
	var ticket: int = _flush_seq
	_flush_owner = ticket
	var payload: String = str(taken.get("payload", ""))
	var payload_digest: String = payload.sha256_text()
	# The baseline rides with the taken work through every retry below and
	# is never silently rewritten mid-flight: only a success exit adopts a
	# new one, and adoption only ever confirms verified agreement.
	var base_revision: int = _baseline_revision
	var base_digest: String = _baseline_digest
	_save_state = "uploading"
	_save_code = ""
	save_changed.emit(save_snapshot())
	var attempt: int = 0
	while attempt < MAX_FLUSH_ATTEMPTS:
		attempt += 1
		if _stale(captured):
			_release_flush(ticket)
			return _cancelled_stale()
		var remote: Dictionary = await _checkpoint.call(
			"load_remote", _transport, _uid)
		if _stale(captured):
			_release_flush(ticket)
			return _cancelled_stale()
		var last: Dictionary = {}
		if str(remote.get("status", "")) == "ok":
			_known_remote_revision = int(remote.get("revision", 0))
			var verdict: Dictionary = _compare_remote(
				remote, payload, payload_digest,
				base_revision, base_digest)
			var action: String = str(verdict.get("action", "conflict"))
			if action == "conflict":
				_release_flush(ticket)
				return _open_flush_conflict(payload, remote,
					str(verdict.get("reason", "remote-advanced")))
			if action == "adopt":
				_adopt_baseline(int(remote.get("revision", 0)),
					str(remote.get("payload", "")))
				base_revision = _baseline_revision
				base_digest = _baseline_digest
			var already: bool = action == "synced"
			if action == "adopt" and payload_digest == base_digest:
				already = true
			if already:
				_release_flush(ticket)
				return _finish_already_synced(
					int(remote.get("revision", 0)))
			last = await _checkpoint.call("save_revision", _transport,
				_uid, int(remote.get("revision", 0)),
				str(remote.get("update_time", "")), payload)
		elif str(remote.get("code", "")) == "not-found":
			if base_revision >= 1 or _acked_revision > 0:
				_release_flush(ticket)
				return _open_missing_remote_conflict(payload)
			_known_remote_revision = 0
			last = await _checkpoint.call("save_revision", _transport,
				_uid, 0, "", payload)
		else:
			last = remote
		if _stale(captured):
			# Dropped, never re-queued: the taken payload belongs to the
			# old account and must not upload under the new one. Its
			# local file keeps it.
			_release_flush(ticket)
			return _cancelled_stale()
		var status: String = str(last.get("status", "failure"))
		if status == "ok":
			_adopt_baseline(int(last.get("revision", _acked_revision)),
				payload)
			_release_flush(ticket)
			if bool(_checkpoint.call("has_pending")):
				_save_state = "queued"
				_save_code = ""
				save_changed.emit(save_snapshot())
				if _auto_flush:
					call_deferred("_flush_async", captured)
			else:
				_save_state = "acked"
				_save_code = ""
				_conflict = {}
				save_changed.emit(save_snapshot())
			return {"status": "ok", "revision": _acked_revision}
		if status == "conflict":
			_release_flush(ticket)
			return _store_save_conflict(payload, last)
		if status == "offline" or status == "unconfigured" \
				or status == "cancelled":
			_requeue_taken(taken)
			_release_flush(ticket)
			_save_state = "offline" if status == "offline" else "error"
			_save_code = str(last.get("code", status))
			save_changed.emit(save_snapshot())
			return last
		if bool(last.get("retryable", false)) \
				and attempt < MAX_FLUSH_ATTEMPTS:
			continue
		_requeue_taken(taken)
		_release_flush(ticket)
		_save_state = "error"
		_save_code = str(last.get("code", "upload-failed"))
		save_changed.emit(save_snapshot())
		return last
	_requeue_taken(taken)
	_release_flush(ticket)
	return {"status": "failure", "code": "upload-failed",
		"retryable": true}


## Return a taken payload to the queue after a failed or stale flush. A
## newer payload already queued supersedes it: checkpoints carry full
## state, so re-queueing the older one would clobber the newer.
func _requeue_taken(taken: Dictionary) -> void:
	if taken.is_empty() or _closed or not _configured:
		return
	if bool(_checkpoint.call("has_pending")):
		return
	_checkpoint.call("queue_checkpoint", _uid, 1,
		str(taken.get("payload", "")))


func _has_baseline() -> bool:
	return _baseline_revision >= 1 and not _baseline_digest.is_empty()


## Record verified agreement: both sides hold `payload` at `revision`.
## The only writer of the baseline, called solely on commit success,
## remote acceptance, restore, and verified-adoption exits.
func _adopt_baseline(revision: int, payload: String) -> void:
	_baseline_revision = revision
	_baseline_digest = payload.sha256_text()
	_acked_revision = maxi(_acked_revision, revision)
	_known_remote_revision = maxi(_known_remote_revision, revision)
	_write_revision_file()


## Compare a loaded remote against the captured sync baseline before any
## commit. Compare-and-swap only guards changes after the guard read; this
## guards progress from another device made before it. Actions: `proceed`
## (remote still at baseline, our payload is new), `adopt` (no baseline
## yet but the remote provably matches our last ack or our own bytes —
## adopt it, then re-check), `synced` (all three agree, nothing to send),
## `conflict` with a reason (anything else — the player chooses).
func _compare_remote(remote: Dictionary, payload: String,
		payload_digest: String, base_revision: int,
		base_digest: String) -> Dictionary:
	var remote_payload: String = str(remote.get("payload", ""))
	var remote_revision: int = int(remote.get("revision", 0))
	if base_revision >= 1 and not base_digest.is_empty():
		if remote_revision == base_revision \
				and remote_payload.sha256_text() == base_digest:
			if payload_digest == base_digest:
				return {"action": "synced"}
			return {"action": "proceed"}
		if remote_revision != base_revision:
			return {"action": "conflict", "reason": "remote-advanced"}
		return {"action": "conflict", "reason": "remote-rewritten"}
	if _acked_revision > 0:
		if remote_revision == _acked_revision:
			return {"action": "adopt"}
		return {"action": "conflict", "reason": "remote-advanced"}
	if remote_payload == payload:
		return {"action": "adopt"}
	return {"action": "conflict", "reason": "foreign-progress"}


## The taken payload already matches the agreed state: drop it without a
## commit and report acknowledged. Never invents a revision.
func _finish_already_synced(remote_revision: int) -> Dictionary:
	_acked_revision = maxi(_acked_revision, remote_revision)
	_known_remote_revision = maxi(_known_remote_revision, remote_revision)
	_write_revision_file()
	_save_state = "acked"
	_save_code = ""
	save_changed.emit(save_snapshot())
	return {"status": "ok", "code": "already-in-sync",
		"revision": _acked_revision}


## A remote that differs from the baseline is a conflict before any
## commit. Both versions stay preserved: the taken local payload in the
## conflict record, the remote in the conflict record and on the server.
func _open_flush_conflict(payload: String, remote: Dictionary,
		reason: String) -> Dictionary:
	var remote_revision: int = int(remote.get("revision", 0))
	return _store_conflict(
		CloudSchema.summarize_payload(payload, remote_revision + 1),
		(remote.get("summary", {}) as Dictionary).duplicate(true),
		remote_revision + 1, remote_revision, remote, payload, reason)


## A missing remote document with acknowledged history is a meaningful
## state, not a silent re-create. The local choice below recreates it
## explicitly; the remote choice has nothing to accept and is refused.
func _open_missing_remote_conflict(payload: String) -> Dictionary:
	var remote_summary: Dictionary = {
		"revision": 0,
		"bytes": 0,
		"digest": "".sha256_text(),
		"gate": "remote-not-found",
	}
	return _store_conflict(
		CloudSchema.summarize_payload(payload, 1), remote_summary, 1, 0,
		{"status": "failure", "code": "not-found"}, payload,
		"remote-missing")


## A compare-and-swap miss on the commit itself: the remote advanced
## between our guard read and our write. Same explicit shape.
func _store_save_conflict(payload: String, last: Dictionary) -> Dictionary:
	return _store_conflict(
		(last.get("local_summary", {}) as Dictionary).duplicate(true),
		(last.get("remote_summary", {}) as Dictionary).duplicate(true),
		int(last.get("local_revision", 0)),
		int(last.get("remote_revision", 0)),
		(last.get("remote", {}) as Dictionary).duplicate(true),
		payload, "revision-conflict")


func _store_conflict(local_summary: Dictionary, remote_summary: Dictionary,
		local_revision: int, remote_revision: int, remote: Dictionary,
		payload: String, code: String) -> Dictionary:
	_conflict = {
		"local_summary": local_summary,
		"remote_summary": remote_summary,
		"local_revision": local_revision,
		"remote_revision": remote_revision,
		"baseline_revision": _baseline_revision,
		"remote": remote,
		"payload": payload,
	}
	_known_remote_revision = maxi(_known_remote_revision, remote_revision)
	_write_revision_file()
	_save_state = "conflict"
	_save_code = code
	save_changed.emit(save_snapshot())
	conflict_found.emit(conflict_snapshot())
	return {"status": "conflict", "code": code, "retryable": false,
		"local_revision": local_revision,
		"remote_revision": remote_revision,
		"baseline_revision": _baseline_revision,
		"local_summary": local_summary.duplicate(true),
		"remote_summary": remote_summary.duplicate(true)}


func _resolve_keep_local(captured: int) -> Dictionary:
	var pending: Dictionary = _checkpoint.call("peek_pending")
	var payload: String = str(pending.get("payload", "")) \
		if not pending.is_empty() else str(_conflict.get("payload", ""))
	if payload.is_empty():
		return {"status": "failure", "code": "no-local-payload",
			"retryable": false}
	# Read the remote fresh before overwriting it and preserve those exact
	# bytes first: the dialog copy may already be stale, and preservation
	# must precede the destructive commit.
	var fresh_first: Dictionary = await _checkpoint.call(
		"load_remote", _transport, _uid)
	if _stale(captured):
		return _cancelled_stale()
	var first_status: String = str(fresh_first.get("status", "failure"))
	if first_status != "ok" \
			and str(fresh_first.get("code", "")) != "not-found":
		_save_state = "conflict"
		_save_code = str(fresh_first.get("code", "local-choice-failed"))
		save_changed.emit(save_snapshot())
		return fresh_first
	var first_text: String = str(fresh_first.get("payload", ""))
	if first_status == "ok" and not _write_rejected("remote", first_text):
		return {"status": "failure", "code": "recovery-save-failed",
			"retryable": false}
	if first_status == "ok" and _upload_resurrects(payload, first_text):
		# The fresh remote sealed this journey's defeat after the dialog
		# opened (or the dialog predates the death). Rebasing our stale
		# alive bytes over it would resurrect the run on the server, so
		# the local choice is refused and the conflict stays open.
		_save_state = "conflict"
		_save_code = "defeat-kept"
		save_changed.emit(save_snapshot())
		return {"status": "failure", "code": "defeat-kept",
			"retryable": false}
	if first_status == "ok" \
			and _upload_commits_stale_death(payload, first_text):
		# The dialog's ended candidate predates the acknowledged revive
		# the fresh remote already holds. Committing the stale death over
		# the newer alive seal would resurrect it remotely, so the local
		# choice retires and the conflict stays open for the live side.
		_save_state = "conflict"
		_save_code = "stale-ended-retired"
		save_changed.emit(save_snapshot())
		return {"status": "failure", "code": "stale-ended-retired",
			"retryable": false}
	var result: Dictionary = await _checkpoint.call(
		"choose_local", _transport, _uid, payload)
	if _stale(captured):
		return _cancelled_stale()
	if str(result.get("status", "")) != "ok":
		_save_state = "conflict"
		_save_code = str(result.get("code", "local-choice-failed"))
		save_changed.emit(save_snapshot())
		return result
	# The remote may have advanced again between the dialog, the first
	# read, and the rebasing commit. The commit result carries the bytes
	# it actually overwrote: preserve those exactly when they differ.
	var overwritten: String = str((result.get("remote", {})
		as Dictionary).get("payload", ""))
	var remote_preserved: bool = true
	var remote_exact: bool = true
	var preserved_revision: int = -1
	if first_status == "ok":
		preserved_revision = int(fresh_first.get("revision", 0))
	if not overwritten.is_empty() and overwritten != first_text:
		preserved_revision = int((result.get("remote", {})
			as Dictionary).get("revision", preserved_revision))
		if _write_rejected("remote", overwritten):
			remote_exact = true
		elif first_status == "ok":
			remote_exact = false
			preserved_revision = int(fresh_first.get("revision", 0))
		else:
			remote_exact = false
			remote_preserved = false
	_adopt_baseline(int(result.get("revision", _acked_revision)), payload)
	_conflict = {}
	_save_state = "acked"
	_save_code = ""
	save_changed.emit(save_snapshot())
	return {"status": "ok", "code": "local-kept",
		"revision": _acked_revision,
		"remote_revision": preserved_revision,
		"remote_preserved": remote_preserved,
		"remote_exact": remote_exact}


func _resolve_keep_remote(captured: int) -> Dictionary:
	var remote: Dictionary = (_conflict.get("remote", {}) as Dictionary
		).duplicate(true)
	if str(remote.get("status", "")) != "ok":
		return {"status": "failure", "code": "no-remote-checkpoint",
			"retryable": false}
	var remote_text: String = str(remote.get("payload", ""))
	var checked: Dictionary = _validate_remote_payload(remote_text)
	if not bool(checked.get("ok", false)):
		return {"status": "failure",
			"code": str(checked.get("error", "invalid-remote-payload")),
			"retryable": false}
	if _download_resurrects(_read_effective_bytes(), remote_text):
		# The local file sealed this journey's defeat after the dialog
		# opened (or the dialog predates the death). Installing the stale
		# alive download would resume the sealed run, so the remote choice
		# is refused and the conflict stays open.
		_save_state = "conflict"
		_save_code = "defeat-kept"
		save_changed.emit(save_snapshot())
		return {"status": "failure", "code": "defeat-kept",
			"retryable": false}
	if _download_installs_stale_death(_read_effective_bytes(), remote_text):
		# The download's ended candidate predates our newer alive seal of
		# the same journey. Installing the stale death over the live seal
		# would end a run that already revived past it, so the remote
		# choice retires and the conflict stays open for the live side.
		_save_state = "conflict"
		_save_code = "stale-ended-retired"
		save_changed.emit(save_snapshot())
		return {"status": "failure", "code": "stale-ended-retired",
			"retryable": false}
	var prepared: Dictionary = _prepare_install(
		checked.get("data", {}) as Dictionary, remote_text)
	if not bool(prepared.get("ok", false)):
		return {"status": "failure",
			"code": str(prepared.get("error", "invalid-remote-payload")),
			"retryable": false}
	var install_text: String = str(prepared.get("install_text", ""))
	var local_text: String = _read_local_main_bytes()
	if local_text.is_empty():
		local_text = str(_conflict.get("payload", ""))
	if not local_text.is_empty() and not _write_rejected(
			"local", local_text):
		return {"status": "failure", "code": "recovery-save-failed",
			"retryable": false}
	if bool(prepared.get("remapped", false)) \
			and not _write_rejected("remote", remote_text):
		return {"status": "failure", "code": "recovery-save-failed",
			"retryable": false}
	_installing_remote = true
	var installed: Error = Journey.write_checkpoint_text(install_text)
	_installing_remote = false
	if _stale(captured):
		return _cancelled_stale()
	if installed != OK:
		_save_state = "conflict"
		_save_code = "remote-install-failed"
		save_changed.emit(save_snapshot())
		return {"status": "failure", "code": "remote-install-failed",
			"retryable": false}
	var floored: Dictionary = _floor_from_checkpoint(
		prepared.get("install_data", {}) as Dictionary, "remote-choice")
	if str(floored.get("code", "")) == "floor-save-failed":
		_save_state = "conflict"
		_save_code = "floor-save-failed"
		save_changed.emit(save_snapshot())
		return {"status": "failure", "code": "floor-save-failed",
			"retryable": true}
	var accepted: Dictionary = await _checkpoint.call(
		"choose_remote", remote)
	if _stale(captured):
		return _cancelled_stale()
	if str(accepted.get("status", "")) == "failure":
		_save_state = "conflict"
		_save_code = str(accepted.get("code", "remote-choice-failed"))
		save_changed.emit(save_snapshot())
		return accepted
	_adopt_baseline(int(remote.get("revision", 0)), remote_text)
	_conflict = {}
	_save_state = "acked"
	_save_code = ""
	save_changed.emit(save_snapshot())
	return {"status": "ok", "code": "remote-kept",
		"revision": _known_remote_revision,
		"remapped": bool(prepared.get("remapped", false))}


## A download that differs from the local journey is a conflict, not an
## install. The local side carries the active file's bytes so an explicit
## local choice can still rebase them afterwards.
func _open_download_conflict(local_text: String, remote: Dictionary) -> void:
	var remote_text: String = str(remote.get("payload", ""))
	_conflict = {
		"local_summary": CloudSchema.summarize_payload(
			local_text, _acked_revision),
		"remote_summary": (remote.get("summary", {}) as Dictionary
			).duplicate(true),
		"local_revision": _acked_revision,
		"remote_revision": int(remote.get("revision", 0)),
		"baseline_revision": _baseline_revision,
		"remote": remote.duplicate(true),
		"payload": local_text,
	}
	_known_remote_revision = maxi(_known_remote_revision,
		int(remote.get("revision", 0)))
	_save_state = "conflict"
	_save_code = "restore-differs"
	save_changed.emit(save_snapshot())
	conflict_found.emit(conflict_snapshot())


## Complete validation of a downloaded payload before anything installs it:
## both size bounds, silent JSON parse, ledger-key refusal, and the strict
## Journey validator. Returns `{ok, data}` or `{ok: false, error}`.
func _validate_remote_payload(text: String) -> Dictionary:
	if text.is_empty():
		return {"ok": false, "error": "empty-payload"}
	if text.to_utf8_buffer().size() > CloudSchema.MAX_CHECKPOINT_BYTES:
		return {"ok": false, "error": "payload-too-large"}
	if text.to_utf8_buffer().size() > Journey.MAX_FILE_BYTES:
		return {"ok": false, "error": "payload-too-large"}
	var decoded: Dictionary = CloudSchema.parse_json_value(text)
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "payload-not-json-object"}
	if CloudSchema.checkpoint_has_forbidden_ledger_keys(text):
		return {"ok": false, "error": "ledger-keys-rejected"}
	var data: Dictionary = decoded.get("value")
	if not Journey.validate(data):
		return {"ok": false, "error": "invalid-checkpoint"}
	return {"ok": true, "data": data}


## Prepare validated remote bytes for install. Imported integer journey ids
## are remapped into this device's receipt namespace (see
## `map_remote_journey_id`) because device-local sequences collide across
## devices; strings install byte-identical. The remap rewrites only the
## journey id span in the original bytes — never a re-serialization, which
## would corrupt every integer into a float — then re-validates, re-bounds,
## and verifies every other field is untouched. Returns `{ok, install_text,
## install_data, remapped}` or `{ok: false, error}`.
func _prepare_install(data: Dictionary, remote_text: String) -> Dictionary:
	# Parsed JSON numbers arrive as floats, so whole floats count as
	# integers here exactly like the Journey validator counts them.
	var journey: Variant = data.get("journey_id", "")
	var journey_int: int = -1
	if journey is int:
		journey_int = int(journey)
	elif journey is float and (journey as float) == floor(journey as float) \
			and journey >= 1.0 \
			and journey <= float(Journey.JSON_INT_LIMIT):
		journey_int = int(journey)
	if journey_int < 0:
		return {"ok": true, "install_text": remote_text,
			"install_data": data, "remapped": false}
	var mapped: String = str(map_remote_journey_id(_uid, journey_int))
	var install_text: String = _remap_journey_id_bytes(remote_text, mapped)
	if install_text.is_empty():
		return {"ok": false, "error": "remap-rejected"}
	if install_text.to_utf8_buffer().size() > Journey.MAX_FILE_BYTES \
			or install_text.to_utf8_buffer().size() \
				> CloudSchema.MAX_CHECKPOINT_BYTES:
		return {"ok": false, "error": "payload-too-large"}
	var decoded: Dictionary = CloudSchema.parse_json_value(install_text)
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "remap-rejected"}
	var install_data: Dictionary = decoded.get("value")
	if not Journey.validate(install_data) \
			or str(install_data.get("journey_id", "")) != mapped \
			or not _install_preserves_fields(data, install_data):
		return {"ok": false, "error": "remap-rejected"}
	return {"ok": true, "install_text": install_text,
		"install_data": install_data, "remapped": true}


## Rewrite only the `"journey_id":<number>` span of validated remote bytes
## with the mapped string id. Empty when the span is missing or malformed,
## in which case the install is refused rather than guessed.
func _remap_journey_id_bytes(remote_text: String, mapped: String) -> String:
	if mapped.is_empty():
		return ""
	for code in mapped.to_utf8_buffer():
		var safe: bool = (code >= 48 and code <= 57) \
			or (code >= 65 and code <= 90) \
			or (code >= 97 and code <= 122)
		if not safe:
			return ""
	var key_at: int = remote_text.find("\"journey_id\"")
	if key_at < 0:
		return ""
	var colon_at: int = remote_text.find(":", key_at + 12)
	if colon_at < 0:
		return ""
	var span: int = colon_at + 1
	while span < remote_text.length():
		var gap: int = remote_text.unicode_at(span)
		if gap != 32 and gap != 9 and gap != 10 and gap != 13:
			break
		span += 1
	var token_start: int = span
	while span < remote_text.length():
		var digit: int = remote_text.unicode_at(span)
		if digit != 46 and (digit < 48 or digit > 57):
			break
		span += 1
	if span <= token_start:
		return ""
	return remote_text.substr(0, token_start) + "\"" + mapped + "\"" \
		+ remote_text.substr(span)


## True when the remapped checkpoint equals the validated remote in every
## field except the journey id.
func _install_preserves_fields(before: Dictionary,
		after: Dictionary) -> bool:
	if before.size() != after.size():
		return false
	for key in before.keys():
		if str(key) == "journey_id":
			continue
		if not after.has(key) or after[key] != before[key]:
			return false
	return true


## Actual Hall row for one validated checkpoint: the saved hero path, the
## score the result screen would count from its counters, and closed
## cycles. No estimates, no placeholders.
func _derive_hall_row(checkpoint: Dictionary) -> Dictionary:
	var score := Score.new()
	score.cycles = maxi(int(checkpoint.get("cycle", 1)) - 1, 0)
	score.beacons = int(checkpoint.get("lit_count", 0))
	score.survived = float(checkpoint.get("survived", 0.0))
	score.level = int(checkpoint.get("level", 1))
	score.kills = int(checkpoint.get("kill_score", 0))
	return {
		"hero": str(checkpoint.get("hero_path", "")),
		"score": score.total(),
		"cycles": score.cycles,
	}


func _read_local_main_bytes() -> String:
	if _partition_key.is_empty():
		return ""
	var reader: FileAccess = FileAccess.open(Journey.path, FileAccess.READ)
	if reader == null:
		return ""
	var length: int = int(reader.get_length())
	if length > Journey.MAX_FILE_BYTES:
		reader.close()
		return ""
	var text: String = reader.get_as_text()
	reader.close()
	return text


## Effective local checkpoint bytes: the main file when it parses and
## validates, else the backup when it does, else empty. Mirrors
## `Journey.read_checkpoint` without re-serializing, so queued bytes stay
## identical to what a seal wrote.
func _read_effective_bytes() -> String:
	if _partition_key.is_empty():
		return ""
	for candidate in [Journey.path, Journey.backup_path]:
		var reader: FileAccess = FileAccess.open(candidate, FileAccess.READ)
		if reader == null:
			continue
		if int(reader.get_length()) > Journey.MAX_FILE_BYTES:
			reader.close()
			continue
		var text: String = reader.get_as_text()
		reader.close()
		if text.is_empty():
			continue
		var decoded: Dictionary = CloudSchema.parse_json_value(text)
		if bool(decoded.get("ok", false)) \
				and typeof(decoded.get("value")) == TYPE_DICTIONARY \
				and Journey.validate(decoded.get("value")):
			return text
	return ""


## Preserve one rejected payload for recovery, byte for byte. Oversized or
## unwritable payloads refuse instead of half-writing.
func _write_rejected(side: String, text: String) -> bool:
	if _partition_key.is_empty() or text.is_empty() \
			or text.to_utf8_buffer().size() > Journey.MAX_FILE_BYTES:
		return false
	var target: String = Journey.account_rejected_path(_partition_key, side)
	var writer: FileAccess = FileAccess.open(target + ".tmp", FileAccess.WRITE)
	if writer == null:
		return false
	writer.store_string(text)
	writer.flush()
	var write_error: Error = writer.get_error()
	writer.close()
	if write_error != OK:
		_discard_path(target + ".tmp")
		return false
	var staged: FileAccess = FileAccess.open(target + ".tmp", FileAccess.READ)
	if staged == null:
		_discard_path(target + ".tmp")
		return false
	var verify: String = staged.get_as_text()
	staged.close()
	if verify != text:
		_discard_path(target + ".tmp")
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(target + ".tmp"),
			ProjectSettings.globalize_path(target)) != OK:
		_discard_path(target + ".tmp")
		return false
	return true


func _discard_path(candidate: String) -> void:
	if FileAccess.file_exists(candidate):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _load_revision_file() -> void:
	_acked_revision = 0
	_known_remote_revision = 0
	_baseline_revision = -1
	_baseline_digest = ""
	_revision_error = ""
	if _partition_key.is_empty():
		return
	var candidate: String = Journey.account_revision_path(_partition_key)
	if not FileAccess.file_exists(candidate):
		return
	var reader: FileAccess = FileAccess.open(candidate, FileAccess.READ)
	if reader == null:
		return
	var decoded: Dictionary = CloudSchema.parse_json_value(
		reader.get_as_text())
	reader.close()
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_DICTIONARY:
		return
	var envelope: Dictionary = decoded.get("value")
	var version: int = int(envelope.get("version", 0))
	if version != REVISION_FILE_VERSION and version != 1:
		return
	_acked_revision = maxi(int(envelope.get("acked_revision", 0)), 0)
	_known_remote_revision = maxi(
		int(envelope.get("known_remote_revision", 0)), 0)
	# Version 1 files predate the baseline: their acknowledged revision
	# still guards (a remote at any other revision conflicts), and the
	# first verified agreement adopts fresh baseline bytes.
	if version == REVISION_FILE_VERSION:
		_baseline_revision = int(envelope.get("baseline_revision", -1))
		_baseline_digest = str(envelope.get("baseline_digest", ""))
		if _baseline_revision < 1 or _baseline_digest.is_empty():
			_baseline_revision = -1
			_baseline_digest = ""


## Persist the acknowledged and known-remote revisions beside the Journey
## slot. Best effort: memory stays authoritative and a failure is recorded
## on the save snapshot instead of failing the upload it follows.
func _write_revision_file() -> void:
	_revision_error = ""
	if _partition_key.is_empty():
		return
	var envelope: Dictionary = {
		"version": REVISION_FILE_VERSION,
		"public_id": _partition_key,
		"acked_revision": _acked_revision,
		"known_remote_revision": _known_remote_revision,
		"baseline_revision": _baseline_revision,
		"baseline_digest": _baseline_digest,
		"saved_at": CloudSchema.now_rfc3339(),
	}
	var target: String = Journey.account_revision_path(_partition_key)
	var writer: FileAccess = FileAccess.open(target + ".tmp", FileAccess.WRITE)
	if writer == null:
		_revision_error = "revision-save-failed"
		return
	writer.store_string(JSON.stringify(envelope))
	writer.flush()
	var write_error: Error = writer.get_error()
	writer.close()
	if write_error != OK:
		_discard_path(target + ".tmp")
		_revision_error = "revision-save-failed"
		return
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(target + ".tmp"),
			ProjectSettings.globalize_path(target)) != OK:
		_discard_path(target + ".tmp")
		_revision_error = "revision-save-failed"


## Reconcile the active journey's receipt from its checkpoint echo without
## granting. Runs after configuring and after learning the canonical id.
## Locally-issued ids with no record are left strictly alone so a failed
## settlement's retry still pays exactly once (`local-pending`); only
## unknown ids are floored with zero granted. Already-recorded journeys
## read back as duplicates with no save. Remote installs floor separately
## through `_floor_from_checkpoint`, never through this path.
func _reconcile_active_receipt_floor() -> void:
	if _vault == null:
		return
	var checkpoint: Dictionary = Journey.read_checkpoint()
	if checkpoint.is_empty():
		_floor_code = "no-checkpoint"
		return
	var outcome: Dictionary = _vault.call("reconcile_local_receipt",
		checkpoint.get("journey_id", ""),
		int(checkpoint.get("checkpoint_id", 0)),
		int(checkpoint.get("shards_awarded", 0)))
	_floor_code = str(outcome.get("code", "floor-retired"))


## Floor one checkpoint's cumulative receipt. Returns `{code}` where code
## is `floored`, `duplicate`, `floor-save-failed`, or `floor-retired`.
func _floor_from_checkpoint(checkpoint: Dictionary, _why: String) -> Dictionary:
	var outcome: Dictionary = _vault.call("initialize_remote_receipt_floor",
		checkpoint.get("journey_id", ""),
		int(checkpoint.get("checkpoint_id", 0)),
		int(checkpoint.get("shards_awarded", 0)))
	var status: int = int(outcome.get("status", -1))
	if status == VaultScript.JourneyReceipt.FLOORED:
		_floor_code = "floored"
	elif status == VaultScript.JourneyReceipt.DUPLICATE:
		_floor_code = "duplicate"
	elif status == VaultScript.JourneyReceipt.SAVE_FAILED:
		_floor_code = "floor-save-failed"
	else:
		_floor_code = "floor-retired"
	return {"code": _floor_code,
		"settled_target": int(outcome.get("settled_target", 0))}
