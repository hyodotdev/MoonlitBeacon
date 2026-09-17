extends SceneTree

## Moonlit shop purchase-ledger, restore, and duplicate-grant regression tests.
##
## The real store is never opened. Inside the runner-isolated user://, a fake backend
## checks the "ledger save → benefit grant → transaction finish" order and restart recovery.

const STORE_SCRIPT: Script = preload("res://scripts/iap/iap_store.gd")
const FAILING_STORE_SCRIPT: Script = preload(
	"res://tests/support/failing_iap_store.gd")
const FAKE_BACKEND_SCRIPT: Script = preload(
	"res://tests/support/fake_iap_backend.gd")
const GODOT_BACKEND_SCRIPT: Script = preload(
	"res://scripts/iap/godot_iap_backend.gd")
const IAPKIT_TRANSPORT_SCRIPT: Script = preload(
	"res://scripts/iap/iapkit_http_transport.gd")
const GODOT_IAP_WRAPPER_SCRIPT: Script = preload(
	"res://addons/godot-iap/godot_iap.gd")
const FAKE_GODOT_IAP_PLUGIN_SCRIPT: Script = preload(
	"res://tests/support/fake_godot_iap_plugin.gd")
const HANGING_IAP_PLUGIN_SCRIPT: Script = preload(
	"res://tests/support/hanging_iap_plugin.gd")
const FAKE_IAPKIT_TRANSPORT_SCRIPT: Script = preload(
	"res://tests/support/fake_iapkit_transport.gd")
const VAULT_SCRIPT: Script = preload("res://scripts/gameplay/vault.gd")
const FAILING_VAULT_SCRIPT: Script = preload(
	"res://tests/support/failing_vault.gd")

const DANCER: String = "res://resources/heroes/dancer.tres"
const KEEPER: String = "res://resources/heroes/keeper.tres"

var _failed: int = 0
var _checked: int = 0
var _save_absolute: String = ""
var _temp_absolute: String = ""
var _backup_absolute: String = ""
var _backup_temp_absolute: String = ""
var _vault_paths: Array[String] = []


func _init() -> void:
	var expected_root: String = OS.get_environment(
		"MOONLIT" + "_VAULT" + "_TEST" + "_ROOT").simplify_path()
	var user_root: String = ProjectSettings.globalize_path("user://").simplify_path()
	if expected_root.is_empty() or not user_root.begins_with(expected_root + "/"):
		printerr("IAP tests aborted: user:// path is not isolated — ", user_root)
		quit(2)
		return

	_save_absolute = ProjectSettings.globalize_path("user://iap_entitlements.cfg")
	_temp_absolute = ProjectSettings.globalize_path("user://iap_entitlements.cfg.tmp")
	_backup_absolute = ProjectSettings.globalize_path("user://iap_entitlements.cfg.bak")
	_backup_temp_absolute = ProjectSettings.globalize_path(
		"user://iap_entitlements.cfg.bak.tmp")
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		_vault_paths.append(ProjectSettings.globalize_path("user://vault.cfg" + suffix))
	call_deferred("_run", user_root)


func _run(user_root: String) -> void:
	await _test_native_request_dispatch_semantics()
	await _test_duplicate_terminal_error_is_request_scoped()
	await _test_iapkit_backend_payload_and_result()
	await _test_iapkit_http_failure_classification()
	await _test_product_fetch_and_request()
	await _test_pending_and_invalid_purchases()
	await _test_server_verification_guards_grant()
	await _test_verification_failure_retries_without_grant()
	await _test_permanent_verification_failure_needs_support()
	await _test_verification_pending_product_cannot_repurchase()
	await _test_unrelated_verification_blocks_checkout_until_settled()
	await _test_verification_pending_revocation_settles_flow()
	await _test_verified_cancellation_revokes_recorded_purchase()
	await _test_refunded_android_receipt_reverified_when_missing()
	await _test_consumed_android_receipt_is_terminal_after_finish()
	await _test_unknown_historical_revocation_does_not_break_sync()
	await _test_duplicate_callback_verifies_once()
	await _test_restore_reports_verification_failure()
	await _test_restore_reports_deterministic_verification_failure()
	await _test_restore_reports_revocation_failure()
	await _test_connect_captures_initialize_replay_failure()
	await _test_connect_preserves_deterministic_failure_notice()
	await _test_resume_preserves_transient_failure_notice()
	await _test_resume_preserves_verified_cancellation_notice()
	await _test_resume_blocks_nested_store_actions()
	await _test_resume_waits_for_callback_started_during_maintenance()
	await _test_native_restore_failure_preserves_specific_notice()
	await _test_native_restore_callback_failure_beats_empty_sync()
	await _test_restore_waits_for_async_native_callback()
	await _test_restore_waits_for_async_native_failure()
	await _test_native_restore_false_waits_for_async_callback()
	await _test_restore_ignores_revoked_transaction_replay()
	await _test_resume_syncs_completed_pending()
	await _test_resume_releases_missing_pending()
	await _test_resume_releases_stale_purchase_request()
	await _test_storekit_deferred_payment_stays_pending()
	await _test_query_failure_preserves_pending_flow()
	await _test_disconnect_settlement_requires_retry()
	await _test_sync_discovered_pending_blocks_repurchase()
	await _test_unrelated_pending_blocks_later_repurchase()
	await _test_pending_callback_during_query_keeps_checkout_locked()
	await _test_completed_callback_beats_stale_pending_query()
	await _test_grant_is_saved_before_finish()
	await _test_individual_hero_purchase_restore_refund_and_cache()
	await _test_revocation_during_verification_is_not_lost()
	await _test_revocation_during_finish_is_not_lost()
	await _test_deferred_revocation_survives_restart()
	await _test_deferred_revocation_save_failure_retries_in_memory()
	await _test_connect_reports_deferred_revocation_failure()
	await _test_resume_reports_deferred_revocation_failure()
	await _test_restore_reports_deferred_revocation_failure()
	await _test_restore_reports_deferred_revocation_save_failure()
	await _test_journal_failure_prevents_grant()
	await _test_consumable_vault_journal_survives_iap_save_failure()
	await _test_primary_replica_failure_recovers_from_backup()
	await _test_benefit_failure_recovers_before_finish()
	await _test_completed_entitlement_reapplies_missing_benefit()
	await _test_finish_failure_is_retryable()
	await _test_restarted_finish_failure_requires_retry()
	await _test_unrelated_duplicate_keeps_purchase_open()
	await _test_sync_unrelated_failure_keeps_active_flow()
	await _test_connect_unrelated_failure_keeps_active_flow()
	await _test_revoked_replay_keeps_repurchase_open()
	await _test_legacy_entitlement_can_be_revoked()
	await _test_vault_iap_source_can_be_revoked_without_iap_journal()
	await _test_explicit_revocation_preserves_play_progress()
	await _test_revocation_benefit_retry()
	await _test_restore_pending_keeps_pending_notice()
	await _test_restore_counts_native_callback_before_completion()
	await _test_consumable_continue_coin()
	await _test_hung_product_fetch_gives_up()
	await _test_restore_and_palette_persistence()
	await _test_unowned_palette_is_not_rendered()
	await _test_versioned_primary_beats_backup()
	await _test_backup_recovery()

	_remove_save_targets()
	if _failed > 0:
		printerr("IAP shop tests failed — ", _failed, "/", _checked, " cases")
		quit(1)
		return
	print("IAP shop tests passed — ", _checked, " cases · isolated path ", user_root)
	quit(0)


func _test_native_request_dispatch_semantics() -> void:
	var wrapper: Node = GODOT_IAP_WRAPPER_SCRIPT.new()
	get_root().add_child(wrapper)
	_expect_false(
		wrapper.has_method("request_purchase_dispatched"),
		"do not restore purchase-dispatch helper APIs that 3.x removed from the wrapper")
	# 3.0.1 kept result-shaped queries native-only, so not restoring them on the wrapper
	# was the contract. 3.0.2 upstream now exposes them as official wrapper public API.
	_expect_true(
		wrapper.has_method("get_available_purchases_result"),
		"3.0.2 upstream officially exposes result-shaped query API on the wrapper")
	_expect_equal(
		wrapper._apple_async_timeout_seconds,
		30.0,
		"ordinary iOS async requests are limited to 30 seconds")
	_expect_equal(
		wrapper._apple_async_restore_timeout_seconds,
		600.0,
		"user-auth restore is limited to 10 minutes (Moonlit patch boundary)")

	var cached_key: String = wrapper._apple_async_result_key("fetchProducts", "fast")
	wrapper._on_products_fetched({
		"method": "fetchProducts",
		"requestId": "fast",
		"success": true,
	})
	var cached_result: Dictionary = await wrapper._await_products_fetched_for(
		"fetchProducts", "fast")
	_expect_true(bool(cached_result.get("success", false)), "fast iOS callback cache is recovered")
	_expect_false(wrapper._apple_async_results.has(cached_key), "recovered iOS callback cache is removed")

	var timeout_result: Dictionary = await wrapper._await_products_fetched_for(
		"fetchProducts", "lost", 0.05)
	_expect_false(bool(timeout_result.get("success", false)), "lost iOS callback times out")
	_expect_true(
		"timed out" in str(timeout_result.get("error", "")),
		"iOS callback timeout error is distinguished")
	# A 3.0.2 timeout resumes on the timer signal stack. Yield one frame so the
	# free() below does not delete a wrapper still in "calling" and trip an engine error.
	await process_frame

	# If the connection drops while a request is waiting, the 3.0.2 waiter completes
	# in place with a disconnect error.
	var disconnect_outcomes: Array[Dictionary] = []
	var disconnect_runner: Callable = func() -> void:
		var result: Dictionary = await wrapper._await_products_fetched_for(
			"getAvailablePurchases", "cut-off")
		disconnect_outcomes.append(result)
	disconnect_runner.call()
	wrapper._on_disconnected()
	_expect_equal(
		disconnect_outcomes.size(), 1, "iOS disconnect immediately ends a waiting request")
	if disconnect_outcomes.size() == 1:
		_expect_false(
			bool(disconnect_outcomes[0].get("success", true)),
			"async request is canceled on iOS disconnect")
		_expect_true(
			"disconnected" in str(disconnect_outcomes[0].get("error", "")),
			"iOS disconnect error is distinguished")

	# The official godot-iap 3.x iOS bridge starts a normal purchase sheet with no success
	# field and returns {"status":"pending"}. Treating that as a sync failure sends Store
	# back to READY the moment the sheet opens, so cover it from wrapper through backend.
	var ios_plugin: Node = FAKE_GODOT_IAP_PLUGIN_SCRIPT.new()
	ios_plugin._platform = "iOS"
	ios_plugin.native_request_result_json = '{"status":"pending"}'
	var ios_wrapper: Node = GODOT_IAP_WRAPPER_SCRIPT.new()
	get_root().add_child(ios_wrapper)
	ios_wrapper._native_plugin = ios_plugin
	ios_wrapper._platform = "iOS"
	ios_wrapper._is_connected = true
	var ios_backend: Node = GODOT_BACKEND_SCRIPT.new(ios_wrapper)
	ios_backend._connect_plugin_signals()
	var ios_errors: Array[Dictionary] = []
	ios_backend.purchase_failed.connect(
		func(error: Dictionary) -> void: ios_errors.append(error.duplicate(true)))
	_expect_true(
		ios_backend.request_purchase(STORE_SCRIPT.SUPPORTER),
		"iOS status pending is a normal purchase dispatch")
	_expect_equal(ios_plugin.native_request_count, 1, "iOS pending native request once")
	_expect_equal(ios_errors.size(), 0, "iOS pending response must not emit purchase_error")
	ios_plugin.native_request_result_json = \
		'{"success":false,"code":"developer-error","error":"bad request"}'
	_expect_false(
		ios_backend.request_purchase(STORE_SCRIPT.SUPPORTER),
		"explicit iOS native failure is a dispatch failure")
	_expect_equal(ios_errors.size(), 1, "explicit iOS failure emits purchase_error once")
	ios_backend.free()
	ios_wrapper.free()
	ios_plugin.free()

	var plugin: Node = FAKE_GODOT_IAP_PLUGIN_SCRIPT.new()
	var backend: Node = GODOT_BACKEND_SCRIPT.new(plugin)
	backend._connect_plugin_signals()
	_expect_false(
		backend._available_purchase_is_valid({}),
		"reject a native purchase row missing required fields")
	_expect_false(
		backend._available_purchase_is_valid({
			"productId": null,
			"purchaseState": "purchased",
			"transactionId": "null-product-transaction",
		}),
		"do not mistake a null product ID for a string")
	_expect_true(
		backend._available_purchase_is_valid(_ios_purchase(
			STORE_SCRIPT.SUPPORTER, "wrapper-valid-transaction")),
		"accept a native purchase row that has product, transaction, and state")

	_expect_true(
		backend.request_purchase("com.crossplatformkorea.moonlitbeacon.supporter"),
		"canonical 3.x null pending response is a normal dispatch")
	_expect_equal(plugin.request_count, 1, "canonical purchase request is called once")
	var props: Variant = plugin.last_props
	var encoded: Dictionary = props.to_dict()
	_expect_equal(
		str(encoded.get("requestPurchase", {}).get("apple", {}).get("sku", "")),
		"com.crossplatformkorea.moonlitbeacon.supporter",
		"iOS product ID is included in the dispatch payload")
	_expect_equal(
		encoded.get("requestPurchase", {}).get("google", {}).get("skus", []),
		["com.crossplatformkorea.moonlitbeacon.supporter"],
		"Android product ID is included in the dispatch payload")
	plugin.dispatched = false
	_expect_false(
		backend.request_purchase("com.crossplatformkorea.moonlitbeacon.supporter"),
		"canonical sync purchase_error is a dispatch failure")
	plugin._store_connected = false
	_expect_false(
		backend.request_purchase("com.crossplatformkorea.moonlitbeacon.supporter"),
		"do not mistake a disconnected store for pending")
	_expect_equal(plugin.request_count, 2, "native purchase request forbidden before connect")
	plugin._store_connected = true

	# Even if the wrapper turns a malformed native-bridge response into null, purchase_error
	# must still reach the backend in the same call. Otherwise it is indistinguishable from
	# a normal async-pending null and Store stays stuck in PURCHASING. A string that makes
	# JSON parse itself die would log ERROR and make the regression runner think the test
	# failed, so use an array payload that "parses but is outside the contract" for the same fail-closed path.
	plugin.native_request_result_json = '["not-a-purchase"]'
	wrapper._native_plugin = plugin
	wrapper._platform = "Android"
	wrapper._is_connected = true
	var malformed_backend: Node = GODOT_BACKEND_SCRIPT.new(
		wrapper, "openiap-kit_pk_test")
	malformed_backend._connect_plugin_signals()
	var malformed_store: Node = STORE_SCRIPT.new()
	malformed_store.set_backend_for_testing(malformed_backend)
	malformed_store._backend_initialized = true
	for product_id in STORE_SCRIPT.SALE_PRODUCT_IDS:
		malformed_store.products[product_id] = {
			"id": product_id,
			"displayPrice": "$1.99",
		}
	malformed_backend.purchase_failed.connect(malformed_store._on_purchase_error)
	malformed_store._set_state(malformed_store.StoreState.READY)
	var malformed_failures: Array[Dictionary] = []
	malformed_store.purchase_failed.connect(
		func(product_id: String, code: String) -> void:
			malformed_failures.append({"product_id": product_id, "code": code}))
	_expect_false(
		malformed_store.purchase(STORE_SCRIPT.SUPPORTER),
		"malformed native purchase response is a checkout dispatch failure")
	_expect_equal(plugin.native_request_count, 1, "malformed native purchase request once")
	_expect_equal(
		malformed_store.state,
		malformed_store.StoreState.READY,
		"PURCHASING lock clears after a malformed native purchase response")
	_expect_equal(
		malformed_store.current_product_id,
		"",
		"current product clears after a malformed native purchase response")
	_expect_equal(malformed_failures.size(), 1, "malformed native purchase failure notice once")
	if not malformed_failures.is_empty():
		_expect_equal(
			malformed_failures[0].get("code", ""),
			"service-error",
			"malformed native purchase response error code")
	malformed_store.free()
	malformed_backend.free()

	var native_query: Dictionary = await backend.available_purchases()
	_expect_true(
		bool(native_query.get("success", false)),
		"Android result-shaped purchase query distinguishes a normal empty")
	_expect_equal(
		native_query.get("purchases", []).size(),
		0,
		"a normal empty query forwards success together with an empty list")
	plugin.native_available_result_json = \
		'{"success":false,"purchases":[],"error":"not initialized"}'
	native_query = await backend.available_purchases()
	_expect_false(
		bool(native_query.get("success", false)),
		"do not treat Android native query failure as a normal empty")
	plugin.native_available_result_json = '{"success":true,"purchases":[]}'
	_expect_true(await backend.restore(), "Android native restore success is forwarded")
	plugin.native_restore_result_json = \
		'{"success":false,"error":"billing unavailable"}'
	_expect_false(await backend.restore(), "Android native restore error is forwarded")
	plugin.native_restore_result_json = "not-json"
	_expect_false(await backend.restore(), "Android malformed restore response is fail-closed")
	plugin.native_available_result_json = JSON.stringify({
		"success": true,
		"purchases": [{
			"productId": null,
			"purchaseState": "purchased",
			"transactionId": "backend-null-product",
		}],
	})
	var malformed_query: Dictionary = await backend.available_purchases()
	_expect_false(
		bool(malformed_query.get("success", false)),
		"adapter must not forward an empty typed purchase object as a normal query")
	var available_options: Dictionary = plugin.last_available_options
	_expect_true(
		bool(available_options.get("onlyIncludeActiveItemsIOS", false)),
		"current iOS purchase query excludes historical revocations")

	plugin._platform = "iOS"
	plugin.ios_available_payload = {
		"success": true,
		"purchasesJson": "[]",
	}
	var ios_query: Dictionary = await backend.available_purchases()
	_expect_true(
		bool(ios_query.get("success", false)),
		"iOS success envelope distinguishes a normal empty")
	plugin.ios_available_payload = {
		"success": false,
		"purchasesJson": "[]",
	}
	ios_query = await backend.available_purchases()
	_expect_false(
		bool(ios_query.get("success", false)),
		"do not treat iOS native query failure as a normal empty")
	plugin.ios_available_payload = {
		"success": true,
		"purchasesJson": "not-json",
	}
	ios_query = await backend.available_purchases()
	_expect_false(
		bool(ios_query.get("success", false)),
		"iOS malformed purchase list is fail-closed")
	plugin.ios_restore_success = true
	_expect_true(await backend.restore(), "iOS canonical restore success is forwarded")
	plugin.ios_restore_success = false
	_expect_false(await backend.restore(), "iOS canonical restore failure is forwarded")
	backend.free()
	plugin.free()
	wrapper.free()


