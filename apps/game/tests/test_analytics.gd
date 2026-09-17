extends SceneTree

## Check privacy-minimization, consent, and offline-queue contracts with no network.

const ANALYTICS_SCRIPT: Script = preload("res://scripts/analytics/analytics.gd")
const FIREBASE_CONFIG_SCRIPT: Script = preload("res://scripts/net/firebase_config.gd")

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	_test_consent_and_configuration()
	_test_activation_and_retention()
	_test_allowlists_and_firestore_body()
	_test_deterministic_retry_id()
	_test_bounded_queue()
	_test_priority_queue()
	_test_runtime_queue_expiry()
	_test_loaded_queue_invariants()
	_test_response_handling()
	_test_revocation()

	if _failed > 0:
		printerr("analytics test failed — ", _failed, "/", _checked, " case(s)")
		quit(1)
		return
	print("analytics test passed — ", _checked, " case(s)")
	quit(0)


func _new_analytics(consent: bool = true, configured: bool = true) -> Node:
	var analytics: Node = ANALYTICS_SCRIPT.new() as Node
	analytics.call("_test_configure", consent, configured, false)
	analytics.call("_test_set_now", 1787673600) # 2026-08-26T00:00:00Z
	return analytics


func _test_consent_and_configuration() -> void:
	var public_ingestion: Dictionary = {
		"analytics_enabled": true,
		"analytics_ingestion_hardened": false,
		"web_api_key": "public-mobile-key",
	}
	_expect_false(
		FIREBASE_CONFIG_SCRIPT.configured_for_analytics(public_ingestion),
		"publishable key plus enabled alone does not turn on unprotected collection")
	public_ingestion["analytics_ingestion_hardened"] = true
	_expect_true(
		FIREBASE_CONFIG_SCRIPT.configured_for_analytics(public_ingestion),
		"only settings that also declare remote-collection protection are valid")

	var denied: Node = _new_analytics(false, true)
	_expect_true(denied.call("configured"), "confirms valid ship settings regardless of consent")
	_expect_false(denied.call("enabled"), "analytics inactive before consent")
	_expect_false(denied.call("track", "app_opened"), "no events collected before consent")
	_expect_equal((denied.call("_test_pending_items") as Array).size(), 0,
		"does not even create a local queue before consent")
	denied.free()

	var missing_config: Node = _new_analytics(true, false)
	_expect_false(missing_config.call("configured"), "unconfigured without a key or an enabled setting")
	_expect_false(missing_config.call("enabled"), "inactive without explicit settings and a key")
	_expect_false(missing_config.call("track", "app_opened"), "no events collected when there are no settings")
	missing_config.free()


