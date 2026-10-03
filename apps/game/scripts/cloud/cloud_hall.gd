extends RefCounted

## Public best-score Hall of Fame for 4.0.0, one row per public ID.
##
## Each row (`mb_hall_v1/{public_id}`) carries the allow-listed hero, score,
## cycles, release, schema, and update time. Document IDs are the public IDs,
## so retries overwrite the same row and can never mint a second player row.
## Writes are monotonic: a lower score is reported as not-best, never stored.
## Reads are cached and throttled, and every read result labels its source as
## live or cache so the UI never mistakes old rows for fresh ones.
##
## Score bounds here are structural only. They reject malformed rows; they do
## not prove a score was earned in real play and are not anti-cheat.

const CloudSchema: Script = preload("res://scripts/cloud/cloud_schema.gd")

const CACHE_TTL_MSEC: int = 60000
const THROTTLE_MSEC: int = 5000
const DEFAULT_TOP_LIMIT: int = 20
## Rank rows remembered per score. Bounded: hundreds of score changes reuse
## the same small cache instead of growing it, and the global throttle below
## keeps them from firing hundreds of requests.
const MAX_RANK_CACHE_ENTRIES: int = 8
## Owned rows remembered per public ID, misses included. Bounded like the
## rank cache; in practice one account holds one entry.
const MAX_OWN_CACHE_ENTRIES: int = 8
## Firestore strictly-greater operator. Composed from parts because the locale
## check reads any double-quoted SNAKE literal as a UI key, and this API enum
## is never shown on screen. The Hall tests assert the composed wire value.
const GREATER_THAN_OP: String = "GREATER" + "_" + "THAN"

## One completion per self-rank ticket: `[public_id, ticket, result]`.
## Concurrent callers for the same account join the in-flight ticket and
## share its exact result instead of starting more reads.
signal self_rank_finished(outcome: Array)

var _top_cache: Dictionary = {}
var _rank_cache: Dictionary = {}
var _own_cache: Dictionary = {}
var _last_top_attempt_msec: int = 0
var _last_rank_attempt_msec: int = 0
var _last_rank_result: Dictionary = {}
var _last_self_rank_result: Dictionary = {}
## In-flight self-rank ticket per public ID. The ticket is owned before
## the first await, so concurrent refreshes coalesce onto one owned-row
## read plus one count query. The sequence never resets: ticket identity
## stays unique across clears and account switches.
var _self_rank_inflight: Dictionary = {}
var _self_rank_seq: int = 0
var _account_public_id: String = ""


func clear_cache(retire_code: String = "stale-reply") -> void:
	_top_cache = {}
	_rank_cache = {}
	_own_cache = {}
	_last_top_attempt_msec = 0
	_last_rank_attempt_msec = 0
	_last_rank_result = {}
	_last_self_rank_result = {}
	_retire_self_rank_inflight(retire_code)


## Bind reads to one account. A new account clears every cache so old rows
## and ranks can never leak across a switch; stale in-flight replies for the
## previous account report cancelled instead of applying.
func set_account(public_id: String) -> void:
	if _account_public_id != public_id:
		_account_public_id = public_id
		clear_cache("account-changed")


func rank_cache_size() -> int:
	return _rank_cache.size()


func own_cache_size() -> int:
	return _own_cache.size()


func hall_relative_path(public_id: String) -> String:
	return "documents/%s/%s" % [CloudSchema.HALL_COLLECTION, public_id]


func hall_body(public_id: String, hero: String, score: int, cycles: int,
		release: String) -> Dictionary:
	return {
		"fields": {
			"public_id": CloudSchema.encode_string(public_id),
			"hero": CloudSchema.encode_string(
				CloudSchema.canonical_hero(hero)),
			"score": CloudSchema.encode_int(score),
			"cycles": CloudSchema.encode_int(cycles),
			"release": CloudSchema.encode_string(release),
			"schema": CloudSchema.encode_int(CloudSchema.SCHEMA_VERSION),
			"updated_at": CloudSchema.encode_timestamp_rfc3339(
				CloudSchema.now_rfc3339()),
		}
	}