func _test_duplicate_terminal_error_is_request_scoped() -> void:
	var service_disconnected: Dictionary = {
		"code": "service-disconnected",
		"message": "Billing service disconnected",
	}
	var other_product_error: Dictionary = {
		"productId": STORE_SCRIPT.LANTERN_COLORS,
		"code": "service-disconnected",
		"message": "Billing service disconnected",
	}
	var plugin: Node = FAKE_GODOT_IAP_PLUGIN_SCRIPT.new()
	var backend: Node = GODOT_BACKEND_SCRIPT.new(plugin)
	backend._connect_plugin_signals()
	var backend_failures: Array[Dictionary] = []
	backend.purchase_failed.connect(
		func(error: Dictionary) -> void:
			backend_failures.append(error.duplicate(true)))

	_expect_true(
		backend.request_purchase(STORE_SCRIPT.SUPPORTER),
		"async purchase request starts before duplicate ServiceDisconnected")
	plugin.purchase_error.emit(service_disconnected.duplicate(true))
	plugin.purchase_error.emit(service_disconnected.duplicate(true))
	plugin.purchase_error.emit(other_product_error.duplicate(true))
	_expect_equal(
		backend_failures.size(),
		2,
		"forward the same request/product error only once and keep other-product errors")
	if backend_failures.size() == 2:
		_expect_equal(
			backend_failures[0].get("code", ""),
			"service-disconnected",
			"current-request terminal error code is forwarded")
		_expect_equal(
			backend_failures[1].get("productId", ""),
			STORE_SCRIPT.LANTERN_COLORS,
			"do not suppress a terminal error for another product")
	_expect_true(
		backend.request_purchase(STORE_SCRIPT.SUPPORTER),
		"next purchase generation starts")
	plugin.purchase_error.emit(service_disconnected.duplicate(true))
	_expect_equal(
		backend_failures.size(),
		3,
		"the next purchase generation forwards the same error again")
	backend.free()
	plugin.free()

	var ui_plugin: Node = FAKE_GODOT_IAP_PLUGIN_SCRIPT.new()
	var ui_backend: Node = GODOT_BACKEND_SCRIPT.new(
		ui_plugin, "openiap-kit_pk_test")
	ui_backend._connect_plugin_signals()
	var store: Node = STORE_SCRIPT.new()
	store.set_backend_for_testing(ui_backend)
	store._backend_initialized = true
	for product_id in STORE_SCRIPT.SALE_PRODUCT_IDS:
		store.products[product_id] = {
			"id": product_id,
			"displayPrice": "$1.99",
		}
	ui_backend.purchase_failed.connect(store._on_purchase_error)
	store._set_state(store.StoreState.READY)
	var ui_failures: Array[Dictionary] = []
	store.purchase_failed.connect(
		func(product_id: String, code: String) -> void:
			ui_failures.append({"product_id": product_id, "code": code}))

	_expect_true(
		store.purchase(STORE_SCRIPT.SUPPORTER),
		"async purchase request starts for the UI flow")
	ui_plugin.purchase_error.emit(service_disconnected.duplicate(true))
	ui_plugin.purchase_error.emit(service_disconnected.duplicate(true))
	_expect_equal(ui_failures.size(), 1, "UI is told about a terminal error only once")
	_expect_equal(store.state, store.StoreState.READY, "shop lock is released after duplicate errors")
	if ui_failures.size() == 1:
		_expect_equal(
			ui_failures[0].get("product_id", ""),
			STORE_SCRIPT.SUPPORTER,
			"UI failure keeps the current product")

	_expect_true(
		store.purchase(STORE_SCRIPT.LANTERN_COLORS),
		"a new UI flow for another product starts")
	ui_plugin.purchase_error.emit(service_disconnected.duplicate(true))
	_expect_equal(ui_failures.size(), 2, "a new UI flow error is noticed separately once")
	if ui_failures.size() == 2:
		_expect_equal(
			ui_failures[1].get("product_id", ""),
			STORE_SCRIPT.LANTERN_COLORS,
			"the new UI flow keeps the other-product error")
	store.free()
	ui_backend.free()
	ui_plugin.free()


func _test_iapkit_backend_payload_and_result() -> void:
	var plugin: Node = FAKE_GODOT_IAP_PLUGIN_SCRIPT.new()
	var transport: Node = FAKE_IAPKIT_TRANSPORT_SCRIPT.new()
	var publishable_key: String = "openiap-kit_" + "pk_" + "T".repeat(64)
	var backend: Node = GODOT_BACKEND_SCRIPT.new(
		plugin, publishable_key, transport)
	var android_purchase: Dictionary = _android_purchase(
		STORE_SCRIPT.SUPPORTER, "verified-google-token")
	var verified: Dictionary = await backend.verify_purchase(
		android_purchase, STORE_SCRIPT.SUPPORTER)
	_expect_true(bool(verified.get("success", false)), "IAPKit Android verification result is forwarded")
	_expect_true(bool(verified.get("is_valid", false)), "IAPKit validity decision is forwarded")
	_expect_equal(verified.get("store", ""), "google", "IAPKit response store is forwarded")
	_expect_equal(
		verified.get("product_id", ""),
		STORE_SCRIPT.SUPPORTER,
		"IAPKit response product ID is forwarded")
	var request: Dictionary = transport.calls[0]
	var body: Dictionary = request.get("body", {})
	_expect_equal(request.get("api_key", ""), publishable_key, "only the publishable key is forwarded")
	_expect_equal(
		body.get("expectedProductId", ""),
		STORE_SCRIPT.SUPPORTER,
		"server exact SKU guard is forwarded")
	_expect_equal(
		body.get("purchaseToken", ""),
		"verified-google-token",
		"Google purchaseToken is forwarded")
	_expect_equal(body.get("store", ""), "google", "Google store is stated")
	_expect_false(body.has("jws"), "Android verification excludes Apple JWS")

	transport.results.append({
		"success": true,
		"body": {
			"store": "apple",
			"isValid": true,
			"state": "entitled",
			"productId": STORE_SCRIPT.LANTERN_COLORS,
		},
	})
	var ios_purchase: Dictionary = _ios_purchase(
		STORE_SCRIPT.LANTERN_COLORS, "verified-ios-transaction")
	verified = await backend.verify_purchase(
		ios_purchase, STORE_SCRIPT.LANTERN_COLORS)
	_expect_true(bool(verified.get("success", false)), "IAPKit Apple verification result is forwarded")
	request = transport.calls[1]
	body = request.get("body", {})
	_expect_equal(
		body.get("jws", ""),
		ios_purchase.get("purchaseToken", ""),
		"Apple StoreKit JWS is forwarded")
	_expect_equal(body.get("store", ""), "apple", "Apple store is stated")
	_expect_false(body.has("purchaseToken"), "Apple verification excludes the Google token")

	var calls_before_invalid: int = transport.calls.size()
	var missing_jws: Dictionary = ios_purchase.duplicate(true)
	missing_jws.erase("purchaseToken")
	verified = await backend.verify_purchase(
		missing_jws, STORE_SCRIPT.LANTERN_COLORS)
	_expect_false(bool(verified.get("success", false)), "reject an Apple purchase with no JWS")
	_expect_equal(
		transport.calls.size(),
		calls_before_invalid,
		"a purchase with no JWS must not make an HTTP call")
	var oversized_jws: Dictionary = ios_purchase.duplicate(true)
	oversized_jws["purchaseToken"] = "A".repeat(100) \
		+ "." + "B".repeat(15_897) + "." + "C".repeat(2)
	verified = await backend.verify_purchase(
		oversized_jws, STORE_SCRIPT.LANTERN_COLORS)
	_expect_false(
		bool(verified.get("success", false)),
		"reject a compact JWS over IAPKit's 16000-character client bound")
	_expect_equal(
		transport.calls.size(),
		calls_before_invalid,
		"oversized Apple JWS must not make an HTTP call")
	var maximum_jws: Dictionary = ios_purchase.duplicate(true)
	maximum_jws["purchaseToken"] = "A".repeat(100) \
		+ "." + "B".repeat(15_896) + "." + "C".repeat(2)
	verified = await backend.verify_purchase(
		maximum_jws, STORE_SCRIPT.LANTERN_COLORS)
	_expect_true(
		bool(verified.get("success", false)),
		"allow a compact JWS at IAPKit's 16000-character client bound")
	_expect_equal(
		transport.calls.back().get("body", {}).get("jws", ""),
		maximum_jws.get("purchaseToken", ""),
		"forward a bound-length Apple JWS without loss")

	transport.results.append({
		"success": false,
		"error_code": "rate-limited",
	})
	verified = await backend.verify_purchase(
		android_purchase, STORE_SCRIPT.SUPPORTER)
	_expect_false(bool(verified.get("success", false)), "do not treat a provider error as success")
	_expect_equal(
		verified.get("error_code", ""),
		"rate-limited",
		"forward the provider error code without a sensitive payload")
	_expect_true(
		bool(verified.get("retryable", false)),
		"legacy provider error without retryable is safely retried")
	for malformed_is_valid in ["false", 1, {}, []]:
		transport.results.append({
			"success": true,
			"body": {
				"store": "google",
				"isValid": malformed_is_valid,
				"state": "ENTITLED",
				"productId": STORE_SCRIPT.SUPPORTER,
			},
		})
		verified = await backend.verify_purchase(
			android_purchase, STORE_SCRIPT.SUPPORTER)
		_expect_false(
			bool(verified.get("success", false)),
			"non-Boolean isValid response is treated as malformed")
		_expect_true(
			bool(verified.get("retryable", false)),
			"malformed 2xx response re-verifies without granting")
	for malformed_success in ["false", "true", 1, {}, []]:
		transport.results.append({
			"success": malformed_success,
			"body": {
				"store": "google",
				"isValid": true,
				"state": "ENTITLED",
				"productId": STORE_SCRIPT.SUPPORTER,
			},
		})
		verified = await backend.verify_purchase(
			android_purchase, STORE_SCRIPT.SUPPORTER)
		_expect_false(
			bool(verified.get("success", false)),
			"non-Boolean transport success is treated as malformed")
	transport.results.append({
		"success": false,
		"error_code": "verification-configuration-error",
		"retryable": "false",
	})
	verified = await backend.verify_purchase(
		android_purchase, STORE_SCRIPT.SUPPORTER)
	_expect_false(
		bool(verified.get("success", false)),
		"non-Boolean transport retryable is not treated as success")
	_expect_true(
		bool(verified.get("retryable", false)),
		"malformed transport envelope is safely re-verified")
	backend.free()
	plugin.free()


func _test_iapkit_http_failure_classification() -> void:
	var transport: Node = IAPKIT_TRANSPORT_SCRIPT.new()
	for status_code in [408, 425, 429, 500, 503]:
		var transient: Dictionary = transport._http_failure(status_code)
		_expect_true(
			bool(transient.get("retryable", false)),
			"HTTP %d is a transient verification outage" % status_code)
		_expect_equal(
			transient.get("error_code", ""),
			"verification-unavailable",
			"transient verification outage uses the retry notice code")
	for status_code in [400, 413, 422]:
		var rejected: Dictionary = transport._http_failure(status_code)
		_expect_false(
			bool(rejected.get("retryable", true)),
			"HTTP %d is a deterministic request reject" % status_code)
		_expect_equal(
			rejected.get("error_code", ""),
			"verification-rejected",
			"deterministic request error uses the support notice code")
	for status_code in [401, 403]:
		var configuration: Dictionary = transport._http_failure(status_code)
		_expect_false(
			bool(configuration.get("retryable", true)),
			"HTTP %d is a deterministic auth-configuration error" % status_code)
		_expect_equal(
			configuration.get("error_code", ""),
			"verification-configuration-error",
			"auth-configuration error uses the ops-check code")
	transport.free()


func _test_product_fetch_and_request() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()

	_expect_equal(store.state, store.StoreState.READY, "shop is ready after product fetch")
	_expect_equal(store.display_price(store.SUPPORTER), "₩3,300", "store local price is used")
	_expect_true(store.can_purchase(store.SUPPORTER), "a fetched unowned product can be purchased")
	_expect_true(store.can_purchase(store.LANTERN_COLORS), "colors can be bought after the full catalog is fetched")
	_expect_false(store.can_purchase(store.HERO_BUNDLE), "legacy hero bundle is blocked at the new-checkout boundary")
	_expect_false(store.purchase(store.HERO_BUNDLE), "hidden legacy hero bundle must not request checkout")
	_expect_true(store.purchase(store.SUPPORTER), "store checkout sheet is requested")
	_expect_equal(
		backend.requested_product_ids, [store.SUPPORTER], "requested product ID is exact")
	backend.emit_failure(store.SUPPORTER, "user-cancelled")
	_expect_equal(store.state, store.StoreState.READY, "shop returns to ready after cancel")
	_expect_false(store.owns(store.SUPPORTER), "cancel does not grant an entitlement")
	_expect_true(store.purchase(store.LANTERN_COLORS), "checkout starts before an error with no product ID")
	backend.purchase_failed.emit({
		"productId": null,
		"code": "service-error",
	})
	_expect_equal(store.state, store.StoreState.READY, "an empty product-ID error ends the current checkout")
	_expect_equal(store.current_product_id, "", "current product clears after an empty product-ID error")
	backend.emit_disconnect()
	_expect_equal(store.state, store.StoreState.UNAVAILABLE, "store disconnect is shown")
	_expect_true(store.can_retry_connection(), "retry is possible after store disconnect")
	_expect_true(await store.retry_connection(), "reconnect after store disconnect")
	_expect_equal(store.state, store.StoreState.READY, "return to ready after store reconnect")
	store.free()
	vault.free()

	_remove_save_targets()
	var empty_store: Node = STORE_SCRIPT.new()
	var empty_backend: Node = FAKE_BACKEND_SCRIPT.new()
	var empty_vault: Node = _new_vault()
	empty_store.set_backend_for_testing(empty_backend)
	empty_store.set_vault_for_testing(empty_vault)
	empty_store.load_entitlements()
	await empty_store._start_backend()
	_expect_equal(
		empty_store.state, empty_store.StoreState.ERROR, "zero products is not shown as ready")
	_expect_true(empty_store.can_retry_connection(), "retry is possible after product fetch failure")
	empty_backend.fetched_products.append({
		"id": empty_store.SUPPORTER,
		"displayPrice": "₩3,300",
	})
	_expect_false(await empty_store.retry_connection(), "reject a retry that fetched only some products")
	_expect_equal(
		empty_store.state, empty_store.StoreState.ERROR, "a partial catalog stays in ERROR")
	_expect_true(empty_store.can_retry_connection(), "retry is possible again after a partial catalog")
	_seed_products(empty_backend, empty_store)
	empty_backend.fetched_products = empty_backend.fetched_products.filter(
		func(product: Dictionary) -> bool:
			return str(product.get("id", "")) != empty_store.HERO_BUNDLE)
	_expect_true(
		await empty_store.retry_connection(),
		"current-sale catalog is ready regardless of old-bundle product fetch failure")
	_expect_equal(
		empty_store.state,
		empty_store.StoreState.READY,
		"current shop is ready even after the old bundle is missing")
	_expect_false(
		empty_store.products.has(empty_store.HERO_BUNDLE),
		"the old bundle that failed to fetch is absent from product details")
	empty_backend.fetched_products.clear()
	await empty_store.refresh_products()
	empty_store._set_state(empty_store.StoreState.ERROR)
	_seed_products(empty_backend, empty_store)
	empty_backend.fetched_products[2]["displayPrice"] = null
	_expect_false(await empty_store.retry_connection(), "catalog rejects a product with a null price")
	_expect_equal(empty_store.display_price(empty_store.HERO_DANCER), "", "null price is not displayed")
	_expect_true(empty_store.can_retry_connection(), "retry is possible again after a missing price")
	_seed_products(empty_backend, empty_store)
	_expect_true(await empty_store.retry_connection(), "full product-fetch retry succeeds")
	_expect_equal(empty_store.state, empty_store.StoreState.READY, "shop is ready after retry")
	empty_store.free()
	empty_vault.free()

	_remove_save_targets()
	var offline_store: Node = STORE_SCRIPT.new()
	var offline_backend: Node = FAKE_BACKEND_SCRIPT.new()
	var offline_vault: Node = _new_vault()
	offline_backend.initialize_result = false
	offline_store.set_backend_for_testing(offline_backend)
	offline_store.set_vault_for_testing(offline_vault)
	offline_store.load_entitlements()
	await offline_store._start_backend()
	_expect_equal(
		offline_store.state, offline_store.StoreState.UNAVAILABLE, "initial connect failure is shown")
	offline_backend.initialize_result = true
	_seed_products(offline_backend, offline_store)
	_expect_true(await offline_store.retry_connection(), "reconnect after initial connect failure")
	_expect_equal(offline_store.state, offline_store.StoreState.READY, "shop is ready after reconnect")
	offline_store.free()
	offline_vault.free()


func _test_pending_and_invalid_purchases() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()

	var pending_count: Array[int] = [0]
	var failure_count: Array[int] = [0]
	store.purchase_pending.connect(
		func(_product_id: String) -> void: pending_count[0] += 1)
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)
	_expect_false(
		await store.process_purchase(_android_purchase(
			store.SUPPORTER, "pending-token", "pending")),
		"pending payment is not granted")
	_expect_equal(pending_count[0], 1, "pending-state notice")
	_expect_equal(store.state, store.StoreState.PENDING, "only a verified pending transaction is in the waiting state")
	_expect_equal(store.current_product_id, store.SUPPORTER, "pending product is tracked")
	store.current_product_id = ""
	store.state = store.StoreState.UNAVAILABLE

	_expect_false(
		await store.process_purchase({
			"productId": "unknown.product",
			"purchaseState": "purchased",
			"purchaseToken": "unknown-token",
			"packageNameAndroid": store.APP_ID,
		}),
		"reject a product outside the catalog")
	_expect_false(
		await store.process_purchase({
			"productId": store.SUPPORTER,
			"purchaseState": "purchased",
			"packageNameAndroid": store.APP_ID,
		}),
		"reject a purchase with no transaction identity")
	_expect_false(
		await store.process_purchase({
			"productId": store.SUPPORTER,
			"purchaseState": "purchased",
			"purchaseToken": "wrong-package-token",
			"packageNameAndroid": "dev.example.other",
		}),
		"reject a purchase from another app")
	_expect_equal(failure_count[0], 3, "error notice for every invalid purchase")
	_expect_false(
		await store.process_purchase({
			"productId": "unknown.product",
			"purchaseState": "pending",
			"purchaseToken": "unknown-pending-token",
			"packageNameAndroid": store.APP_ID,
		}),
		"reject a pending transaction outside the catalog")
	_expect_equal(store.state, store.StoreState.UNAVAILABLE, "unverified pending must not lock the shop")
	_expect_equal(store.current_product_id, "", "must not track an unverified pending product")
	_expect_equal(failure_count[0], 4, "unverified pending also notices the error once")
	_expect_equal(backend.finished_purchases.size(), 0, "rejected transaction must not finish")
	_expect_false(store.owns(store.SUPPORTER), "rejected transaction has no entitlement")
	store.free()
	backend.free()
	vault.free()


func _test_server_verification_guards_grant() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()

	backend.verification_results.append({
		"success": true,
		"is_valid": true,
		"store": "google",
		"state": "entitled",
		"product_id": store.HERO_BUNDLE,
	})
	_expect_false(
		await store.process_purchase(_android_purchase(
			store.SUPPORTER, "wrong-product-token")),
		"reject a server response with a mismatched product ID")
	backend.verification_results.append({
		"success": true,
		"is_valid": true,
		"store": "apple",
		"state": "entitled",
		"product_id": store.SUPPORTER,
	})
	_expect_false(
		await store.process_purchase(_android_purchase(
			store.SUPPORTER, "wrong-store-token")),
		"reject a server response with a mismatched store")
	backend.verification_results.append({
		"success": true,
		"is_valid": true,
		"store": "google",
		"state": "ready-to-consume",
		"product_id": store.SUPPORTER,
	})
	_expect_false(
		await store.process_purchase(_android_purchase(
			store.SUPPORTER, "consumable-state-token")),
		"reject a consumable state on a non-consumable")
	backend.verification_results.append({
		"success": true,
		"is_valid": false,
		"store": "google",
		"state": "inauthentic",
		"product_id": store.SUPPORTER,
	})
	_expect_false(
		await store.process_purchase(_android_purchase(
			store.SUPPORTER, "inauthentic-token")),
		"reject a purchase the server judged forged")
	_expect_false(store.owns(store.SUPPORTER), "rejected result does not grant")
	_expect_equal(backend.finished_purchases.size(), 0, "rejected result must not finish")

	backend.verification_results.append({
		"success": true,
		"is_valid": true,
		"store": "google",
		"state": "pending_acknowledgment",
		"product_id": store.SUPPORTER,
	})
	_expect_true(
		await store.process_purchase(_android_purchase(
			store.SUPPORTER, "pending-ack-token")),
		"valid purchase is granted before Google acknowledgment")
	_expect_true(store.owns(store.SUPPORTER), "verified Google entitlement is granted")
	var verify_index: int = backend.calls.find("verify:" + store.SUPPORTER)
	var finish_index: int = backend.calls.find("finish:" + store.SUPPORTER)
	_expect_true(
		verify_index >= 0 and finish_index > verify_index,
		"transaction finishes only after server verification")

	backend.verification_results.append({
		"success": true,
		"is_valid": true,
		"store": "apple",
		"state": "entitled",
		"product_id": store.LANTERN_COLORS,
	})
	_expect_true(
		await store.process_purchase(_ios_purchase(
			store.LANTERN_COLORS, "apple-entitled-transaction")),
		"Apple entitled purchase is granted")
	_expect_true(store.owns(store.LANTERN_COLORS), "verified Apple entitlement is granted")

	var coins_before_consumable_verification: int = vault.continue_coins
	backend.verification_results.append({
		"success": true,
		"is_valid": true,
		"store": "google",
		"state": "ready-to-consume",
		"product_id": store.CONTINUE_COIN,
	})
	_expect_true(
		await store.process_purchase(_android_purchase(
			store.CONTINUE_COIN, "google-ready-to-consume-token")),
		"Google ready-to-consume consumable is granted")
	backend.verification_results.append({
		"success": true,
		"is_valid": true,
		"store": "apple",
		"state": "ready_to_consume",
		"product_id": store.CONTINUE_COIN_5,
	})
	_expect_true(
		await store.process_purchase(_ios_purchase(
			store.CONTINUE_COIN_5, "apple-ready-to-consume-transaction")),
		"Apple ready-to-consume consumable is granted")
	_expect_equal(
		vault.continue_coins,
		coins_before_consumable_verification + 6,
		"coins granted match the verified consumable count")
	_expect_true(
		bool(backend.finished_consumable_flags[-2]) \
			and bool(backend.finished_consumable_flags[-1]),
		"verified consumable uses consume finish")
	var finished_before_malformed: int = backend.finished_purchases.size()
	backend.verification_results.append({
		"success": true,
		"is_valid": "false",
		"store": "google",
		"state": "entitled",
		"product_id": store.HERO_BUNDLE,
	})
	_expect_false(
		await store.process_purchase(_android_purchase(
			store.HERO_BUNDLE, "malformed-is-valid-token")),
		"shop boundary also rejects a truthy string isValid from an inner backend")
	_expect_false(store.owns(store.HERO_BUNDLE), "malformed isValid does not grant")
	_expect_equal(
		backend.finished_purchases.size(),
		finished_before_malformed,
		"malformed isValid must not finish")
	store.free()
	backend.free()
	vault.free()