func _test_activation_and_retention() -> void:
	var cohort_start: int = 1787673600
	var first: Node = _new_analytics()
	first.call("_test_set_now", cohort_start)
	_expect_true(first.call("activate"), "cold launch activates on the first valid consent")
	_expect_equal(_pending_event_names(first), ["analytics_activated", "app_opened"],
		"first consent waits for both activation and app open")
	var first_cohort: Dictionary = first.call("_test_cohort") as Dictionary
	_expect_equal(int(first_cohort.get("unix", 0)), cohort_start,
		"local cohort time is confirmed only after activation save")
	_expect_equal(str(first_cohort.get("version", "")), "2.1.0",
		"cohort stores the current app version")
	_expect_false(first.call("activate"), "blocks duplicate cold launch in one app session")
	_expect_equal(_pending_event_names(first).size(), 2, "duplicate activate does not grow events")
	first.free()

	var day_one: Node = _new_analytics()
	day_one.call("_test_set_now", cohort_start + 24 * 60 * 60)
	day_one.call("_test_set_cohort", cohort_start, "2.1.0", 0)
	_expect_true(day_one.call("activate"), "records D1 cold launch")
	_expect_equal(_pending_event_names(day_one), ["app_opened", "retention_checkpoint"],
		"an existing cohort records only app open and D1 without activation")
	var day_one_event: Dictionary = (
		(day_one.call("_test_pending_items") as Array)[1] as Dictionary).get(
			"event", {}) as Dictionary
	_expect_equal((day_one_event.get("properties", {}) as Dictionary).get("day"), 1,
		"D1 checkpoint value")
	_expect_equal(int((day_one.call("_test_cohort") as Dictionary).get("mask", 0)), 1,
		"sets the local bit after D1 success")
	day_one.free()

	var calendar_day_one: Node = _new_analytics()
	calendar_day_one.call("_test_set_now", cohort_start + 32 * 60 * 60)
	calendar_day_one.call("_test_set_cohort", cohort_start + 23 * 60 * 60,
		"2.1.0", 0)
	_expect_true(calendar_day_one.call("activate"), "records next-date D1 even 24h earlier")
	_expect_equal(_pending_event_names(calendar_day_one), [
		"app_opened", "retention_checkpoint"],
		"D1 is recorded on the UTC calendar-date boundary")
	calendar_day_one.free()

	var day_seven: Node = _new_analytics()
	day_seven.call("_test_set_now", cohort_start + 7 * 24 * 60 * 60)
	day_seven.call("_test_set_cohort", cohort_start, "2.1.0", 1)
	_expect_true(day_seven.call("activate"), "records D7 cold launch")
	_expect_equal(_pending_event_names(day_seven), ["app_opened", "retention_checkpoint"],
		"skips an already-sent D1 and records only D7")
	_expect_equal(int((day_seven.call("_test_cohort") as Dictionary).get("mask", 0)), 3,
		"sets cumulative bits after D7 success")
	day_seven.free()

	var day_thirty: Node = _new_analytics()
	day_thirty.call("_test_set_now", cohort_start + 30 * 24 * 60 * 60)
	day_thirty.call("_test_set_cohort", cohort_start, "2.1.0", 3)
	_expect_true(day_thirty.call("activate"), "records D30 cold launch")
	_expect_equal(int((day_thirty.call("_test_cohort") as Dictionary).get("mask", 0)), 7,
		"bits sent exactly once through D30")
	day_thirty.free()

	var no_backfill: Node = _new_analytics()
	no_backfill.call("_test_set_now", cohort_start + 30 * 24 * 60 * 60)
	no_backfill.call("_test_set_cohort", cohort_start, "2.1.0", 0)
	_expect_true(no_backfill.call("activate"), "records first return after 30 days")
	_expect_equal(_pending_event_names(no_backfill), [
		"app_opened", "retention_checkpoint"],
		"first return after 30 days does not backfill D1/D7")
	var no_backfill_event: Dictionary = (
		(no_backfill.call("_test_pending_items") as Array)[1] as Dictionary).get(
		"event", {}) as Dictionary
	_expect_equal(
		(no_backfill_event.get("properties", {}) as Dictionary).get("day"), 30,
		"30-day return records only D30")
	_expect_equal(int((no_backfill.call("_test_cohort") as Dictionary).get("mask", 0)), 7,
		"past D1/D7 are also completed locally to block later backfill")
	no_backfill.free()

	var resumed: Node = _new_analytics()
	resumed.call("_test_set_now", cohort_start)
	_expect_true(resumed.call("activate"), "records first-run on a foreground return")
	resumed.call("_test_set_now", cohort_start + 24 * 60 * 60)
	_expect_true(resumed.call("_record_foreground"), "records next-day return on a still-alive mobile process")
	_expect_equal(_pending_event_names(resumed), [
		"analytics_activated", "app_opened", "app_opened", "retention_checkpoint"],
		"resume also leaves a new app open and D1")
	var resumed_items: Array = resumed.call("_test_pending_items") as Array
	var cold_open: Dictionary = (resumed_items[1] as Dictionary).get(
		"event", {}) as Dictionary
	var foreground_open: Dictionary = (resumed_items[2] as Dictionary).get(
		"event", {}) as Dictionary
	_expect_equal((cold_open.get("properties", {}) as Dictionary).get("open_kind"),
		"cold", "first app open is classified as a cold launch")
	_expect_equal((foreground_open.get("properties", {}) as Dictionary).get(
		"open_kind"), "resume", "mobile return is distinct from the start-conversion denominator")
	_expect_equal(str(foreground_open.get("session_id", "")),
		str(cold_open.get("session_id", "")),
		"cold run session survives returning from background")
	resumed.free()

	var failing: Node = _new_analytics()
	failing.call("_test_set_now", cohort_start)
	failing.call("_test_fail_next_persist")
	_expect_false(failing.call("activate"), "activation-queue save failure is propagated")
	_expect_equal((failing.call("_test_pending_items") as Array).size(), 0,
		"queue rolls back if activation save fails")
	_expect_equal(int((failing.call("_test_cohort") as Dictionary).get("unix", 0)), 0,
		"does not create a cohort if activation save fails")
	failing.free()

	var metadata_failure: Node = _new_analytics()
	metadata_failure.call("_test_set_now", cohort_start)
	metadata_failure.call("_test_fail_next_metadata_persist")
	_expect_false(metadata_failure.call("activate"), "cohort-settings save failure is propagated")
	_expect_equal(_pending_event_names(metadata_failure), [],
		"an unsaved activation is also removed from the upload queue")
	metadata_failure.free()

	var recovered_metadata_failure: Node = _new_analytics()
	recovered_metadata_failure.call("_test_set_now", cohort_start)
	_expect_true(recovered_metadata_failure.call("track", "analytics_activated", {
		"cohort_version": "2.1.0",
		"cohort_day": "2026-08-26",
	}), "prepares an unconfirmed activation collision state")
	var recovered_item: Dictionary = (
		(recovered_metadata_failure.call("_test_pending_items") as Array)[0]
		as Dictionary)
	recovered_metadata_failure.set("_in_flight_id", str(recovered_item.get("id", "")))
	recovered_metadata_failure.call("_test_fail_next_metadata_persist")
	_expect_false(recovered_metadata_failure.call("activate"),
		"recovery activation-metadata save failure is propagated")
	_expect_equal(str(recovered_metadata_failure.get("_in_flight_id")), "",
		"unsaved recovery activation send is also cancelled immediately")
	_expect_equal(_pending_event_names(recovered_metadata_failure), [],
		"unsaved recovery activation queue removed")
	recovered_metadata_failure.free()

	var checkpoint_failure: Node = _new_analytics()
	checkpoint_failure.call("_test_set_now", cohort_start + 24 * 60 * 60)
	checkpoint_failure.call("_test_set_cohort", cohort_start, "2.1.0", 0)
	checkpoint_failure.call("_test_fail_next_metadata_persist")
	_expect_true(checkpoint_failure.call("activate"), "app open is kept even if checkpoint save fails")
	_expect_equal(_pending_event_names(checkpoint_failure), ["app_opened"],
		"an unsaved D1 is removed from the upload queue")
	_expect_equal(int((checkpoint_failure.call(
		"_test_cohort") as Dictionary).get("mask", 0)), 0,
		"local bit stays unconfirmed if D1 save fails")
	checkpoint_failure.free()

	# Even if the app dies between queue save and Settings save, the next run first recovers the already atomically
	# saved lifecycle events so it does not create duplicate documents.
	var recovered_activation: Node = _new_analytics()
	recovered_activation.call("_test_set_now", cohort_start)
	recovered_activation.call("track", "analytics_activated", {
		"cohort_version": "2.1.0",
		"cohort_day": "2026-08-26",
	})
	_expect_true(recovered_activation.call("activate"), "recovers an unconfirmed activation queue")
	_expect_equal(_pending_event_names(recovered_activation).count(
		"analytics_activated"), 1, "blocks duplicate activation during recovery")
	recovered_activation.free()

	var recovered_retention: Node = _new_analytics()
	recovered_retention.call("_test_set_now", cohort_start + 24 * 60 * 60)
	recovered_retention.call("_test_set_cohort", cohort_start, "2.1.0", 0)
	recovered_retention.call("track", "retention_checkpoint", {
		"day": 1,
		"cohort_version": "2.1.0",
		"cohort_day": "2026-08-26",
	})
	_expect_true(recovered_retention.call("activate"), "recovers an unconfirmed D1 queue")
	_expect_equal(_pending_event_names(recovered_retention).count(
		"retention_checkpoint"), 1, "blocks duplicate D1 during recovery")
	_expect_equal(int((recovered_retention.call(
		"_test_cohort") as Dictionary).get("mask", 0)), 1,
		"confirms the local bit from the recovered D1 queue")
	recovered_retention.free()

	var recovered_retention_failure: Node = _new_analytics()
	recovered_retention_failure.call("_test_set_now", cohort_start + 24 * 60 * 60)
	recovered_retention_failure.call("_test_set_cohort", cohort_start, "2.1.0", 0)
	recovered_retention_failure.call("track", "retention_checkpoint", {
		"day": 1,
		"cohort_version": "2.1.0",
		"cohort_day": "2026-08-26",
	})
	recovered_retention_failure.call("_test_fail_next_metadata_persist")
	_expect_true(recovered_retention_failure.call("activate"),
		"app open is kept even if recovering the D1 bit save fails")
	_expect_equal(_pending_event_names(recovered_retention_failure), ["app_opened"],
		"a recovered D1 whose bit was not saved is removed from the upload queue")
	_expect_equal(int((recovered_retention_failure.call(
		"_test_cohort") as Dictionary).get("mask", 0)), 0,
		"recovered local bit stays unconfirmed if D1 save fails")
	recovered_retention_failure.free()


