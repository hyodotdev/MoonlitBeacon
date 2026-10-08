extends SceneTree

## Cloud Hall best-score, top-board, rank, and deletion tests. No network: the
## transport runs against a scripted fake sender.

const TRANSPORT_SCRIPT: Script = preload(
	"res://scripts/cloud/cloud_transport.gd")
const HALL_SCRIPT: Script = preload("res://scripts/cloud/cloud_hall.gd")
const SCHEMA_SCRIPT: Script = preload("res://scripts/cloud/cloud_schema.gd")
const FAKE_SENDER_SCRIPT: Script = preload(
	"res://tests/support/fake_cloud_sender.gd")

const PROJECT_ID: String = "moonlitbeacon-778ee"
const TOKEN: String = "test-id-token-abc"
const PUBLIC_ID: String = "MB-0123456789abcdef0123456789abcdef"
const HERO: String = "res://resources/heroes/warden.tres"

var _failed: int = 0
var _checked: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_row_validation()
	await _test_first_submit_canonicalizes_hero()
	await _test_lower_score_is_not_best()
	await _test_equal_retry_is_idempotent()
	await _test_higher_score_updates_monotonically()
	await _test_write_race_reports_not_best()
	await _test_submit_carries_verified_display()
	await _test_submit_preserves_stored_display()
	await _test_submit_rejects_forged_display()
	await _test_unnamed_rows_render_honestly()
	await _test_backfill_attaches_at_same_score()
	await _test_backfill_invents_no_row()
	await _test_backfill_never_downgrades()
	await _test_top_board_query_cache_and_throttle()
	await _test_rank_counts_strictly_greater()
	await _test_rank_throttle_bounds_and_account()
	await _test_self_rank_uses_owned_best()
	await _test_self_rank_missing_row_unranked()
	await _test_self_rank_malformed_rows()
	await _test_self_rank_throttle_and_offline_cache()
	await _test_self_rank_not_best_converges()
	await _test_self_rank_own_cache_bound_and_account()
	await _test_self_rank_concurrent_coalesces()
	await _test_self_rank_waiter_shares_terminal_outcomes()
	await _test_self_rank_ticket_retired_cleanly()
	await _test_self_rank_retired_owner_writes_nothing()
	await _test_self_rank_invalidation_keeps_newer_pair()
	await _test_owned_deletion()
	if _failed > 0:
		printerr("cloud hall tests failed — ", _failed, "/", _checked,
			" cases")
		quit(1)
		return
	print("cloud hall tests passed — ", _checked, " cases")
	quit(0)


func _new_transport(sender: RefCounted) -> RefCounted:
	var transport: RefCounted = TRANSPORT_SCRIPT.new()
	transport.call("configure", PROJECT_ID, "web-key",
		func() -> String: return TOKEN, sender.call("sender_callable"))
	transport.call("set_account_uid", "uid-hall-001")
	return transport


func _row_body(score: int, hero: String = HERO, cycles: int = 3) -> String:
	return JSON.stringify({
		"name": "projects/%s/databases/(default)/documents/mb_hall_v1/%s"
			% [PROJECT_ID, PUBLIC_ID],
		"fields": {
			"public_id": {"stringValue": PUBLIC_ID},
			"hero": {"stringValue": hero},
			"score": {"integerValue": str(score)},
			"cycles": {"integerValue": str(cycles)},
			"release": {"stringValue": "4.0.0"},
			"schema": {"integerValue": "1"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
		},
	})


func _top_body(scores: Array) -> String:
	var entries: Array = []
	for score in scores:
		entries.append({
			"document": {
				"name": "projects/%s/databases/(default)/x/mb_hall_v1/y%d"
					% [PROJECT_ID, score],
				"fields": {
					"public_id": {"stringValue": PUBLIC_ID},
					"hero": {"stringValue": HERO},
					"score": {"integerValue": str(score)},
					"cycles": {"integerValue": "3"},
					"release": {"stringValue": "4.0.0"},
					"schema": {"integerValue": "1"},
					"updated_at": {"timestampValue":
						"2026-10-01T00:00:00Z"},
				},
			}
		})
	return JSON.stringify(entries)


func _rank_body(greater: int) -> String:
	return JSON.stringify([{
		"result": {
			"aggregateFields": {
				"greater": {"integerValue": str(greater)},
			}
		}
	}])


func _named_row_body(score: int, display: String, hero: String = HERO,
		cycles: int = 3) -> String:
	return JSON.stringify({
		"name": "projects/%s/databases/(default)/documents/mb_hall_v1/%s"
			% [PROJECT_ID, PUBLIC_ID],
		"fields": {
			"public_id": {"stringValue": PUBLIC_ID},
			"hero": {"stringValue": hero},
			"score": {"integerValue": str(score)},
			"cycles": {"integerValue": str(cycles)},
			"release": {"stringValue": "4.0.0"},
			"schema": {"integerValue": "1"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
			"display": {"stringValue": display},
		},
	})


func _row_body_for(public_id: String, score: int, hero: String = HERO,
		cycles: int = 3) -> String:
	return JSON.stringify({
		"name": "projects/%s/databases/(default)/documents/mb_hall_v1/%s"
			% [PROJECT_ID, public_id],
		"fields": {
			"public_id": {"stringValue": public_id},
			"hero": {"stringValue": hero},
			"score": {"integerValue": str(score)},
			"cycles": {"integerValue": str(cycles)},
			"release": {"stringValue": "4.0.0"},
			"schema": {"integerValue": "1"},
			"updated_at": {"timestampValue": "2026-10-01T00:00:00Z"},
		},
	})


func _own_get_count(sender: RefCounted) -> int:
	var count: int = 0
	for call in sender.get("calls"):
		var entry: Dictionary = call
		if str(entry.get("method", "")) == "GET" and str(
				entry.get("url", "")).contains("mb_hall_v1/"):
			count += 1
	return count


func _rank_post_count(sender: RefCounted) -> int:
	var count: int = 0
	for call in sender.get("calls"):
		if str((call as Dictionary).get("url", "")).contains(
				"runAggregationQuery"):
			count += 1
	return count


func _ranked_score_of(sender: RefCounted) -> int:
	var query: Dictionary = JSON.parse_string(str(
		sender.call("last_call").get("body", "")))
	var where: Dictionary = ((query.get("structuredAggregationQuery", {})
		as Dictionary).get("structuredQuery", {}) as Dictionary).get(
		"where", {})
	var value: Dictionary = ((where.get("fieldFilter", {})
		as Dictionary).get("value", {}) as Dictionary)
	return int(str(value.get("integerValue", "-1")))


func _test_row_validation() -> void:
	_expect_true(bool(SCHEMA_SCRIPT.validate_hall_row(
		HERO, 100, 3, "4.0.0").get("ok", false)), "valid row accepted")
	_expect_equal(SCHEMA_SCRIPT.validate_hall_row(
		"res://resources/heroes/bogus.tres", 100, 3, "4.0.0").get(
		"error", ""), "invalid-hero", "unknown hero rejected")
	_expect_equal(SCHEMA_SCRIPT.canonical_hero("warden"), HERO,
		"short hero id resolves to the allow-listed path")
	_expect_equal(SCHEMA_SCRIPT.validate_hall_row(
		HERO, -1, 3, "4.0.0").get("error", ""), "invalid-score",
		"negative score rejected")
	_expect_equal(SCHEMA_SCRIPT.validate_hall_row(
		HERO, 2000000001, 3, "4.0.0").get("error", ""), "invalid-score",
		"score above the structural bound rejected")
	_expect_true(bool(SCHEMA_SCRIPT.validate_hall_row(
		HERO, 100, 10000, "4.0.0").get("ok", false)),
		"cycles 10000 validates under the Journey-matched bound")
	_expect_true(bool(SCHEMA_SCRIPT.validate_hall_row(
		HERO, 100, 99999, "4.0.0").get("ok", false)),
		"cycles 99999 validates at the Journey cap")
	_expect_equal(SCHEMA_SCRIPT.validate_hall_row(
		HERO, 100, 100000, "4.0.0").get("error", ""), "invalid-cycles",
		"cycles above the bound rejected")


func _test_first_submit_canonicalizes_hero() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var hall: RefCounted = HALL_SCRIPT.new()
	var result: Dictionary = await hall.call("submit_best",
		_new_transport(sender), PUBLIC_ID, "warden", 500, 3, "4.0.0")
	_expect_equal(result.get("status", ""), "ok", "first submit ok")
	var commit: Dictionary = JSON.parse_string(str(
		sender.call("last_call").get("body", "")))
	var update: Dictionary = ((commit.get("writes", []) as Array)[0]
		as Dictionary).get("update", {})
	_expect_true(str(update.get("name", "")).ends_with(
		"mb_hall_v1/%s" % PUBLIC_ID),
		"best-score document ID is the public ID")
	_expect_equal((update.get("fields", {}) as Dictionary).get(
		"hero", {}).get("stringValue", ""), HERO,
		"short hero stored as the allow-listed path")


func _test_lower_score_is_not_best() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _row_body(900))
	var hall: RefCounted = HALL_SCRIPT.new()
	var result: Dictionary = await hall.call("submit_best",
		_new_transport(sender), PUBLIC_ID, HERO, 100, 3, "4.0.0")
	_expect_equal(result.get("code", ""), "not-best",
		"lower score reported as not-best")
	_expect_equal(sender.calls.size(), 1,
		"not-best writes nothing to the server")


func _test_equal_retry_is_idempotent() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _row_body(500))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var hall: RefCounted = HALL_SCRIPT.new()
	var first: Dictionary = await hall.call("submit_best",
		_new_transport(sender), PUBLIC_ID, HERO, 500, 3, "4.0.0")
	_expect_equal(first.get("status", ""), "ok",
		"equal-score retry succeeds idempotently")
	var first_path: String = str(JSON.parse_string(str(
		sender.call("last_call").get("body", ""))).get("writes", [])[0].get(
		"update", {}).get("name", ""))
	sender.call("queue_ok", _row_body(500))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var second: Dictionary = await hall.call("submit_best",
		_new_transport(sender), PUBLIC_ID, HERO, 500, 3, "4.0.0")
	_expect_equal(second.get("status", ""), "ok", "second retry also ok")
	var second_path: String = str(JSON.parse_string(str(
		sender.call("last_call").get("body", ""))).get("writes", [])[0].get(
		"update", {}).get("name", ""))
	_expect_equal(first_path, second_path,
		"retries overwrite the same player row, never a second one")