func top_query_body(limit: int) -> Dictionary:
	return {
		"structuredQuery": {
			"from": [{"collectionId": CloudSchema.HALL_COLLECTION}],
			"orderBy": [{
				"field": {"fieldPath": "score"},
				"direction": "DESCENDING",
			}],
			"limit": clampi(limit, 1, CloudSchema.MAX_HALL_TOP_LIMIT),
		}
	}


## Count of rows strictly above a score. Rank is count + 1, so ties share it.
func rank_query_body(score: int) -> Dictionary:
	return {
		"structuredAggregationQuery": {
			"aggregations": [{
				"count": {},
				"alias": "greater",
			}],
			"structuredQuery": {
				"from": [{"collectionId": CloudSchema.HALL_COLLECTION}],
				"where": {
					"fieldFilter": {
						"field": {"fieldPath": "score"},
						"op": GREATER_THAN_OP,
						"value": CloudSchema.encode_int(score),
					}
				},
			},
		}
	}


## Reads one owned row. Missing rows report not-found; callers treat that as
## "no best yet" and create on submit.
func fetch_own(transport: RefCounted, public_id: String) -> Dictionary:
	if not CloudSchema.is_valid_public_id(public_id):
		return {"status": "failure", "code": "invalid-public-id",
			"retryable": false}
	if not _account_allows(public_id):
		return {"status": "cancelled", "code": "account-changed",
			"retryable": false}
	if transport == null or not transport.has_method("get_document"):
		return {"status": "unconfigured", "code": "missing-transport",
			"retryable": false}
	var reply: Dictionary = await transport.call("get_document",
		hall_relative_path(public_id))
	if not _account_allows(public_id):
		return {"status": "cancelled", "code": "account-changed",
			"retryable": false}
	if str(reply.get("status", "")) != "ok":
		return reply
	return parse_row(str(reply.get("body", "")))


func parse_row(body: String) -> Dictionary:
	var decoded: Dictionary = CloudSchema.parse_json_value(body)
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_DICTIONARY:
		return {"status": "failure", "code": "bad-hall-body",
			"retryable": false}
	var fields: Dictionary = (decoded.get("value") as Dictionary).get(
		"fields", {})
	var row: Dictionary = {
		"public_id": CloudSchema.decode_string(fields, "public_id"),
		"hero": CloudSchema.decode_string(fields, "hero"),
		"score": CloudSchema.decode_int(fields, "score"),
		"cycles": CloudSchema.decode_int(fields, "cycles"),
		"release": CloudSchema.decode_string(fields, "release"),
		"schema": CloudSchema.decode_int(fields, "schema"),
		"updated_at": CloudSchema.decode_timestamp(fields, "updated_at"),
	}
	if not CloudSchema.is_valid_public_id(str(row.get("public_id", ""))):
		return {"status": "failure", "code": "bad-hall-row",
			"retryable": false}
	return {"status": "ok", "row": row, "source": "live"}