func _test_allowlists_and_firestore_body() -> void:
	var analytics: Node = _new_analytics()
	var run_id: String = str(analytics.call("new_run_id"))
	_expect_equal(run_id.length(), 32, "a run ID is a 128-bit temp token")
	_expect_true(analytics.call("track", "run_started", {
		"hero": "warden",
		"boon_tier": 2,
	}, run_id), "allowed start events collected")
	_expect_false(analytics.call("track", "made_up_event"), "rejects an arbitrary event name")
	_expect_false(analytics.call("track", "run_started", {
		"hero": "warden",
		"player_name": "moonlight",
	}, run_id), "rejects an arbitrary property that could hold a name")
	_expect_false(analytics.call("track", "boon_purchased", {
		"boon": "com.example.iap.bundle",
	}), "rejects an off-allowlist value that looks like a paid product")
	_expect_false(analytics.call("track", "retention_checkpoint", {"day": 2}),
		"rejects an undefined retention day")
	_expect_false(analytics.call("track", "analytics_activated"),
		"rejects activation with no cohort")
	_expect_false(analytics.call("track", "retention_checkpoint", {"day": 1}),
		"rejects a retention checkpoint with no cohort")
	_expect_false(analytics.call("track", "app_opened", {"open_kind": "background"}),
		"rejects an undefined app-open kind")
	_expect_true(analytics.call("track", "beacon_choice", {
		"beacon": 1,
		"cycle": 1,
		"terrain": "forest",
		"mode": "overcharge",
		"elapsed_ms": 90000,
	}, run_id), "accepts the overcharge choice separately from the ignite result")
	_expect_true(analytics.call("track", "relic_chosen", {
		"relic": "moon_ring",
		"family": "moon_dance",
		"source": "opening",
		"stack": 1,
		"cycle": 1,
		"elapsed_ms": 0,
	}, run_id), "accepts starting gear as resonance-analysis input")
	_expect_true(analytics.call("track", "overcharge_resolved", {
		"outcome": "defeat",
		"terrain": "forest",
		"cycle": 1,
		"duration_ms": 3000,
		"reward": "none",
	}, run_id), "accepts a defeat result during overcharge")
	_expect_true(analytics.call("track", "overcharge_resolved", {
		"outcome": "success",
		"terrain": "forest",
		"cycle": 1,
		"duration_ms": 6500,
		"reward": "growth",
	}, run_id), "accepts the growth reward of max-power overcharge")
	_expect_true(analytics.call("track", "cycle_decision", {
		"choice": "continue",
		"cycle": 1,
		"overcharges": 3,
		"elapsed_ms": 120000,
	}, run_id), "accepts keep-going after a guardian")
	_expect_false(analytics.call("track", "cycle_decision", {
		"choice": "purchase",
	}, run_id), "rejects a choice other than settle or continue")
	_expect_true(analytics.call("track", "run_ended", {"reason": "cashout"}, run_id),
		"accepts cycle-reward settlement as the end reason")

	var request: Dictionary = analytics.call("_test_request") as Dictionary
	var fields: Dictionary = (request.get("body", {}) as Dictionary).get(
		"fields", {}) as Dictionary
	_expect_true(str(request.get("id", "")).begins_with("e_"),
		"Firestore documents use a deterministic non-identifying ID")
	_expect_true(fields.has("session_id") and fields.has("run_id"),
		"includes session- and run-scoped temp IDs")
	for forbidden in ["nonce", "sequence", "player_name", "device_id", "iap_product_id"]:
		_expect_false(fields.has(forbidden), "no forbidden fields in the send body: " + forbidden)
	var property_fields: Dictionary = fields.get(
		"properties", {}).get("mapValue", {}).get("fields", {})
	_expect_equal(property_fields.keys().size(), 2, "only allowed properties are included in the Firestore body")
	analytics.free()


func _test_deterministic_retry_id() -> void:
	var analytics: Node = _new_analytics()
	var nonce: String = "a".repeat(32)
	_expect_true(analytics.call("_test_set_nonce", nonce), "accepts the test nonce format")
	_expect_true(analytics.call("track", "app_opened"), "retry sample events collected")
	var first: Dictionary = analytics.call("_test_request") as Dictionary
	var again: Dictionary = analytics.call("_test_request") as Dictionary
	_expect_equal(first.get("id"), again.get("id"), "retry reuses the same document ID")
	_expect_equal(first.get("id"), analytics.call("_test_document_id", nonce, 0),
		"document ID is decided from nonce and sequence")
	_expect_false(str(first.get("id", "")).contains(nonce),
		"does not expose the raw local nonce in the document ID")
	analytics.free()


func _test_bounded_queue() -> void:
	var analytics: Node = _new_analytics()
	analytics.call("_test_set_nonce", "b".repeat(32))
	var max_pending: int = 200
	for _index in range(max_pending + 5):
		_expect_true(analytics.call("track", "app_opened"), "saves a bounded-queue event")
	var pending: Array = analytics.call("_test_pending_items") as Array
	_expect_equal(pending.size(), max_pending, "queue cap 200")
	_expect_equal(int((pending[0] as Dictionary).get("sequence", -1)), 5,
		"drops oldest events first when over the cap")
	analytics.free()

	var overflow_source: Node = _new_analytics()
	var overflow_nonce: String = "2".repeat(32)
	overflow_source.call("_test_set_nonce", overflow_nonce)
	var overflow_run_id: String = str(overflow_source.call("new_run_id"))
	_expect_true(overflow_source.call("track", "run_started", {
		"hero": "warden",
		"boon_tier": 0,
	}, overflow_run_id), "prepares a valid run-start sample for over-cap recovery")
	var template_item: Dictionary = (
		(overflow_source.call("_test_pending_items") as Array)[0]
		as Dictionary).duplicate(true)
	var overflow_pending: Array = []
	for sequence in range(201):
		var overflow_item: Dictionary = template_item.duplicate(true)
		overflow_item["sequence"] = sequence
		overflow_item["id"] = overflow_source.call(
			"_test_document_id", overflow_nonce, sequence)
		overflow_pending.append(overflow_item)
	var overflow_state: Dictionary = {
		"schema": 1,
		"nonce": overflow_nonce,
		"next_sequence": 201,
		"pending": overflow_pending,
	}
	var overflow_restore: Node = _new_analytics()
	_expect_false(overflow_restore.call("_test_apply_state", overflow_state),
		"a recovery queue with only 201 protected run starts fail-closes instead of infinite trim")
	_expect_equal((overflow_restore.call("_test_pending_items") as Array).size(), 0,
		"does not partially apply a rejected over-cap recovery state")
	overflow_restore.free()
	overflow_source.free()