func _test_verification_failure_retries_without_grant() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "checkout starts before the verification outage")
	var purchase: Dictionary = _android_purchase(
		store.SUPPORTER, "verification-retry-token")
	backend.verification_results.append({
		"success": false,
		"error_code": "rate-limited",
	})
	var failure_codes: Array[String] = []
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code))

	_expect_false(await store.process_purchase(purchase), "hold the grant during a verification outage")
	_expect_false(store.owns(store.SUPPORTER), "do not grant during a verification outage")
	_expect_equal(backend.finished_purchases.size(), 0, "must not finish during a verification outage")
	_expect_equal(store.state, store.StoreState.ERROR, "show a verification outage as a retryable state")
	_expect_equal(
		store.current_product_id,
		store.SUPPORTER,
		"keep the verification-pending product to block duplicate purchase")
	_expect_equal(
		failure_codes,
		["verification-unavailable"],
		"distinguish a verification outage from a normal cancel")
	backend.owned_purchases.append(purchase)

	_expect_true(await store.retry_connection(), "IAPKit verification retry succeeds")
	_expect_true(store.owns(store.SUPPORTER), "grant only once after re-verification succeeds")
	_expect_equal(backend.finished_purchases.size(), 1, "finish after re-verification succeeds")
	_expect_equal(backend.verified_purchases.size(), 2, "failed transaction is re-verified once")
	_expect_equal(store.state, store.StoreState.READY, "shop returns to ready after re-verification")
	store.free()
	vault.free()


func _test_permanent_verification_failure_needs_support() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "checkout starts before the deterministic verification error")
	backend.verification_results.append({
		"success": false,
		"error_code": "verification-configuration-error",
		"retryable": false,
	})
	var failure_codes: Array[String] = []
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code))

	_expect_false(
		await store.process_purchase(_android_purchase(
			store.SUPPORTER, "invalid-key-verification-token")),
		"deterministic verification error rejects the grant")
	_expect_false(store.owns(store.SUPPORTER), "do not grant during a deterministic error")
	_expect_equal(backend.finished_purchases.size(), 0, "must not finish during a deterministic error")
	_expect_equal(
		store.current_product_id,
		"",
		"do not hold a deterministic error as a transient retry transaction")
	_expect_equal(store.state, store.StoreState.READY, "shop flow is settled after a support error")
	_expect_equal(
		failure_codes,
		["verification-configuration-error"],
		"do not present a bad key as a brief outage")
	store.free()
	vault.free()


func _test_verification_pending_product_cannot_repurchase() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "another product's checkout flow starts")
	backend.verification_results.append({
		"success": false,
		"error_code": "verification-unavailable",
		"retryable": true,
	})
	backend.verification_results.append({
		"success": false,
		"error_code": "verification-configuration-error",
		"retryable": false,
	})

	_expect_false(
		await store.process_purchase(_android_purchase(
			store.HERO_KNIGHT, "background-retryable-token")),
		"hold a background transient verification failure")
	_expect_false(
		await store.process_purchase(_android_purchase(
			store.LANTERN_COLORS, "background-deterministic-token")),
		"isolate a background deterministic verification failure")
	backend.emit_failure(store.SUPPORTER, "user-cancelled")

	_expect_equal(store.state, store.StoreState.READY, "shop is ready after the earlier product is canceled")
	_expect_true(
		store._has_verification_pending_product(store.HERO_KNIGHT),
		"transient failure transaction is tracked")
	_expect_true(
		store._has_verification_pending_product(store.LANTERN_COLORS),
		"deterministic failure transaction is tracked")
	_expect_false(
		store.can_purchase(store.HERO_KNIGHT),
		"block duplicate purchase before re-verifying a transient failure")
	_expect_false(
		store.can_purchase(store.LANTERN_COLORS),
		"block duplicate purchase before re-verifying a deterministic failure")
	store.free()
	vault.free()


func _test_unrelated_verification_blocks_checkout_until_settled() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "earlier product checkout starts")
	backend.verification_observer = func(_purchase: Dictionary) -> void:
		# Pin an unrelated PURCHASED callback deterministically into the server-verification window.
		await backend.connected
	backend.emit_purchase(_android_purchase(
		store.HERO_KNIGHT, "unrelated-verification-in-flight"))
	_expect_true(
		store._has_processing_product(store.HERO_KNIGHT),
		"another product's in-flight server verification is tracked")
	backend.emit_failure(store.SUPPORTER, "user-cancelled")
	_expect_equal(store.state, store.StoreState.READY, "return to ready after the earlier checkout is canceled")
	_expect_false(
		store.can_purchase(store.HERO_KNIGHT),
		"block duplicate checkout of another SKU still in server verification")

	backend.connected.emit()
	await store._wait_for_purchase_callbacks()
	_expect_true(store.owns(store.HERO_KNIGHT), "grant the other SKU after verification completes")
	_expect_false(
		store._has_processing_product(store.HERO_KNIGHT),
		"release the processing lock after verification completes")
	store.free()
	vault.free()


func _test_verification_pending_revocation_settles_flow() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "iOS checkout starts before revocation")
	var purchase: Dictionary = _ios_purchase(
		store.SUPPORTER, "revoked-after-transient-verification")
	backend.verification_results.append({
		"success": false,
		"error_code": "verification-unavailable",
		"retryable": true,
	})
	_expect_false(
		await store.process_purchase(purchase),
		"hold the grant on a transient verification failure")
	var transaction_key: String = store._transaction_key(purchase)
	_expect_true(
		store._verification_pending_transactions.has(transaction_key),
		"verification-pending transaction is tracked before revocation")
	var revoked: Dictionary = purchase.duplicate(true)
	revoked["revocationDateIOS"] = 1_785_258_800_000

	_expect_true(
		await store.process_revocation(revoked),
		"handle a follow-up revocation of a verification-pending transaction as valid")
	_expect_false(
		store._verification_pending_transactions.has(transaction_key),
		"unlock a verification-pending transaction that was revoked")
	_expect_equal(store.current_product_id, "", "current product flow ends after revocation")
	_expect_equal(store.state, store.StoreState.READY, "shop returns to ready after revocation")
	_expect_equal(
		str(store.revoked_transactions.get(transaction_key, "")),
		store.SUPPORTER,
		"save a revocation tombstone to block replayed transactions")
	_expect_false(store.owns(store.SUPPORTER), "revoked transaction does not grant")
	store.free()
	vault.free()


func _test_verified_cancellation_revokes_recorded_purchase() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	var purchase: Dictionary = _android_purchase(
		store.HERO_BUNDLE, "server-canceled-token")
	_expect_true(await store.process_purchase(purchase), "purchase is granted before cancellation verification")
	_expect_true(vault.hero_open(KEEPER), "IAP hero exists before cancellation verification")
	backend.owned_purchases.append(purchase)
	backend.verification_results.append({
		"success": true,
		"is_valid": false,
		"store": "google",
		"state": "canceled",
		"product_id": store.HERO_BUNDLE,
	})

	var sync_result: Dictionary = await store._sync_available_purchases()
	_expect_true(bool(sync_result.get("success", false)), "verified cancellation sync succeeds")
	_expect_false(store.owns(store.HERO_BUNDLE), "verified cancellation claws back the entitlement")
	_expect_false(vault.hero_open(KEEPER), "verified cancellation claws back the IAP hero")
	_expect_equal(store.revoked_transactions.size(), 1, "save a tombstone for a verified cancellation")
	_expect_equal(backend.finished_purchases.size(), 1, "cancellation verification must not finish again")
	store.free()
	backend.free()
	vault.free()


func _test_refunded_android_receipt_reverified_when_missing() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	var purchase: Dictionary = _android_purchase(
		store.HERO_BUNDLE, "refunded-missing-owned-token")
	purchase["obfuscatedAccountIdAndroid"] = "private-account-id"
	purchase["obfuscatedProfileIdAndroid"] = "private-profile-id"
	purchase["developerPayloadAndroid"] = "private-developer-payload"
	purchase["dataAndroid"] = {"private": "raw-store-payload"}
	var transaction_key: String = store._transaction_key(purchase)
	_expect_true(await store.process_purchase(purchase), "purchase is granted before the Android refund")
	_expect_true(store.owns(store.HERO_BUNDLE), "entitlement exists before the Android refund")
	_expect_true(vault.hero_open(KEEPER), "IAP hero exists before the Android refund")
	_expect_true(
		store.purchase_records.has(transaction_key),
		"durable Android verification token is recorded after finish")
	var durable_record: Dictionary = store.purchase_records[transaction_key]
	_expect_equal(durable_record.size(), 6, "only the minimal refund re-verify fields and timestamp are saved")
	_expect_true(
		int(durable_record.get("lastVerifiedAtMs", 0)) > 0,
		"refund re-verify cooldown timestamp is saved")
	_expect_equal(
		durable_record.get("purchaseToken", ""),
		"refunded-missing-owned-token",
		"refund re-verify token is saved")
	for private_key in [
		"obfuscatedAccountIdAndroid",
		"obfuscatedProfileIdAndroid",
		"developerPayloadAndroid",
		"dataAndroid",
	]:
		_expect_false(
			durable_record.has(private_key),
			"unnecessary purchase personal data is not stored: %s" % private_key)
	# The next step in this test must reproduce a refund audit after 6 minutes.
	durable_record["lastVerifiedAtMs"] = 1
	store.purchase_records[transaction_key] = durable_record
	_expect_equal(store.save_entitlements(), OK, "refund re-verify past timestamp is saved")
	store.free()
	backend.free()

	# Android queryPurchasesAsync returns a refunded one-time product as an empty list.
	# On reload the stored token must be re-verified directly with IAPKit to confirm CANCELED.
	var reloaded: Node = STORE_SCRIPT.new()
	var recovered_backend: Node = FAKE_BACKEND_SCRIPT.new()
	_seed_products(recovered_backend, reloaded)
	recovered_backend.verification_results.append({
		"success": true,
		"is_valid": false,
		"store": "google",
		"state": "canceled",
		"product_id": reloaded.HERO_BUNDLE,
	})
	reloaded.set_backend_for_testing(recovered_backend)
	reloaded.set_vault_for_testing(vault)
	reloaded.load_entitlements()
	_expect_true(
		reloaded.purchase_records.has(transaction_key),
		"finished-transaction verification token is restored after reload")
	await reloaded._start_backend()

	_expect_equal(
		recovered_backend.owned_purchases.size(),
		0,
		"refunded transaction is absent from current purchases")
	_expect_equal(
		recovered_backend.verified_purchases.size(),
		1,
		"re-verify a finished token missing from the list with IAPKit")
	_expect_false(reloaded.owns(reloaded.HERO_BUNDLE), "Android refund claws back the entitlement")
	_expect_false(vault.hero_open(KEEPER), "Android refund claws back the IAP hero")
	_expect_false(
		reloaded.purchase_records.has(transaction_key),
		"refunded verification token is removed from the active ledger")
	_expect_equal(reloaded.transactions.size(), 0, "refunded transaction is removed from the active ledger")
	_expect_equal(reloaded.revoked_transactions.size(), 1, "refund transaction tombstone is saved")
	_expect_equal(
		recovered_backend.finished_purchases.size(),
		0,
		"must not finish again during refund re-verification")
	reloaded.free()
	vault.free()


## A Google consumable that has finished consume disappears from current purchases. If the
## app re-verifies the refund-check token on resume, IAPKit expresses the normal terminal
## state as `Consumed / isValid: false`. Only for a local transaction that already granted
## and finished should that be a successful no-op, not an ERROR over the whole shop.
func _test_consumed_android_receipt_is_terminal_after_finish() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()

	var purchase: Dictionary = _android_purchase(
		store.CONTINUE_COIN, "consumed-terminal-token")
	backend.verification_results.append({
		"success": true,
		"is_valid": true,
		"store": "google",
		"state": "ready-to-consume",
		"product_id": store.CONTINUE_COIN,
	})
	var coins_before: int = vault.continue_coins
	_expect_true(await store.process_purchase(purchase), "first consumable verify and grant")
	_expect_equal(vault.continue_coins, coins_before + 1, "first consumable grant count")
	_expect_equal(backend.finished_purchases.size(), 1, "first consumable consume finish")

	# Even if a finished consume lingers briefly in Play's owned snapshot, do not re-verify
	# inside IAPKit's 300-second negative replay guard.
	backend.owned_purchases.assign([purchase])
	var verified_before_stale_owned: int = backend.verified_purchases.size()
	await store._sync_after_resume()
	_expect_equal(store.state, store.StoreState.READY, "shop is ready during stale-owned cooldown")
	_expect_equal(
		backend.verified_purchases.size(),
		verified_before_stale_owned,
		"finished consume stale owned receipt is not re-verified immediately")
	_expect_equal(vault.continue_coins, coins_before + 1, "stale owned row does not re-grant")
	backend.owned_purchases.clear()

	var failure_count: Array[int] = [0]
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)
	backend.verification_results.append({
		"success": true,
		"is_valid": false,
		"store": "google",
		"state": "consumed",
		"product_id": store.CONTINUE_COIN,
	})
	# The first success timestamp is still inside IAPKit's 300-second negative cooldown. Move
	# only the record into the past so a 6-minute-later re-verify can be reproduced deterministically.
	var recorded: Dictionary = store.purchase_records[store._transaction_key(purchase)]
	recorded["lastVerifiedAtMs"] = 1
	store.purchase_records[store._transaction_key(purchase)] = recorded
	await store._sync_after_resume()

	_expect_equal(store.state, store.StoreState.READY, "shop is ready after consumed re-verification")
	_expect_equal(failure_count[0], 0, "consumed re-verification has no failure notice")
	_expect_equal(vault.continue_coins, coins_before + 1, "consumed re-verification does not re-grant")
	_expect_equal(backend.finished_purchases.size(), 1, "consumed re-verification does not finish again")
	var verified_count: int = backend.verified_purchases.size()
	await store._sync_after_resume()
	_expect_equal(store.state, store.StoreState.READY, "shop is ready during consumed cooldown")
	_expect_equal(
		backend.verified_purchases.size(),
		verified_count,
		"do not send the same receipt back to IAPKit right after consume finishes")
	_expect_equal(failure_count[0], 0, "no failure notice during consumed cooldown")

	# A new consumed token with no local finished ledger may be an attacker replay, so
	# the same response must not grant a benefit.
	backend.verification_results.append({
		"success": true,
		"is_valid": false,
		"store": "google",
		"state": "consumed",
		"product_id": store.CONTINUE_COIN,
	})
	_expect_false(
		await store.process_purchase(_android_purchase(
			store.CONTINUE_COIN, "unrecorded-consumed-token")),
		"reject a consumed transaction with no ledger")
	_expect_equal(vault.continue_coins, coins_before + 1, "rejected transaction does not grant coins")

	store.free()
	vault.free()


func _test_unknown_historical_revocation_does_not_break_sync() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	var old_revoked: Dictionary = _ios_purchase(
		store.SUPPORTER, "unknown-old-revoked-transaction")
	old_revoked["revocationDateIOS"] = 1_785_258_800_000
	var current_purchase: Dictionary = _ios_purchase(
		store.SUPPORTER, "newer-active-transaction")
	backend.owned_purchases.assign([old_revoked, current_purchase])
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()

	await store._start_backend()
	_expect_true(store.owns(store.SUPPORTER), "grant the latest transaction unrelated to a historical revocation")
	_expect_equal(
		store.state,
		store.StoreState.READY,
		"a historical revocation missing locally does not put the shop in ERROR")
	_expect_equal(store.transactions.size(), 1, "only the latest active transaction is saved on the ledger")
	_expect_equal(
		store.revoked_transactions.size(),
		0,
		"do not save an unnecessary tombstone for a historical revocation with nothing to claw back")
	# _start_backend() parents the backend under the store, so store.free() frees it too.
	# Freeing backend again here would double-end the Godot object lifetime.
	store.free()
	vault.free()


func _test_duplicate_callback_verifies_once() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	backend.verification_observer = func(_purchase: Dictionary) -> void:
		await process_frame
	var purchase: Dictionary = _android_purchase(
		store.SUPPORTER, "concurrent-verification-token")

	backend.purchase_updated.connect(store._on_purchase_updated)
	backend.emit_purchase(purchase)
	_expect_false(
		await store.process_purchase(purchase),
		"reject a duplicate callback for the same transaction during verification")
	await process_frame
	await process_frame
	_expect_true(store.owns(store.SUPPORTER), "first verified transaction is granted normally")
	_expect_equal(backend.verified_purchases.size(), 1, "same transaction is server-verified once")
	_expect_equal(backend.finished_purchases.size(), 1, "same transaction finishes once")
	backend.verification_observer = Callable()
	store.free()
	backend.free()
	vault.free()