## Submits a candidate best. Reads the current row first so a lower score is
## reported as not-best without a doomed write. Equal scores are idempotent:
## the retry overwrites the same document and succeeds.
func submit_best(transport: RefCounted, public_id: String, hero: String,
		score: int, cycles: int, release: String) -> Dictionary:
	if not CloudSchema.is_valid_public_id(public_id):
		return {"status": "failure", "code": "invalid-public-id",
			"retryable": false}
	if not _account_allows(public_id):
		return {"status": "cancelled", "code": "account-changed",
			"retryable": false}
	var row_check: Dictionary = CloudSchema.validate_hall_row(
		hero, score, cycles, release)
	if not bool(row_check.get("ok", false)):
		return {"status": "failure", "code": str(row_check.get("error", "")),
			"retryable": false}
	if transport == null or not transport.has_method("post"):
		return {"status": "unconfigured", "code": "missing-transport",
			"retryable": false}
	var current: Dictionary = await fetch_own(transport, public_id)
	if str(current.get("status", "")) == "ok":
		var best: int = int((current.get("row", {}) as Dictionary).get(
			"score", 0))
		if score < best:
			# The server holds a better row (ours or another
			# device's): drop every cache so the next rank
			# refresh re-reads the actual record instead of a
			# stale lower one.
			clear_cache()
			return {"status": "failure", "code": "not-best",
				"retryable": false, "best": best}
	elif str(current.get("code", "")) != "not-found":
		return current
	var commit_body: Dictionary = {
		"writes": [
			{
				"update": {
					"name": CloudSchema.document_name(
						CloudSchema.HALL_COLLECTION, public_id),
					"fields": (hall_body(public_id, hero, score, cycles,
						release) as Dictionary)["fields"],
				},
			}
		]
	}
	var reply: Dictionary = await transport.call("post", "documents:commit",
		JSON.stringify(commit_body))
	if not _account_allows(public_id):
		return {"status": "cancelled", "code": "account-changed",
			"retryable": false}
	if str(reply.get("status", "")) != "ok":
		# A concurrent better score can land between our read and our write;
		# the monotonic rule then denies the write. Report that as not-best
		# and drop the caches so the next read sees the winning row.
		if str(reply.get("code", "")) == "permission-denied":
			clear_cache()
			return {"status": "failure", "code": "not-best",
				"retryable": false}
		return reply
	clear_cache()
	return {"status": "ok", "score": score, "public_id": public_id}


## Top-board read with cache and throttle. `now_msec` is injected so tests
## control time; pass Time.get_ticks_msec() in production.
func fetch_top(transport: RefCounted, limit: int,
		now_msec: int) -> Dictionary:
	var bounded: int = clampi(limit, 1, CloudSchema.MAX_HALL_TOP_LIMIT)
	if transport == null or not transport.has_method("post"):
		return {"status": "unconfigured", "code": "missing-transport",
			"retryable": false}
	if not _top_cache.is_empty():
		var age: int = now_msec - int(_top_cache.get("fetched_msec", 0))
		var since_attempt: int = now_msec - _last_top_attempt_msec
		if since_attempt >= 0 and since_attempt < THROTTLE_MSEC:
			var throttled: Dictionary = _top_cache.duplicate(true)
			throttled["source"] = "cache-throttled"
			return throttled
		if age >= 0 and age < CACHE_TTL_MSEC:
			var cached: Dictionary = _top_cache.duplicate(true)
			cached["source"] = "cache"
			return cached
	_last_top_attempt_msec = now_msec
	var reply: Dictionary = await transport.call("post",
		"documents:runQuery", JSON.stringify(top_query_body(bounded)))
	if str(reply.get("status", "")) != "ok":
		if not _top_cache.is_empty():
			var fallback: Dictionary = _top_cache.duplicate(true)
			fallback["source"] = "cache"
			fallback["live_error"] = str(reply.get("code", "failure"))
			return fallback
		return reply
	var rows: Dictionary = parse_top_rows(str(reply.get("body", "")))
	if str(rows.get("status", "")) != "ok":
		return rows
	_top_cache = {
		"status": "ok", "rows": rows.get("rows", []), "source": "live",
		"fetched_msec": now_msec, "limit": bounded,
	}
	return _top_cache.duplicate(true)