func _test_priority_queue() -> void:
	var analytics: Node = _new_analytics()
	analytics.call("_test_set_nonce", "c".repeat(32))
	_expect_true(analytics.call("activate"), "prepares a saturated-queue lifecycle sample")
	var run_id: String = str(analytics.call("new_run_id"))
	_expect_true(analytics.call("track", "run_started", {
		"hero": "warden",
		"boon_tier": 0,
	}, run_id), "prepares a saturated-queue run-start sample")
	var details_saved: bool = true
	for _index in range(197):
		details_saved = bool(analytics.call("track", "tutorial_step_completed", {
			"step": "move",
			"elapsed_ms": 1000,
		}, run_id)) and details_saved
	_expect_true(details_saved, "saves 197 details after a structure event")
	_expect_equal((analytics.call("_test_pending_items") as Array).size(), 200,
		"mixed lifecycle/structure/detail queue is also capped at 200")
	_expect_true(analytics.call("track", "run_ended", {
		"reason": "quit",
	}, run_id), "saves a run-end structure event even on a saturated queue")
	var names: Array = _pending_event_names(analytics)
	_expect_equal(names.size(), 200, "cap stays 200 after protecting a structure event")
	_expect_equal(names.count("analytics_activated"), 1,
		"activation lifecycle kept under saturation")
	_expect_equal(names.count("app_opened"), 1,
		"app-open structure kept under saturation")
	_expect_equal(names.count("run_started"), 1,
		"run-start structure kept under saturation")
	_expect_equal(names.count("run_ended"), 1,
		"run-end structure saved under saturation")
	_expect_equal(names.count("tutorial_step_completed"), 196,
		"under saturation the oldest detail is dropped first")
	analytics.free()

	var paired: Node = _new_analytics()
	paired.call("_test_set_nonce", "9".repeat(32))
	var paired_run_id: String = str(paired.call("new_run_id"))
	_expect_true(paired.call("track", "run_started", {
		"hero": "warden",
		"boon_tier": 0,
	}, paired_run_id), "prepares a sample that keeps a run start/end pair")
	var paired_structures_saved: bool = true
	for _index in range(199):
		paired_structures_saved = bool(paired.call("track", "app_opened", {
			"open_kind": "resume",
		})) and paired_structures_saved
	_expect_true(paired_structures_saved, "saves 199 structure events after run start")
	_expect_true(paired.call("track", "run_ended", {
		"reason": "quit",
	}, paired_run_id), "saves an end on a saturated queue while keeping the same-run start")
	var paired_names: Array = _pending_event_names(paired)
	_expect_equal(paired_names.size(), 200, "queue cap holds after keeping run start and end")
	_expect_equal(paired_names.count("run_started"), 1,
		"a new run end does not remove the same-run start as a victim")
	_expect_equal(paired_names.count("run_ended"), 1,
		"saves the run end while keeping the same-run start")
	_expect_equal(paired_names.count("app_opened"), 198,
		"removes another same-rank structure event instead")
	paired.free()

	var no_alternative: Node = _new_analytics()
	no_alternative.call("_test_set_nonce", "8".repeat(32))
	var protected_run_id: String = str(no_alternative.call("new_run_id"))
	var starts_saved: bool = true
	for _index in range(200):
		starts_saved = bool(no_alternative.call("track", "run_started", {
			"hero": "warden",
			"boon_tier": 0,
		}, protected_run_id)) and starts_saved
	_expect_true(starts_saved, "prepares a saturated queue that only has the same-run start")
	_expect_false(no_alternative.call("track", "app_opened", {
		"open_kind": "resume",
	}), "if only a pending run start exists, a later app open is rejected instead of starting")
	_expect_false(no_alternative.call("track", "run_ended", {
		"reason": "quit",
	}, protected_run_id), "rejects an end event if there is no victim besides the same-run start")
	var no_alternative_names: Array = _pending_event_names(no_alternative)
	_expect_equal(no_alternative_names.size(), 200,
		"same-run start queue cap holds after rejecting an end")
	_expect_equal(no_alternative_names.count("run_started"), 200,
		"rejecting an end does not change the protected run start")
	_expect_equal(no_alternative_names.count("run_ended"), 0,
		"an end event with no victim does not stay in the queue")
	_expect_equal(int((no_alternative.call("_test_state") as Dictionary).get(
		"next_sequence", -1)), 200, "a rejected end event does not consume sequence either")
	no_alternative.free()

	var pending_start: Node = _new_analytics()
	pending_start.call("_test_set_nonce", "3".repeat(32))
	var pending_run_id: String = str(pending_start.call("new_run_id"))
	_expect_true(pending_start.call("track", "run_started", {
		"hero": "warden",
		"boon_tier": 0,
	}, pending_run_id), "prepares a run start that has not been sent yet")
	var pending_fill_saved: bool = true
	for _index in range(199):
		pending_fill_saved = bool(pending_start.call("track", "app_opened", {
			"open_kind": "resume",
		})) and pending_fill_saved
	_expect_true(pending_fill_saved, "saves 199 structure events after a pending run start")
	_expect_true(pending_start.call("track", "app_opened", {
		"open_kind": "resume",
	}), "after saturation, resume replaces app open rather than the pending run start")
	_expect_equal(_run_event_count(
		pending_start, pending_run_id, "run_started"), 1,
		"pending run start survives resume eviction")
	var second_pending_run_id: String = str(pending_start.call("new_run_id"))
	_expect_true(pending_start.call("track", "run_started", {
		"hero": "dancer",
		"boon_tier": 0,
	}, second_pending_run_id), "another run start also replaces app open instead of the existing pending start")
	_expect_equal(_run_event_count(
		pending_start, pending_run_id, "run_started"), 1,
		"existing pending run start survives another structure event")
	_expect_true(pending_start.call("track", "run_ended", {
		"reason": "quit",
	}, pending_run_id), "saves the original run end after resume eviction")
	_expect_equal((pending_start.call("_test_pending_items") as Array).size(), 200,
		"queue cap holds after protecting a pending start and saving an end")
	_expect_equal(_run_event_count(pending_start, pending_run_id, "run_started"),
		1, "matching start exists after start→resume eviction→end")
	_expect_equal(_run_event_count(pending_start, pending_run_id, "run_ended"),
		1, "one end exists after start→resume eviction→end")
	_expect_true(_all_run_ends_have_starts(pending_start),
		"no orphan end after start→resume eviction→end")
	pending_start.free()

	# Do not only look at an incoming end; every end already in the queue must keep its start
	# A paired end can be removed, so do not unconditionally lock structure events either.
	for incoming_name in ["app_opened", "run_started"]:
		var existing_pair: Node = _new_analytics()
		existing_pair.call("_test_set_nonce",
			("7" if incoming_name == "app_opened" else "6").repeat(32))
		var existing_run_id: String = str(existing_pair.call("new_run_id"))
		_expect_true(existing_pair.call("track", "run_started", {
			"hero": "warden",
			"boon_tier": 0,
		}, existing_run_id), "prepares an already-finished run start: " + incoming_name)
		_expect_true(existing_pair.call("track", "run_ended", {
			"reason": "quit",
		}, existing_run_id), "prepares an already-finished run end: " + incoming_name)
		var existing_fill_saved: bool = true
		for _index in range(198):
			existing_fill_saved = bool(existing_pair.call("track", "app_opened", {
				"open_kind": "resume",
			})) and existing_fill_saved
		_expect_true(existing_fill_saved,
			"saves 198 structure events after an already-finished run: " + incoming_name)
		var incoming_saved: bool = false
		if incoming_name == "app_opened":
			incoming_saved = bool(existing_pair.call("track", "app_opened", {
				"open_kind": "resume",
			}))
		else:
			incoming_saved = bool(existing_pair.call("track", "run_started", {
				"hero": "dancer",
				"boon_tier": 0,
			}, existing_pair.call("new_run_id")))
		_expect_true(incoming_saved,
			"follow-up structure event uses a safe victim instead of the finished-run start: " + incoming_name)
		_expect_equal((existing_pair.call("_test_pending_items") as Array).size(),
			200, "queue cap holds after checking the existing-run invariant: " + incoming_name)
		_expect_equal(_run_event_count(existing_pair, existing_run_id, "run_started"),
			1, "follow-up structure event keeps the finished-run start: " + incoming_name)
		_expect_equal(_run_event_count(existing_pair, existing_run_id, "run_ended"),
			1, "finished-run end is also kept if a substitute structure exists: " + incoming_name)
		_expect_true(_all_run_ends_have_starts(existing_pair),
			"no orphan end after a follow-up structure event: " + incoming_name)
		existing_pair.free()

	var different_end: Node = _new_analytics()
	different_end.call("_test_set_nonce", "5".repeat(32))
	var completed_run_id: String = str(different_end.call("new_run_id"))
	var ending_run_id: String = str(different_end.call("new_run_id"))
	_expect_true(different_end.call("track", "run_started", {
		"hero": "warden",
		"boon_tier": 0,
	}, completed_run_id), "prepares the already-finished run start before another end")
	_expect_true(different_end.call("track", "run_ended", {
		"reason": "quit",
	}, completed_run_id), "prepares the already-finished run end before another end")
	_expect_true(different_end.call("track", "run_started", {
		"hero": "dancer",
		"boon_tier": 0,
	}, ending_run_id), "prepares the run start that another end will close")
	var different_end_fill_saved: bool = true
	for _index in range(197):
		different_end_fill_saved = bool(different_end.call("track", "app_opened", {
			"open_kind": "resume",
		})) and different_end_fill_saved
	_expect_true(different_end_fill_saved, "saves 197 structure events after two runs")
	_expect_true(different_end.call("track", "run_ended", {
		"reason": "quit",
	}, ending_run_id), "another run end is saved without removing the existing end's start")
	_expect_equal((different_end.call("_test_pending_items") as Array).size(), 200,
		"queue cap holds after another run end")
	_expect_equal(_run_event_count(different_end, completed_run_id, "run_ended"), 1,
		"existing finished-run end is kept if a substitute app open exists")
	_expect_equal(_run_event_count(different_end, ending_run_id, "run_ended"), 1,
		"a new run end is also saved with a matching start")
	_expect_true(_all_run_ends_have_starts(different_end),
		"every end still has a matching start after another run end")
	different_end.free()

	var pair_only: Node = _new_analytics()
	pair_only.call("_test_set_nonce", "4".repeat(32))
	var pair_only_saved: bool = true
	for _index in range(100):
		var pair_run_id: String = str(pair_only.call("new_run_id"))
		pair_only_saved = bool(pair_only.call("track", "run_started", {
			"hero": "warden",
			"boon_tier": 0,
		}, pair_run_id)) and pair_only_saved
		pair_only_saved = bool(pair_only.call("track", "run_ended", {
			"reason": "quit",
		}, pair_run_id)) and pair_only_saved
	_expect_true(pair_only_saved, "prepares a saturated queue of 100 finished-run pairs")
	_expect_true(pair_only.call("track", "app_opened", {
		"open_kind": "resume",
	}), "paired-end fallback still relieves saturation when the only alternative is a finished run")
	_expect_equal((pair_only.call("_test_pending_items") as Array).size(), 200,
		"queue cap holds after paired-end fallback")
	_expect_equal(_pending_event_names(pair_only).count("run_started"), 100,
		"paired-end fallback does not remove a start that would orphan an end")
	_expect_equal(_pending_event_names(pair_only).count("run_ended"), 99,
		"paired-end fallback removes only one end when there is no alternative")
	_expect_true(_all_run_ends_have_starts(pair_only),
		"every end still has a matching start after paired-end fallback")
	pair_only.free()

	var protected: Node = _new_analytics()
	protected.call("_test_set_nonce", "d".repeat(32))
	var structures_saved: bool = true
	for _index in range(200):
		structures_saved = bool(protected.call("track", "app_opened", {
			"open_kind": "resume",
		})) and structures_saved
	_expect_true(structures_saved, "prepares a saturated queue of only structure events")
	_expect_false(protected.call("track", "tutorial_step_completed", {
		"step": "move",
		"elapsed_ms": 1000,
	}), "a new detail is dropped before existing structure events")
	var protected_items: Array = protected.call("_test_pending_items") as Array
	_expect_equal(protected_items.size(), 200, "queue cap holds after rejecting a detail")
	_expect_equal(_pending_event_names(protected).count("tutorial_step_completed"), 0,
		"a rejected detail does not stay in the queue")
	_expect_equal(int((protected.call("_test_state") as Dictionary).get(
		"next_sequence", -1)), 200, "a rejected detail does not consume sequence either")
	protected.free()

	var in_flight: Node = _new_analytics()
	in_flight.call("_test_set_nonce", "e".repeat(32))
	var in_flight_run_id: String = str(in_flight.call("new_run_id"))
	_expect_true(in_flight.call("track", "run_started", {
		"hero": "warden",
		"boon_tier": 0,
	}, in_flight_run_id), "prepares an in-flight run-start head")
	var structures_filled: bool = true
	for _index in range(199):
		structures_filled = bool(in_flight.call("track", "app_opened", {
			"open_kind": "resume",
		})) and structures_filled
	_expect_true(structures_filled, "saves 199 structure events behind an in-flight head")
	var before_in_flight: Array = in_flight.call("_test_pending_items") as Array
	var in_flight_id: String = str((before_in_flight[0] as Dictionary).get("id", ""))
	in_flight.set("_in_flight_id", in_flight_id)
	_expect_true(in_flight.call("track", "run_ended", {
		"reason": "quit",
	}, in_flight_run_id), "during saturation, skips the in-flight head and saves a new structure event")
	var after_in_flight: Array = in_flight.call("_test_pending_items") as Array
	_expect_equal(after_in_flight.size(), 200, "queue cap holds after a new structure event during send")
	_expect_equal(str((after_in_flight[0] as Dictionary).get("id", "")),
		in_flight_id, "in-flight head is kept when picking a saturation victim")
	_expect_equal(_pending_event_names(in_flight).count("run_started"), 1,
		"in-flight run-start structure event preserved")
	_expect_equal(_pending_event_names(in_flight).count("run_ended"), 1,
		"saves a new run-end structure event")
	var only_in_flight: Array = [after_in_flight[0]]
	_expect_false(in_flight.call("_make_room_for_event", only_in_flight,
		"run_ended"), "rejects incoming when only in-flight victims remain")
	_expect_equal(only_in_flight.size(), 1,
		"in-flight array preserved when there are no victim candidates")
	in_flight.call("_test_receive", 200)
	_expect_equal((in_flight.call("_test_pending_items") as Array).size(), 199,
		"handles the success callback of a preserved in-flight head")
	_expect_equal(_pending_event_names(in_flight).count("run_started"), 0,
		"success callback removes only the head that was actually sent")
	_expect_equal(_pending_event_names(in_flight).count("run_ended"), 1,
		"new run-end event survives after callback")
	in_flight.free()