func _test_higher_score_updates_monotonically() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _row_body(500))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var hall: RefCounted = HALL_SCRIPT.new()
	var result: Dictionary = await hall.call("submit_best",
		_new_transport(sender), PUBLIC_ID, HERO, 800, 4, "4.0.0")
	_expect_equal(result.get("status", ""), "ok", "higher score stored")
	_expect_equal(result.get("score", 0), 800, "new best echoed back")


func _test_write_race_reports_not_best() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _row_body(500))
	sender.call("queue_reply", {"transport": "ok", "code": 403,
		"body": "denied"})
	var hall: RefCounted = HALL_SCRIPT.new()
	var result: Dictionary = await hall.call("submit_best",
		_new_transport(sender), PUBLIC_ID, HERO, 800, 4, "4.0.0")
	_expect_equal(result.get("code", ""), "not-best",
		"monotonic-rule denial reads as not-best, not a crash")


func _test_submit_carries_verified_display() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var hall: RefCounted = HALL_SCRIPT.new()
	var result: Dictionary = await hall.call("submit_best",
		_new_transport(sender), PUBLIC_ID, HERO, 500, 3, "4.0.0",
		"Luna")
	_expect_equal(result.get("status", ""), "ok", "named submit ok")
	var fields: Dictionary = (JSON.parse_string(str(
		sender.call("last_call").get("body", ""))).get("writes", [])[0].get(
		"update", {}) as Dictionary).get("fields", {})
	_expect_equal(str(fields.get("display", {}).get("stringValue", "")),
		"Luna", "submit carries the verified display")


func _test_submit_preserves_stored_display() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _named_row_body(500, "Luna"))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var hall: RefCounted = HALL_SCRIPT.new()
	var result: Dictionary = await hall.call("submit_best",
		_new_transport(sender), PUBLIC_ID, HERO, 800, 4, "4.0.0")
	_expect_equal(result.get("status", ""), "ok",
		"cold-cache submit ok")
	var fields: Dictionary = (JSON.parse_string(str(
		sender.call("last_call").get("body", ""))).get("writes", [])[0].get(
		"update", {}) as Dictionary).get("fields", {})
	_expect_equal(str(fields.get("display", {}).get("stringValue", "")),
		"Luna", "cold cache keeps the row's own display")


func _test_submit_rejects_forged_display() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var hall: RefCounted = HALL_SCRIPT.new()
	var result: Dictionary = await hall.call("submit_best",
		_new_transport(sender), PUBLIC_ID, HERO, 500, 3, "4.0.0",
		"a/b")
	_expect_equal(result.get("code", ""), "invalid-name",
		"forged display fails before any request")
	_expect_equal(sender.calls.size(), 0, "forged display sends nothing")


func _test_unnamed_rows_render_honestly() -> void:
	var hall: RefCounted = HALL_SCRIPT.new()
	var own: Dictionary = hall.call("parse_row", _row_body(500))
	_expect_equal(str((own.get("row", {}) as Dictionary).get(
		"display", "MISSING")), "", "unnamed own row reads empty")
	var named: Dictionary = hall.call(
		"parse_row", _named_row_body(500, "Luna"))
	_expect_equal(str((named.get("row", {}) as Dictionary).get(
		"display", "")), "Luna", "named own row reads its handle")