func _test_restore_reports_verification_failure() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	backend.owned_purchases.append(_ios_purchase(
		store.LANTERN_COLORS, "restore-verification-failure"))
	backend.verification_results.append({
		"success": false,
		"error_code": "service-timeout",
	})
	var restore_finished_count: Array[int] = [0]
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	store.restore_finished.connect(
		func(_count: int) -> void: restore_finished_count[0] += 1)
	store.state_changed.connect(func() -> void: events.append("state"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	_expect_false(
		await store.restore_purchases(),
		"do not show a verification-failed restore as an empty success")
	_expect_false(store.owns(store.LANTERN_COLORS), "restore verification failure does not grant")
	_expect_equal(backend.finished_purchases.size(), 0, "restore verification failure must not finish")
	_expect_equal(restore_finished_count[0], 0, "restore verification failure must not emit a finished notice")
	_expect_equal(store.state, store.StoreState.ERROR, "restore verification failure offers retry")
	_expect_equal(
		failure_codes,
		["verification-unavailable"],
		"do not overwrite a restore transient outage with a generic query error")
	_expect_equal(
		events[-1],
		"failure:verification-unavailable",
		"keep the transient-outage UI signal after the ERROR transition")
	store.free()
	vault.free()


func _test_restore_reports_deterministic_verification_failure() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	backend.owned_purchases.append(_android_purchase(
		store.SUPPORTER, "restore-deterministic-failure"))
	backend.verification_results.append({
		"success": false,
		"error_code": "verification-configuration-error",
		"retryable": false,
	})
	var restore_finished_count: Array[int] = [0]
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	store.restore_finished.connect(
		func(_count: int) -> void: restore_finished_count[0] += 1)
	store.state_changed.connect(func() -> void: events.append("state"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	_expect_false(
		await store.restore_purchases(),
		"do not show a deterministic verification-reject restore as an empty success")
	_expect_false(store.owns(store.SUPPORTER), "deterministic restore error does not grant")
	_expect_equal(backend.finished_purchases.size(), 0, "deterministic restore error must not finish")
	_expect_equal(restore_finished_count[0], 0, "deterministic restore error must not emit a finished notice")
	_expect_equal(store.state, store.StoreState.ERROR, "deterministic restore error is a needs-support state")
	_expect_equal(
		failure_codes,
		["verification-configuration-error"],
		"do not overwrite a deterministic verification error code with a restore-query error")
	_expect_equal(
		events[-1],
		"failure:verification-configuration-error",
		"keep the needs-support UI signal after the ERROR transition")
	store.free()
	vault.free()


func _test_restore_reports_revocation_failure() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = FAILING_VAULT_SCRIPT.new()
	vault.should_fail = false
	vault.load_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	var purchase: Dictionary = _ios_purchase(
		store.HERO_BUNDLE, "restore-revocation-failure")
	_expect_true(await store.process_purchase(purchase), "hero bundle is granted before revocation failure")
	var revoked: Dictionary = purchase.duplicate(true)
	revoked["revocationDateIOS"] = 1_785_258_800_000
	backend.owned_purchases.append(revoked)
	vault.should_fail = true
	var restore_finished_count: Array[int] = [0]
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	store.restore_finished.connect(
		func(_count: int) -> void: restore_finished_count[0] += 1)
	store.state_changed.connect(func() -> void: events.append("state"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	_expect_false(
		await store.restore_purchases(),
		"do not show a benefit-revocation-failure restore as success")
	_expect_false(store.owns(store.HERO_BUNDLE), "revocation tombstone is saved even if restore fails")
	_expect_true(vault.hero_open(KEEPER), "do not mistake a benefit-save failure state for success")
	_expect_equal(store.revoked_transactions.size(), 1, "failed-revocation transaction tombstone is kept")
	_expect_equal(restore_finished_count[0], 0, "revocation failure must not emit a finished notice")
	_expect_equal(store.state, store.StoreState.ERROR, "revocation failure is a needs-support state")
	_expect_equal(
		failure_codes,
		["revocation-benefit-failed"],
		"do not overwrite a revocation-failure code with a restore-query error")
	_expect_equal(
		events[-1],
		"failure:revocation-benefit-failed",
		"keep the revocation-failure UI signal after the ERROR transition")
	store.free()
	vault.free()


func _test_connect_captures_initialize_replay_failure() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	var purchase: Dictionary = _ios_purchase(
		store.SUPPORTER, "initialize-replay-failure")
	backend.verification_results.append({
		"success": false,
		"error_code": "verification-configuration-error",
		"retryable": false,
	})
	backend.initialize_observer = func() -> void:
		backend.emit_purchase(purchase)
		await process_frame
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	var retry_snapshots: Array[bool] = []
	store.state_changed.connect(func() -> void: events.append("state"))
	store.interaction_changed.connect(
		func() -> void: retry_snapshots.append(store.can_retry_connection()))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	await store._start_backend()
	_expect_equal(store.state, store.StoreState.ERROR, "initialize replay verification reject is ERROR")
	_expect_false(store.owns(store.SUPPORTER), "initialize replay verification reject does not grant")
	_expect_equal(backend.finished_purchases.size(), 0, "initialize replay verification reject must not finish")
	_expect_equal(
		failure_codes,
		["verification-configuration-error"],
		"keep the specific error once during initialize")
	_expect_equal(
		events[-1],
		"failure:verification-configuration-error",
		"keep the specific error signal after initialize ERROR")
	_expect_equal(
		retry_snapshots[-1],
		true,
		"release the connect guard before the initialize error notice so the retry button enables")
	backend.initialize_observer = Callable()
	store.free()
	vault.free()


func _test_connect_preserves_deterministic_failure_notice() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	backend.owned_purchases.append(_android_purchase(
		store.SUPPORTER, "connect-deterministic-failure"))
	backend.verification_results.append({
		"success": false,
		"error_code": "verification-configuration-error",
		"retryable": false,
	})
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	var retry_snapshots: Array[bool] = []
	store.state_changed.connect(func() -> void: events.append("state"))
	store.interaction_changed.connect(
		func() -> void: retry_snapshots.append(store.can_retry_connection()))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	await store._start_backend()
	_expect_equal(store.state, store.StoreState.ERROR, "first-connect verification reject is ERROR")
	_expect_false(store.owns(store.SUPPORTER), "first-connect verification reject does not grant")
	_expect_equal(backend.finished_purchases.size(), 0, "first-connect verification reject must not finish")
	_expect_equal(
		failure_codes,
		["verification-configuration-error"],
		"do not overwrite a first-connect deterministic error with product-fetch copy")
	_expect_equal(
		events[-1],
		"failure:verification-configuration-error",
		"keep the needs-support UI signal after first-connect ERROR")
	_expect_equal(
		retry_snapshots[-1],
		true,
		"release the connect guard before the first-connect failure notice so the retry button enables")
	store.free()
	vault.free()


func _test_resume_preserves_transient_failure_notice() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	backend.owned_purchases.append(_ios_purchase(
		store.LANTERN_COLORS, "resume-transient-failure"))
	backend.verification_results.append({
		"success": false,
		"error_code": "service-timeout",
	})
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	store.state_changed.connect(func() -> void: events.append("state"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	await store._sync_after_resume()
	_expect_equal(store.state, store.StoreState.ERROR, "app-resume verification outage is ERROR")
	_expect_false(store.owns(store.LANTERN_COLORS), "app-resume verification outage does not grant")
	_expect_equal(backend.finished_purchases.size(), 0, "app-resume verification outage must not finish")
	_expect_equal(
		failure_codes,
		["verification-unavailable"],
		"do not overwrite an app-resume transient outage with product-fetch copy")
	_expect_equal(
		events[-1],
		"failure:verification-unavailable",
		"keep the transient-outage UI signal after app-resume ERROR")
	store.free()
	vault.free()


func _test_resume_preserves_verified_cancellation_notice() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "checkout starts before server cancel")
	backend.owned_purchases.append(_ios_purchase(
		store.SUPPORTER, "resume-verified-cancellation"))
	backend.verification_results.append({
		"success": true,
		"is_valid": false,
		"store": "apple",
		"state": "canceled",
		"product_id": store.SUPPORTER,
	})
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	var purchase_snapshots: Array[bool] = []
	store.state_changed.connect(func() -> void: events.append("state"))
	store.interaction_changed.connect(
		func() -> void:
			purchase_snapshots.append(store.can_purchase(store.SUPPORTER))
			events.append("interaction"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	await store._sync_after_resume()
	_expect_equal(store.state, store.StoreState.READY, "shop returns to ready after server cancel")
	_expect_true(store.current_product_id.is_empty(), "current checkout lock clears after server cancel")
	_expect_false(store.owns(store.SUPPORTER), "server-canceled transaction does not grant")
	_expect_equal(backend.finished_purchases.size(), 0, "server-canceled transaction must not finish")
	_expect_equal(failure_codes, ["canceled"], "keep the server-cancel notice once")
	_expect_equal(events[-1], "failure:canceled", "keep the server-canceled notice after the READY transition")
	_expect_equal(
		purchase_snapshots[-1],
		true,
		"release the resume guard before the server-cancel notice so buy buttons re-enable")
	store.free()
	vault.free()


func _test_resume_blocks_nested_store_actions() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	var first_query: Array[bool] = [true]
	var restore_attempt: Array[bool] = [true]
	var purchase_attempt: Array[bool] = [true]
	var purchase_snapshots: Array[bool] = []
	store.interaction_changed.connect(
		func() -> void:
			purchase_snapshots.append(store.can_purchase(store.SUPPORTER)))
	backend.available_observer = func() -> void:
		if not first_query[0]:
			return
		first_query[0] = false
		restore_attempt[0] = await store.restore_purchases()
		purchase_attempt[0] = store.purchase(store.SUPPORTER)
		await process_frame

	await store._sync_after_resume()
	_expect_false(restore_attempt[0], "nested restore must not start during resume sync")
	_expect_false(purchase_attempt[0], "nested purchase must not start during resume sync")
	_expect_equal(store.state, store.StoreState.READY, "shop stays ready after nested attempts are blocked")
	_expect_true(store.current_product_id.is_empty(), "no product lock after nested attempts are blocked")
	_expect_equal(
		purchase_snapshots,
		[false, true],
		"lock buy buttons when resume starts and re-enable on the finished signal")
	backend.available_observer = Callable()
	store.free()
	vault.free()


func _test_resume_waits_for_callback_started_during_maintenance() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	backend.finish_results.append(false)
	_expect_true(
		await store.process_purchase(_ios_purchase(
			store.SUPPORTER, "maintenance-pending-finish")),
		"unfinished transaction is saved before the maintenance callback")
	var callback_purchase: Dictionary = _ios_purchase(
		store.LANTERN_COLORS, "maintenance-started-callback")
	var callback_done: Array[bool] = [false]
	var should_emit: Array[bool] = [true]
	backend.verification_observer = func(_purchase: Dictionary) -> void:
		await process_frame
		await process_frame
		callback_done[0] = true
	backend.finish_observer = func(_purchase: Dictionary) -> void:
		if not should_emit[0]:
			return
		should_emit[0] = false
		backend.emit_purchase(callback_purchase)

	await store._sync_after_resume()
	_expect_equal(
		[
			callback_done[0],
			store.owns(store.LANTERN_COLORS),
			backend.finished_purchases.size(),
		],
		[true, true, 3],
		"handle even the async callback started by maintenance finish before resume completes")
	backend.finish_observer = Callable()
	backend.verification_observer = Callable()
	store.free()
	vault.free()


func _test_native_restore_failure_preserves_specific_notice() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	backend.restore_result = false
	backend.restore_observer = func() -> void:
		backend.emit_failure(store.SUPPORTER, "verification-configuration-error")
	var restore_finished_count: Array[int] = [0]
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	store.restore_finished.connect(
		func(_count: int) -> void: restore_finished_count[0] += 1)
	store.state_changed.connect(func() -> void: events.append("state"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	_expect_false(
		await store.restore_purchases(),
		"preserve the specific native restore failure")
	_expect_equal(restore_finished_count[0], 0, "native restore failure must not emit a finished notice")
	_expect_equal(
		failure_codes,
		["verification-configuration-error"],
		"do not overwrite a specific native error with restore-failed")
	_expect_equal(
		events[-1],
		"failure:verification-configuration-error",
		"keep the specific native error UI signal after restore state is settled")
	backend.restore_observer = Callable()
	store.free()
	vault.free()


func _test_native_restore_callback_failure_beats_empty_sync() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	backend.restore_observer = func() -> void:
		backend.emit_failure(store.SUPPORTER, "verification-configuration-error")
	var restore_finished_count: Array[int] = [0]
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	store.restore_finished.connect(
		func(_count: int) -> void: restore_finished_count[0] += 1)
	store.state_changed.connect(func() -> void: events.append("state"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	_expect_false(
		await store.restore_purchases(),
		"native callback error beats a later empty-query success")
	_expect_equal(restore_finished_count[0], 0, "empty restore notice forbidden after a native callback error")
	_expect_equal(store.state, store.StoreState.ERROR, "native callback error is a restore-failure state")
	_expect_equal(
		failure_codes,
		["verification-configuration-error"],
		"do not overwrite a specific native callback error with an empty restore notice")
	_expect_equal(
		events[-1],
		"failure:verification-configuration-error",
		"keep the native callback error UI signal after restore-failure state")
	backend.restore_observer = Callable()
	store.free()
	vault.free()


func _test_restore_waits_for_async_native_callback() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	var purchase: Dictionary = _ios_purchase(
		store.SUPPORTER, "async-native-restore-success")
	backend.owned_purchases.append(purchase)
	var verification_done: Array[bool] = [false]
	backend.verification_observer = func(_purchase: Dictionary) -> void:
		await process_frame
		await process_frame
		verification_done[0] = true
	backend.restore_observer = func() -> void:
		backend.emit_purchase(purchase)
	var restored_count: Array[int] = [-1]
	var restore_snapshot: Array[Variant] = []
	store.restore_finished.connect(
		func(count: int) -> void:
			restored_count[0] = count
			restore_snapshot.assign([
				verification_done[0],
				store.owns(store.SUPPORTER),
				backend.finished_purchases.size(),
			]))

	var restore_result: bool = await store.restore_purchases()
	await process_frame
	await process_frame
	await process_frame
	_expect_true(restore_result, "async native callback restore succeeds")
	_expect_true(store.owns(store.SUPPORTER), "wait for the async native callback grant to complete")
	_expect_equal(restored_count[0], 1, "restore count is computed after the async native callback grant")
	_expect_equal(backend.finished_purchases.size(), 1, "wait for the async native callback finish to complete")
	_expect_equal(
		restore_snapshot,
		[true, true, 1],
		"verification, entitlement, and finish are done by the restore-finished signal")
	backend.verification_observer = Callable()
	backend.restore_observer = Callable()
	store.free()
	vault.free()


func _test_restore_waits_for_async_native_failure() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	var purchase: Dictionary = _ios_purchase(
		store.SUPPORTER, "async-native-restore-failure")
	backend.owned_purchases.append(purchase)
	backend.verification_results.append({
		"success": false,
		"error_code": "verification-configuration-error",
		"retryable": false,
	})
	backend.verification_observer = func(_purchase: Dictionary) -> void:
		await process_frame
		await process_frame
	backend.restore_observer = func() -> void:
		backend.emit_purchase(purchase)
	var restore_finished_count: Array[int] = [0]
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	store.restore_finished.connect(
		func(_count: int) -> void:
			restore_finished_count[0] += 1
			events.append("restore"))
	store.state_changed.connect(func() -> void: events.append("state"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	var restore_result: bool = await store.restore_purchases()
	await process_frame
	await process_frame
	await process_frame
	_expect_false(restore_result, "must not return restore success for an async native verification failure")
	_expect_false(store.owns(store.SUPPORTER), "async native verification failure does not grant")
	_expect_equal(restore_finished_count[0], 0, "must not emit restore-finished after an async verification failure")
	_expect_equal(store.state, store.StoreState.ERROR, "async verification failure is a restore ERROR")
	_expect_equal(
		failure_codes,
		["verification-configuration-error"],
		"keep the specific async native verification error once")
	_expect_equal(
		events[-1],
		"failure:verification-configuration-error",
		"keep the specific error signal after the async verification-failure transition")
	backend.verification_observer = Callable()
	backend.restore_observer = Callable()
	store.free()
	vault.free()


func _test_native_restore_false_waits_for_async_callback() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	var purchase: Dictionary = _ios_purchase(
		store.SUPPORTER, "async-native-restore-false")
	var verification_done: Array[bool] = [false]
	backend.restore_result = false
	backend.verification_observer = func(_purchase: Dictionary) -> void:
		await process_frame
		await process_frame
		verification_done[0] = true
	backend.restore_observer = func() -> void:
		backend.emit_purchase(purchase)
	var failure_codes: Array[String] = []
	var failure_snapshot: Array[Variant] = []
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			failure_snapshot.assign([
				verification_done[0],
				store.owns(store.SUPPORTER),
				backend.finished_purchases.size(),
			]))

	var restore_result: bool = await store.restore_purchases()
	await process_frame
	await process_frame
	await process_frame
	_expect_false(restore_result, "keep the native false restore result")
	_expect_true(verification_done[0], "wait for verification started before native false to finish")
	_expect_true(store.owns(store.SUPPORTER), "successful callback grant completes before native false")
	_expect_equal(backend.finished_purchases.size(), 1, "successful callback finish completes before native false")
	_expect_equal(failure_codes, ["restore-failed"], "native false generic error once")
	_expect_equal(
		failure_snapshot,
		[true, true, 1],
		"async callback finishes before the native false error signal")
	backend.verification_observer = Callable()
	backend.restore_observer = Callable()
	store.free()
	vault.free()


func _test_restore_ignores_revoked_transaction_replay() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	var purchase: Dictionary = _ios_purchase(
		store.LANTERN_COLORS, "restore-revoked-replay")
	_expect_true(await store.process_purchase(purchase), "color transaction is saved before restore replay")
	var revoked: Dictionary = purchase.duplicate(true)
	revoked["revocationDateIOS"] = 1_785_258_800_000
	_expect_true(await store.process_revocation(revoked), "color transaction is revoked before restore replay")
	backend.owned_purchases.append(purchase)
	var restored_count: Array[int] = [-1]
	var failure_count: Array[int] = [0]
	store.restore_finished.connect(
		func(count: int) -> void: restored_count[0] = count)
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)

	_expect_true(
		await store.restore_purchases(),
		"replaying an old transaction blocked by a tombstone is not a restore error")
	_expect_equal(store.state, store.StoreState.READY, "shop is ready after ignoring an old revoked transaction")
	_expect_false(store.owns(store.LANTERN_COLORS), "an old revoked transaction must not resurrect the entitlement")
	_expect_equal(restored_count[0], 0, "an old revoked transaction is excluded from the restore count")
	_expect_equal(failure_count[0], 0, "replaying an old revoked transaction must not emit an error notice")
	store.free()
	vault.free()


func _test_resume_syncs_completed_pending() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "checkout starts before waiting for approval")
	backend.emit_purchase(_android_purchase(
		store.SUPPORTER, "resume-pending-token", "pending"))
	_expect_equal(store.state, store.StoreState.PENDING, "waiting for approval before backgrounding")
	backend.owned_purchases.append(_android_purchase(
		store.SUPPORTER, "resume-pending-token"))

	await store._sync_after_resume()
	_expect_true(store.owns(store.SUPPORTER), "app-resume query grants a completed payment")
	_expect_equal(store.state, store.StoreState.READY, "return to ready after app-resume grant")
	_expect_equal(store.current_product_id, "", "in-progress product is cleared after app resume")
	_expect_equal(backend.finished_purchases.size(), 1, "app-resume transaction finishes once")
	store.free()
	vault.free()


func _test_sync_discovered_pending_blocks_repurchase() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	backend.owned_purchases.append(_android_purchase(
		store.SUPPORTER, "sync-pending-token", "pending"))
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()

	await store._start_backend()
	_expect_equal(store.state, store.StoreState.PENDING, "keep the pending-transaction state that sync found")
	_expect_equal(store.current_product_id, store.SUPPORTER, "sync pending product is tracked")
	_expect_false(store.can_purchase(store.SUPPORTER), "repurchase forbidden while a pending transaction exists")
	backend.owned_purchases.clear()
	backend.owned_purchases.append(_android_purchase(
		store.SUPPORTER, "sync-pending-token"))
	await store._sync_after_resume()
	_expect_true(store.owns(store.SUPPORTER), "grant on app resume after pending approval")
	_expect_equal(store.state, store.StoreState.READY, "return to ready after pending approval")
	store.free()
	vault.free()


func _test_unrelated_pending_blocks_later_repurchase() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "current checkout starts before the other pending")
	backend.emit_purchase(_android_purchase(
		store.HERO_KNIGHT, "unrelated-pending-product-token", "pending"))
	_expect_equal(
		store.current_product_id,
		store.SUPPORTER,
		"the other pending does not overwrite the current product flow")
	backend.emit_failure(store.SUPPORTER, "user-cancelled")
	_expect_equal(store.state, store.StoreState.READY, "return to ready after the current checkout ends")
	_expect_false(store.owns(store.HERO_KNIGHT), "the other pending product is not granted")
	_expect_false(
		store.can_purchase(store.HERO_KNIGHT),
		"another pending transaction still blocks duplicate checkout of that SKU")

	# The same SKU can be bought again only after the transaction disappears from the next successful store snapshot.
	await store._sync_after_resume()
	_expect_true(
		store.can_purchase(store.HERO_KNIGHT),
		"allow checkout after pending disappears from a successful snapshot")
	store.free()
	vault.free()


func _test_pending_callback_during_query_keeps_checkout_locked() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "another product's checkout starts before the query race")
	var pending: Dictionary = _android_purchase(
		store.HERO_KNIGHT, "pending-arrived-during-query", "pending")
	backend.available_observer = func() -> void:
		# Reproduce a race where the callback arrives just after the native query already built an empty snapshot.
		backend.emit_purchase(pending)

	await store._sync_after_resume()
	backend.emit_failure(store.SUPPORTER, "user-cancelled")
	_expect_equal(store.state, store.StoreState.READY, "return to ready after the earlier checkout ends")
	_expect_false(store.owns(store.HERO_KNIGHT), "pending product is not granted during the query")
	_expect_true(
		store._has_store_pending_product(store.HERO_KNIGHT),
		"pending transaction is still tracked after a previous empty snapshot")
	_expect_false(
		store.can_purchase(store.HERO_KNIGHT),
		"a previous empty snapshot does not clear a pending lock that arrived during the query")
	store.free()
	vault.free()


func _test_completed_callback_beats_stale_pending_query() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	var transaction_key: String = "completed-during-stale-query"
	var pending: Dictionary = _android_purchase(
		store.SUPPORTER, transaction_key, "pending")
	await store.process_purchase(pending)
	backend.owned_purchases.assign([pending])
	var completed: Dictionary = _android_purchase(
		store.SUPPORTER, transaction_key)
	backend.available_observer = func() -> void:
		# Race: the callback is PURCHASED but the in-flight query still returns PENDING.
		await store.process_purchase(completed)

	await store._sync_after_resume()
	_expect_true(store.owns(store.SUPPORTER), "in-query completed callback is granted")
	_expect_false(
		store._has_store_pending_product(store.SUPPORTER),
		"a stale pending snapshot does not resurrect completed-callback state")
	_expect_equal(
		backend.verified_purchases.size(),
		1,
		"do not re-verify a stale snapshot; only handle the latest callback")
	store.free()
	vault.free()


func _test_resume_releases_missing_pending() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "checkout starts before the pending transaction disappears")
	backend.emit_purchase(_android_purchase(
		store.SUPPORTER, "missing-pending-token", "pending"))
	_expect_equal(store.state, store.StoreState.PENDING, "waiting for approval before disappearance is confirmed")
	var failure_count: Array[int] = [0]
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)

	backend.emit_disconnect()
	_expect_equal(store.state, store.StoreState.PENDING, "keep the approval-pending copy even after disconnect")
	_expect_true(store.can_retry_connection(), "retry is possible even if disconnected while waiting for approval")
	_expect_true(await store.retry_connection(), "store reconnect while waiting for approval")
	_expect_equal(store.state, store.StoreState.READY, "unlock a pending transaction that disappeared from the query")
	_expect_equal(store.current_product_id, "", "tracking of a disappeared pending product is cleared")
	_expect_equal(failure_count[0], 1, "disappeared pending transaction failure notice once")
	_expect_true(store.can_purchase(store.SUPPORTER), "repurchase is possible after the pending transaction disappears")
	store.free()
	vault.free()


func _test_resume_releases_stale_purchase_request() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "checkout request starts before the callback is lost")
	_expect_equal(store.state, store.StoreState.PURCHASING, "checkout-sheet state before the callback is lost")
	var failure_count: Array[int] = [0]
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)

	await store._sync_after_resume()
	_expect_equal(store.state, store.StoreState.READY, "resume query unlocks a lost checkout request")
	_expect_equal(store.current_product_id, "", "lost checkout request product tracking is cleared")
	_expect_equal(failure_count[0], 1, "lost checkout request failure notice once")
	_expect_true(store.can_purchase(store.SUPPORTER), "retry is possible after a lost checkout request")
	store.free()
	vault.free()


func _test_storekit_deferred_payment_stays_pending() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "checkout starts before Ask to Buy")
	var pending_count: Array[int] = [0]
	var failure_count: Array[int] = [0]
	store.purchase_pending.connect(
		func(_product_id: String) -> void: pending_count[0] += 1)
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)

	backend.purchase_failed.emit({
		"productId": store.SUPPORTER,
		"code": "deferred-payment",
	})
	_expect_equal(store.state, store.StoreState.PENDING, "show Ask to Buy as waiting for approval")
	_expect_equal(store.current_product_id, store.SUPPORTER, "Ask to Buy product is tracked")
	_expect_equal(pending_count[0], 1, "Ask to Buy pending notice once")
	_expect_equal(failure_count[0], 0, "do not show Ask to Buy as a payment failure")

	await store._sync_after_resume()
	_expect_equal(
		store.state,
		store.StoreState.PENDING,
		"Ask to Buy is kept even after a normal empty query before a transaction")
	_expect_equal(store.current_product_id, store.SUPPORTER, "Ask to Buy is still tracked after an empty query")
	_expect_equal(failure_count[0], 0, "Ask to Buy empty query must not be pending-not-found")

	backend.emit_disconnect()
	_expect_true(store.can_retry_connection(), "reconnect is possible after Ask to Buy disconnect")
	_expect_true(await store.retry_connection(), "store reconnect during Ask to Buy")
	_expect_equal(store.state, store.StoreState.PENDING, "Ask to Buy is kept after a reconnect empty query")
	_expect_equal(store.current_product_id, store.SUPPORTER, "Ask to Buy product is kept after reconnect")
	_expect_false(store.can_purchase(store.SUPPORTER), "duplicate purchase forbidden during Ask to Buy")

	backend.emit_purchase(_ios_purchase(store.SUPPORTER, "approved-ask-to-buy"))
	_expect_true(store.owns(store.SUPPORTER), "approved Ask to Buy entitlement is granted")
	_expect_equal(store.state, store.StoreState.READY, "return to ready after Ask to Buy approval")
	_expect_equal(store.current_product_id, "", "product tracking clears after Ask to Buy approval")
	store.free()
	vault.free()


func _test_disconnect_settlement_requires_retry() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "checkout request starts before disconnect")
	backend.emit_disconnect()
	backend.emit_failure(store.SUPPORTER, "service-error")

	_expect_equal(
		store.state, store.StoreState.UNAVAILABLE, "a disconnected-checkout error must not restore the ready state")
	_expect_false(store.can_purchase(store.SUPPORTER), "buy buttons stay disabled while disconnected")
	_expect_true(store.can_retry_connection(), "reconnect is offered after a disconnected-checkout error")
	_expect_true(await store.retry_connection(), "reconnect succeeds after a disconnected-checkout error")
	_expect_equal(store.state, store.StoreState.READY, "return to ready only after reconnect")
	store.free()
	vault.free()


func _test_query_failure_preserves_pending_flow() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "checkout request starts before query failure")
	backend.emit_purchase(_android_purchase(
		store.SUPPORTER, "query-failure-pending", "pending"))
	backend.available_result = false
	var failure_count: Array[int] = [0]
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)

	await store._sync_after_resume()
	_expect_equal(store.state, store.StoreState.ERROR, "do not mistake a purchase-query failure for empty")
	_expect_equal(
		store.current_product_id, store.SUPPORTER, "pending product tracking is kept after query failure")
	_expect_equal(failure_count[0], 0, "query failure must not emit pending-not-found")
	_expect_false(store.can_purchase(store.SUPPORTER), "duplicate purchase forbidden after query failure")
	_expect_true(store.can_retry_connection(), "explicit retry is offered after query failure")

	backend.available_result = true
	backend.owned_purchases.append({})
	_expect_false(await store.retry_connection(), "reject a re-query of an empty purchase row")
	_expect_equal(store.state, store.StoreState.ERROR, "ERROR is kept after an empty purchase row")
	_expect_equal(
		store.current_product_id, store.SUPPORTER, "pending product tracking is kept after an empty purchase row")
	_expect_equal(failure_count[0], 0, "an empty purchase row must not emit pending-not-found")
	backend.owned_purchases.clear()
	_expect_true(await store.retry_connection(), "a normal empty re-query succeeds after query failure")
	_expect_equal(store.state, store.StoreState.READY, "return to ready after a confirmed normal empty")
	_expect_equal(store.current_product_id, "", "pending tracking is cleared after a confirmed normal empty")
	_expect_equal(failure_count[0], 1, "pending-not-found is noticed only after a confirmed normal empty")
	store.free()
	vault.free()


func _test_grant_is_saved_before_finish() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	var order_was_safe: Array[bool] = [false]
	backend.finish_observer = func(_purchase: Dictionary) -> void:
		var saved: ConfigFile = ConfigFile.new()
		var saved_entitlements: Array = []
		if saved.load(_save_absolute) == OK:
			saved_entitlements = saved.get_value("iap", "entitlements", [])
		order_was_safe[0] = store.HERO_BUNDLE in saved_entitlements \
			and vault.hero_open(DANCER) and vault.hero_open(KEEPER)

	var purchase: Dictionary = _android_purchase(
		store.HERO_BUNDLE, "hero-bundle-token")
	_expect_true(await store.process_purchase(purchase), "hero bundle purchase is processed")
	_expect_true(order_was_safe[0], "transaction finishes only after ledger and hero saves")
	_expect_true(vault.hero_open(DANCER), "Shadow Dancer permanently unlocked")
	_expect_true(vault.hero_open(KEEPER), "Beacon Keeper permanently unlocked")
	_expect_equal(vault.shards, 0, "paid bundle does not deduct shards")
	_expect_true(
		vault.HERO_SOURCE_IAP_BUNDLE in vault.hero_sources.get(DANCER, []),
		"hero IAP source is recorded")
	_expect_equal(store.transactions.size(), 1, "transaction key is recorded once")
	_expect_equal(store.pending_finishes.size(), 0, "finished transaction is not retried")
	_expect_equal(backend.finished_purchases.size(), 1, "transaction finishes once")
	_expect_true(await store.process_purchase(purchase), "accept a duplicate callback for a finished transaction")
	_expect_equal(backend.finished_purchases.size(), 1, "duplicate callback must not finish again")
	store.free()
	backend.free()
	vault.free()


func _test_individual_hero_purchase_restore_refund_and_cache() -> void:
	_remove_save_targets()
	var expected_ids: Array[String] = [
		STORE_SCRIPT.APP_ID + ".hero_dancer",
		STORE_SCRIPT.APP_ID + ".hero_keeper",
		STORE_SCRIPT.APP_ID + ".hero_knight",
		STORE_SCRIPT.APP_ID + ".hero_eclipse",
		STORE_SCRIPT.APP_ID + ".hero_sage",
	]
	var expected_prices: Array[String] = [
		"$4.99", "$9.99", "$14.99", "$19.99", "$24.99",
	]
	_expect_equal(STORE_SCRIPT.HERO_PRODUCT_IDS, expected_ids, "exactly five individual hero SKUs")
	_expect_false(
		STORE_SCRIPT.HERO_BUNDLE in STORE_SCRIPT.SALE_PRODUCT_IDS,
		"old hero_bundle is excluded from the current sale list")

	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	var purchases: Array[Dictionary] = []
	for index in store.HERO_PRODUCT_IDS.size():
		var product_id: String = store.HERO_PRODUCT_IDS[index]
		var path: String = store.hero_path_for_product(product_id)
		var source: String = vault.hero_iap_source(path)
		_expect_equal(store.hero_product_for_path(path), product_id, "hero SKU mapping is bidirectional")
		_expect_equal(
			str(store.catalog_entry(product_id).get("usd_price", "")),
			expected_prices[index],
			"%s baseline price" % product_id)
		var purchase: Dictionary = _ios_purchase(
			product_id, "individual-purchase-%d" % index)
		purchases.append(purchase)
		_expect_true(await store.process_purchase(purchase), "%s individual purchase" % product_id)
		_expect_true(store.owns(product_id), "%s entitlement ledger" % product_id)
		_expect_true(vault.hero_open(path), "%s hero unlock" % product_id)
		_expect_equal(vault.hero_sources.get(path, []), [source], "%s exclusive source" % product_id)
		_expect_true(await store.process_purchase(purchase), "%s duplicate callback is idempotent" % product_id)
	_expect_equal(backend.finished_purchases.size(), 5, "each individual hero transaction finishes once")

	# An offline restart that keeps the IAP ledger and only deletes Vault still re-grants permanent entitlements.
	store.free()
	vault.free()
	_remove_vault_targets()
	var offline_store: Node = STORE_SCRIPT.new()
	var offline_backend: Node = FAKE_BACKEND_SCRIPT.new()
	offline_backend.initialize_result = false
	var offline_vault: Node = _new_vault()
	offline_store.set_backend_for_testing(offline_backend)
	offline_store.set_vault_for_testing(offline_vault)
	offline_store.load_entitlements()
	await offline_store._start_backend()
	_expect_equal(
		offline_store.state,
		offline_store.StoreState.UNAVAILABLE,
		"offline restart shows the shop as disconnected")
	for product_id in offline_store.HERO_PRODUCT_IDS:
		var path: String = offline_store.hero_path_for_product(product_id)
		_expect_true(offline_store.owns(product_id), "%s offline entitlement cache" % product_id)
		_expect_true(offline_vault.hero_open(path), "%s offline hero re-grant" % product_id)
		_expect_true(
			offline_vault.hero_iap_source(path) in offline_vault.hero_sources.get(path, []),
			"%s offline source restore" % product_id)
	offline_store.free()
	offline_vault.free()

	# Run a real store restore against an empty local ledger and revive each of the five SKUs.
	_remove_save_targets()
	var restored_store: Node = STORE_SCRIPT.new()
	var restored_backend: Node = FAKE_BACKEND_SCRIPT.new()
	var restored_vault: Node = _new_vault()
	_seed_products(restored_backend, restored_store)
	# Even if product details for a delisted old bundle cannot be fetched, transaction restore must
	# keep working on its own path. Current-sale catalog readiness must not be blocked by that miss.
	restored_backend.fetched_products = restored_backend.fetched_products.filter(
		func(product: Dictionary) -> bool:
			return str(product.get("id", "")) != restored_store.HERO_BUNDLE)
	restored_store.set_backend_for_testing(restored_backend)
	restored_store.set_vault_for_testing(restored_vault)
	restored_store.load_entitlements()
	await restored_store._start_backend()
	var legacy_purchase: Dictionary = _ios_purchase(
		restored_store.HERO_BUNDLE, "legacy-bundle-restore")
	var purchases_with_legacy: Array[Dictionary] = purchases.duplicate(true)
	purchases_with_legacy.append(legacy_purchase)
	restored_backend.owned_purchases.assign(purchases_with_legacy)
	var restore_counts: Array[int] = []
	restored_store.restore_finished.connect(
		func(count: int) -> void: restore_counts.append(count))
	_expect_true(await restored_store.restore_purchases(), "restore five individual heroes and the old bundle")
	_expect_equal(restore_counts, [6], "restore-finished count is five plus one old bundle")
	for product_id in restored_store.HERO_PRODUCT_IDS:
		var path: String = restored_store.hero_path_for_product(product_id)
		_expect_true(restored_store.owns(product_id), "%s fresh restore entitlement" % product_id)
		_expect_true(restored_vault.hero_open(path), "%s fresh restore hero" % product_id)

	# The old bundle is not for sale and has no product details, but Dancer+Keeper rights still restore stacked.
	for path in restored_store.HERO_BUNDLE_PATHS:
		_expect_true(
			restored_vault.HERO_SOURCE_IAP_BUNDLE \
				in restored_vault.hero_sources.get(path, []),
			"old-bundle Dancer/Keeper sources are kept")

	# A per-hero refund claws back only the mapped source; refunding the selected hero falls back to Warden on the next run.
	var sage_path: String = restored_store.hero_path_for_product(restored_store.HERO_SAGE)
	_expect_true(restored_vault.choose_hero(sage_path), "Sage is selected before refund")
	var sage_revoked: Dictionary = purchases[4].duplicate(true)
	sage_revoked["revocationDateIOS"] = 1_785_258_800_000
	_expect_true(await restored_store.process_revocation(sage_revoked), "Sage individual refund")
	_expect_false(restored_vault.hero_open(sage_path), "only the refunded Sage is locked")
	_expect_equal(
		restored_vault.hero_path(), restored_vault.HEROES[0], "fallback to Warden after refunding the selected hero")

	var knight_path: String = restored_store.hero_path_for_product(restored_store.HERO_KNIGHT)
	var knight_revoked: Dictionary = purchases[2].duplicate(true)
	knight_revoked["revocationDateIOS"] = 1_785_258_800_000
	_expect_true(await restored_store.process_revocation(knight_revoked), "Knight individual refund")
	_expect_false(restored_vault.hero_open(knight_path), "refunded Knight is locked")
	_expect_true(
		restored_vault.hero_open(
			restored_store.hero_path_for_product(restored_store.HERO_ECLIPSE)),
		"Knight refund does not touch Eclipse")

	var dancer_path: String = restored_store.hero_path_for_product(restored_store.HERO_DANCER)
	var dancer_revoked: Dictionary = purchases[0].duplicate(true)
	dancer_revoked["revocationDateIOS"] = 1_785_258_800_000
	_expect_true(await restored_store.process_revocation(dancer_revoked), "Dancer individual refund")
	_expect_true(restored_vault.hero_open(dancer_path), "Dancer is kept via the old-bundle source")
	_expect_false(
		restored_vault.hero_iap_source(dancer_path) \
			in restored_vault.hero_sources.get(dancer_path, []),
		"only the Dancer individual source is removed")
	var legacy_revoked: Dictionary = legacy_purchase.duplicate(true)
	legacy_revoked["revocationDateIOS"] = 1_785_258_800_000
	_expect_true(await restored_store.process_revocation(legacy_revoked), "old bundle refund")
	_expect_false(restored_vault.hero_open(dancer_path), "Dancer is locked after every source is gone")
	var keeper_path: String = restored_store.hero_path_for_product(restored_store.HERO_KEEPER)
	_expect_true(restored_vault.hero_open(keeper_path), "individual Keeper rights remain after a bundle refund")
	restored_store.free()
	restored_vault.free()


func _test_revocation_during_verification_is_not_lost() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	var purchase: Dictionary = _ios_purchase(
		store.HERO_BUNDLE, "verification-race-transaction")
	var revoked: Dictionary = purchase.duplicate(true)
	revoked["revocationDateIOS"] = 1_785_258_800_000
	var revocation_result: Array[bool] = [false]
	var success_count: Array[int] = [0]
	var revoked_count: Array[int] = [0]
	store.purchase_succeeded.connect(
		func(_product_id: String) -> void: success_count[0] += 1)
	store.purchase_revoked.connect(
		func(_product_id: String) -> void: revoked_count[0] += 1)
	backend.verification_observer = func(_purchase: Dictionary) -> void:
		revocation_result[0] = await store.process_revocation(revoked)

	_expect_true(await store.process_purchase(purchase), "handle a transaction revoked during verification")
	_expect_true(revocation_result[0], "accept revocation of the same transaction during verification await")
	_expect_false(store.owns(store.HERO_BUNDLE), "do not grant when revoked during verification")
	_expect_false(vault.hero_open(KEEPER), "do not grant the IAP hero when revoked during verification")
	_expect_equal(backend.finished_purchases.size(), 0, "must not finish a transaction revoked during verification")
	_expect_equal(store.revoked_transactions.size(), 1, "save a tombstone for a transaction revoked during verification")
	_expect_equal(store._deferred_revocations.size(), 0, "handle the durable revocation queue during verification")
	_expect_equal(success_count[0], 0, "must not emit a purchase-success notice for a revocation during verification")
	_expect_equal(revoked_count[0], 1, "revocation notice once during verification")
	backend.verification_observer = Callable()
	store.free()
	backend.free()
	vault.free()


func _test_revocation_during_finish_is_not_lost() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	var purchase: Dictionary = _ios_purchase(
		store.LANTERN_COLORS, "finish-race-transaction")
	var revoked: Dictionary = purchase.duplicate(true)
	revoked["revocationDateIOS"] = 1_785_258_800_000
	var success_count: Array[int] = [0]
	var revoked_count: Array[int] = [0]
	store.purchase_succeeded.connect(
		func(_product_id: String) -> void: success_count[0] += 1)
	store.purchase_revoked.connect(
		func(_product_id: String) -> void: revoked_count[0] += 1)
	backend.finish_observer = func(_purchase: Dictionary) -> void:
		store.process_revocation(revoked)

	_expect_true(await store.process_purchase(purchase), "revocation callback is accepted during finish")
	_expect_false(store.owns(store.LANTERN_COLORS), "revoked entitlement is finally clawed back during finish")
	_expect_equal(store.pending_finishes.size(), 0, "finish wait is cleared during revocation")
	_expect_equal(store.revoked_transactions.size(), 1, "revocation tombstone is saved during finish")
	_expect_equal(success_count[0], 0, "immediate revocation must not emit a purchase-success notice")
	_expect_equal(revoked_count[0], 1, "revocation notice once right after finish")
	store.free()
	backend.free()
	vault.free()


func _test_deferred_revocation_survives_restart() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	backend.finish_results.append(false)
	var purchase: Dictionary = _ios_purchase(
		store.HERO_BUNDLE, "durable-deferred-revocation")
	_expect_true(await store.process_purchase(purchase), "purchase ledger is saved before reload revocation")
	_expect_true(store.owns(store.HERO_BUNDLE), "entitlement is kept after finish failure")
	_expect_equal(store.pending_finishes.size(), 1, "failed finish stays queued for retry")
	var transaction_key: String = store._transaction_key(purchase)
	store._processing[transaction_key] = "finish"
	var revoked: Dictionary = purchase.duplicate(true)
	revoked["revocationDateIOS"] = 1_785_258_800_000

	_expect_true(await store.process_revocation(revoked), "durable revocation queue is saved during finish")
	_expect_true(
		store._deferred_revocations.has(transaction_key),
		"durable revocation queue exists before app exit")
	store.free()
	backend.free()

	var reloaded: Node = STORE_SCRIPT.new()
	var recovered_backend: Node = FAKE_BACKEND_SCRIPT.new()
	_seed_products(recovered_backend, reloaded)
	reloaded.set_backend_for_testing(recovered_backend)
	reloaded.set_vault_for_testing(vault)
	reloaded.load_entitlements()
	_expect_true(
		reloaded._deferred_revocations.has(transaction_key),
		"durable revocation queue is restored after reload")
	await reloaded._start_backend()
	_expect_false(reloaded.owns(reloaded.HERO_BUNDLE), "reload claws back the revoked entitlement")
	_expect_false(vault.hero_open(KEEPER), "reload claws back the IAP hero source")
	_expect_equal(reloaded.revoked_transactions.size(), 1, "reload saves the transaction tombstone")
	_expect_equal(reloaded._deferred_revocations.size(), 0, "processed durable revocation queue is cleared")

	var persisted: Node = STORE_SCRIPT.new()
	persisted.load_entitlements()
	_expect_equal(persisted._deferred_revocations.size(), 0, "revocation-queue removal is kept across reload")
	_expect_equal(persisted.revoked_transactions.size(), 1, "revocation tombstone is kept across reload")
	reloaded.free()
	persisted.free()
	vault.free()


func _test_deferred_revocation_save_failure_retries_in_memory() -> void:
	_remove_save_targets()
	var store: Node = FAILING_STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.fail_target_path = "user://unused-iap-failure-target"
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	backend.finish_results.append(false)
	var purchase: Dictionary = _ios_purchase(
		store.HERO_BUNDLE, "memory-deferred-revocation")
	_expect_true(await store.process_purchase(purchase), "purchase ledger is saved before in-memory revocation")
	var transaction_key: String = store._transaction_key(purchase)
	store._processing[transaction_key] = "finish"
	var revoked: Dictionary = purchase.duplicate(true)
	revoked["revocationDateIOS"] = 1_785_258_800_000
	store.fail_target_path = store.BACKUP_SAVE_PATH

	_expect_false(
		await store.process_revocation(revoked),
		"detect a revocation-queue disk save failure")
	_expect_true(
		store._deferred_revocations.has(transaction_key),
		"keep a save-failed revocation callback in session memory")

	store.fail_target_path = "user://unused-iap-failure-target"
	store._processing.erase(transaction_key)
	_expect_true(
		await store._drain_deferred_revocation(transaction_key),
		"reprocess the in-memory revocation after save-path recovery")
	_expect_false(store.owns(store.HERO_BUNDLE), "memory retry claws back the entitlement")
	_expect_false(vault.hero_open(KEEPER), "memory retry claws back the IAP hero source")
	_expect_equal(store._deferred_revocations.size(), 0, "in-memory revocation queue is cleared after recovery")
	store.free()
	backend.free()
	vault.free()


func _test_connect_reports_deferred_revocation_failure() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = FAILING_VAULT_SCRIPT.new()
	vault.should_fail = false
	vault.load_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	await _queue_deferred_hero_revocation(
		store, backend, "connect-deferred-revocation")
	vault.should_fail = true
	store._set_state(store.StoreState.ERROR)
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	store.state_changed.connect(func() -> void: events.append("state"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	_expect_false(
		await store.retry_connection(),
		"must not return shop-ready success when durable revocation fails during connect")
	_expect_equal(store.state, store.StoreState.ERROR, "durable revocation failure during connect is ERROR")
	_expect_false(store.owns(store.HERO_BUNDLE), "revocation tombstone still claws back even if connect fails")
	_expect_true(vault.hero_open(KEEPER), "detect a benefit-revocation save failure during connect")
	_expect_equal(
		failure_codes,
		["revocation-benefit-failed"],
		"keep the specific durable-revocation error once during connect")
	_expect_equal(
		events[-1],
		"failure:revocation-benefit-failed",
		"keep the durable-revocation error signal after connect ERROR")
	store.free()
	vault.free()


func _test_resume_reports_deferred_revocation_failure() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = FAILING_VAULT_SCRIPT.new()
	vault.should_fail = false
	vault.load_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	await _queue_deferred_hero_revocation(
		store, backend, "resume-deferred-revocation")
	vault.should_fail = true
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	store.state_changed.connect(func() -> void: events.append("state"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	await store._sync_after_resume()
	_expect_equal(store.state, store.StoreState.ERROR, "durable revocation failure during resume is ERROR")
	_expect_false(store.owns(store.HERO_BUNDLE), "revocation tombstone still claws back even if resume fails")
	_expect_true(vault.hero_open(KEEPER), "detect a benefit-revocation save failure during resume")
	_expect_equal(
		failure_codes,
		["revocation-benefit-failed"],
		"keep the specific durable-revocation error once during resume")
	_expect_equal(
		events[-1],
		"failure:revocation-benefit-failed",
		"keep the durable-revocation error signal after resume ERROR")
	store.free()
	vault.free()


func _test_restore_reports_deferred_revocation_failure() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = FAILING_VAULT_SCRIPT.new()
	vault.should_fail = false
	vault.load_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	await _queue_deferred_hero_revocation(
		store, backend, "restore-deferred-revocation")
	vault.should_fail = true
	var restore_finished_count: Array[int] = [0]
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	store.restore_finished.connect(
		func(_count: int) -> void:
			restore_finished_count[0] += 1
			events.append("restore"))
	store.state_changed.connect(func() -> void: events.append("state"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	_expect_false(
		await store.restore_purchases(),
		"must not return restore success when durable revocation fails during restore")
	_expect_equal(restore_finished_count[0], 0, "must not emit restore-finished after a durable revocation failure")
	_expect_equal(store.state, store.StoreState.ERROR, "durable revocation failure during restore is ERROR")
	_expect_false(store.owns(store.HERO_BUNDLE), "revocation tombstone still claws back even if restore fails")
	_expect_true(vault.hero_open(KEEPER), "detect a benefit-revocation save failure during restore")
	_expect_equal(
		failure_codes,
		["revocation-benefit-failed"],
		"keep the specific durable-revocation error once during restore")
	_expect_equal(
		events[-1],
		"failure:revocation-benefit-failed",
		"keep the durable-revocation error signal after restore ERROR")
	store.free()
	vault.free()


func _test_restore_reports_deferred_revocation_save_failure() -> void:
	_remove_save_targets()
	var store: Node = FAILING_STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.fail_target_path = "user://unused-iap-failure-target"
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	await _queue_deferred_hero_revocation(
		store, backend, "restore-deferred-save-failure")
	store.fail_target_path = store.BACKUP_SAVE_PATH
	var restore_finished_count: Array[int] = [0]
	var failure_codes: Array[String] = []
	var events: Array[String] = []
	store.restore_finished.connect(
		func(_count: int) -> void:
			restore_finished_count[0] += 1
			events.append("restore"))
	store.state_changed.connect(func() -> void: events.append("state"))
	store.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code)
			events.append("failure:" + code))

	_expect_false(
		await store.restore_purchases(),
		"must not return restore success when the durable revocation ledger fails during restore")
	_expect_equal(restore_finished_count[0], 0, "must not emit restore-finished after a revocation-ledger failure")
	_expect_equal(store.state, store.StoreState.ERROR, "revocation-ledger failure during restore is ERROR")
	_expect_true(store.owns(store.HERO_BUNDLE), "roll back the entitlement when revocation-ledger save fails")
	_expect_equal(
		failure_codes,
		["revocation-save-failed"],
		"keep the specific revocation-ledger error once during restore")
	_expect_equal(
		events[-1],
		"failure:revocation-save-failed",
		"keep the revocation-ledger error signal after restore ERROR")
	store.free()
	vault.free()


func _test_journal_failure_prevents_grant() -> void:
	_remove_save_targets()
	var store: Node = FAILING_STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()

	_expect_false(
		await store.process_purchase(_android_purchase(
			store.HERO_BUNDLE, "journal-failure-token")),
		"return a ledger save failure as a purchase failure")
	_expect_false(vault.hero_open(DANCER), "first hero is not granted after ledger failure")
	_expect_false(vault.hero_open(KEEPER), "second hero is not granted after ledger failure")
	_expect_false(store.owns(store.HERO_BUNDLE), "entitlement is rolled back after ledger failure")
	_expect_equal(store.transactions.size(), 0, "transaction key is rolled back after ledger failure")
	_expect_equal(backend.finished_purchases.size(), 0, "ledger-failure transaction must not finish")
	store.free()
	backend.free()
	vault.free()


func _test_consumable_vault_journal_survives_iap_save_failure() -> void:
	_remove_save_targets()
	var store: Node = FAILING_STORE_SCRIPT.new()
	var vault: Node = _new_vault()
	vault.load_vault()
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	var transaction_key: String = "coin-vault-before-iap-journal"
	var coins_before: int = vault.continue_coins

	_expect_false(
		store._grant_consumable(store.CONTINUE_COIN_5, transaction_key),
		"return failure when IAP ledger save fails after a Vault grant")
	_expect_equal(vault.continue_coins, coins_before + 5, "atomic grant from before failure is kept")
	_expect_equal(
		int(vault.continue_coin_grants.get(transaction_key, 0)),
		5,
		"Vault balance and transaction key are kept together")
	_expect_false(
		store.consumable_grants.has(transaction_key),
		"failed IAP ledger is rolled back in memory")

	store.fail_target_path = "user://unused-iap-failure-target"
	_expect_true(
		store._grant_consumable(store.CONTINUE_COIN_5, transaction_key),
		"retry IAP ledger save for the same transaction")
	_expect_equal(
		vault.continue_coins,
		coins_before + 5,
		"IAP ledger retry does not double-grant coins")
	_expect_equal(
		str(store.consumable_grants.get(transaction_key, "")),
		store.CONTINUE_COIN_5,
		"IAP grant ledger is complete after retry")

	# A reload that reads a schema-4-era IAP ledger must not grow the balance already
	# received; it should only fill Vault's new transaction-key ledger.
	var legacy_transaction_key: String = "legacy-iap-journal-coin"
	var coins_before_legacy_adoption: int = vault.continue_coins
	store.consumable_grants[legacy_transaction_key] = store.CONTINUE_COIN
	_expect_true(
		store._grant_consumable(store.CONTINUE_COIN, legacy_transaction_key),
		"migrate the legacy IAP consumable ledger into Vault")
	_expect_equal(
		vault.continue_coins,
		coins_before_legacy_adoption,
		"legacy IAP ledger migration does not re-grant coins")
	_expect_equal(
		int(vault.continue_coin_grants.get(legacy_transaction_key, 0)),
		1,
		"save the legacy IAP transaction key into Vault's idempotent ledger")
	store.free()
	vault.free()


func _test_primary_replica_failure_recovers_from_backup() -> void:
	_remove_save_targets()
	var store: Node = FAILING_STORE_SCRIPT.new()
	store.fail_target_path = store.SAVE_PATH
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	_expect_true(
		await store.process_purchase(_ios_purchase(
			store.SUPPORTER, "primary-mirror-failure")),
		"purchase is kept via backup commit after primary replace fails")
	_expect_true(store.owns(store.SUPPORTER), "entitlement is kept in the primary-failure session")
	_expect_true(FileAccess.file_exists(_backup_absolute), "latest backup replica exists")
	_expect_false(FileAccess.file_exists(_save_absolute), "failed primary is not created")

	var recovered: Node = STORE_SCRIPT.new()
	recovered.load_entitlements()
	_expect_true(recovered.owns(recovered.SUPPORTER), "entitlement is recovered from the higher-revision backup")
	_expect_true(FileAccess.file_exists(_save_absolute), "primary replica is repaired on load")
	_expect_equal(recovered.revision, store.revision, "revision is kept after repair")
	store.free()
	backend.free()
	vault.free()
	recovered.free()


func _test_benefit_failure_recovers_before_finish() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var failing_vault: Node = FAILING_VAULT_SCRIPT.new()
	failing_vault.load_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(failing_vault)
	store.load_entitlements()
	var purchase: Dictionary = _android_purchase(
		store.HERO_BUNDLE, "benefit-retry-token")

	_expect_false(await store.process_purchase(purchase), "detect a benefit save failure")
	_expect_true(store.owns(store.HERO_BUNDLE), "keep the permanent entitlement that justifies retry")
	_expect_equal(store.pending_finishes.size(), 1, "unfinished transaction is preserved")
	_expect_equal(backend.finished_purchases.size(), 0, "benefit-failure transaction must not finish")
	_expect_false(failing_vault.hero_open(DANCER), "no partial unlock after benefit failure")

	var recovered_vault: Node = _new_vault()
	store.set_vault_for_testing(recovered_vault)
	_expect_true(await store.process_purchase(purchase), "retry the benefit for the same transaction")
	_expect_true(recovered_vault.hero_open(DANCER), "first hero is granted on retry")
	_expect_true(recovered_vault.hero_open(KEEPER), "second hero is granted on retry")
	_expect_equal(backend.finished_purchases.size(), 1, "transaction finishes after benefit recovery")
	_expect_equal(store.pending_finishes.size(), 0, "pending ledger is cleared after benefit recovery")
	store.free()
	backend.free()
	failing_vault.free()
	recovered_vault.free()


func _test_completed_entitlement_reapplies_missing_benefit() -> void:
	_remove_save_targets()
	var original_store: Node = STORE_SCRIPT.new()
	var original_backend: Node = FAKE_BACKEND_SCRIPT.new()
	var original_vault: Node = _new_vault()
	_seed_products(original_backend, original_store)
	original_store.set_backend_for_testing(original_backend)
	original_store.set_vault_for_testing(original_vault)
	original_store.load_entitlements()
	await original_store._start_backend()
	_expect_true(
		await original_store.process_purchase(_ios_purchase(
			original_store.HERO_BUNDLE, "completed-benefit-reapply")),
		"hero transaction is finished before benefit re-apply")
	_expect_true(original_vault.hero_open(KEEPER), "hero is unlocked before benefit re-apply")
	_expect_equal(original_store.pending_finishes.size(), 0, "finished transaction has no finish wait")
	original_store.free()
	original_vault.free()
	_remove_vault_targets()

	var reloaded: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var failing_vault: Node = FAILING_VAULT_SCRIPT.new()
	_seed_products(backend, reloaded)
	failing_vault.should_fail = true
	failing_vault.load_vault()
	reloaded.set_backend_for_testing(backend)
	reloaded.set_vault_for_testing(failing_vault)
	reloaded.load_entitlements()
	var failure_codes: Array[String] = []
	reloaded.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code))

	await reloaded._start_backend()
	_expect_true(reloaded.owns(reloaded.HERO_BUNDLE), "finished transaction keeps the permanent-entitlement ledger")
	_expect_false(failing_vault.hero_open(KEEPER), "do not treat a Vault save failure as a successful unlock")
	_expect_equal(
		reloaded.state,
		reloaded.StoreState.ERROR,
		"do not hide a finished-entitlement benefit re-apply failure behind shop ready")
	_expect_equal(
		failure_codes,
		["benefit-save-failed"],
		"finished-entitlement benefit re-apply failure code noticed once")
	_expect_true(reloaded.can_retry_connection(), "explicit retry is offered after benefit re-apply failure")

	failing_vault.should_fail = false
	_expect_true(await reloaded.retry_connection(), "re-apply a finished benefit after Vault recovery")
	_expect_equal(reloaded.state, reloaded.StoreState.READY, "shop is ready after benefit re-apply")
	_expect_true(failing_vault.hero_open(DANCER), "first hero is re-applied after recovery")
	_expect_true(failing_vault.hero_open(KEEPER), "second hero is re-applied after recovery")
	_expect_equal(backend.finished_purchases.size(), 0, "do not finish a finished transaction again")
	reloaded.free()
	failing_vault.free()


func _test_finish_failure_is_retryable() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	backend.finish_results.append(false)
	backend.finish_results.append(true)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	var purchase: Dictionary = _ios_purchase(store.SUPPORTER, "ios-finish-retry")
	var success_count: Array[int] = [0]
	store.purchase_succeeded.connect(
		func(_product_id: String) -> void: success_count[0] += 1)

	_expect_true(await store.process_purchase(purchase), "benefit grant succeeds before finish failure")
	_expect_true(store.owns(store.SUPPORTER), "saved entitlement is kept even if finish fails")
	_expect_equal(store.pending_finishes.size(), 1, "failed-finish transaction is kept for retry")
	_expect_true(await store.process_purchase(purchase), "retry finish for the same transaction")
	_expect_equal(backend.finished_purchases.size(), 2, "retry once after finish failure")
	_expect_equal(store.pending_finishes.size(), 0, "pending is cleared after retry succeeds")
	_expect_true(await store.process_purchase(purchase), "accept a duplicate callback after finish")
	_expect_equal(backend.finished_purchases.size(), 2, "must not finish again after finish")
	_expect_equal(success_count[0], 1, "finish retry and duplicate callback must not duplicate the success notice")
	store.free()
	backend.free()
	vault.free()


func _test_restarted_finish_failure_requires_retry() -> void:
	_remove_save_targets()
	var original: Node = STORE_SCRIPT.new()
	var original_backend: Node = FAKE_BACKEND_SCRIPT.new()
	var original_vault: Node = _new_vault()
	original_backend.finish_results.append(false)
	original.set_backend_for_testing(original_backend)
	original.set_vault_for_testing(original_vault)
	original.load_entitlements()
	var purchase: Dictionary = _android_purchase(
		original.SUPPORTER, "restart-finish-retry")
	_expect_true(await original.process_purchase(purchase), "entitlement is granted before restart")
	_expect_equal(original.pending_finishes.size(), 1, "finish wait is saved before restart")
	original.free()
	original_backend.free()
	original_vault.free()

	var recovered: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, recovered)
	backend.finish_results.append(false)
	backend.finish_results.append(false)
	backend.finish_results.append(true)
	recovered.set_backend_for_testing(backend)
	recovered.set_vault_for_testing(vault)
	recovered.load_entitlements()
	var failure_codes: Array[String] = []
	recovered.purchase_failed.connect(
		func(_product_id: String, code: String) -> void:
			failure_codes.append(code))

	await recovered._start_backend()
	_expect_equal(
		recovered.state,
		recovered.StoreState.ERROR,
		"do not hide a restart finish re-failure behind READY")
	_expect_equal(recovered.pending_finishes.size(), 1, "re-failed transaction stays on the ledger")
	_expect_false(
		recovered._processing.has(recovered._transaction_key(purchase)),
		"processing lock is released after re-failure")
	_expect_equal(failure_codes, ["finish-failed"], "finish-only retry error notice")
	_expect_true(recovered.can_retry_connection(), "explicit reconnect is possible after finish failure")
	_expect_true(await recovered.retry_connection(), "the next finish retry succeeds")
	_expect_equal(recovered.state, recovered.StoreState.READY, "ready state after finish succeeds")
	_expect_equal(recovered.pending_finishes.size(), 0, "pending ledger is cleared after finish succeeds")
	_expect_equal(backend.finished_purchases.size(), 3, "finish is attempted three times after restart")
	recovered.free()
	vault.free()


func _test_unrelated_duplicate_keeps_purchase_open() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	var completed_color: Dictionary = _ios_purchase(
		store.LANTERN_COLORS, "completed-color-transaction")
	_expect_true(await store.process_purchase(completed_color), "preceding color transaction is finished")
	_expect_true(store.purchase(store.SUPPORTER), "follow-up supporter checkout starts")
	_expect_equal(store.state, store.StoreState.PURCHASING, "follow-up checkout is in progress")
	var pending_count: Array[int] = [0]
	var failure_count: Array[int] = [0]
	var success_count: Array[int] = [0]
	store.purchase_pending.connect(
		func(_product_id: String) -> void: pending_count[0] += 1)
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)
	store.purchase_succeeded.connect(
		func(_product_id: String) -> void: success_count[0] += 1)
	_expect_true(
		await store.process_purchase(_ios_purchase(
			store.HERO_BUNDLE, "unrelated-background-transaction")),
		"another product's background transaction is granted")
	_expect_true(store.owns(store.HERO_BUNDLE), "the other product's entitlement is saved normally")
	_expect_equal(success_count[0], 0, "another product's success notice must not overwrite the current checkout")
	backend.emit_purchase(_android_purchase(
		store.LANTERN_COLORS, "unrelated-pending-token", "pending"))
	backend.emit_failure(store.LANTERN_COLORS, "unrelated-error")
	_expect_equal(pending_count[0], 0, "another product's pending notice must not overwrite the current checkout")
	_expect_equal(failure_count[0], 0, "another product's error notice must not overwrite the current checkout")

	_expect_true(
		await store.process_purchase(completed_color), "accept a duplicate callback for another product")
	_expect_equal(
		store.current_product_id, store.SUPPORTER, "follow-up product is kept after a duplicate callback")
	_expect_equal(
		store.state, store.StoreState.PURCHASING, "checkout state is kept after a duplicate callback")
	backend.emit_failure(store.SUPPORTER, "user-cancelled")
	_expect_equal(store.state, store.StoreState.READY, "return to ready only on the actual follow-up cancel")
	store.free()
	vault.free()


func _test_sync_unrelated_failure_keeps_active_flow() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "supporter checkout starts before the background error")
	backend.owned_purchases.append(_android_purchase(
		store.SUPPORTER, "active-sync-pending", "pending"))
	backend.owned_purchases.append(_android_purchase(
		store.HERO_BUNDLE, "unrelated-sync-rejection"))
	backend.verification_results.append({
		"success": false,
		"error_code": "verification-configuration-error",
		"retryable": false,
	})
	var failure_count: Array[int] = [0]
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)

	var sync_result: Dictionary = await store._sync_available_purchases()
	_expect_true(
		bool(sync_result.get("success", false)),
		"another product's deterministic error does not fail the current checkout sync")
	_expect_equal(store.state, store.StoreState.PENDING, "current product stays waiting for approval")
	_expect_equal(
		store.current_product_id,
		store.SUPPORTER,
		"a background verification error does not change the current product")
	_expect_false(store.owns(store.HERO_BUNDLE), "rejected background product is not granted")
	_expect_equal(backend.finished_purchases.size(), 0, "rejected background transaction must not finish")
	_expect_equal(failure_count[0], 0, "a background error must not overwrite current checkout copy")
	store.free()
	vault.free()