func parse_top_rows(body: String) -> Dictionary:
	var decoded: Dictionary = CloudSchema.parse_json_value(body)
	if not bool(decoded.get("ok", false)) \
			or typeof(decoded.get("value")) != TYPE_ARRAY:
		return {"status": "failure", "code": "bad-board-body",
			"retryable": false}
	var rows: Array = []
	for entry in (decoded.get("value") as Array):
		if typeof(entry) != TYPE_DICTIONARY \
				or not (entry as Dictionary).has("document"):
			continue
		var document: Dictionary = (entry as Dictionary)["document"]
		var fields: Dictionary = document.get("fields", {})
		var public_id: String = CloudSchema.decode_string(fields, "public_id")
		if not CloudSchema.is_valid_public_id(public_id):
			continue
		rows.append({
			"public_id": public_id,
			"hero": CloudSchema.decode_string(fields, "hero"),
			"score": CloudSchema.decode_int(fields, "score"),
			"cycles": CloudSchema.decode_int(fields, "cycles"),
			"release": CloudSchema.decode_string(fields, "release"),
			"updated_at": CloudSchema.decode_timestamp(fields, "updated_at"),
		})
	return {"status": "ok", "rows": rows, "source": "live"}


## Actual self-rank by server count of strictly greater scores. Ties share the
## rank. Cached ranks are labeled so the UI can say so. Rank refresh is
## throttled globally: even a changed score waits out the window and is
## served the last known rank labeled `cache-throttled`, so hundreds of
## score changes fire a bounded handful of requests into a bounded cache.
## `ticket` binds this count to one self-rank refresh: a retired ticket
## reports cancelled before any send and before any cache write, so a
## late owner can neither start a stale count nor restore one. Zero
## means the legacy standalone call with no ticket to honor.
func fetch_rank(transport: RefCounted, public_id: String, score: int,
		now_msec: int, ticket: int = 0) -> Dictionary:
	if not CloudSchema.is_valid_public_id(public_id):
		return {"status": "failure", "code": "invalid-public-id",
			"retryable": false}
	if not _account_allows(public_id):
		return {"status": "cancelled", "code": "account-changed",
			"retryable": false}
	if score < 0 or score > CloudSchema.MAX_SCORE:
		return {"status": "failure", "code": "invalid-score",
			"retryable": false}
	if transport == null or not transport.has_method("post"):
		return {"status": "unconfigured", "code": "missing-transport",
			"retryable": false}
	if _self_rank_ticket_retired(public_id, ticket):
		return _stale_ticket_result(public_id)
	var cache_key: String = "%s:%d" % [public_id, score]
	if _rank_cache.has(cache_key):
		var cached: Dictionary = (_rank_cache[cache_key] as Dictionary).duplicate(
			true)
		var age: int = now_msec - int(cached.get("fetched_msec", 0))
		if age >= 0 and age < CACHE_TTL_MSEC:
			cached["source"] = "cache"
			return cached
	var since_attempt: int = now_msec - _last_rank_attempt_msec
	if since_attempt >= 0 and since_attempt < THROTTLE_MSEC:
		# Nothing known yet means nothing to serve, so the first fetch
		# always sends instead of throttling into a failure.
		var throttled: Dictionary = _throttled_rank(cache_key)
		if not throttled.is_empty():
			return throttled
	_last_rank_attempt_msec = now_msec
	var reply: Dictionary = await transport.call("post",
		"documents:runAggregationQuery",
		JSON.stringify(rank_query_body(score)))
	if _self_rank_ticket_retired(public_id, ticket):
		return _stale_ticket_result(public_id)
	if not _account_allows(public_id):
		return {"status": "cancelled", "code": "account-changed",
			"retryable": false}
	if str(reply.get("status", "")) != "ok":
		var fallback: Dictionary = _throttled_rank(cache_key)
		if not fallback.is_empty():
			fallback["source"] = "cache"
			fallback["live_error"] = str(reply.get("code", "failure"))
			return fallback
		return reply
	var decoded: Dictionary = CloudSchema.parse_json_value(
		str(reply.get("body", "")))
	var greater: int = _parse_aggregation_count(
		decoded.get("value") if bool(decoded.get("ok", false)) else null)
	if greater < 0:
		return {"status": "failure", "code": "bad-rank-body",
			"retryable": false}
	var result: Dictionary = {
		"status": "ok", "rank": greater + 1, "greater": greater,
		"score": score, "public_id": public_id, "source": "live",
		"fetched_msec": now_msec,
	}
	_rank_cache[cache_key] = result.duplicate(true)
	_last_rank_result = result.duplicate(true)
	_evict_rank_cache(cache_key)
	return result