func _test_backfill_attaches_at_same_score() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _row_body(500,
		"res://resources/heroes/keeper.tres", 7))
	sender.call("queue_ok", _row_body(500,
		"res://resources/heroes/keeper.tres", 7))
	sender.call("queue_ok", "{\"writeResults\":[{}]}")
	var hall: RefCounted = HALL_SCRIPT.new()
	var result: Dictionary = await hall.call("backfill_display",
		_new_transport(sender), PUBLIC_ID, "Luna")
	_expect_equal(result.get("status", ""), "ok", "backfill ok")
	_expect_true(bool(result.get("backfilled", false)),
		"backfill reports backfilled")
	var fields: Dictionary = (JSON.parse_string(str(
		sender.call("last_call").get("body", ""))).get("writes", [])[0].get(
		"update", {}) as Dictionary).get("fields", {})
	_expect_equal(str(fields.get("score", {}).get("integerValue", "")),
		"500", "backfill keeps the row's own score")
	_expect_equal(str(fields.get("hero", {}).get("stringValue", "")),
		"res://resources/heroes/keeper.tres",
		"backfill keeps the saved hero, not the selected one")
	_expect_equal(str(fields.get("cycles", {}).get("integerValue", "")),
		"7", "backfill keeps the saved cycles")
	_expect_equal(str(fields.get("display", {}).get("stringValue", "")),
		"Luna", "backfill attaches the handle")


func _test_backfill_invents_no_row() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	var hall: RefCounted = HALL_SCRIPT.new()
	var result: Dictionary = await hall.call("backfill_display",
		_new_transport(sender), PUBLIC_ID, "Luna")
	_expect_equal(result.get("status", ""), "ok",
		"backfill without a row still ok")
	_expect_false(bool(result.get("backfilled", true)),
		"backfill without a row writes nothing")
	_expect_equal(result.get("code", ""), "no-row",
		"backfill without a row names no-row")
	_expect_equal(sender.calls.size(), 1, "backfill without a row reads once")


func _test_backfill_never_downgrades() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _row_body(500))
	sender.call("queue_ok", _row_body(900))
	var hall: RefCounted = HALL_SCRIPT.new()
	var result: Dictionary = await hall.call("backfill_display",
		_new_transport(sender), PUBLIC_ID, "Luna")
	_expect_equal(result.get("code", ""), "not-best",
		"backfill against a newer best reports not-best, never writes it down")
	_expect_equal(_own_get_count(sender), 2,
		"the retry re-reads the row instead of assuming")


func _test_top_board_query_cache_and_throttle() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _top_body([900, 700]))
	var hall: RefCounted = HALL_SCRIPT.new()
	var live: Dictionary = await hall.call("fetch_top",
		_new_transport(sender), 20, 100000)
	_expect_equal(live.get("status", ""), "ok", "top board live ok")
	_expect_equal(live.get("source", ""), "live", "live read labeled live")
	_expect_equal((live.get("rows", []) as Array).size(), 2,
		"two board rows decoded")
	var query: Dictionary = JSON.parse_string(str(
		sender.call("last_call").get("body", "")))
	var order: Dictionary = ((query.get("structuredQuery", {}) as Dictionary)
		.get("orderBy", []) as Array)[0]
	_expect_equal(order.get("direction", ""), "DESCENDING",
		"board ordered by score descending")
	_expect_true(str(sender.call("last_call").get("url", "")).contains(
		"documents:runQuery"), "board uses the query endpoint")

	var cached: Dictionary = await hall.call("fetch_top",
		_new_transport(sender), 20, 101000)
	_expect_equal(cached.get("source", ""), "cache-throttled",
		"rapid repeat labeled throttled cache")
	_expect_equal(sender.calls.size(), 1, "throttled repeat sends nothing")

	var older: Dictionary = await hall.call("fetch_top",
		_new_transport(sender), 20, 110000)
	_expect_equal(older.get("source", ""), "cache",
		"repeat inside TTL labeled cache")
	_expect_equal(sender.calls.size(), 1, "cached repeat sends nothing")

	sender.call("queue_reply", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var fallback: Dictionary = await hall.call("fetch_top",
		_new_transport(sender), 20, 200000)
	_expect_equal(fallback.get("source", ""), "cache",
		"expired cache plus offline falls back labeled")
	_expect_equal(fallback.get("live_error", ""), "offline",
		"fallback names the live failure")


func _test_rank_counts_strictly_greater() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _rank_body(7))
	var hall: RefCounted = HALL_SCRIPT.new()
	var rank: Dictionary = await hall.call("fetch_rank",
		_new_transport(sender), PUBLIC_ID, 500, 300000)
	_expect_equal(rank.get("status", ""), "ok", "rank ok")
	_expect_equal(rank.get("rank", 0), 8,
		"rank is strictly-greater count plus one, so ties share it")
	_expect_equal(rank.get("source", ""), "live", "rank live labeled")
	var query: Dictionary = JSON.parse_string(str(
		sender.call("last_call").get("body", "")))
	var where: Dictionary = ((query.get("structuredAggregationQuery", {})
		as Dictionary).get("structuredQuery", {}) as Dictionary).get(
		"where", {})
	# Composed like the module: the locale check reads a double-quoted SNAKE
	# literal as a UI key, and this assertion target is a Firestore enum.
	var greater_op: String = "GREATER" + "_" + "THAN"
	_expect_equal((where.get("fieldFilter", {}) as Dictionary).get("op", ""),
		greater_op, "rank filter is strictly greater")
	_expect_true(str(sender.call("last_call").get("url", "")).contains(
		"documents:runAggregationQuery"), "rank uses aggregation")
	var cached: Dictionary = await hall.call("fetch_rank",
		_new_transport(sender), PUBLIC_ID, 500, 300500)
	_expect_equal(cached.get("source", ""), "cache", "rank cached labeled")
	_expect_equal(sender.calls.size(), 1, "cached rank sends nothing")