func _test_connect_unrelated_failure_keeps_active_flow() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	_expect_true(store.purchase(store.SUPPORTER), "supporter checkout starts before reconnect isolation")
	backend.emit_disconnect()
	backend.owned_purchases.append(_android_purchase(
		store.SUPPORTER, "active-connect-pending", "pending"))
	backend.owned_purchases.append(_android_purchase(
		store.HERO_BUNDLE, "unrelated-connect-rejection"))
	backend.verification_results.append({
		"success": false,
		"error_code": "verification-configuration-error",
		"retryable": false,
	})
	var failure_count: Array[int] = [0]
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)

	_expect_true(
		await store.retry_connection(),
		"another product's error during reconnect does not fail the current checkout sync")
	_expect_equal(store.state, store.StoreState.PENDING, "current product stays waiting for approval after reconnect")
	_expect_equal(
		store.current_product_id,
		store.SUPPORTER,
		"a reconnect background error does not change the current product")
	_expect_false(store.owns(store.HERO_BUNDLE), "the other product rejected on reconnect is not granted")
	_expect_equal(backend.finished_purchases.size(), 0, "rejected other transaction must not finish")
	_expect_equal(failure_count[0], 0, "a reconnect other-product error must not overwrite current checkout copy")
	store.free()
	vault.free()