func _test_runtime_queue_expiry() -> void:
	var start: int = 1787673600
	var analytics: Node = _new_analytics()
	analytics.call("_test_set_now", start)
	_expect_true(analytics.call("track", "app_opened"), "saves a 14-day queue-boundary sample")
	analytics.call("_test_set_now", start + 14 * 24 * 60 * 60)
	_expect_true(analytics.call("_prune_expired_pending"), "checks a queue that is exactly 14 days old")
	_expect_equal((analytics.call("_test_pending_items") as Array).size(), 1,
		"exactly 14 days is still kept")
	analytics.call("_test_set_now", start + 14 * 24 * 60 * 60 + 1)
	_expect_true(analytics.call("_prune_expired_pending"), "clears a queue older than 14 days during a run")
	_expect_equal((analytics.call("_test_pending_items") as Array).size(), 0,
		"stale events stay unsent even without restarting the process")
	analytics.free()

	var exact_run: Node = _new_analytics()
	exact_run.call("_test_set_now", start)
	var exact_run_id: String = str(exact_run.call("new_run_id"))
	_expect_true(exact_run.call("track", "run_started", {
		"hero": "warden",
		"boon_tier": 0,
	}, exact_run_id), "saves an exactly-14-day run-start sample")
	_expect_true(exact_run.call("track", "run_ended", {
		"reason": "quit",
	}, exact_run_id), "saves an exactly-14-day run-end sample")
	exact_run.call("_test_set_now", start + 14 * 24 * 60 * 60)
	_expect_true(exact_run.call("_prune_expired_pending"),
		"checks a run bundle that is exactly 14 days old")
	_expect_equal(_run_event_count(exact_run, exact_run_id, "run_started"), 1,
		"run starts that are exactly 14 days old are kept")
	_expect_equal(_run_event_count(exact_run, exact_run_id, "run_ended"), 1,
		"run ends that are exactly 14 days old are kept")
	exact_run.free()

	var active_run: Node = _new_analytics()
	active_run.call("_test_set_now", start)
	var active_run_id: String = str(active_run.call("new_run_id"))
	_expect_true(active_run.call("track", "run_started", {
		"hero": "dancer",
		"boon_tier": 1,
	}, active_run_id), "expired-run start saved")
	active_run.call("_test_set_now", start + 10 * 24 * 60 * 60)
	_expect_true(active_run.call("track", "tutorial_step_completed", {
		"step": "move",
		"elapsed_ms": 1000,
	}, active_run_id), "saves a run-detail event newer than the expired start")
	_expect_true(active_run.call("track", "run_ended", {
		"reason": "quit",
	}, active_run_id), "saves a run end newer than the expired start")
	var active_sequence: int = int((active_run.call(
		"_test_state") as Dictionary).get("next_sequence", -1))
	active_run.call("_test_set_now", start + 14 * 24 * 60 * 60 + 1)
	_expect_true(active_run.call("_prune_expired_pending"),
		"clears run starts older than 14 days during a run")
	_expect_equal((active_run.call("_test_pending_items") as Array).size(), 0,
		"also clears newer detail and end of the same run as the expired start")
	_expect_false(active_run.call("track", "continue_used", {
		"cycle": 1,
		"elapsed_ms": 2000,
	}, active_run_id), "rejects re-adding follow-up events of an expired active run")
	_expect_false(active_run.call("track", "run_ended", {
		"reason": "title",
	}, active_run_id), "rejects re-adding the end of an expired active run")
	_expect_equal(int((active_run.call("_test_state") as Dictionary).get(
		"next_sequence", -1)), active_sequence,
		"rejecting an expired-run follow-up does not consume sequence")
	active_run.free()

	var failed_prune: Node = _new_analytics()
	failed_prune.call("_test_set_now", start)
	var first_invalidated_id: String = str(failed_prune.call("new_run_id"))
	failed_prune.call("track", "run_started", {
		"hero": "warden",
		"boon_tier": 0,
	}, first_invalidated_id)
	failed_prune.call("_test_set_now", start + 14 * 24 * 60 * 60 + 1)
	_expect_true(failed_prune.call("_prune_expired_pending"),
		"prepares the existing tombstone before persist-failure rollback")
	var second_run_id: String = str(failed_prune.call("new_run_id"))
	_expect_true(failed_prune.call("track", "run_started", {
		"hero": "keeper",
		"boon_tier": 0,
	}, second_run_id), "saves a new run start targeted by persist failure")
	failed_prune.call("_test_set_now", start + 28 * 24 * 60 * 60 + 2)
	var tombstones_before: Dictionary = (failed_prune.get(
		"_invalidated_pending_run_ids") as Dictionary).duplicate(true)
	failed_prune.call("_test_fail_next_persist")
	_expect_false(failed_prune.call("_prune_expired_pending"),
		"expired-run cleanup save failure is propagated")
	_expect_equal(_run_event_count(failed_prune, second_run_id, "run_started"), 1,
		"pending start rolls back if cleanup save fails")
	_expect_equal(failed_prune.get("_invalidated_pending_run_ids"),
		tombstones_before, "tombstone also keeps the previous state if cleanup save fails")
	_expect_true(failed_prune.call("track", "continue_used", {
		"cycle": 1,
		"elapsed_ms": 1000,
	}, second_run_id), "still accepts follow-up events of a rolled-back pending start")
	failed_prune.call("clear_pending")
	_expect_equal((failed_prune.get(
		"_invalidated_pending_run_ids") as Dictionary).size(), 0,
		"queue reset also resets expired-run tombstones")
	failed_prune.free()

	var bounded: Node = _new_analytics()
	var many_invalidated: Dictionary = {}
	var invalidated_ids: Array[String] = []
	for index in range(201):
		var invalidated_id: String = str(index).sha256_text().substr(0, 32)
		invalidated_ids.append(invalidated_id)
		many_invalidated[invalidated_id] = true
	bounded.call("_remember_invalidated_pending_runs", many_invalidated)
	var bounded_tombstones: Dictionary = bounded.get(
		"_invalidated_pending_run_ids") as Dictionary
	_expect_equal(bounded_tombstones.size(), 200,
		"expired-run tombstones stay within the pending-queue cap")
	_expect_false(bounded_tombstones.has(invalidated_ids[0]),
		"drops oldest runs first when tombstones exceed the cap")
	_expect_true(bounded_tombstones.has(invalidated_ids[200]),
		"recent expired runs are kept even at the tombstone cap")
	bounded.call("_test_configure", true, true, false)
	_expect_equal((bounded.get(
		"_invalidated_pending_run_ids") as Dictionary).size(), 0,
		"resetting test state also clears expired-run tombstones")
	bounded.free()