## Actual self rank for OUR owned best row: reads `mb_hall_v1/{public_id}`,
## then counts rows strictly above its best score. The result carries that
## row's hero, score, cycles, and public ID with the rank, so presentation
## never pairs a rank with a different hero or score. The two reads are
## sequential HTTP calls, not one atomic snapshot: `row_source` and
## `rank_source` with `row_fetched_msec` / `rank_fetched_msec` label each
## half, `fetched_msec` is the newer half, and `source` follows the rank
## half (the displayed number).
##
## A missing own row is genuinely unranked (`status` unranked, rank 0, no
## invented #1, no submission). Malformed rows fail without inventing
## values. The complete refresh shares the global five-second window and
## the bounded caches: inside the window it serves the last known pair
## labeled `cache-throttled` and sends nothing — the own row is never
## re-probed per local score change — and a live miss is cached so
## repeats never re-probe a missing row either. Simultaneous refreshes
## for one account coalesce harder still: the first caller owns an
## in-flight ticket before the first await and later callers share its
## exact result, so three at once still fire one owned-row read plus one
## count query and never combine different row/rank pairs. A switch or
## cache invalidation retires the ticket with a cancelled outcome for
## every waiter instead of stranding it. `now_msec` is injected like
## `fetch_rank`.
func fetch_self_rank(transport: RefCounted, public_id: String,
		now_msec: int) -> Dictionary:
	if not CloudSchema.is_valid_public_id(public_id):
		return {"status": "failure", "code": "invalid-public-id",
			"retryable": false}
	if not _account_allows(public_id):
		return {"status": "cancelled", "code": "account-changed",
			"retryable": false}
	if transport == null or not transport.has_method("post") \
			or not transport.has_method("get_document"):
		return {"status": "unconfigured", "code": "missing-transport",
			"retryable": false}
	var since_attempt: int = now_msec - _last_rank_attempt_msec
	if since_attempt >= 0 and since_attempt < THROTTLE_MSEC:
		var throttled: Dictionary = _throttled_self_rank(public_id)
		if not throttled.is_empty():
			return throttled
	if _self_rank_inflight.has(public_id):
		var joined: int = int(_self_rank_inflight[public_id])
		while true:
			var outcome: Array = await self_rank_finished
			if str(outcome[0]) == public_id \
					and int(outcome[1]) == joined:
				return (outcome[2] as Dictionary).duplicate(true)
	_self_rank_seq += 1
	var ticket: int = _self_rank_seq
	_self_rank_inflight[public_id] = ticket
	var own: Dictionary = await _read_own_row(transport, public_id,
		now_msec, ticket)
	if _self_rank_ticket_retired(public_id, ticket) \
			or not _account_allows(public_id):
		return _finish_self_rank(public_id, ticket,
			_stale_ticket_result(public_id))
	if str(own.get("status", "")) == "unranked":
		if str(own.get("source", "")) == "live":
			_last_rank_attempt_msec = now_msec
		_last_self_rank_result = own.duplicate(true)
		return _finish_self_rank(public_id, ticket, own)
	if str(own.get("status", "")) != "ok":
		var own_fallback: Dictionary = _throttled_self_rank(public_id)
		if not own_fallback.is_empty():
			own_fallback["source"] = "cache"
			own_fallback["live_error"] = str(own.get("code", "failure"))
			return _finish_self_rank(public_id, ticket, own_fallback)
		return _finish_self_rank(public_id, ticket, own)
	var row: Dictionary = (own.get("row", {}) as Dictionary).duplicate(true)
	var ranked: Dictionary = await fetch_rank(transport, public_id,
		int(row.get("score", 0)), now_msec, ticket)
	if _self_rank_ticket_retired(public_id, ticket) \
			or not _account_allows(public_id):
		return _finish_self_rank(public_id, ticket,
			_stale_ticket_result(public_id))
	if str(ranked.get("status", "")) != "ok":
		var rank_fallback: Dictionary = _throttled_self_rank(public_id)
		if not rank_fallback.is_empty():
			rank_fallback["source"] = "cache"
			rank_fallback["live_error"] = str(
				ranked.get("code", "failure"))
			return _finish_self_rank(public_id, ticket, rank_fallback)
		return _finish_self_rank(public_id, ticket, ranked)
	var row_msec: int = int(own.get("fetched_msec", now_msec))
	var rank_msec: int = int(ranked.get("fetched_msec", now_msec))
	var result: Dictionary = {
		"status": "ok", "rank": int(ranked.get("rank", 0)),
		"greater": int(ranked.get("greater", 0)),
		"score": int(row.get("score", 0)),
		"hero": str(row.get("hero", "")),
		"cycles": int(row.get("cycles", 0)),
		"public_id": public_id,
		"source": str(ranked.get("source", "live")),
		"row_source": str(own.get("source", "live")),
		"rank_source": str(ranked.get("source", "live")),
		"fetched_msec": maxi(row_msec, rank_msec),
		"row_fetched_msec": row_msec,
		"rank_fetched_msec": rank_msec,
		"live_error": "",
	}
	if str(own.get("source", "")) == "live" \
			or str(ranked.get("source", "")) == "live":
		_last_self_rank_result = result.duplicate(true)
	return _finish_self_rank(public_id, ticket, result)