func _test_revoked_replay_keeps_repurchase_open() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	var old_purchase: Dictionary = _ios_purchase(
		store.LANTERN_COLORS, "old-repurchase-transaction")
	_expect_true(await store.process_purchase(old_purchase), "old transaction is granted before repurchase")
	var revoked: Dictionary = old_purchase.duplicate(true)
	revoked["revocationDateIOS"] = 1_785_258_800_000
	_expect_true(await store.process_revocation(revoked), "old transaction is revoked before repurchase")
	_expect_true(store.purchase(store.LANTERN_COLORS), "start a new repurchase of the same product")
	var failure_count: Array[int] = [0]
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)

	_expect_true(await store.process_revocation(revoked), "old revocation callback is received again")
	_expect_equal(
		store.state, store.StoreState.PURCHASING, "new repurchase state is kept after replaying the old revocation")
	_expect_equal(
		store.current_product_id,
		store.LANTERN_COLORS,
		"replaying an old revocation must not clear a new repurchase of the same product")
	_expect_false(
		await store.process_purchase(old_purchase), "reject replay of a revoked old transaction")
	_expect_equal(
		store.state, store.StoreState.PURCHASING, "new repurchase is kept after replaying the old transaction")
	_expect_equal(
		store.current_product_id,
		store.LANTERN_COLORS,
		"an old transaction must not clear the new repurchase product")
	_expect_equal(failure_count[0], 0, "an old-transaction error must not overwrite the new repurchase notice")
	backend.emit_failure(store.LANTERN_COLORS, "user-cancelled")
	_expect_equal(store.state, store.StoreState.READY, "only an actual repurchase cancel ends the flow")
	store.free()
	vault.free()