func _test_loaded_queue_invariants() -> void:
	var start: int = 1787673600

	var exact_source: Node = _new_analytics()
	exact_source.call("_test_set_now", start)
	exact_source.call("_test_set_nonce", "f".repeat(32))
	var exact_run_id: String = str(exact_source.call("new_run_id"))
	exact_source.call("track", "run_started", {
		"hero": "warden",
		"boon_tier": 0,
	}, exact_run_id)
	exact_source.call("track", "run_ended", {"reason": "quit"}, exact_run_id)
	var exact_state: Dictionary = exact_source.call("_test_state") as Dictionary
	var exact_restore: Node = _new_analytics()
	exact_restore.call("_test_set_now", start + 14 * 24 * 60 * 60)
	_expect_true(exact_restore.call("_test_apply_state", exact_state),
		"recovers saved runs that are exactly 14 days old")
	_expect_equal(_run_event_count(exact_restore, exact_run_id, "run_started"), 1,
		"saved run starts are kept at exactly 14 days")
	_expect_equal(_run_event_count(exact_restore, exact_run_id, "run_ended"), 1,
		"saved run ends are also kept at exactly 14 days")
	exact_restore.free()
	exact_source.free()

	var expired_source: Node = _new_analytics()
	expired_source.call("_test_set_now", start)
	expired_source.call("_test_set_nonce", "0".repeat(32))
	var expired_run_id: String = str(expired_source.call("new_run_id"))
	expired_source.call("track", "run_started", {
		"hero": "dancer",
		"boon_tier": 1,
	}, expired_run_id)
	expired_source.call("_test_set_now", start + 10 * 24 * 60 * 60)
	expired_source.call("track", "tutorial_step_completed", {
		"step": "dash",
		"elapsed_ms": 2000,
	}, expired_run_id)
	expired_source.call("track", "run_ended", {"reason": "quit"}, expired_run_id)
	expired_source.call("track", "app_opened", {"open_kind": "resume"})
	var expired_state: Dictionary = expired_source.call("_test_state") as Dictionary
	var expired_restore: Node = _new_analytics()
	expired_restore.call("_test_set_now", start + 14 * 24 * 60 * 60 + 1)
	_expect_true(expired_restore.call("_test_apply_state", expired_state),
		"recovers a save queue that contains an expired start")
	_expect_equal(_pending_event_names(expired_restore), ["app_opened"],
		"recovery also removes only newer detail/end of an expired start")
	var expired_sequence: int = int((expired_restore.call(
		"_test_state") as Dictionary).get("next_sequence", -1))
	_expect_false(expired_restore.call("track", "run_ended", {
		"reason": "title",
	}, expired_run_id), "recovery rejects re-adding an expired run end")
	_expect_equal(int((expired_restore.call("_test_state") as Dictionary).get(
		"next_sequence", -1)), expired_sequence,
		"rejecting an expired run during recovery also leaves sequence unchanged")
	expired_restore.free()
	expired_source.free()

	var invalid_source: Node = _new_analytics()
	invalid_source.call("_test_set_now", start)
	invalid_source.call("_test_set_nonce", "a".repeat(32))
	var invalid_run_id: String = str(invalid_source.call("new_run_id"))
	invalid_source.call("track", "run_started", {
		"hero": "keeper",
		"boon_tier": 2,
	}, invalid_run_id)
	invalid_source.call("track", "continue_used", {
		"cycle": 1,
		"elapsed_ms": 3000,
	}, invalid_run_id)
	invalid_source.call("track", "run_ended", {"reason": "quit"}, invalid_run_id)
	invalid_source.call("track", "app_opened", {"open_kind": "resume"})
	var invalid_state: Dictionary = invalid_source.call("_test_state") as Dictionary
	var invalid_pending: Array = invalid_state.get("pending", []) as Array
	var invalid_start_payload: Dictionary = (
		(invalid_pending[0] as Dictionary).get("event", {}) as Dictionary)
	(invalid_start_payload.get("properties", {}) as Dictionary)["hero"] = "unknown"
	var invalid_restore: Node = _new_analytics()
	invalid_restore.call("_test_set_now", start)
	_expect_true(invalid_restore.call("_test_apply_state", invalid_state),
		"recovers a save queue that contains a verification-failed start")
	_expect_equal(_pending_event_names(invalid_restore), ["app_opened"],
		"also removes same-run detail and end of a verification-failed start")
	_expect_false(invalid_restore.call("track", "continue_used", {
		"cycle": 2,
		"elapsed_ms": 4000,
	}, invalid_run_id), "rejects re-adding follow-up events of a verification-failed run")
	invalid_restore.free()
	invalid_source.free()

	# A raw queue with no start can be a healthy run whose start was already acked by the server.
	# Do not drop such ends at load just because they look like orphans.
	var acked_source: Node = _new_analytics()
	acked_source.call("_test_set_now", start)
	var acked_run_id: String = str(acked_source.call("new_run_id"))
	_expect_true(acked_source.call("track", "run_started", {
		"hero": "sage",
		"boon_tier": 0,
	}, acked_run_id), "prepares a server-acked run start")
	acked_source.call("_test_receive", 200)
	_expect_equal((acked_source.call("_test_pending_items") as Array).size(), 0,
		"run start is removed from the raw queue after server ack")
	_expect_true(acked_source.call("track", "tutorial_step_completed", {
		"step": "beacon",
		"elapsed_ms": 5000,
	}, acked_run_id), "allows follow-up events of an acked start")
	_expect_true(acked_source.call("track", "run_ended", {
		"reason": "cashout",
	}, acked_run_id), "allows end of an acked start")
	var acked_state: Dictionary = acked_source.call("_test_state") as Dictionary
	var acked_restore: Node = _new_analytics()
	acked_restore.call("_test_set_now", start)
	_expect_true(acked_restore.call("_test_apply_state", acked_state),
		"recovers an ack-run queue that never had a raw start")
	_expect_equal(_run_event_count(acked_restore, acked_run_id,
		"tutorial_step_completed"), 1, "preserves ack-run detail events with no raw start")
	_expect_equal(_run_event_count(acked_restore, acked_run_id, "run_ended"), 1,
		"preserves an ack-run end with no raw start")
	acked_restore.free()
	acked_source.free()