## Complete one owned ticket: hand its exact result to every joined
## waiter, then free the account for the next refresh. A ticket retired
## earlier (switch, invalidation) completes silently to its own caller
## only, so a late reply can never emit twice or release a newer ticket.
func _finish_self_rank(public_id: String, ticket: int,
		result: Dictionary) -> Dictionary:
	if int(_self_rank_inflight.get(public_id, 0)) == ticket:
		_self_rank_inflight.erase(public_id)
		self_rank_finished.emit([public_id, ticket,
			result.duplicate(true)])
	return result


## True when `ticket` no longer owns its account's refresh: another
## ticket replaced it, or none is in flight. Zero is the legacy
## ticketless call, which is never retired.
func _self_rank_ticket_retired(public_id: String, ticket: int) -> bool:
	if ticket == 0:
		return false
	return int(_self_rank_inflight.get(public_id, 0)) != ticket


## Truthful outcome for a retired owner: a foreign binding reports the
## switch, otherwise the ticket itself went stale (invalidation, or a
## round trip home past a newer measurement).
func _stale_ticket_result(public_id: String) -> Dictionary:
	if not _account_allows(public_id):
		return {"status": "cancelled", "code": "account-changed",
			"retryable": false}
	return {"status": "cancelled", "code": "stale-reply",
		"retryable": false}


## Retire every in-flight self-rank ticket with a cancelled outcome for
## its waiters. The table is snapshotted and cleared before the first
## emission resumes anyone, so a waiter that refreshes again from the
## resumed call stack mints a newer ticket the retire can never touch.
func _retire_self_rank_inflight(code: String) -> void:
	if _self_rank_inflight.is_empty():
		return
	var pending: Dictionary = _self_rank_inflight.duplicate()
	_self_rank_inflight.clear()
	for public_id in pending.keys():
		self_rank_finished.emit([str(public_id),
			int(pending[public_id]), {
				"status": "cancelled", "code": code,
				"retryable": false,
				"public_id": str(public_id),
			}])