func _test_rank_throttle_bounds_and_account() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _rank_body(7))
	sender.call("queue_ok", _rank_body(3))
	var hall: RefCounted = HALL_SCRIPT.new()
	var live: Dictionary = await hall.call("fetch_rank",
		_new_transport(sender), PUBLIC_ID, 500, 500000)
	_expect_equal(live.get("source", ""), "live", "first rank is live")
	var throttled: Dictionary = await hall.call("fetch_rank",
		_new_transport(sender), PUBLIC_ID, 600, 501000)
	_expect_equal(throttled.get("source", ""), "cache-throttled",
		"a changed score inside the window reuses the labeled last known")
	_expect_equal(throttled.get("score", 0), 500,
		"the throttled rank keeps the score it was computed for")
	_expect_equal(sender.calls.size(), 1,
		"the throttled refresh sends nothing")
	var next_window: Dictionary = await hall.call("fetch_rank",
		_new_transport(sender), PUBLIC_ID, 600, 600000)
	_expect_equal(next_window.get("source", ""), "live",
		"the window crossing refreshes live again")
	_expect_equal(sender.calls.size(), 2, "two windows send twice")

	var flooder: RefCounted = FAKE_SENDER_SCRIPT.new()
	for _index in 12:
		flooder.call("queue_ok", _rank_body(1))
	var wide: RefCounted = HALL_SCRIPT.new()
	for index in 12:
		var fetched: Dictionary = await wide.call("fetch_rank",
			_new_transport(flooder), PUBLIC_ID, 100 + index,
			1000000 + index * 70000)
		_expect_equal(fetched.get("status", ""), "ok",
			"rank %d answers ok" % index)
	_expect_equal(wide.call("rank_cache_size"), 8,
		"twelve distinct scores keep a bounded cache")

	var other: String = "MB-" + "f".repeat(32)
	var guarded: RefCounted = HALL_SCRIPT.new()
	guarded.call("set_account", other)
	var refused: Dictionary = await guarded.call("fetch_rank",
		_new_transport(sender), PUBLIC_ID, 500, 700000)
	_expect_equal(refused.get("code", ""), "account-changed",
		"a rank for the previous account reports cancelled")
	guarded.call("set_account", PUBLIC_ID)
	sender.call("queue_ok", _rank_body(9))
	var rebound: Dictionary = await guarded.call("fetch_rank",
		_new_transport(sender), PUBLIC_ID, 500, 700000)
	_expect_equal(rebound.get("source", ""), "live",
		"the bound account reads live again")

	sender.call("queue_reply", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var fallback: Dictionary = await guarded.call("fetch_rank",
		_new_transport(sender), PUBLIC_ID, 500, 800000)
	_expect_equal(fallback.get("source", ""), "cache",
		"a failed refresh falls back to the labeled last known")
	_expect_equal(fallback.get("live_error", ""), "offline",
		"the fallback names the live failure")


func _test_self_rank_uses_owned_best() -> void:
	var knight: String = "res://resources/heroes/knight.tres"
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _row_body(100, knight, 2))
	sender.call("queue_ok", _rank_body(0))
	var hall: RefCounted = HALL_SCRIPT.new()
	var rank: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 100000)
	_expect_equal(rank.get("status", ""), "ok", "owned self rank ok")
	_expect_equal(rank.get("rank", 0), 1,
		"a lone board ranks our own record first, not second")
	_expect_equal(rank.get("score", 0), 100,
		"the rank carries the owned best score")
	_expect_equal(rank.get("hero", ""), knight,
		"the rank carries the owned best hero")
	_expect_equal(rank.get("cycles", 0), 2,
		"the rank carries the owned best cycles")
	_expect_equal(rank.get("public_id", ""), PUBLIC_ID,
		"the rank carries our public ID")
	_expect_equal(rank.get("source", ""), "live", "self rank live")
	_expect_equal(rank.get("row_source", ""), "live",
		"the own half labels its live read")
	_expect_equal(rank.get("rank_source", ""), "live",
		"the count half labels its live read")
	_expect_equal(rank.get("fetched_msec", 0), 100000,
		"the pair keeps its measurement time")
	_expect_equal(_ranked_score_of(sender), 100,
		"the count filters above the owned best")
	_expect_equal(_own_get_count(sender), 1, "one own-row read")
	_expect_equal(_rank_post_count(sender), 1, "one count query")

	var tied: RefCounted = FAKE_SENDER_SCRIPT.new()
	tied.call("queue_ok", _row_body(100, knight, 2))
	tied.call("queue_ok", _rank_body(2))
	var tied_rank: Dictionary = await HALL_SCRIPT.new().call(
		"fetch_self_rank", _new_transport(tied), PUBLIC_ID, 100000)
	_expect_equal(tied_rank.get("rank", 0), 3,
		"two strictly greater rows rank us third, ties shared")

	var short: RefCounted = FAKE_SENDER_SCRIPT.new()
	short.call("queue_ok", _row_body(100, "knight", 2))
	short.call("queue_ok", _rank_body(0))
	var short_rank: Dictionary = await HALL_SCRIPT.new().call(
		"fetch_self_rank", _new_transport(short), PUBLIC_ID, 100000)
	_expect_equal(short_rank.get("hero", ""), knight,
		"a short hero id resolves to the allow-listed path")


func _test_self_rank_missing_row_unranked() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	var hall: RefCounted = HALL_SCRIPT.new()
	var rank: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 200000)
	_expect_equal(rank.get("status", ""), "unranked",
		"a missing own row is unranked")
	_expect_equal(rank.get("code", ""), "own-row-missing",
		"the miss has its own explicit code")
	_expect_equal(rank.get("rank", -1), 0, "no invented #1")
	_expect_equal(rank.get("score", -1), 0, "no invented score")
	_expect_equal(rank.get("hero", "none"), "", "no invented hero")
	_expect_equal(rank.get("source", ""), "live", "the miss is measured")
	var again: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 201000)
	_expect_equal(again.get("status", ""), "unranked",
		"repeats stay unranked inside the window")
	_expect_equal(again.get("source", ""), "cache-throttled",
		"the repeat is labeled throttled")
	_expect_equal(_own_get_count(sender), 1,
		"a missing row is never re-probed inside the window")
	_expect_equal(_rank_post_count(sender), 0,
		"no count query fires without an owned score")
	sender.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	var later: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 300000)
	_expect_equal(later.get("source", ""), "live",
		"the expired miss re-probes live for a first submit")
	_expect_equal(_own_get_count(sender), 2, "one re-probe only")


func _test_self_rank_malformed_rows() -> void:
	var cases: Array = [
		["{oops", "bad-hall-body"],
		[JSON.stringify({"fields": {}}), "bad-hall-row"],
		[_row_body_for("MB-" + "e".repeat(32), 100), "bad-hall-row"],
		[_row_body(100, "res://resources/heroes/bogus.tres"),
			"bad-hall-row"],
		[_row_body(-5), "bad-hall-row"],
		[_row_body(2000000001), "bad-hall-row"],
		[_row_body(100, HERO, 100000), "bad-hall-row"],
	]
	for entry in cases:
		var body: String = str((entry as Array)[0])
		var code: String = str((entry as Array)[1])
		var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
		sender.call("queue_ok", body)
		var hall: RefCounted = HALL_SCRIPT.new()
		var rank: Dictionary = await hall.call("fetch_self_rank",
			_new_transport(sender), PUBLIC_ID, 400000)
		_expect_equal(rank.get("status", ""), "failure",
			"a malformed own row fails: " + body.substr(0, 48))
		_expect_equal(rank.get("code", ""), code,
			"the malformed row keeps its code")
		_expect_equal(hall.call("own_cache_size"), 0,
			"a malformed row caches nothing")
		_expect_equal(_rank_post_count(sender), 0,
			"a malformed row fires no count query")