func _test_response_handling() -> void:
	var analytics: Node = _new_analytics()
	analytics.call("track", "app_opened")
	var original_id: String = str((analytics.call("_test_request") as Dictionary).get("id", ""))
	analytics.call("_test_receive", 500)
	_expect_equal((analytics.call("_test_pending_items") as Array).size(), 1,
		"server errors stay in the offline queue")
	_expect_equal(str((analytics.call("_test_request") as Dictionary).get("id", "")),
		original_id, "ID is kept even on a server-error retry")
	var retry_deadline: int = int(analytics.call("_test_next_attempt_msec"))
	analytics.call("track", "app_opened")
	_expect_equal(int(analytics.call("_test_next_attempt_msec")), retry_deadline,
		"server backoff keeps a future deadline even if a new event arrives")
	analytics.call("_test_receive", 200)
	_expect_equal((analytics.call("_test_pending_items") as Array).size(), 1,
		"only the processed head is removed after a success response")
	analytics.call("_test_receive", 200)
	_expect_equal((analytics.call("_test_pending_items") as Array).size(), 0,
		"queue is removed after the next head succeeds")

	analytics.call("track", "app_opened")
	analytics.call("_test_receive", 409)
	_expect_equal((analytics.call("_test_pending_items") as Array).size(), 0,
		"an already created deterministic document is treated as success")
	analytics.call("track", "app_opened")
	analytics.call("_test_receive", 400)
	_expect_equal((analytics.call("_test_pending_items") as Array).size(), 0,
		"permanently invalid events do not block the queue")
	analytics.free()