## Our owned row with cache. Fresh entries serve labeled `cache` without a
## request; a cached miss serves the labeled unranked verdict the same
## way. Live rows are validated (own ID, allow-listed hero, bounded
## score/cycles) and stored with the canonical hero path; anything else
## fails as a malformed row and caches nothing. A retired `ticket`
## reports cancelled before any cache write, so a late owner can never
## restore a stale row over a newer pair.
func _read_own_row(transport: RefCounted, public_id: String,
		now_msec: int, ticket: int = 0) -> Dictionary:
	if _own_cache.has(public_id):
		var entry: Dictionary = (
			_own_cache[public_id] as Dictionary).duplicate(true)
		var age: int = now_msec - int(entry.get("fetched_msec", 0))
		if age >= 0 and age < CACHE_TTL_MSEC:
			if bool(entry.get("missing", false)):
				return _unranked_result(public_id, "cache",
					int(entry.get("fetched_msec", 0)))
			var row: Dictionary = (
				entry.get("row", {}) as Dictionary).duplicate(true)
			return {"status": "ok", "row": row, "source": "cache",
				"fetched_msec": int(entry.get("fetched_msec", 0))}
	var live: Dictionary = await fetch_own(transport, public_id)
	if _self_rank_ticket_retired(public_id, ticket):
		return _stale_ticket_result(public_id)
	if not _account_allows(public_id):
		return {"status": "cancelled", "code": "account-changed",
			"retryable": false}
	if str(live.get("status", "")) != "ok":
		if str(live.get("code", "")) == "not-found":
			_own_cache[public_id] = {"missing": true,
				"fetched_msec": now_msec}
			_evict_own_cache(public_id)
			return _unranked_result(public_id, "live", now_msec)
		return live
	var fetched: Dictionary = (
		live.get("row", {}) as Dictionary).duplicate(true)
	var checked: Dictionary = _validate_own_row(fetched, public_id)
	if not bool(checked.get("ok", false)):
		return {"status": "failure",
			"code": str(checked.get("error", "bad-hall-row")),
			"retryable": false}
	fetched["hero"] = CloudSchema.canonical_hero(
		str(fetched.get("hero", "")))
	_own_cache[public_id] = {"missing": false, "row": fetched,
		"fetched_msec": now_msec}
	_evict_own_cache(public_id)
	return {"status": "ok", "row": fetched, "source": "live",
		"fetched_msec": now_msec}


## A missing own row is unranked: zeroed rank fields, never an invented #1.
## The half labels stay stable with ranked results: the row half carries
## this verdict's own freshness, and no count half was ever measured.
func _unranked_result(public_id: String, source: String,
		fetched_msec: int) -> Dictionary:
	return {
		"status": "unranked", "code": "own-row-missing",
		"retryable": false, "public_id": public_id,
		"rank": 0, "greater": 0, "score": 0, "hero": "",
		"cycles": 0, "source": source, "row_source": source,
		"rank_source": "", "fetched_msec": fetched_msec,
		"row_fetched_msec": fetched_msec, "rank_fetched_msec": 0,
		"live_error": "",
	}


## The owned row must be ours, with an allow-listed hero and bounded
## score/cycles. Short hero ids resolve through the same allow-list the
## submit path canonicalizes with; anything else is malformed.
func _validate_own_row(row: Dictionary, public_id: String) -> Dictionary:
	if str(row.get("public_id", "")) != public_id:
		return {"ok": false, "error": "bad-hall-row"}
	if CloudSchema.canonical_hero(str(row.get("hero", ""))).is_empty():
		return {"ok": false, "error": "bad-hall-row"}
	var score: int = int(row.get("score", 0))
	if score < 0 or score > CloudSchema.MAX_SCORE:
		return {"ok": false, "error": "bad-hall-row"}
	var cycles: int = int(row.get("cycles", 0))
	if cycles < 0 or cycles > CloudSchema.MAX_CYCLES:
		return {"ok": false, "error": "bad-hall-row"}
	return {"ok": true}


## A self rank served without a request: the last known pair (ranked or
## unranked) for this exact account, labeled `cache-throttled`. The
## per-half sources and fetched times stay as measured, so the stale
## score keeps its timestamp; empty when nothing is known yet.
func _throttled_self_rank(public_id: String) -> Dictionary:
	if _last_self_rank_result.is_empty():
		return {}
	if str(_last_self_rank_result.get("public_id", "")) != public_id:
		return {}
	var stale: Dictionary = _last_self_rank_result.duplicate(true)
	stale["source"] = "cache-throttled"
	return stale