func _test_legacy_entitlement_can_be_revoked() -> void:
	_remove_save_targets()
	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value("iap", "schema_version", 1)
	legacy.set_value("iap", "entitlements", [STORE_SCRIPT.SUPPORTER])
	legacy.set_value("iap", "transactions", {})
	legacy.set_value("iap", "pending_finishes", {})
	legacy.set_value("iap", "selected_palette", "ember")
	_expect_equal(legacy.save(_save_absolute), OK, "prepare a legacy IAP entitlement with no transaction key")
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	_expect_true(store.owns(store.SUPPORTER), "legacy IAP entitlement is migrated")
	var revoked: Dictionary = _ios_purchase(
		store.SUPPORTER, "legacy-revoked-transaction")
	revoked["revocationDateIOS"] = 1_785_258_800_000

	_expect_true(await store.process_revocation(revoked), "accept revocation of a legacy entitlement with no transaction key")
	_expect_false(store.owns(store.SUPPORTER), "claw back a legacy entitlement with no transaction key")
	_expect_equal(store.revoked_transactions.size(), 1, "save a tombstone for a revoked legacy entitlement")
	store.free()
	backend.free()
	vault.free()


func _test_vault_iap_source_can_be_revoked_without_iap_journal() -> void:
	_remove_save_targets()
	var vault: Node = _new_vault()
	_expect_true(
		vault.grant_heroes(
			STORE_SCRIPT.HERO_BUNDLE_PATHS,
			vault.HERO_SOURCE_IAP_BUNDLE),
		"prepare a selectively restored Vault IAP hero")
	_expect_true(vault.hero_open(KEEPER), "Vault hero source exists without an IAP ledger")
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	_expect_false(store.owns(store.HERO_BUNDLE), "IAP ledger is empty in the selective-restore situation")
	var revoked: Dictionary = _ios_purchase(
		store.HERO_BUNDLE, "vault-only-revocation")
	revoked["revocationDateIOS"] = 1_785_258_800_000

	_expect_true(
		await store.process_revocation(revoked),
		"a trusted revocation uses the Vault IAP source as recovery evidence")
	_expect_false(vault.hero_open(KEEPER), "claw back an IAP-only hero from selective restore")
	_expect_false(
		vault.any_hero_has_source(
			store.HERO_BUNDLE_PATHS,
			vault.HERO_SOURCE_IAP_BUNDLE),
		"selectively restored IAP source is removed")
	_expect_equal(store.revoked_transactions.size(), 1, "save a revocation tombstone from Vault evidence")
	store.free()
	backend.free()
	vault.free()


func _test_explicit_revocation_preserves_play_progress() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	var purchase: Dictionary = _ios_purchase(
		store.HERO_BUNDLE, "revoked-hero-transaction")
	purchase["purchaseToken"] = "original-purchase-jws"
	_expect_true(await store.process_purchase(purchase), "hero bundle is granted before revocation")
	var dancer_only: Array[String] = [DANCER]
	_expect_true(
		vault.grant_heroes(dancer_only, vault.HERO_SOURCE_SHARDS),
		"play unlock source is added")
	var revoked: Dictionary = purchase.duplicate(true)
	revoked["purchaseToken"] = "revocation-update-jws"
	revoked["revocationDateIOS"] = 1_785_258_800_000
	var wrong_app_revocation: Dictionary = revoked.duplicate(true)
	wrong_app_revocation["appBundleIdIOS"] = "dev.example.other"
	var revoked_count: Array[int] = [0]
	store.purchase_revoked.connect(
		func(_product_id: String) -> void: revoked_count[0] += 1)

	_expect_false(
		await store.process_revocation(wrong_app_revocation),
		"reject a revocation callback with another app's identity")
	_expect_true(store.owns(store.HERO_BUNDLE), "entitlement is kept after another app's revocation")
	_expect_true(vault.hero_open(KEEPER), "IAP hero is kept after another app's revocation")
	_expect_equal(store.revoked_transactions.size(), 0, "must not tombstone another app's revocation")
	_expect_true(await store.process_revocation(revoked), "explicit refund signal is handled")
	_expect_false(store.owns(store.HERO_BUNDLE), "refunded bundle entitlement is clawed back")
	_expect_true(vault.hero_open(DANCER), "hero with a shard source is kept")
	_expect_false(vault.hero_open(KEEPER), "hero that had only an IAP source is locked")
	_expect_true(
		vault.HERO_SOURCE_SHARDS in vault.hero_sources.get(DANCER, []),
		"shard unlock source is kept")
	_expect_false(
		vault.HERO_SOURCE_IAP_BUNDLE in vault.hero_sources.get(DANCER, []),
		"IAP hero source is removed")
	_expect_true(store.HERO_BUNDLE in store.revoked_products, "revocation tombstone is recorded permanently")
	_expect_equal(store.revoked_transactions.size(), 1, "revoked transaction key is recorded permanently")
	_expect_equal(store.transactions.size(), 0, "revoked product's transaction key is removed")
	_expect_equal(store.pending_finishes.size(), 0, "revoked product's finish wait is cleared")
	_expect_equal(backend.finished_purchases.size(), 1, "must not finish on a refund signal")
	_expect_true(await store.process_revocation(revoked), "duplicate refund signal is handled idempotently")
	_expect_equal(revoked_count[0], 1, "duplicate refund notice is forbidden")
	_expect_false(await store.process_purchase(purchase), "reject a purchase-callback replay from before revocation")
	_expect_false(store.owns(store.HERO_BUNDLE), "revoked entitlement is kept after replaying an old purchase")
	_expect_equal(backend.finished_purchases.size(), 1, "replaying an old purchase must not finish")

	var incomplete: ConfigFile = ConfigFile.new()
	incomplete.set_value("iap", "schema_version", store.SCHEMA_VERSION)
	incomplete.set_value("iap", "entitlements", [store.HERO_BUNDLE])
	_expect_equal(incomplete.save(_save_absolute), OK, "prepare a corrupt primary after revocation")
	var reloaded: Node = STORE_SCRIPT.new()
	reloaded.load_entitlements()
	_expect_true(
		reloaded.HERO_BUNDLE in reloaded.revoked_products, "revocation tombstone is kept across reload")
	_expect_equal(reloaded.revoked_transactions.size(), 1, "revoked transaction is recovered from backup")
	_expect_false(reloaded.owns(reloaded.HERO_BUNDLE), "no revoked entitlement after reload")
	_expect_true(
		vault.grant_heroes(
			store.HERO_BUNDLE_PATHS, vault.HERO_SOURCE_IAP_BUNDLE),
		"prepare a separately restored Vault situation")
	_expect_true(vault.hero_open(KEEPER), "IAP hero exists right after a separate restore")
	var recovered_backend: Node = FAKE_BACKEND_SCRIPT.new()
	reloaded.set_backend_for_testing(recovered_backend)
	reloaded.set_vault_for_testing(vault)
	await reloaded._start_backend()
	_expect_false(vault.hero_open(KEEPER), "revocation backup claws the IAP hero back again")
	var repurchase: Dictionary = _ios_purchase(
		store.HERO_BUNDLE, "repurchased-hero-transaction")
	_expect_true(await store.process_purchase(repurchase), "new transaction is repurchased after refund")
	_expect_false(store.HERO_BUNDLE in store.revoked_products, "revocation tombstone is removed after repurchase")
	_expect_true(vault.hero_open(KEEPER), "IAP hero is granted again after repurchase")
	_expect_equal(backend.finished_purchases.size(), 2, "repurchase transaction finishes once")
	_expect_true(await store.process_revocation(revoked), "old revocation is received again after repurchase")
	_expect_true(store.owns(store.HERO_BUNDLE), "an old revocation does not claw back a newer transaction's entitlement")
	_expect_true(vault.hero_open(KEEPER), "the new-transaction hero is kept after the old revocation")
	_expect_equal(revoked_count[0], 1, "re-receiving an old revocation has no extra clawback notice")
	store.free()
	backend.free()
	vault.free()
	reloaded.free()


func _test_revocation_benefit_retry() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = FAILING_VAULT_SCRIPT.new()
	vault.should_fail = false
	vault.load_vault()
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	var purchase: Dictionary = _ios_purchase(
		store.HERO_BUNDLE, "retry-revocation-transaction")
	_expect_true(await store.process_purchase(purchase), "hero is granted before clawback retry")
	vault.should_fail = true
	var revoked: Dictionary = purchase.duplicate(true)
	revoked["revocationDateIOS"] = 1_785_258_800_000
	var revoked_count: Array[int] = [0]
	store.purchase_revoked.connect(
		func(_product_id: String) -> void: revoked_count[0] += 1)

	_expect_false(await store.process_revocation(revoked), "detect a Vault clawback failure")
	_expect_false(store.owns(store.HERO_BUNDLE), "revoked entitlement is saved even if clawback fails")
	_expect_equal(store.revoked_transactions.size(), 1, "transaction tombstone is saved even if clawback fails")
	_expect_true(vault.hero_open(KEEPER), "clawback save failure rolls Vault state back")
	_expect_equal(revoked_count[0], 0, "must not emit a revocation-success notice before clawback completes")

	vault.should_fail = false
	_expect_true(await store.process_revocation(revoked), "retry clawback with the same revocation callback")
	_expect_false(vault.hero_open(KEEPER), "IAP hero is clawed back after retry")
	_expect_equal(revoked_count[0], 1, "revocation notice once when clawback succeeds")
	_expect_true(await store.process_revocation(revoked), "accept a duplicate of a completed revocation")
	_expect_equal(revoked_count[0], 1, "completed revocation notice must not duplicate")
	store.free()
	backend.free()
	vault.free()


func _test_restore_pending_keeps_pending_notice() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	backend.owned_purchases.append(_android_purchase(
		store.SUPPORTER, "restore-pending-token", "pending"))
	var pending_count: Array[int] = [0]
	var restore_finished_count: Array[int] = [0]
	store.purchase_pending.connect(
		func(_product_id: String) -> void: pending_count[0] += 1)
	store.restore_finished.connect(
		func(_count: int) -> void: restore_finished_count[0] += 1)

	_expect_true(await store.restore_purchases(), "confirm an approval-pending transaction during restore")
	_expect_equal(store.state, store.StoreState.PENDING, "keep the waiting-for-approval state after restore")
	_expect_equal(store.current_product_id, store.SUPPORTER, "restore tracks the approval-pending product")
	_expect_equal(pending_count[0], 1, "approval-pending notice once during restore")
	_expect_equal(
		restore_finished_count[0],
		0,
		"an empty restore-finished notice must not overwrite the approval-pending notice")
	store.free()
	vault.free()


func _test_restore_counts_native_callback_before_completion() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	var purchase: Dictionary = _ios_purchase(
		store.SUPPORTER, "native-restore-callback-transaction")
	var unrelated_purchase: Dictionary = _ios_purchase(
		"com.crossplatformkorea.moonlitbeacon.legacy",
		"native-restore-unrelated-transaction")
	backend.owned_purchases.append(purchase)
	backend.restore_observer = func() -> void:
		backend.emit_purchase(unrelated_purchase)
		backend.emit_failure(
			"com.crossplatformkorea.moonlitbeacon.legacy",
			"legacy-restore-error")
		backend.emit_purchase(purchase)
	var restored_count: Array[int] = [-1]
	var failure_count: Array[int] = [0]
	store.restore_finished.connect(
		func(count: int) -> void: restored_count[0] = count)
	store.purchase_failed.connect(
		func(_product_id: String, _code: String) -> void: failure_count[0] += 1)

	_expect_true(await store.restore_purchases(), "native callback restore succeeds first")
	_expect_true(store.owns(store.SUPPORTER), "native callback restores the entitlement first")
	_expect_equal(restored_count[0], 1, "notice one restore based on entitlements from before restore")
	_expect_equal(backend.finished_purchases.size(), 1, "finish once after a duplicate query")
	_expect_equal(failure_count[0], 0, "another system's SKU must not overwrite the restore-success notice")
	# Release the self-capturing test Callable so Godot shutdown does not leave a reference cycle.
	backend.restore_observer = Callable()
	store.free()
	vault.free()