func _test_self_rank_throttle_and_offline_cache() -> void:
	var knight: String = "res://resources/heroes/knight.tres"
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _row_body(100, knight, 2))
	sender.call("queue_ok", _rank_body(0))
	var hall: RefCounted = HALL_SCRIPT.new()
	var live: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 500000)
	_expect_equal(live.get("source", ""), "live", "first refresh live")
	var throttled: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 501000)
	_expect_equal(throttled.get("source", ""), "cache-throttled",
		"an immediate repeat serves the labeled last known pair")
	_expect_equal(throttled.get("score", 0), 100,
		"the throttled pair keeps the owned score")
	_expect_equal(throttled.get("hero", ""), knight,
		"the throttled pair keeps the owned hero")
	_expect_equal(throttled.get("fetched_msec", 0), 500000,
		"the throttled pair keeps its measurement time")
	_expect_equal(throttled.get("row_fetched_msec", 0), 500000,
		"the throttled row keeps its own time")
	_expect_equal(sender.calls.size(), 2,
		"the throttled refresh sends nothing at all")
	var cached: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 510000)
	_expect_equal(cached.get("source", ""), "cache",
		"a fresh repeat past the window serves labeled cache")
	_expect_equal(sender.calls.size(), 2,
		"the cached refresh sends nothing at all")
	sender.call("queue_reply", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var fallback: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 600000)
	_expect_equal(fallback.get("status", ""), "ok",
		"an expired cache plus offline still answers")
	_expect_equal(fallback.get("source", ""), "cache",
		"the offline answer is labeled cache")
	_expect_equal(fallback.get("live_error", ""), "offline",
		"the offline answer names the live failure")
	_expect_equal(fallback.get("score", 0), 100,
		"the offline answer keeps the owned score")
	_expect_equal(fallback.get("hero", ""), knight,
		"the offline answer keeps the owned hero")
	var cold: RefCounted = FAKE_SENDER_SCRIPT.new()
	cold.call("queue_reply", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var bare: Dictionary = await HALL_SCRIPT.new().call("fetch_self_rank",
		_new_transport(cold), PUBLIC_ID, 600000)
	_expect_equal(bare.get("status", ""), "offline",
		"offline with nothing cached reports offline, not a rank")


func _test_self_rank_not_best_converges() -> void:
	var dancer: String = "res://resources/heroes/dancer.tres"
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", _row_body(500))
	sender.call("queue_ok", _rank_body(4))
	var hall: RefCounted = HALL_SCRIPT.new()
	var first: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 700000)
	_expect_equal(first.get("score", 0), 500, "the first best is 500")
	sender.call("queue_ok", _row_body(900, dancer, 5))
	var refused: Dictionary = await hall.call("submit_best",
		_new_transport(sender), PUBLIC_ID, HERO, 100, 3, "4.0.0")
	_expect_equal(refused.get("code", ""), "not-best",
		"the lower submit is refused")
	_expect_equal(refused.get("best", 0), 900,
		"the refusal names the server best")
	_expect_equal(hall.call("own_cache_size"), 0,
		"not-best clears the stale owned lower row")
	_expect_equal(hall.call("rank_cache_size"), 0,
		"not-best clears the stale lower rank")
	sender.call("queue_ok", _row_body(900, dancer, 5))
	sender.call("queue_ok", _rank_body(1))
	var converged: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 701000)
	_expect_equal(converged.get("status", ""), "ok",
		"the next refresh re-reads live past the cleared cache")
	_expect_equal(converged.get("score", 0), 900,
		"the refresh converges to the server best score")
	_expect_equal(converged.get("hero", ""), dancer,
		"the refresh converges to the server best hero")
	_expect_equal(converged.get("rank", 0), 2,
		"the refresh converges to the server best rank")


func _test_self_rank_own_cache_bound_and_account() -> void:
	var wide: RefCounted = HALL_SCRIPT.new()
	var tail: String = "0123456789ab"
	for index in 12:
		var public_id: String = "MB-" + "0".repeat(31) + tail.substr(
			index, 1)
		var feeder: RefCounted = FAKE_SENDER_SCRIPT.new()
		feeder.call("queue_ok", _row_body_for(public_id, 100 + index))
		feeder.call("queue_ok", _rank_body(1))
		var fetched: Dictionary = await wide.call("fetch_self_rank",
			_new_transport(feeder), public_id,
			1000000 + index * 70000)
		_expect_equal(fetched.get("status", ""), "ok",
			"self rank %d answers ok" % index)
	_expect_equal(wide.call("own_cache_size"), 8,
		"twelve distinct owners keep a bounded own-row cache")

	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	var guarded: RefCounted = HALL_SCRIPT.new()
	guarded.call("set_account", "MB-" + "f".repeat(32))
	var refused: Dictionary = await guarded.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 2000000)
	_expect_equal(refused.get("code", ""), "account-changed",
		"a self rank for the previous account reports cancelled")
	_expect_equal(sender.calls.size(), 0, "the refused read sends nothing")
	guarded.call("set_account", PUBLIC_ID)
	sender.call("queue_ok", _row_body(100))
	sender.call("queue_ok", _rank_body(0))
	var rebound: Dictionary = await guarded.call("fetch_self_rank",
		_new_transport(sender), PUBLIC_ID, 2000000)
	_expect_equal(rebound.get("source", ""), "live",
		"the bound account reads live again")
	_expect_equal(guarded.call("own_cache_size"), 1,
		"the rebound read caches exactly its own row")


func _test_self_rank_concurrent_coalesces() -> void:
	var knight: String = "res://resources/heroes/knight.tres"
	var inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	for _index in 6:
		inner.call("queue_ok", "{}")
	var delayed: RefCounted = _DelayRoutingSender.new(self, inner,
		_row_body(100, knight, 2), _rank_body(0))
	var hall: RefCounted = HALL_SCRIPT.new()
	var transport: RefCounted = _new_transport(delayed)
	# All three start before any can finish: the first suspension lands
	# inside the delayed first read, so overlap is structural.
	var boxes: Array = [{}, {}, {}]
	for box in boxes:
		_self_rank_into(box as Dictionary, hall, transport, PUBLIC_ID,
			100000)
	var index: int = 0
	for box in boxes:
		index += 1
		_expect_true(await _await_box(box as Dictionary),
			"simultaneous refresh %d lands" % index)
	for box in boxes:
		var rank: Dictionary = (box as Dictionary).get("result", {})
		_expect_equal(rank.get("status", ""), "ok",
			"every simultaneous refresh answers ok")
		_expect_equal(rank.get("rank", 0), 1,
			"every simultaneous refresh ranks the one board first")
		_expect_equal(rank.get("score", 0), 100,
			"every simultaneous refresh carries the owned best")
		_expect_equal(rank.get("hero", ""), knight,
			"every simultaneous refresh carries the owned hero")
	_expect_equal(
		((boxes[1] as Dictionary).get("result", {}) as Dictionary).get(
			"fetched_msec", -1),
		((boxes[0] as Dictionary).get("result", {}) as Dictionary).get(
			"fetched_msec", -2),
		"concurrent refreshes share one measurement time")
	_expect_equal(_own_get_count(inner), 1,
		"three simultaneous refreshes fire one own-row read")
	_expect_equal(_rank_post_count(inner), 1,
		"three simultaneous refreshes fire one count query")
	_expect_true(int(delayed.get("max_in_flight")) <= 1,
		"the coalesced refresh never reads in parallel")