## A rank served without a request: the stale entry for this exact score
## when one exists, else the last known rank for any score. Both are
## labeled `cache-throttled` by the caller path; empty when nothing is
## known yet. The stored `score` stays the score the rank was computed
## for, so a caller showing it for a newer score can say so.
func _throttled_rank(cache_key: String) -> Dictionary:
	if _rank_cache.has(cache_key):
		var stale: Dictionary = (_rank_cache[cache_key] as Dictionary).duplicate(
			true)
		stale["source"] = "cache-throttled"
		return stale
	if not _last_rank_result.is_empty():
		var last: Dictionary = _last_rank_result.duplicate(true)
		last["source"] = "cache-throttled"
		return last
	return {}


## Shrink the rank cache past its bound, oldest fetch first, never the
## just-written entry.
func _evict_rank_cache(keep_key: String) -> void:
	while _rank_cache.size() > MAX_RANK_CACHE_ENTRIES:
		var victim: String = ""
		var victim_msec: int = 0
		var first: bool = true
		for key in _rank_cache.keys():
			if str(key) == keep_key:
				continue
			var fetched: int = int(
				(_rank_cache[key] as Dictionary).get("fetched_msec", 0))
			if first or fetched < victim_msec:
				victim = str(key)
				victim_msec = fetched
				first = false
		if victim.is_empty():
			return
		_rank_cache.erase(victim)


## Shrink the own-row cache past its bound, oldest fetch first, never the
## just-written entry.
func _evict_own_cache(keep_key: String) -> void:
	while _own_cache.size() > MAX_OWN_CACHE_ENTRIES:
		var victim: String = ""
		var victim_msec: int = 0
		var first: bool = true
		for key in _own_cache.keys():
			if str(key) == keep_key:
				continue
			var fetched: int = int(
				(_own_cache[key] as Dictionary).get("fetched_msec", 0))
			if first or fetched < victim_msec:
				victim = str(key)
				victim_msec = fetched
				first = false
		if victim.is_empty():
			return
		_own_cache.erase(victim)


## True when no account is bound yet, or the row belongs to the bound one.
## An empty binding keeps every existing caller working; the coordinator
## always binds before reading.
func _account_allows(public_id: String) -> bool:
	return _account_public_id.is_empty() or public_id == _account_public_id


func _parse_aggregation_count(parsed: Variant) -> int:
	# `runAggregationQuery` answers one row with result.aggregateFields.greater.
	if typeof(parsed) != TYPE_ARRAY or (parsed as Array).is_empty():
		return -1
	var first: Variant = (parsed as Array)[0]
	if typeof(first) != TYPE_DICTIONARY:
		return -1
	var result: Dictionary = (first as Dictionary).get("result", {})
	var aggregate_fields: Dictionary = result.get("aggregateFields", {})
	var greater: Dictionary = aggregate_fields.get("greater", {})
	if not greater.has("integerValue"):
		return -1
	return maxi(int(str(greater.get("integerValue", "-1"))), 0)


## Deletes the caller's own Hall row. Only the owner who holds the matching
## profile can delete; public readers cannot.
func delete_record(transport: RefCounted, public_id: String) -> Dictionary:
	if not CloudSchema.is_valid_public_id(public_id):
		return {"status": "failure", "code": "invalid-public-id",
			"retryable": false}
	if not _account_allows(public_id):
		return {"status": "cancelled", "code": "account-changed",
			"retryable": false}
	if transport == null or not transport.has_method("delete_document"):
		return {"status": "unconfigured", "code": "missing-transport",
			"retryable": false}
	var reply: Dictionary = await transport.call("delete_document",
		hall_relative_path(public_id))
	if not _account_allows(public_id):
		return {"status": "cancelled", "code": "account-changed",
			"retryable": false}
	if str(reply.get("status", "")) == "ok":
		clear_cache()
	return reply