## Continue coins are this repository's first consumable. Pin the four splits from non-consumables
## — repeat purchase, exclusion from permanent entitlements, consumable finish, **once per transaction key**.
##
## The last item is the important one. Coins are additive, so reading the same transaction twice
## would stack twice. Real money is on the line, so cover restart and re-verify paths too.
func _test_consumable_continue_coin() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()

	_expect_true(
		STORE_SCRIPT.is_consumable(STORE_SCRIPT.CONTINUE_COIN),
		"continue coins are a consumable")
	_expect_false(
		STORE_SCRIPT.is_consumable(STORE_SCRIPT.SUPPORTER),
		"supporter is not a consumable")

	var coins_before: int = vault.continue_coins
	var first: Dictionary = _android_purchase(STORE_SCRIPT.CONTINUE_COIN, "coin-1")
	store._on_purchase_updated(first)
	await store._wait_for_purchase_callbacks()
	_expect_equal(vault.continue_coins, coins_before + 1, "one purchase grants one coin")
	_expect_false(
		store.owns(STORE_SCRIPT.CONTINUE_COIN),
		"consumable is not owned as a permanent entitlement")
	_expect_false(
		STORE_SCRIPT.CONTINUE_COIN in store.entitlements,
		"consumable does not remain in entitlements")
	if not backend.finished_consumable_flags.is_empty():
		_expect_true(
			bool(backend.finished_consumable_flags.back()),
			"consumable must finish as consumable to be bought again")

	# Replaying the same transaction must not grow coins. Store resync and restart normally
	# bring the same transaction back, so this is where that must be blocked.
	store._on_purchase_updated(first)
	await store._wait_for_purchase_callbacks()
	_expect_equal(
		vault.continue_coins, coins_before + 1, "reprocessing the same transaction does not grant")

	# A different transaction grants again — repeat purchase is normal for consumables.
	var second: Dictionary = _android_purchase(STORE_SCRIPT.CONTINUE_COIN, "coin-2")
	store._on_purchase_updated(second)
	await store._wait_for_purchase_callbacks()
	_expect_equal(vault.continue_coins, coins_before + 2, "a new transaction grants again")

	# Reloading the save (app restart) keeps the grant ledger so it does not stack again.
	store.load_entitlements()
	_expect_equal(
		store.consumable_grants.size(), 2, "grant ledger remains after reload")
	store._on_purchase_updated(first)
	await store._wait_for_purchase_callbacks()
	_expect_equal(
		vault.continue_coins, coins_before + 2, "the same transaction is not re-granted after restart")

	# Spend side. With a zero balance, spend does nothing.
	_expect_true(vault.spend_continue_coin(), "spend succeeds when coins remain")
	_expect_equal(vault.continue_coins, coins_before + 1, "spending decreases by one")

	# Packs. They share the single-coin ledger but stack several in one transaction — if the
	# grant count disagrees with the store title, that is grounds for a refund.
	var bundle_base: int = vault.continue_coins
	for bundle_product_id in [
			STORE_SCRIPT.CONTINUE_COIN_5, STORE_SCRIPT.CONTINUE_COIN_10]:
		var expected: int = int(
			STORE_SCRIPT.CONSUMABLE_GRANTS.get(bundle_product_id, 0))
		_expect_true(
			STORE_SCRIPT.is_consumable(bundle_product_id),
			"%s consumable classification" % bundle_product_id)
		var bundle: Dictionary = _android_purchase(
			bundle_product_id, "bundle-" + str(expected))
		store._on_purchase_updated(bundle)
		await store._wait_for_purchase_callbacks()
		_expect_equal(
			vault.continue_coins, bundle_base + expected,
			"%s purchase grants %d coins" % [bundle_product_id, expected])
		# Packs would also stack twice if the same transaction is read twice. Confirm the ledger blocks that.
		store._on_purchase_updated(bundle)
		await store._wait_for_purchase_callbacks()
		_expect_equal(
			vault.continue_coins, bundle_base + expected,
			"%s reprocessing the same transaction does not grant" % bundle_product_id)
		_expect_false(
			store.owns(bundle_product_id),
			"%s is not owned as a permanent entitlement" % bundle_product_id)
		while vault.continue_coins > bundle_base:
			vault.spend_continue_coin()
	_expect_equal(
		int(STORE_SCRIPT.CONSUMABLE_GRANTS.get(STORE_SCRIPT.CONTINUE_COIN, 0)),
		1,
		"single-pack grant stays one, as listed on the store")

	while vault.continue_coins > 0:
		vault.spend_continue_coin()
	_expect_false(vault.spend_continue_coin(), "spend fails when the balance is 0")
	_expect_equal(
		vault.STARTING_COINS, 2, "a new vault starts with two free continues")
	_expect_equal(vault.continue_coins, 0, "failed spend does not touch the balance")

	store.free()
	vault.free()


## A product query that never answers must not lock the shop forever.
##
## Copied from what happened on a Pixel 10 on 2026-08-06. IAPKit verification rejected a
## purchase that was never finished, it stayed on the account, the `fetchProducts` callback
## never arrived even after several minutes, and that await never returning killed even
## "Reconnect". With no answer, time out, return an empty list, and let the user press again.
func _test_hung_product_fetch_gives_up() -> void:
	var plugin: Node = HANGING_IAP_PLUGIN_SCRIPT.new()
	root.add_child(plugin)
	var backend: Node = GODOT_BACKEND_SCRIPT.new(plugin, "openiap-kit_pk_test")
	root.add_child(backend)
	backend._fetch_timeout_seconds = 0.4

	var started_msec: int = Time.get_ticks_msec()
	var fetched: Array[Dictionary] = await backend.fetch_products(
		STORE_SCRIPT.PRODUCT_IDS)
	var elapsed_msec: int = Time.get_ticks_msec() - started_msec

	_expect_equal(plugin.fetch_calls, 1, "query is attempted once")
	_expect_true(fetched.is_empty(), "a query with no answer is an empty list")
	_expect_true(
		elapsed_msec < 5_000,
		"give up within the time limit — actually %dms" % elapsed_msec)

	# It must be callable again. If the first attempt still holds the coroutine, this hangs.
	plugin.should_answer = true
	var retried: Array[Dictionary] = await backend.fetch_products(
		STORE_SCRIPT.PRODUCT_IDS)
	_expect_equal(plugin.fetch_calls, 2, "re-query is possible even after the timeout")
	_expect_true(retried.is_empty(), "an empty response is an empty list")

	backend.queue_free()
	plugin.queue_free()


func _test_restore_and_palette_persistence() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	var backend: Node = FAKE_BACKEND_SCRIPT.new()
	var vault: Node = _new_vault()
	_seed_products(backend, store)
	store.set_backend_for_testing(backend)
	store.set_vault_for_testing(vault)
	store.load_entitlements()
	await store._start_backend()
	backend.owned_purchases.append(
		_ios_purchase(store.LANTERN_COLORS, "restore-lantern-transaction"))
	var restored_count: Array[int] = [-1]
	store.restore_finished.connect(
		func(count: int) -> void: restored_count[0] = count)

	_expect_true(await store.restore_purchases(), "explicit purchase restore succeeds")
	_expect_equal(restored_count[0], 1, "notice one newly restored entitlement")
	_expect_true(store.owns(store.LANTERN_COLORS), "lantern color entitlement is restored")
	_expect_equal(store.available_palettes().size(), 4, "four paid colors are offered")
	_expect_true(store.select_palette("moon"), "moon blue is selected")
	_expect_false(store.select_palette("not-a-palette"), "reject a color outside the catalog")
	var color_revocation: Dictionary = _ios_purchase(
		store.LANTERN_COLORS, "restore-lantern-transaction")
	color_revocation["revocationDateIOS"] = 1_785_258_800_000
	_expect_true(
		await store.process_revocation(color_revocation), "explicit revocation of a color purchase is handled")
	_expect_equal(store.selected_palette, store.DEFAULT_PALETTE, "return to the default color after refund")
	_expect_equal(store.available_palettes(), [store.DEFAULT_PALETTE], "paid colors lock after refund")

	var reloaded: Node = STORE_SCRIPT.new()
	reloaded.load_entitlements()
	_expect_false(reloaded.owns(reloaded.LANTERN_COLORS), "refunded entitlement is gone after reload")
	_expect_equal(
		reloaded.selected_palette, reloaded.DEFAULT_PALETTE, "default color is kept across reload")
	backend.owned_purchases.clear()
	backend.owned_purchases.append(_android_purchase(
		store.LANTERN_COLORS, "restored-after-refund-token"))
	_expect_true(await store.restore_purchases(), "restore the same purchase again")
	_expect_equal(restored_count[0], 1, "restore with a new transaction ID is one entitlement")
	_expect_true(store.owns(store.LANTERN_COLORS), "new-transaction entitlement is restored after refund")
	_expect_equal(backend.finished_purchases.size(), 2, "the new restore transaction is finished")
	store.free()
	reloaded.free()
	vault.free()


func _test_unowned_palette_is_not_rendered() -> void:
	var store: Node = STORE_SCRIPT.new()
	store.selected_palette = "moon"
	_expect_false(store.owns(store.LANTERN_COLORS), "test premise: no color entitlement")
	_expect_equal(
		store.lantern_light_color(),
		store.PALETTES[store.DEFAULT_PALETTE]["light"],
		"saved color without entitlement renders as the default light")
	_expect_equal(
		store.lantern_glow_color(),
		store.PALETTES[store.DEFAULT_PALETTE]["glow"],
		"saved color without entitlement renders as the default glow")
	_expect_equal(
		store.palette_name(),
		tr(str(store.PALETTES[store.DEFAULT_PALETTE]["name"])),
		"saved color name without entitlement is also the default")
	store.entitlements.append(store.LANTERN_COLORS)
	_expect_equal(
		store.lantern_light_color(),
		store.PALETTES["moon"]["light"],
		"with entitlement, the saved paid color is rendered")
	store.free()


func _test_versioned_primary_beats_backup() -> void:
	_remove_save_targets()
	var backup: ConfigFile = ConfigFile.new()
	backup.set_value("iap", "schema_version", 1)
	backup.set_value("iap", "entitlements", [STORE_SCRIPT.LANTERN_COLORS])
	backup.set_value("iap", "transactions", {})
	backup.set_value("iap", "pending_finishes", {})
	backup.set_value("iap", "selected_palette", "moon")
	_expect_equal(backup.save(_backup_absolute), OK, "prepare a legacy-schema IAP backup")
	var primary: ConfigFile = ConfigFile.new()
	primary.set_value("iap", "schema_version", 1)
	primary.set_value("iap", "entitlements", [STORE_SCRIPT.SUPPORTER])
	primary.set_value("iap", "transactions", {})
	primary.set_value("iap", "pending_finishes", {})
	primary.set_value("iap", "selected_palette", "ember")
	_expect_equal(primary.save(_save_absolute), OK, "prepare a newer legacy-schema IAP primary")

	var store: Node = STORE_SCRIPT.new()
	store.load_entitlements()
	_expect_true(store.owns(store.SUPPORTER), "latest primary entitlement is kept during schema upgrade")
	_expect_false(
		store.owns(store.LANTERN_COLORS), "old backup is not restored during schema upgrade")
	store.free()

	_remove_save_targets()
	var complete_backup: ConfigFile = ConfigFile.new()
	complete_backup.set_value("iap", "schema_version", 1)
	complete_backup.set_value("iap", "entitlements", [STORE_SCRIPT.SUPPORTER])
	complete_backup.set_value("iap", "transactions", {})
	complete_backup.set_value("iap", "pending_finishes", {})
	complete_backup.set_value("iap", "selected_palette", "ember")
	_expect_equal(
		complete_backup.save(_backup_absolute), OK, "prepare a complete legacy-schema IAP backup")
	var truncated_primary: ConfigFile = ConfigFile.new()
	truncated_primary.set_value("iap", "schema_version", 1)
	truncated_primary.set_value("iap", "entitlements", [STORE_SCRIPT.HERO_BUNDLE])
	truncated_primary.set_value("iap", "transactions", {})
	_expect_equal(
		truncated_primary.save(_save_absolute), OK, "prepare a parseable truncated IAP primary")

	var recovered: Node = STORE_SCRIPT.new()
	recovered.load_entitlements()
	_expect_true(recovered.owns(recovered.SUPPORTER), "prefer a complete backup over a truncated IAP primary")
	_expect_false(recovered.owns(recovered.HERO_BUNDLE), "truncated IAP primary entitlements are excluded")
	var repaired: ConfigFile = ConfigFile.new()
	_expect_equal(repaired.load(_save_absolute), OK, "truncated IAP primary is repaired")
	_expect_equal(
		repaired.get_value("iap", "entitlements", []),
		[STORE_SCRIPT.SUPPORTER],
		"repaired IAP primary keeps the backup entitlement")
	recovered.free()

	_remove_save_targets()
	var newer_backup: ConfigFile = ConfigFile.new()
	newer_backup.set_value("iap", "schema_version", 2)
	newer_backup.set_value("iap", "entitlements", [STORE_SCRIPT.LANTERN_COLORS])
	newer_backup.set_value("iap", "transactions", {})
	newer_backup.set_value("iap", "pending_finishes", {})
	newer_backup.set_value("iap", "revoked_products", [])
	newer_backup.set_value("iap", "selected_palette", "moon")
	_expect_equal(newer_backup.save(_backup_absolute), OK, "prepare a higher-schema IAP backup")
	var older_primary: ConfigFile = ConfigFile.new()
	older_primary.set_value("iap", "schema_version", 1)
	older_primary.set_value("iap", "entitlements", [STORE_SCRIPT.SUPPORTER])
	older_primary.set_value("iap", "transactions", {})
	older_primary.set_value("iap", "pending_finishes", {})
	older_primary.set_value("iap", "selected_palette", "ember")
	_expect_equal(older_primary.save(_save_absolute), OK, "prepare a lower-schema IAP primary")

	var upgraded: Node = STORE_SCRIPT.new()
	upgraded.load_entitlements()
	_expect_true(upgraded.owns(upgraded.LANTERN_COLORS), "same revision prefers the higher schema")
	_expect_false(upgraded.owns(upgraded.SUPPORTER), "prefer backup over a lower-schema primary")
	upgraded.free()

	_remove_save_targets()
	var versionless_backup: ConfigFile = ConfigFile.new()
	versionless_backup.set_value("iap", "entitlements", [STORE_SCRIPT.SUPPORTER])
	versionless_backup.set_value("iap", "transactions", {})
	versionless_backup.set_value("iap", "pending_finishes", {})
	versionless_backup.set_value("iap", "selected_palette", "ember")
	_expect_equal(
		versionless_backup.save(_backup_absolute), OK, "prepare a complete version-less IAP backup")
	var sparse_versionless_primary: ConfigFile = ConfigFile.new()
	sparse_versionless_primary.set_value(
		"iap", "entitlements", [STORE_SCRIPT.HERO_BUNDLE])
	_expect_equal(
		sparse_versionless_primary.save(_save_absolute),
		OK,
		"prepare a truncated version-less IAP primary")

	var legacy_recovered: Node = STORE_SCRIPT.new()
	legacy_recovered.load_entitlements()
	_expect_true(
		legacy_recovered.owns(legacy_recovered.SUPPORTER),
		"prefer a complete backup over a truncated version-less IAP primary")
	_expect_false(
		legacy_recovered.owns(legacy_recovered.HERO_BUNDLE),
		"truncated version-less IAP entitlements are excluded")
	legacy_recovered.free()


func _test_backup_recovery() -> void:
	_remove_save_targets()
	var store: Node = STORE_SCRIPT.new()
	store.entitlements.append(store.SUPPORTER)
	_expect_equal(store.save_entitlements(), OK, "first IAP ledger save")
	store.entitlements.append(store.LANTERN_COLORS)
	_expect_equal(store.save_entitlements(), OK, "next IAP ledger save")

	var incomplete: ConfigFile = ConfigFile.new()
	incomplete.set_value("iap", "schema_version", store.SCHEMA_VERSION)
	incomplete.set_value("iap", "entitlements", [store.HERO_BUNDLE])
	_expect_equal(incomplete.save(_save_absolute), OK, "prepare a truncated IAP ledger")
	var restored: Node = STORE_SCRIPT.new()
	restored.load_entitlements()
	_expect_true(restored.owns(restored.SUPPORTER), "supporter entitlement is recovered from a corrupt ledger")
	_expect_true(restored.owns(restored.LANTERN_COLORS), "color entitlement is recovered from the latest replica")
	_expect_false(restored.owns(restored.HERO_BUNDLE), "corrupt ledger values are excluded")
	_expect_false(FileAccess.file_exists(_temp_absolute), "temp file is removed after recovery")
	store.free()
	restored.free()


func _seed_products(backend: Node, store: Node) -> void:
	backend.fetched_products.clear()
	backend.fetched_products.append({
		"id": store.SUPPORTER,
		"displayName": "Moonlit Supporter",
		"displayPrice": "₩3,300",
	})
	backend.fetched_products.append({
		"id": store.HERO_BUNDLE,
		"displayName": "Hero Bundle",
		"displayPrice": "₩4,400",
	})
	backend.fetched_products.append({
		"id": store.HERO_DANCER,
		"displayName": "Shadow Dancer",
		"displayPrice": "$4.99",
	})
	backend.fetched_products.append({
		"id": store.HERO_KEEPER,
		"displayName": "Beacon Keeper",
		"displayPrice": "$9.99",
	})
	backend.fetched_products.append({
		"id": store.HERO_KNIGHT,
		"displayName": "Moon Knight",
		"displayPrice": "$14.99",
	})
	backend.fetched_products.append({
		"id": store.HERO_ECLIPSE,
		"displayName": "Eclipse Weaver",
		"displayPrice": "$19.99",
	})
	backend.fetched_products.append({
		"id": store.HERO_SAGE,
		"displayName": "Starlight Sage",
		"displayPrice": "$24.99",
	})
	backend.fetched_products.append({
		"id": store.LANTERN_COLORS,
		"displayName": "Lantern Colors",
		"displayPrice": "₩1,100",
	})
	backend.fetched_products.append({
		"id": store.CONTINUE_COIN,
		"displayName": "Continue Coin",
		"displayPrice": "₩700",
	})
	backend.fetched_products.append({
		"id": store.CONTINUE_COIN_5,
		"displayName": "Continue Coins ×5",
		"displayPrice": "₩2,900",
	})
	backend.fetched_products.append({
		"id": store.CONTINUE_COIN_10,
		"displayName": "Continue Coins ×10",
		"displayPrice": "₩4,900",
	})


func _android_purchase(
		product_id: String, token: String, purchase_state: String = "purchased"
		) -> Dictionary:
	return {
		"productId": product_id,
		"purchaseState": purchase_state,
		"purchaseToken": token,
		"packageNameAndroid": STORE_SCRIPT.APP_ID,
		"store": "google-play",
	}


func _ios_purchase(product_id: String, transaction_id: String) -> Dictionary:
	return {
		"productId": product_id,
		"purchaseState": "purchased",
		"transactionId": transaction_id,
		"purchaseToken": "header.%s.signature" % transaction_id,
		"appBundleIdIOS": STORE_SCRIPT.APP_ID,
		"store": "app-store",
	}


func _new_vault() -> Node:
	var vault: Node = VAULT_SCRIPT.new()
	vault.load_vault()
	return vault


func _queue_deferred_hero_revocation(
		store: Node, backend: Node, transaction_id: String) -> void:
	backend.finish_results.append(false)
	var purchase: Dictionary = _ios_purchase(store.HERO_BUNDLE, transaction_id)
	_expect_true(await store.process_purchase(purchase), "hero transaction is saved before durable revocation")
	var transaction_key: String = store._transaction_key(purchase)
	store._processing[transaction_key] = "finish"
	var revoked: Dictionary = purchase.duplicate(true)
	revoked["revocationDateIOS"] = 1_785_258_800_000
	_expect_true(await store.process_revocation(revoked), "durable revocation queue is saved during finish")
	store._processing.erase(transaction_key)


func _remove_save_targets() -> void:
	for path in [
		_save_absolute, _temp_absolute, _backup_absolute, _backup_temp_absolute]:
		_remove_path(path)
	_remove_vault_targets()


func _remove_vault_targets() -> void:
	for path in _vault_paths:
		_remove_path(path)


func _remove_path(path: String) -> void:
	if FileAccess.file_exists(path):
		var file_error: Error = DirAccess.remove_absolute(path)
		if file_error != OK:
			printerr("failed to clean test save file: ", path, " — ", error_string(file_error))
	elif DirAccess.dir_exists_absolute(path):
		var dir_error: Error = DirAccess.remove_absolute(path)
		if dir_error != OK:
			printerr("failed to clean test save folder: ", path, " — ", error_string(dir_error))


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checked += 1
	if actual == expected:
		return
	_failed += 1
	printerr("  FAIL ", label, " — expected=", expected, " actual=", actual)


func _expect_true(actual: bool, label: String) -> void:
	_expect_equal(actual, true, label)


func _expect_false(actual: bool, label: String) -> void:
	_expect_equal(actual, false, label)