func _test_revocation() -> void:
	var analytics: Node = _new_analytics()
	analytics.call("_test_set_cohort", 1787673600, "2.1.0", 3)
	analytics.call("track", "app_opened")
	analytics.call("_remember_invalidated_pending_runs", {
		"b".repeat(32): true,
	})
	_expect_equal((analytics.call("_test_pending_items") as Array).size(), 1,
		"queued events exist before revoke")
	_expect_equal((analytics.get(
		"_invalidated_pending_run_ids") as Dictionary).size(), 1,
		"expired-run tombstone exists before revoke")
	analytics.call("_test_set_consent", false)
	analytics.call("refresh_consent")
	_expect_false(analytics.call("enabled"), "inactive immediately on consent revoke")
	_expect_equal((analytics.call("_test_pending_items") as Array).size(), 0,
		"unsent events are deleted immediately on consent revoke")
	_expect_equal((analytics.get(
		"_invalidated_pending_run_ids") as Dictionary).size(), 0,
		"expired-run tombstones are deleted immediately on consent revoke")
	_expect_equal(int((analytics.call("_test_cohort") as Dictionary).get("unix", 0)), 0,
		"local cohort metadata is deleted immediately on consent revoke")
	analytics.free()


func _pending_event_names(analytics: Node) -> Array:
	var names: Array = []
	for item in analytics.call("_test_pending_items") as Array:
		names.append(str(((item as Dictionary).get("event", {}) as Dictionary).get(
			"event", "")))
	return names


func _all_run_ends_have_starts(analytics: Node) -> bool:
	var starts: Dictionary = {}
	var ends: Array[String] = []
	for item in analytics.call("_test_pending_items") as Array:
		var payload: Dictionary = (item as Dictionary).get("event", {}) as Dictionary
		var event_name: String = str(payload.get("event", ""))
		var run_id: String = str(payload.get("run_id", ""))
		if event_name == "run_started":
			starts[run_id] = true
		elif event_name == "run_ended":
			ends.append(run_id)
	for run_id in ends:
		if run_id.is_empty() or not starts.has(run_id):
			return false
	return true


func _run_event_count(analytics: Node, run_id: String, event_name: String) -> int:
	var count: int = 0
	for item in analytics.call("_test_pending_items") as Array:
		var payload: Dictionary = (item as Dictionary).get("event", {}) as Dictionary
		if str(payload.get("run_id", "")) == run_id \
				and str(payload.get("event", "")) == event_name:
			count += 1
	return count


func _expect_true(value: Variant, label: String) -> void:
	_checked += 1
	if not bool(value):
		_failed += 1
		printerr("  failed: ", label)


func _expect_false(value: Variant, label: String) -> void:
	_expect_true(not bool(value), label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		_failed += 1
		printerr("  failed: ", label, " — got ", actual, ", expected ", expected)