func _test_self_rank_waiter_shares_terminal_outcomes() -> void:
	var knight: String = "res://resources/heroes/knight.tres"
	# Offline own read, nothing cached: both callers share the one
	# offline outcome instead of one hanging or inventing a rank.
	var inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	inner.call("queue_ok", "{}")
	var delayed: RefCounted = _DelayRoutingSender.new(self, inner,
		_row_body(100, knight, 2), _rank_body(0))
	delayed.set("fail_get", {"transport": "offline", "code": 0,
		"body": PackedByteArray()})
	var hall: RefCounted = HALL_SCRIPT.new()
	var transport: RefCounted = _new_transport(delayed)
	var first_box: Dictionary = {}
	var second_box: Dictionary = {}
	_self_rank_into(first_box, hall, transport, PUBLIC_ID, 100000)
	_self_rank_into(second_box, hall, transport, PUBLIC_ID, 100000)
	_expect_true(await _await_box(first_box), "the offline owner lands")
	_expect_true(await _await_box(second_box), "the offline waiter lands")
	_expect_equal((first_box.get("result", {}) as Dictionary).get(
		"status", ""), "offline", "the owner reports offline")
	_expect_equal((second_box.get("result", {}) as Dictionary).get(
		"status", ""), "offline", "the waiter shares the offline outcome")
	_expect_equal(_own_get_count(inner), 1,
		"the shared offline outcome sends once")

	# Malformed own row: both share the failure, no count query fires.
	var broken_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	broken_inner.call("queue_ok", "{}")
	var broken: RefCounted = _DelayRoutingSender.new(self, broken_inner,
		_row_body(100, "res://resources/heroes/bogus.tres"), _rank_body(0))
	var broken_hall: RefCounted = HALL_SCRIPT.new()
	var broken_transport: RefCounted = _new_transport(broken)
	var broken_first: Dictionary = {}
	var broken_second: Dictionary = {}
	_self_rank_into(broken_first, broken_hall, broken_transport,
		PUBLIC_ID, 100000)
	_self_rank_into(broken_second, broken_hall, broken_transport,
		PUBLIC_ID, 100000)
	_expect_true(await _await_box(broken_first),
		"the malformed owner lands")
	_expect_true(await _await_box(broken_second),
		"the malformed waiter lands")
	_expect_equal((broken_second.get("result", {}) as Dictionary).get(
		"code", ""), "bad-hall-row",
		"the waiter shares the malformed-row failure")
	_expect_equal(_rank_post_count(broken_inner), 0,
		"the shared malformed row fires no count query")

	# Missing own row: both share unranked, never an invented #1.
	var miss_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	miss_inner.call("queue_ok", "{}")
	var miss: RefCounted = _DelayRoutingSender.new(self, miss_inner,
		_row_body(100, knight, 2), _rank_body(0))
	miss.set("fail_get", {"transport": "ok", "code": 404,
		"body": "missing"})
	var miss_hall: RefCounted = HALL_SCRIPT.new()
	var miss_transport: RefCounted = _new_transport(miss)
	var miss_first: Dictionary = {}
	var miss_second: Dictionary = {}
	_self_rank_into(miss_first, miss_hall, miss_transport, PUBLIC_ID,
		100000)
	_self_rank_into(miss_second, miss_hall, miss_transport, PUBLIC_ID,
		100000)
	_expect_true(await _await_box(miss_first), "the unranked owner lands")
	_expect_true(await _await_box(miss_second),
		"the unranked waiter lands")
	var miss_result: Dictionary = miss_second.get("result", {})
	_expect_equal(miss_result.get("status", ""), "unranked",
		"the waiter shares unranked")
	_expect_equal(miss_result.get("rank", -1), 0,
		"the shared unranked outcome invents no #1")


func _test_self_rank_ticket_retired_cleanly() -> void:
	var knight: String = "res://resources/heroes/knight.tres"
	var other: String = "MB-" + "f".repeat(32)
	var inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	inner.call("queue_ok", "{}")
	var delayed: RefCounted = _DelayRoutingSender.new(self, inner,
		_row_body(100, knight, 2), _rank_body(0))
	delayed.set("delay_frames", 30)
	var hall: RefCounted = HALL_SCRIPT.new()
	hall.call("set_account", PUBLIC_ID)
	var transport: RefCounted = _new_transport(delayed)
	var owner_box: Dictionary = {}
	var waiter_box: Dictionary = {}
	_self_rank_into(owner_box, hall, transport, PUBLIC_ID, 100000)
	_self_rank_into(waiter_box, hall, transport, PUBLIC_ID, 100000)
	for _index in 2:
		await process_frame
	_expect_false(owner_box.has("result"),
		"the owner is still in flight before the switch")
	hall.call("set_account", other)
	_expect_true(await _await_box(waiter_box, 10),
		"the retired waiter lands promptly, not after the delay")
	var retired: Dictionary = waiter_box.get("result", {})
	_expect_equal(retired.get("status", ""), "cancelled",
		"the retired waiter reports cancelled")
	_expect_equal(retired.get("code", ""), "account-changed",
		"the retirement names the switch")
	_expect_true(await _await_box(owner_box),
		"the retired owner still lands")
	_expect_equal((owner_box.get("result", {}) as Dictionary).get(
		"status", ""), "cancelled",
		"the late owner reply reports cancelled, never a rank")
	# The new account refreshes live on a fresh ticket right away.
	var rebound_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	rebound_inner.call("queue_ok", "{}")
	rebound_inner.call("queue_ok", "{}")
	var rebound: RefCounted = _DelayRoutingSender.new(self,
		rebound_inner, _row_body_for(other, 700, knight, 4),
		_rank_body(2))
	var rebound_rank: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(rebound), other, 100000)
	_expect_equal(rebound_rank.get("score", 0), 700,
		"the new account reads its own best after the switch")
	_expect_equal(rebound_rank.get("rank", 0), 3,
		"the new account ranks its own best after the switch")
	# And back again: A to B to A strands no lock.
	hall.call("set_account", PUBLIC_ID)
	var home_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	home_inner.call("queue_ok", "{}")
	home_inner.call("queue_ok", "{}")
	var home: RefCounted = _DelayRoutingSender.new(self, home_inner,
		_row_body(100, knight, 2), _rank_body(0))
	var home_rank: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(home), PUBLIC_ID, 200000)
	_expect_equal(home_rank.get("status", ""), "ok",
		"the round trip home refreshes live")
	_expect_equal(home_rank.get("rank", 0), 1,
		"the round trip home ranks the owned best first")

	# A cache invalidation retires the whole refresh while the owner
	# still measures: waiter and owner both report cancelled, the late
	# reply writes no cache and starts no count query, and the next
	# refresh re-reads live at once (the window reset with the caches).
	var clear_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	for _index in 4:
		clear_inner.call("queue_ok", "{}")
	var clearer: RefCounted = _DelayRoutingSender.new(self, clear_inner,
		_row_body(100, knight, 2), _rank_body(0))
	clearer.set("delay_frames", 30)
	var clear_hall: RefCounted = HALL_SCRIPT.new()
	var clear_transport: RefCounted = _new_transport(clearer)
	var clear_owner: Dictionary = {}
	var clear_waiter: Dictionary = {}
	_self_rank_into(clear_owner, clear_hall, clear_transport, PUBLIC_ID,
		100000)
	_self_rank_into(clear_waiter, clear_hall, clear_transport,
		PUBLIC_ID, 100000)
	for _index in 2:
		await process_frame
	clear_hall.call("clear_cache")
	_expect_true(await _await_box(clear_waiter, 10),
		"the invalidated waiter lands promptly")
	_expect_equal((clear_waiter.get("result", {}) as Dictionary).get(
		"code", ""), "stale-reply",
		"the invalidation names the stale ticket")
	_expect_true(await _await_box(clear_owner),
		"the invalidated owner still lands")
	var clear_result: Dictionary = clear_owner.get("result", {})
	_expect_equal(clear_result.get("status", ""), "cancelled",
		"the invalidated owner reports cancelled, never its stale ok")
	_expect_equal(clear_result.get("code", ""), "stale-reply",
		"the invalidated owner names the stale ticket")
	_expect_equal(_rank_post_count(clear_inner), 0,
		"the retired owner starts no count query")
	var reread: Dictionary = await clear_hall.call("fetch_self_rank",
		clear_transport, PUBLIC_ID, 100000)
	_expect_equal(reread.get("source", ""), "live",
		"the next refresh re-reads live at once past the invalidation")
	_expect_equal(reread.get("score", 0), 100,
		"the re-read measures the current row")
	_expect_equal(_own_get_count(clear_inner), 2,
		"one discarded late read plus one live re-read")


## A retired owner must never restore stale standing: when the old
## Knight-100 read lands after a fresh Dancer-600 pair completed, the
## old caller reports cancelled and every cache keeps the newer pair.
func _test_self_rank_retired_owner_writes_nothing() -> void:
	var knight: String = "res://resources/heroes/knight.tres"
	var dancer: String = "res://resources/heroes/dancer.tres"
	var other: String = "MB-" + "f".repeat(32)
	# Retired during the own read: the late reply is discarded whole.
	var old_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	old_inner.call("queue_ok", "{}")
	var old_delayed: RefCounted = _DelayRoutingSender.new(self,
		old_inner, _row_body(100, knight, 2), _rank_body(0))
	old_delayed.set("delay_frames", 30)
	var hall: RefCounted = HALL_SCRIPT.new()
	hall.call("set_account", PUBLIC_ID)
	var old_box: Dictionary = {}
	_self_rank_into(old_box, hall, _new_transport(old_delayed),
		PUBLIC_ID, 100000)
	for _index in 2:
		await process_frame
	_expect_equal(_own_get_count(old_inner), 0,
		"the old read is still in flight at the switch")
	hall.call("set_account", other)
	hall.call("set_account", PUBLIC_ID)
	var fresh_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	fresh_inner.call("queue_ok", _row_body(600, dancer, 6))
	fresh_inner.call("queue_ok", _rank_body(1))
	var fresh: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(fresh_inner), PUBLIC_ID, 100000)
	_expect_equal(fresh.get("score", 0), 600,
		"the fresh pair completes first with the new best")
	_expect_false(old_box.has("result"),
		"the old owner is still pending past the fresh completion")
	_expect_true(await _await_box(old_box),
		"the retired old owner still lands")
	var old_result: Dictionary = old_box.get("result", {})
	_expect_equal(old_result.get("status", ""), "cancelled",
		"the retired old owner reports cancelled")
	_expect_equal(old_result.get("code", ""), "stale-reply",
		"the round trip home names the stale ticket, not the account")
	_expect_equal(_own_get_count(old_inner), 1,
		"the late own read still returns, then is discarded")
	_expect_equal(_rank_post_count(old_inner), 0,
		"the retired owner starts no count query")
	var throttled: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(fresh_inner), PUBLIC_ID, 101000)
	_expect_equal(throttled.get("score", 0), 600,
		"the throttled serve keeps the newer best")
	_expect_equal(throttled.get("hero", ""), dancer,
		"the throttled serve keeps the newer hero")
	var fresh_calls: int = (fresh_inner.get("calls") as Array).size()
	var old_calls: int = (old_inner.get("calls") as Array).size()
	var crossed: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(fresh_inner), PUBLIC_ID, 106000)
	_expect_equal(crossed.get("source", ""), "cache",
		"the window crossing serves the kept pair from cache")
	_expect_equal(crossed.get("score", 0), 600,
		"the kept pair is the newer best, not the stale row")
	_expect_equal((fresh_inner.get("calls") as Array).size(),
		fresh_calls, "the kept pair fires no new request")
	_expect_equal((old_inner.get("calls") as Array).size(), old_calls,
		"the retired owner fires nothing more after landing")

	# Retired during the count: the started query's answer is dropped
	# and the newer pair still stands.
	var count_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	count_inner.call("queue_ok", "{}")
	count_inner.call("queue_ok", "{}")
	var count_delayed: RefCounted = _DelayRoutingSender.new(self,
		count_inner, _row_body(100, knight, 2), _rank_body(0))
	count_delayed.set("delay_frames", 30)
	var count_hall: RefCounted = HALL_SCRIPT.new()
	count_hall.call("set_account", PUBLIC_ID)
	var count_box: Dictionary = {}
	_self_rank_into(count_box, count_hall,
		_new_transport(count_delayed), PUBLIC_ID, 100000)
	var post_away: bool = false
	for _index in 60:
		if _own_get_count(count_inner) == 1:
			post_away = true
			break
		await process_frame
	_expect_true(post_away,
		"the old count query leaves before the switch")
	count_hall.call("set_account", other)
	count_hall.call("set_account", PUBLIC_ID)
	var count_fresh_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	count_fresh_inner.call("queue_ok", _row_body(600, dancer, 6))
	count_fresh_inner.call("queue_ok", _rank_body(1))
	var count_fresh: Dictionary = await count_hall.call(
		"fetch_self_rank", _new_transport(count_fresh_inner),
		PUBLIC_ID, 100000)
	_expect_equal(count_fresh.get("score", 0), 600,
		"the fresh pair completes while the old count is away")
	_expect_true(await _await_box(count_box),
		"the retired count owner still lands")
	_expect_equal((count_box.get("result", {}) as Dictionary).get(
		"status", ""), "cancelled",
		"the retired count owner reports cancelled")
	_expect_equal(_rank_post_count(count_inner), 1,
		"only the pre-retirement count query ever leaves")
	_expect_equal(_rank_post_count(count_fresh_inner), 1,
		"the fresh pair counts once")
	var count_kept: Dictionary = await count_hall.call(
		"fetch_self_rank", _new_transport(count_fresh_inner),
		PUBLIC_ID, 101000)
	_expect_equal(count_kept.get("score", 0), 600,
		"the kept pair survives the late count answer")
	_expect_equal(count_kept.get("hero", ""), dancer,
		"the kept hero survives the late count answer")


## Same-account invalidation keeps the newer pair: a best submission
## retires the old read, the fresh refresh measures the new best, and
## the late old reply changes nothing. A late old completion also
## never releases a newer ticket that is still pending.
func _test_self_rank_invalidation_keeps_newer_pair() -> void:
	var knight: String = "res://resources/heroes/knight.tres"
	var dancer: String = "res://resources/heroes/dancer.tres"
	var old_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	old_inner.call("queue_ok", "{}")
	var old_delayed: RefCounted = _DelayRoutingSender.new(self,
		old_inner, _row_body(100, knight, 2), _rank_body(0))
	old_delayed.set("delay_frames", 30)
	var hall: RefCounted = HALL_SCRIPT.new()
	hall.call("set_account", PUBLIC_ID)
	var old_box: Dictionary = {}
	_self_rank_into(old_box, hall, _new_transport(old_delayed),
		PUBLIC_ID, 100000)
	for _index in 2:
		await process_frame
	var submit_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	submit_inner.call("queue_reply", {"transport": "ok", "code": 404,
		"body": "missing"})
	submit_inner.call("queue_ok", "{\"writeResults\":[{}]}")
	var submitted: Dictionary = await hall.call("submit_best",
		_new_transport(submit_inner), PUBLIC_ID, dancer, 600, 6,
		"4.0.0")
	_expect_equal(submitted.get("status", ""), "ok",
		"the new best submits while the old read is away")
	var fresh_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	fresh_inner.call("queue_ok", _row_body(600, dancer, 6))
	fresh_inner.call("queue_ok", _rank_body(1))
	var fresh: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(fresh_inner), PUBLIC_ID, 100000)
	_expect_equal(fresh.get("score", 0), 600,
		"the fresh pair measures the submitted best")
	_expect_true(await _await_box(old_box),
		"the invalidated old owner still lands")
	var old_result: Dictionary = old_box.get("result", {})
	_expect_equal(old_result.get("status", ""), "cancelled",
		"the invalidated old owner reports cancelled")
	_expect_equal(old_result.get("code", ""), "stale-reply",
		"the invalidation names the stale ticket")
	_expect_equal(_rank_post_count(old_inner), 0,
		"the invalidated owner starts no count query")
	var kept: Dictionary = await hall.call("fetch_self_rank",
		_new_transport(fresh_inner), PUBLIC_ID, 101000)
	_expect_equal(kept.get("score", 0), 600,
		"the newer pair survives the late old reply")
	_expect_equal(kept.get("hero", ""), dancer,
		"the newer hero survives the late old reply")

	# The old ticket completes while a newer ticket for the same
	# account is still pending: the old caller is cancelled and the
	# newer ticket (and its waiter) are untouched.
	var stale_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	stale_inner.call("queue_ok", "{}")
	var stale_delayed: RefCounted = _DelayRoutingSender.new(self,
		stale_inner, _row_body(100, knight, 2), _rank_body(0))
	stale_delayed.set("delay_frames", 30)
	var pending_hall: RefCounted = HALL_SCRIPT.new()
	var stale_box: Dictionary = {}
	_self_rank_into(stale_box, pending_hall,
		_new_transport(stale_delayed), PUBLIC_ID, 100000)
	for _index in 2:
		await process_frame
	pending_hall.call("clear_cache")
	var new_inner: RefCounted = FAKE_SENDER_SCRIPT.new()
	new_inner.call("queue_ok", "{}")
	new_inner.call("queue_ok", "{}")
	var new_delayed: RefCounted = _DelayRoutingSender.new(self,
		new_inner, _row_body(600, dancer, 6), _rank_body(1))
	new_delayed.set("delay_frames", 30)
	var new_box: Dictionary = {}
	var new_waiter: Dictionary = {}
	_self_rank_into(new_box, pending_hall,
		_new_transport(new_delayed), PUBLIC_ID, 100000)
	_self_rank_into(new_waiter, pending_hall,
		_new_transport(new_delayed), PUBLIC_ID, 100000)
	_expect_true(await _await_box(stale_box),
		"the old ticket still lands")
	_expect_equal((stale_box.get("result", {}) as Dictionary).get(
		"status", ""), "cancelled",
		"the old ticket reports cancelled")
	_expect_false(new_box.has("result"),
		"the newer ticket is still pending at the old completion")
	_expect_true(await _await_box(new_box),
		"the newer ticket completes after the old one")
	_expect_true(await _await_box(new_waiter),
		"the newer ticket's waiter is not stranded")
	_expect_equal((new_box.get("result", {}) as Dictionary).get(
		"score", 0), 600,
		"the newer ticket measures the newer best")
	_expect_equal((new_waiter.get("result", {}) as Dictionary).get(
		"score", 0), 600,
		"the newer waiter shares the newer best, not the old reply")
	_expect_equal(_own_get_count(new_inner), 1,
		"the newer ticket reads once")
	_expect_equal(_rank_post_count(new_inner), 1,
		"the newer ticket counts once")


func _self_rank_into(box: Dictionary, hall: RefCounted,
		transport: RefCounted, public_id: String,
		now_msec: int) -> void:
	box["result"] = await hall.call("fetch_self_rank", transport,
		public_id, now_msec)


func _await_box(box: Dictionary, frames: int = 240) -> bool:
	for _index in frames:
		if box.has("result"):
			return true
		await process_frame
	return box.has("result")


func _test_owned_deletion() -> void:
	var sender: RefCounted = FAKE_SENDER_SCRIPT.new()
	sender.call("queue_ok", "{}")
	var hall: RefCounted = HALL_SCRIPT.new()
	var result: Dictionary = await hall.call("delete_record",
		_new_transport(sender), PUBLIC_ID)
	_expect_equal(result.get("status", ""), "ok", "owned deletion ok")
	_expect_equal(sender.call("last_call").get("method", ""), "DELETE",
		"deletion uses DELETE")
	_expect_true(str(sender.call("last_call").get("url", "")).contains(
		"mb_hall_v1/%s" % PUBLIC_ID), "deletion targets the owned row")


func _expect_true(value: bool, label: String) -> void:
	_checked += 1
	if not value:
		_failed += 1
		printerr("  expected true — ", label)


func _expect_false(value: bool, label: String) -> void:
	_checked += 1
	if value:
		_failed += 1
		printerr("  expected false — ", label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual != expected:
		_failed += 1
		printerr("  expected ", expected, " got ", actual, " — ", label)


## Fake sender that holds every call for a few frames — the deterministic
## stand-in for a slow transport — then answers Hall reads from fixed
## bodies by URL while the inner fake still records every call.
class _DelayRoutingSender:
	extends RefCounted
	var _tree: SceneTree
	var _inner: RefCounted
	var _row_body: String
	var _rank_body: String
	var delay_frames: int = 5
	var in_flight: int = 0
	var max_in_flight: int = 0
	## Optional routed failure envelopes for the own read and the count
	## query. Empty means the fixed ok bodies above.
	var fail_get: Dictionary = {}
	var fail_post: Dictionary = {}

	func _init(tree: SceneTree, inner: RefCounted, row_body: String,
			rank_body: String) -> void:
		_tree = tree
		_inner = inner
		_row_body = row_body
		_rank_body = rank_body

	func sender_callable() -> Callable:
		return Callable(self, "send")

	func send(method: String, url: String, headers: Dictionary,
			body: String) -> Dictionary:
		in_flight += 1
		max_in_flight = maxi(max_in_flight, in_flight)
		for _index in delay_frames:
			await _tree.process_frame
		in_flight -= 1
		var recorded: Dictionary = await _inner.call("send", method, url,
			headers, body)
		if str(url).contains("runAggregationQuery"):
			if not fail_post.is_empty():
				return fail_post.duplicate(true)
			return {"transport": "ok", "code": 200, "body": _rank_body}
		if str(method) == "GET" and str(url).contains("mb_hall_v1/"):
			if not fail_get.is_empty():
				return fail_get.duplicate(true)
			return {"transport": "ok", "code": 200, "body": _row_body}
		return recorded
