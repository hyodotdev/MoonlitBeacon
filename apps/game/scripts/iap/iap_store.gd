extends Node

## Moonlit shop catalog, permanent entitlements, and transaction ledger.
##
## New sale SKUs are 7 permanent products and 3 continue-coin consumables. Restore-only legacy
## SKUs are non-consumable. When a payment result arrives
## 1) confirm it is PURCHASED
## 2) verify store, product, and current state with IAPKit
## 3) save the benefit atomically, then
## 4) finish the store transaction last.
##
## If the app dies between 2 and 3, the same transaction returns on next launch. The transaction key
## is already stored, so the benefit is not granted twice and only finish is retried.

signal state_changed
signal products_changed
signal entitlement_changed(product_id: String)
signal purchase_succeeded(product_id: String)
signal purchase_pending(product_id: String)
signal purchase_failed(product_id: String, code: String)
signal purchase_revoked(product_id: String)
signal restore_finished(restored_count: int)
signal lantern_changed(palette_id: String)
## Refresh button enablement even when only connect/resume guards change and StoreState stays the same.
## Separate from state_changed so status copy is not overwritten.
signal interaction_changed

const BACKEND_SCRIPT: Script = preload("res://scripts/iap/godot_iap_backend.gd")

const SAVE_PATH: String = "user://iap_entitlements.cfg"
const TEMP_SAVE_PATH: String = SAVE_PATH + ".tmp"
const BACKUP_SAVE_PATH: String = SAVE_PATH + ".bak"
const BACKUP_TEMP_SAVE_PATH: String = BACKUP_SAVE_PATH + ".tmp"
const SECTION: String = "iap"
const SCHEMA_VERSION: int = 5
const APP_ID: String = "com.crossplatformkorea.moonlitbeacon"
## IAPKit's replay guard treats `Consumed / isValid: false` as a stable terminal state and
## will not re-verify the same receipt for 300 seconds. Right after consuming a Google consumable,
## Android resume and the next launch can send the same token back-to-back, turning a valid purchase
## into 429 `REPEATED_FAILURE`. Skip finished-ledger re-verification for 6 minutes, longer than the
## server window, but still run the first verify/grant and the refund/revocation check after 6 minutes.
const PURCHASE_REVERIFY_INTERVAL_MSEC: int = 360_000

const SUPPORTER: String = APP_ID + ".supporter"
const HERO_BUNDLE: String = APP_ID + ".hero_bundle"
const LANTERN_COLORS: String = APP_ID + ".lantern_colors"
## Arcade continue coins. **This repository's first consumable.**
##
## Sold in three packs. The single-coin SKU is already listed on both stores as of 1.0.2, so
## **do not touch the ID or grant count** — swapping a product still in review
## sends the whole submission back. Growth only appends new SKUs after it.
const CONTINUE_COIN: String = APP_ID + ".continue_coin"
const CONTINUE_COIN_5: String = APP_ID + ".continue_coin_5"
const CONTINUE_COIN_10: String = APP_ID + ".continue_coin_10"
const HERO_DANCER: String = APP_ID + ".hero_dancer"
const HERO_KEEPER: String = APP_ID + ".hero_keeper"
const HERO_KNIGHT: String = APP_ID + ".hero_knight"
const HERO_ECLIPSE: String = APP_ID + ".hero_eclipse"
const HERO_SAGE: String = APP_ID + ".hero_sage"

## `PRODUCT_IDS` still includes the old hero_bundle so restore and refunds keep working.
## Only the new sale UI and catalog-ready check use `SALE_PRODUCT_IDS` to hide the bundle.
const HERO_PRODUCT_IDS: Array[String] = [
	HERO_DANCER,
	HERO_KEEPER,
	HERO_KNIGHT,
	HERO_ECLIPSE,
	HERO_SAGE,
]
## Consumables are bought, spent, and can be bought again. Their lifecycle differs from non-consumables
## in three places — they are not stored in permanent `entitlements`, they are not restore targets,
## and grants happen **once per transaction key** (see `consumable_grants` below).
const CONSUMABLE_PRODUCT_IDS: Array[String] = [
	CONTINUE_COIN,
	CONTINUE_COIN_5,
	CONTINUE_COIN_10,
]

## How many units one consumable purchase grants.
##
## Larger packs cost less per coin — $0.49/1, $1.99/5, $3.49/10.
## Per-coin $0.490 → $0.398 → $0.349. If that stair reverses, buying the larger pack
## becomes a worse deal, so recalculate whenever prices change.
## If this count disagrees with the store title/description, that is grounds for a refund, so
## change it together with `notes/release/store-localizations.csv`.
const CONSUMABLE_GRANTS: Dictionary = {
	CONTINUE_COIN: 1,
	CONTINUE_COIN_5: 5,
	CONTINUE_COIN_10: 10,
}

const PRODUCT_IDS: Array[String] = [
	SUPPORTER,
	HERO_BUNDLE,
	CONTINUE_COIN,
	CONTINUE_COIN_5,
	CONTINUE_COIN_10,
	HERO_DANCER,
	HERO_KEEPER,
	HERO_KNIGHT,
	HERO_ECLIPSE,
	HERO_SAGE,
	LANTERN_COLORS,
]

## Shop row one — continue coins, cheapest first.
const COIN_SALE_PRODUCT_IDS: Array[String] = [
	CONTINUE_COIN,
	CONTINUE_COIN_5,
	CONTINUE_COIN_10,
]
## Shop row two — characters and permanent products.
const PERMANENT_SALE_PRODUCT_IDS: Array[String] = [
	HERO_DANCER,
	HERO_KEEPER,
	HERO_KNIGHT,
	HERO_ECLIPSE,
	HERO_SAGE,
	SUPPORTER,
	LANTERN_COLORS,
]
## Catalog-ready checks the two rows together. Callers that only read this one list
## (price lookup, can-purchase) stay unchanged when a row is added.
const SALE_PRODUCT_IDS: Array[String] = [
	CONTINUE_COIN,
	CONTINUE_COIN_5,
	CONTINUE_COIN_10,
	HERO_DANCER,
	HERO_KEEPER,
	HERO_KNIGHT,
	HERO_ECLIPSE,
	HERO_SAGE,
	SUPPORTER,
	LANTERN_COLORS,
]

const HERO_BUNDLE_PATHS: Array[String] = [
	"res://resources/heroes/dancer.tres",
	"res://resources/heroes/keeper.tres",
]

const HERO_PATH_BY_PRODUCT: Dictionary = {
	HERO_DANCER: "res://resources/heroes/dancer.tres",
	HERO_KEEPER: "res://resources/heroes/keeper.tres",
	HERO_KNIGHT: "res://resources/heroes/knight.tres",
	HERO_ECLIPSE: "res://resources/heroes/eclipse.tres",
	HERO_SAGE: "res://resources/heroes/sage.tres",
}

const CATALOG: Dictionary = {
	SUPPORTER: {
		"title": "IAP_SUPPORTER_TITLE",
		"description": "IAP_SUPPORTER_DESC",
		"accent": Color(1.0, 0.78, 0.36, 1.0),
	},
	HERO_BUNDLE: {
		"title": "IAP_HERO_BUNDLE_TITLE",
		"description": "IAP_HERO_BUNDLE_DESC",
		"accent": Color(0.74, 0.88, 1.0, 1.0),
	},
	HERO_DANCER: {
		"title": "HERO_DANCER_NAME",
		"description": "HERO_DANCER_DESC",
		"accent": Color(0.90, 0.48, 0.88, 1.0),
		"usd_price": "$4.99",
	},
	HERO_KEEPER: {
		"title": "HERO_KEEPER_NAME",
		"description": "HERO_KEEPER_DESC",
		"accent": Color(1.0, 0.66, 0.35, 1.0),
		"usd_price": "$9.99",
	},
	HERO_KNIGHT: {
		"title": "HERO_KNIGHT_NAME",
		"description": "HERO_KNIGHT_DESC",
		"accent": Color(0.52, 0.78, 1.0, 1.0),
		"usd_price": "$14.99",
	},
	HERO_ECLIPSE: {
		"title": "HERO_ECLIPSE_NAME",
		"description": "HERO_ECLIPSE_DESC",
		"accent": Color(0.68, 0.46, 1.0, 1.0),
		"usd_price": "$19.99",
	},
	HERO_SAGE: {
		"title": "HERO_SAGE_NAME",
		"description": "HERO_SAGE_DESC",
		"accent": Color(0.42, 1.0, 0.76, 1.0),
		"usd_price": "$24.99",
	},
	LANTERN_COLORS: {
		"title": "IAP_LANTERN_TITLE",
		"description": "IAP_LANTERN_DESC",
		"accent": Color(0.82, 0.68, 1.0, 1.0),
	},
	CONTINUE_COIN: {
		"title": "IAP_CONTINUE_TITLE",
		"description": "IAP_CONTINUE_DESC",
		"accent": Color(1.0, 0.86, 0.5, 1.0),
		"usd_price": "$0.49",
	},
	CONTINUE_COIN_5: {
		"title": "IAP_CONTINUE_5_TITLE",
		"description": "IAP_CONTINUE_5_DESC",
		"accent": Color(1.0, 0.78, 0.38, 1.0),
		"usd_price": "$1.99",
	},
	CONTINUE_COIN_10: {
		"title": "IAP_CONTINUE_10_TITLE",
		"description": "IAP_CONTINUE_10_DESC",
		"accent": Color(1.0, 0.70, 0.28, 1.0),
		"usd_price": "$3.49",
	},
}


static func is_consumable(product_id: String) -> bool:
	return product_id in CONSUMABLE_PRODUCT_IDS

const DEFAULT_PALETTE: String = "ember"
const PALETTES: Dictionary = {
	"ember": {
		"name": "IAP_COLOR_EMBER",
		"light": Color(1.0, 0.55, 0.20, 1.0),
		"glow": Color(1.0, 0.72, 0.32, 1.0),
	},
	"moon": {
		"name": "IAP_COLOR_MOON",
		"light": Color(0.38, 0.72, 1.0, 1.0),
		"glow": Color(0.54, 0.82, 1.0, 1.0),
	},
	"violet": {
		"name": "IAP_COLOR_VIOLET",
		"light": Color(0.78, 0.42, 1.0, 1.0),
		"glow": Color(0.90, 0.62, 1.0, 1.0),
	},
	"jade": {
		"name": "IAP_COLOR_JADE",
		"light": Color(0.35, 1.0, 0.65, 1.0),
		"glow": Color(0.55, 1.0, 0.78, 1.0),
	},
}

enum StoreState {
	UNAVAILABLE,
	LOADING,
	READY,
	PURCHASING,
	PENDING,
	RESTORING,
	ERROR,
}

var state: StoreState = StoreState.UNAVAILABLE
var products: Dictionary = {}
var entitlements: Array[String] = []
## Transaction key → product ID.
var transactions: Dictionary = {}
## Minimal purchase original kept so refund state can still be re-checked with IAPKit after finish.
## JWS/purchaseToken stay in the user:// app sandbox and must never appear in logs or UI.
var purchase_records: Dictionary = {}
## Transaction key → plain Dictionary from the store, used to retry finish.
var pending_finishes: Dictionary = {}
## Products the store explicitly refunded or revoked. Leave a tombstone so an IAP source can be
## clawed back even if Vault is restored separately. Do not add one just because a purchase is absent.
var revoked_products: Array[String] = []
## Transaction keys that already granted a consumable. `{transaction_key: product_id}`.
##
## **This ledger is what makes consumable grants happen exactly once.** Non-consumables
## do not need it because re-applying `entitlements` is idempotent (already owned is enough), but coins
## are additive, so reading the same transaction twice would stack twice. The ledger is saved before
## the benefit, so a crash right after save will not grant again on the next launch.
var consumable_grants: Dictionary = {}
## Revoked transaction key → product ID. Unlike product tombstones, this is not cleared by a new purchase.
## Stops a late replay of the same old PURCHASED callback from resurrecting a revoked entitlement.
var revoked_transactions: Dictionary = {}
var revision: int = 0
var selected_palette: String = DEFAULT_PALETTE
var current_product_id: String = ""
## StoreKit Ask to Buy does not create a transaction yet and only sends a deferred-payment error.
## A normal empty purchase list is not enough to treat that approval wait as canceled.
var _pending_without_store_transaction: bool = false

var _backend: Node
var _backend_started: bool = false
var _backend_initialized: bool = false
var _connection_attempt_in_progress: bool = false
var _resume_sync_in_progress: bool = false
var _processing: Dictionary = {}
## Track the in-flight product separately so a revocation of the same transaction can be matched
## to the exact product even during verification, before the row enters the ledger.
var _processing_products: Dictionary = {}
## Approval-pending transactions seen in the current store snapshot or a purchase callback.
## Even when isolated from another product's UI flow, duplicate checkout of that SKU must stay blocked.
var _store_pending_transactions: Dictionary = {}
## A newer callback can arrive while waiting on availablePurchases. Per-transaction mutation numbers
## let a transaction that changed after the query started win over a stale snapshot row.
var _store_pending_mutation_revision: int = 0
var _store_pending_mutations: Dictionary = {}
## New transactions not yet granted because the server was temporarily down. While the app is alive,
## lock that product flow against duplicate checkout and re-verify on store replay.
var _verification_pending_transactions: Dictionary = {}
## Revocation of the same transaction that arrived while waiting on finish. Do not drop the callback;
## handle it right after finish so a briefly granted entitlement does not survive until next launch.
var _deferred_revocations: Dictionary = {}
var _announced_revocations: Dictionary = {}
## During restore, the state change must redraw UI first, then show the exact failure copy once.
## Hold inner sync failure signals briefly and emit them after the ERROR transition.
var _capture_purchase_failures: bool = false
var _captured_purchase_failure: Dictionary = {}
## Native restore can return before purchase_updated is processed. Count in-flight callbacks so
## restore-finished is not announced before verification and ledger save complete.
var _active_purchase_callbacks: int = 0
var _vault_override: Node


func _ready() -> void:
	load_entitlements()
	call_deferred("_start_backend")


func _exit_tree() -> void:
	if _backend != null:
		_backend.shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		call_deferred("_sync_after_resume")


func set_backend_for_testing(backend: Node) -> void:
	_backend = backend


func set_vault_for_testing(vault: Node) -> void:
	_vault_override = vault


func _start_backend() -> void:
	if _backend_started:
		return
	_backend_started = true
	if not storefront_enabled():
		# Direct-distribution builds apply neither the payment UI nor leftover IAP sources from a previous
		# Play install. Returning to a Play build re-grants idempotently from the ledger.
		_revoke_external_benefit(HERO_BUNDLE)
		for product_id in HERO_PRODUCT_IDS:
			_revoke_external_benefit(product_id)
		_set_state(StoreState.UNAVAILABLE)
		return
	# Re-apply cached permanent entitlements even if only the Vault file was deleted or restored from
	# an old device backup. Grant helpers are source-idempotent, so this cannot double-unlock.
	for product_id in revoked_products:
		_revoke_external_benefit(product_id)
	# If the app dies while waiting on finish, a revocation callback still remains in the schema 4 ledger.
	# Drain the durable queue before re-granting leftover entitlements.
	await _drain_all_deferred_revocations()
	for product_id in entitlements:
		_grant_external_benefit(product_id)
	if _backend == null:
		if OS.get_name() not in ["Android", "iOS"]:
			_set_state(StoreState.UNAVAILABLE)
			return
		_backend = BACKEND_SCRIPT.new()
	if _backend.get_parent() == null:
		add_child(_backend)
	_backend.purchase_updated.connect(_on_purchase_updated)
	_backend.purchase_failed.connect(_on_purchase_error)
	_backend.disconnected.connect(_on_backend_disconnected)
	await _connect_and_sync()


func storefront_enabled() -> bool:
	return not OS.has_feature("direct_distribution")


func can_retry_connection() -> bool:
	return storefront_enabled() and _backend != null \
		and (state in [StoreState.UNAVAILABLE, StoreState.ERROR] \
			or not _backend_initialized) \
		and not _connection_attempt_in_progress \
		and not _resume_sync_in_progress


func retry_connection() -> bool:
	if not can_retry_connection():
		return false
	return await _connect_and_sync()


func _connect_and_sync() -> bool:
	if _connection_attempt_in_progress or _resume_sync_in_progress \
			or _backend == null:
		return false
	_connection_attempt_in_progress = true
	_set_state(StoreState.LOADING)
	# The native store can replay unfinished transactions even during initialize/fetch.
	# Wrap the whole connect in one capture boundary so the post-LOADING terminal state cannot hide an error.
	_begin_purchase_failure_capture()
	if not _backend_initialized and not await _backend.initialize():
		await _wait_for_purchase_callbacks()
		var initialize_failure: Dictionary = _end_purchase_failure_capture()
		_connection_attempt_in_progress = false
		_set_state(StoreState.UNAVAILABLE)
		interaction_changed.emit()
		_replay_purchase_failure(initialize_failure)
		return false
	_backend_initialized = true
	await refresh_products()
	var sync_result: Dictionary = await _sync_available_purchases()
	await _wait_for_purchase_callbacks()
	var pending_finishes_succeeded: bool = await _retry_pending_finishes()
	var deferred_revocations_succeeded: bool = \
		await _drain_all_deferred_revocations()
	var benefits_reapplied: bool = _reapply_saved_entitlement_benefits()
	await _wait_for_purchase_callbacks()
	var captured_failure: Dictionary = _end_purchase_failure_capture()
	if not _backend_initialized:
		_connection_attempt_in_progress = false
		if state != StoreState.PENDING:
			_set_state(StoreState.UNAVAILABLE)
		interaction_changed.emit()
		_replay_purchase_failure(captured_failure)
		return false
	var sync_failed: bool = not bool(sync_result.get("success", false))
	var maintenance_failed: bool = not pending_finishes_succeeded \
		or not deferred_revocations_succeeded \
		or not benefits_reapplied
	if sync_failed or maintenance_failed \
			or _captured_failure_requires_error(captured_failure):
		_connection_attempt_in_progress = false
		_set_state(StoreState.ERROR)
		interaction_changed.emit()
		var fallback_code: String = "finish-failed" \
			if not pending_finishes_succeeded \
			else "revocation-retry-failed" \
			if not deferred_revocations_succeeded \
			else "benefit-save-failed" if not benefits_reapplied else ""
		_replay_purchase_failure(captured_failure, fallback_code)
		return false
	_connection_attempt_in_progress = false
	if state != StoreState.PENDING:
		_set_state(StoreState.READY if _catalog_is_complete() else StoreState.ERROR)
	interaction_changed.emit()
	# Notices that cleared the current checkout even though the query itself succeeded, such as
	# pending-not-found, must be re-emitted after the terminal state change so READY copy cannot hide them.
	if _captured_failure_is_success_notice(captured_failure):
		_replay_purchase_failure(captured_failure)
	return _catalog_is_complete()


func _sync_after_resume() -> void:
	if _resume_sync_in_progress or _connection_attempt_in_progress \
			or not _backend_initialized or _backend == null \
			or state in [StoreState.LOADING, StoreState.RESTORING]:
		return
	_resume_sync_in_progress = true
	# StoreState stays READY, so lock the buttons immediately without a state signal.
	interaction_changed.emit()
	_begin_purchase_failure_capture()
	var sync_result: Dictionary = await _sync_available_purchases()
	await _wait_for_purchase_callbacks()
	var pending_finishes_succeeded: bool = await _retry_pending_finishes()
	var deferred_revocations_succeeded: bool = \
		await _drain_all_deferred_revocations()
	var benefits_reapplied: bool = _reapply_saved_entitlement_benefits()
	await _wait_for_purchase_callbacks()
	var captured_failure: Dictionary = _end_purchase_failure_capture()
	var sync_failed: bool = not bool(sync_result.get("success", false))
	var maintenance_failed: bool = not pending_finishes_succeeded \
		or not deferred_revocations_succeeded \
		or not benefits_reapplied
	var captured_error: bool = _captured_failure_requires_error(captured_failure)
	_resume_sync_in_progress = false
	if sync_failed or maintenance_failed or captured_error:
		if _backend_initialized:
			# Do not treat a query failure as a normal empty list and unlock the in-flight transaction. Keep the
			# current product and switch to ERROR so the user can reconnect explicitly.
			_set_state(StoreState.ERROR)
	# On success, do not reset status copy to READY; only re-enable the buttons.
	interaction_changed.emit()
	if sync_failed or maintenance_failed or captured_error \
			or _captured_failure_is_success_notice(captured_failure):
		var fallback_code: String = "finish-failed" \
			if not pending_finishes_succeeded \
			else "revocation-retry-failed" \
			if not deferred_revocations_succeeded \
			else "benefit-save-failed" if not benefits_reapplied else ""
		_replay_purchase_failure(captured_failure, fallback_code)


func refresh_products() -> void:
	if _backend == null:
		return
	var fetched: Array[Dictionary] = await _backend.fetch_products(PRODUCT_IDS)
	products.clear()
	for product in fetched:
		var raw_product_id: Variant = product.get("id", null)
		var product_id: String = "" if raw_product_id == null \
			else str(raw_product_id)
		if product_id in PRODUCT_IDS:
			products[product_id] = product.duplicate(true)
	products_changed.emit()


func catalog_entry(product_id: String) -> Dictionary:
	return CATALOG.get(product_id, {}).duplicate(true)


func product_details(product_id: String) -> Dictionary:
	return products.get(product_id, {}).duplicate(true)


func display_price(product_id: String) -> String:
	var product: Dictionary = products.get(product_id, {})
	var value: Variant = product.get("displayPrice", null)
	return "" if value == null else str(value)


func is_hero_product(product_id: String) -> bool:
	return product_id in HERO_PRODUCT_IDS


func hero_path_for_product(product_id: String) -> String:
	return str(HERO_PATH_BY_PRODUCT.get(product_id, ""))


func hero_product_for_path(path: String) -> String:
	for product_id in HERO_PRODUCT_IDS:
		if hero_path_for_product(product_id) == path:
			return product_id
	return ""


func _catalog_is_complete() -> bool:
	for product_id in SALE_PRODUCT_IDS:
		if not products.has(product_id) \
				or display_price(product_id).strip_edges().is_empty():
			return false
	return true


func can_purchase(product_id: String) -> bool:
	return state == StoreState.READY \
		and _backend_initialized \
		and _backend != null \
		and not _connection_attempt_in_progress \
		and not _resume_sync_in_progress \
		and _backend.verification_ready() \
		# Restore/refund callbacks still receive the full `PRODUCT_IDS` set, but checkout may open only SKUs
		# on the current sale list so the hidden old hero_bundle cannot be bought again.
		and product_id in SALE_PRODUCT_IDS \
		and products.has(product_id) \
		and not owns(product_id) \
		and not _has_processing_product(product_id) \
		and not _has_store_pending_product(product_id) \
		and not _has_verification_pending_product(product_id) \
		and not benefit_already_earned(product_id)


func benefit_already_earned(product_id: String) -> bool:
	if (product_id != HERO_BUNDLE and not is_hero_product(product_id)) \
			or owns(product_id):
		return false
	var vault: Node = _vault_override
	if vault == null:
		vault = get_node_or_null("/root/Vault")
	if vault == null:
		return false
	var paths: Array[String] = HERO_BUNDLE_PATHS
	if is_hero_product(product_id):
		paths = [hero_path_for_product(product_id)]
	for path in paths:
		# Not `hero_open()` — that path includes the debug all-heroes bypass.
		if not vault.hero_earned(path):
			return false
	return true


func purchase(product_id: String) -> bool:
	if not can_purchase(product_id):
		return false
	current_product_id = product_id
	_pending_without_store_transaction = false
	_set_state(StoreState.PURCHASING)
	if not _backend.request_purchase(product_id):
		# The plugin may emit purchase_error synchronously first. If that signal already settled the flow,
		# do not announce the same failure twice.
		if current_product_id == product_id:
			_fail_current("request-failed")
		return false
	return true


func restore_purchases() -> bool:
	if _backend == null or not _backend_initialized \
			or state not in [StoreState.READY, StoreState.ERROR] \
			or _has_active_product_flow() \
			or _connection_attempt_in_progress \
			or _resume_sync_in_progress:
		return false
	# The real plugin emits purchase_updated before restore() returns.
	# Remember entitlements from just before restore so the restored count stays accurate even if that
	# callback updates the ledger first.
	var owned_before_restore: Dictionary = {}
	for product_id in PRODUCT_IDS:
		owned_before_restore[product_id] = owns(product_id)
	current_product_id = ""
	_pending_without_store_transaction = false
	_set_state(StoreState.RESTORING)
	# StoreKit restore can emit purchase_updated before the await returns, so preserve failure signals
	# in one boundary from the native restore call until the query finishes.
	_begin_purchase_failure_capture()
	var native_restore_succeeded: bool = await _backend.restore()
	if not native_restore_succeeded:
		await _wait_for_purchase_callbacks()
		var restore_failure: Dictionary = _end_purchase_failure_capture()
		_set_state(_settled_store_state())
		_replay_purchase_failure(restore_failure, "restore-failed")
		return false
	var sync_result: Dictionary = await _sync_available_purchases()
	await _wait_for_purchase_callbacks()
	var pending_finishes_succeeded: bool = await _retry_pending_finishes()
	var deferred_revocations_succeeded: bool = \
		await _drain_all_deferred_revocations()
	var benefits_reapplied: bool = _reapply_saved_entitlement_benefits()
	await _wait_for_purchase_callbacks()
	var captured_failure: Dictionary = _end_purchase_failure_capture()
	var sync_failed: bool = not bool(sync_result.get("success", false))
	var captured_error: bool = _captured_failure_requires_error(captured_failure)
	if sync_failed or not pending_finishes_succeeded \
			or not deferred_revocations_succeeded \
			or not benefits_reapplied \
			or captured_error:
		_set_state(StoreState.ERROR if _backend_initialized else StoreState.UNAVAILABLE)
		var fallback_code: String = "restore-query-failed" if sync_failed \
			else "finish-failed" if not pending_finishes_succeeded \
			else "revocation-retry-failed" \
			if not deferred_revocations_succeeded \
			else "benefit-save-failed" if not benefits_reapplied else ""
		_replay_purchase_failure(
			captured_failure,
			fallback_code)
		return false
	if _captured_failure_is_success_notice(captured_failure):
		if state != StoreState.PENDING:
			_set_state(_settled_store_state())
		_replay_purchase_failure(captured_failure)
		return false
	var count: int = 0
	for product_id in PRODUCT_IDS:
		if not bool(owned_before_restore.get(product_id, false)) and owns(product_id):
			count += 1
	if state != StoreState.PENDING:
		_set_state(StoreState.READY if _catalog_is_complete() else StoreState.ERROR)
		restore_finished.emit(count)
	return true


func owns(product_id: String) -> bool:
	return storefront_enabled() and product_id in entitlements


func available_palettes() -> Array[String]:
	if owns(LANTERN_COLORS):
		var all: Array[String] = []
		for palette_id in PALETTES:
			all.append(str(palette_id))
		return all
	return [DEFAULT_PALETTE]


func select_palette(palette_id: String) -> bool:
	if palette_id not in available_palettes() or palette_id == selected_palette:
		return palette_id == selected_palette
	var before: String = selected_palette
	selected_palette = palette_id
	if save_entitlements() != OK:
		selected_palette = before
		return false
	lantern_changed.emit(selected_palette)
	return true


func palette_name(palette_id: String = "") -> String:
	var chosen: String = _effective_palette_id() if palette_id.is_empty() else palette_id
	return tr(str(PALETTES.get(chosen, PALETTES[DEFAULT_PALETTE]).get("name", "")))


func lantern_light_color() -> Color:
	return PALETTES.get(
		_effective_palette_id(),
		PALETTES[DEFAULT_PALETTE]).get("light", Color.WHITE)


func lantern_glow_color() -> Color:
	return PALETTES.get(
		_effective_palette_id(),
		PALETTES[DEFAULT_PALETTE]).get("glow", Color.WHITE)


func _effective_palette_id() -> String:
	if not owns(LANTERN_COLORS) or selected_palette not in PALETTES:
		return DEFAULT_PALETTE
	return selected_palette


func _on_purchase_updated(purchase: Dictionary) -> void:
	_active_purchase_callbacks += 1
	# restore can also send other system/legacy SKUs from the app package.
	# As with available sync, ignore them for the current UI flow when they are outside this ledger.
	if _product_id(purchase) not in PRODUCT_IDS:
		_finish_purchase_callback()
		return
	if _purchase_is_explicitly_revoked(purchase):
		await process_revocation(purchase)
		_finish_purchase_callback()
		return
	await process_purchase(purchase)
	_finish_purchase_callback()


func _on_purchase_error(error: Dictionary) -> void:
	var raw_product_id: Variant = error.get("productId", null)
	var product_id: String = "" if raw_product_id == null else str(raw_product_id)
	# restore can also send legacy/foreign SKU errors from the app package. If the named SKU is outside
	# this ledger, do not turn a managed restore into a failure.
	if not product_id.strip_edges().is_empty() and product_id not in PRODUCT_IDS:
		return
	if product_id.strip_edges().is_empty():
		product_id = current_product_id
	var code: String = str(error.get("code", "purchase-failed"))
	if code.to_lower() == "deferred-payment" and product_id in PRODUCT_IDS:
		_mark_purchase_pending(product_id, true)
		return
	_report_purchase_failure(product_id, code)


func _on_backend_disconnected() -> void:
	_backend_initialized = false
	if state in [StoreState.PURCHASING, StoreState.PENDING]:
		# Keep the in-progress copy, but refresh the shop reconnect button immediately.
		state_changed.emit()
	else:
		_set_state(StoreState.UNAVAILABLE)


## Transaction-processing boundary that tests also call directly.
func process_purchase(purchase: Dictionary) -> bool:
	var result: Dictionary = await _process_purchase_result(purchase, false)
	return bool(result.get("accepted", false))


func _process_purchase_result(
		purchase: Dictionary, reverify_recorded: bool) -> Dictionary:
	var product_id: String = _product_id(purchase)
	var transaction_key: String = _transaction_key(purchase)
	var unrelated_to_active_flow: bool = _is_unrelated_to_active_flow(product_id)
	if _purchase_state(purchase) == "pending":
		if _pending_purchase_is_valid(purchase, product_id, transaction_key):
			_remember_store_pending(transaction_key, product_id)
			_mark_purchase_pending(product_id)
		else:
			_report_purchase_failure(product_id, "invalid-purchase", "", false)
			return {"accepted": false, "retryable": false, "failed": true}
		return {"accepted": false, "retryable": false}
	if not _purchase_is_grantable(purchase, product_id, transaction_key):
		# An unverified purchase_updated cannot be treated as the result of the current checkout sheet.
		_report_purchase_failure(product_id, "invalid-purchase", "", false)
		return {"accepted": false, "retryable": false, "failed": true}
	_forget_store_pending(transaction_key)
	if str(revoked_transactions.get(transaction_key, "")) == product_id:
		# Replaying a refunded old transaction must not close a new repurchase flow for the same SKU.
		_report_purchase_failure(product_id, "revoked-transaction", "", false)
		return {"accepted": false, "retryable": false}
	if _processing.has(transaction_key):
		return {"accepted": false, "retryable": false, "busy": true}
	_set_processing(transaction_key, product_id, "verification")

	var plain_purchase: Dictionary = _plain_dictionary(purchase)
	var already_recorded: bool = transactions.has(transaction_key)
	var existing_record: Variant = purchase_records.get(transaction_key, {})
	var verified_at_ms: int = int(existing_record.get("lastVerifiedAtMs", 0)) \
		if existing_record is Dictionary else 0
	if already_recorded and not pending_finishes.has(transaction_key) \
			and not reverify_recorded:
		# Duplicate callback for a transaction already saved through finish. Do not grant or finish again.
		_finish_processing(transaction_key, product_id)
		return {"accepted": true, "retryable": false}

	if not already_recorded or reverify_recorded:
		var verification: Dictionary = await _backend.verify_purchase(
			plain_purchase, product_id)
		# A consumed Google consumable disappears from current purchases on the next resume query.
		# Re-verifying the durable refund-check token makes IAPKit return exactly
		# `Consumed / isValid: false`, which is the normal terminal state of a transaction that already
		# finished verify, grant, and finish. Never allow that for a new transaction; only allow it on
		# post-finish re-verification of a consumable whose ledger finish is already done.
		var allow_terminal_consumed: bool = reverify_recorded \
			and already_recorded \
			and is_consumable(product_id) \
			and not pending_finishes.has(transaction_key)
		var decision: Dictionary = _verification_decision(
			verification,
			plain_purchase,
			product_id,
			allow_terminal_consumed)
		if bool(decision.get("retryable", false)):
			if not already_recorded:
				_hold_for_verification(
					transaction_key, product_id, unrelated_to_active_flow)
			else:
				_clear_processing(transaction_key)
			await _drain_deferred_revocation(transaction_key)
			return {"accepted": false, "retryable": true, "failed": true}
		_verification_pending_transactions.erase(transaction_key)
		if bool(decision.get("canceled", false)):
			_clear_processing(transaction_key)
			if already_recorded or product_id in entitlements:
				var revoked: bool = await _process_verified_cancellation(
					plain_purchase)
				return {
					"accepted": revoked,
					"retryable": false,
					"failed": not revoked,
				}
			_report_purchase_failure(
				product_id, "canceled", transaction_key, true)
			await _drain_deferred_revocation(transaction_key)
			return {"accepted": false, "retryable": false}
		if not bool(decision.get("accepted", false)):
			var failure_code: String = str(
				decision.get("error_code", "verification-rejected"))
			if failure_code not in [
				"verification-configuration-error",
				"verification-rejected",
			]:
				failure_code = "verification-rejected"
			_report_purchase_failure(
				product_id, failure_code, transaction_key, true)
			# An unfinished store transaction may already be owned even after a deterministic reject.
			# Block duplicate checkout of that product until a later sync changes the decision.
			_verification_pending_transactions[transaction_key] = product_id
			await _drain_deferred_revocation(transaction_key)
			return {"accepted": false, "retryable": false, "failed": true}
		verified_at_ms = int(Time.get_unix_time_from_system() * 1000.0)
	var durable_record: Dictionary = _durable_purchase_record(
		plain_purchase, product_id, transaction_key, verified_at_ms)
	if durable_record.is_empty():
		_report_purchase_failure(
			product_id, "invalid-purchase-record", transaction_key)
		await _drain_deferred_revocation(transaction_key)
		return {"accepted": false, "retryable": false, "failed": true}
	_set_processing(transaction_key, product_id, "purchase")

	if already_recorded and purchase_records.get(transaction_key, {}) != durable_record:
		# A live transaction from schema 4 or earlier, or one found again in the current purchase list,
		# is enriched with the server-verified original so later refunds missing from the list can still be checked.
		# Store the re-verify timestamp too so this does not collide with IAPKit's normal consumed cooldown.
		var previous_record: Variant = purchase_records.get(transaction_key)
		purchase_records[transaction_key] = durable_record
		if save_entitlements() != OK:
			if previous_record is Dictionary:
				purchase_records[transaction_key] = previous_record
			else:
				purchase_records.erase(transaction_key)
			_report_purchase_failure(
				product_id, "journal-save-failed", transaction_key)
			await _drain_deferred_revocation(transaction_key)
			return {"accepted": false, "retryable": false, "failed": true}

	if already_recorded and not pending_finishes.has(transaction_key):
		# A finished transaction that also passed sync re-verification. Do not grant or finish again.
		_finish_processing(transaction_key, product_id)
		return {"accepted": true, "retryable": false}

	var newly_owned: bool = false
	if not already_recorded:
		var before_entitlements: Array[String] = entitlements.duplicate()
		var before_transactions: Dictionary = transactions.duplicate(true)
		var before_records: Dictionary = purchase_records.duplicate(true)
		var before_pending: Dictionary = pending_finishes.duplicate(true)
		var before_revoked: Array[String] = revoked_products.duplicate()
		var before_revoked_transactions: Dictionary = revoked_transactions.duplicate(true)
		# Consumables are not permanent entitlements. Putting them in `entitlements` would look like they
		# cannot be bought again, and restore/re-apply would stack coins on every purchase.
		if not is_consumable(product_id) and product_id not in entitlements:
			entitlements.append(product_id)
			newly_owned = true
		revoked_products.erase(product_id)
		transactions[transaction_key] = product_id
		purchase_records[transaction_key] = durable_record
		pending_finishes[transaction_key] = plain_purchase
		if save_entitlements() != OK:
			entitlements = before_entitlements
			transactions = before_transactions
			purchase_records = before_records
			pending_finishes = before_pending
			revoked_products = before_revoked
			revoked_transactions = before_revoked_transactions
			_report_purchase_failure(
				product_id, "entitlement-save-failed", transaction_key)
			return {"accepted": false, "retryable": false, "failed": true}
	elif not pending_finishes.has(transaction_key):
		pending_finishes[transaction_key] = plain_purchase
		if save_entitlements() != OK:
			pending_finishes.erase(transaction_key)
			_report_purchase_failure(product_id, "journal-save-failed", transaction_key)
			return {"accepted": false, "retryable": false, "failed": true}

	if _deferred_revocations.has(transaction_key):
		# A revocation that arrives during verification first commits the entitlement/transaction ledger
		# atomically, then is handled before the actual benefit grant and finish. That leaves a tombstone
		# even if the app dies, and a refunded benefit never reaches the external Vault, even briefly.
		_clear_processing(transaction_key)
		var revoked_before_grant: bool = await _drain_deferred_revocation(
			transaction_key)
		return {
			"accepted": revoked_before_grant,
			"retryable": false,
			"failed": not revoked_before_grant,
		}

	# Consumables are stacked exactly once per transaction key. The ledger is saved before the benefit,
	# so if the app dies in between, the next launch will not stack again.
	if is_consumable(product_id) \
			and not _grant_consumable(product_id, transaction_key):
		_report_purchase_failure(product_id, "benefit-save-failed", transaction_key)
		return {"accepted": false, "retryable": false, "failed": true}

	# Save the ledger and permanent entitlements first. If the app dies here, the next launch can
	# re-apply the idempotent grants below using entitlements as the source.
	if not _grant_external_benefit(product_id):
		_report_purchase_failure(product_id, "benefit-save-failed", transaction_key)
		return {"accepted": false, "retryable": false, "failed": true}
	if newly_owned:
		entitlement_changed.emit(product_id)

	var finished: bool = await _backend.finish(
		plain_purchase, is_consumable(product_id))
	if finished:
		pending_finishes.erase(transaction_key)
		# The benefit and transaction key are already saved. If this fails, the next launch only retries finish.
		save_entitlements()
	_finish_processing(transaction_key, product_id)
	await _drain_deferred_revocation(transaction_key)
	if newly_owned and owns(product_id) and not unrelated_to_active_flow:
		purchase_succeeded.emit(product_id)
	return {"accepted": true, "retryable": false}


## Handle only refunds/revocations the store stated explicitly. Absence from `available_purchases()`
## cannot be distinguished from a network error, so it is not grounds to claw back an entitlement.
func process_revocation(purchase: Dictionary) -> bool:
	var product_id: String = _product_id(purchase)
	var transaction_key: String = _transaction_key(purchase)
	if not _purchase_is_explicitly_revoked(purchase) \
			or product_id not in PRODUCT_IDS \
			or transaction_key.is_empty() \
			or not _revocation_has_matching_app_identity(purchase):
		_report_purchase_failure(product_id, "invalid-revocation", "", false)
		return false

	if _processing.has(transaction_key):
		var operation: String = str(_processing[transaction_key])
		var processing_product: String = _processing_product(transaction_key)
		if processing_product != product_id:
			_report_purchase_failure(product_id, "invalid-revocation", "", false)
			return false
		if operation in ["verification", "purchase", "finish"]:
			return _queue_deferred_revocation(
				transaction_key, product_id, purchase)
		# If the same revocation is already in flight, the second callback has nothing to do.
		return operation == "revocation"

	var active_transaction: bool = str(transactions.get(transaction_key, "")) == product_id
	var known_revocation: bool = \
		str(revoked_transactions.get(transaction_key, "")) == product_id
	var legacy_entitlement: bool = (
		product_id in entitlements or _has_external_iap_benefit_source(product_id)
	) \
		and not _has_active_transaction(product_id)
	var verification_pending: bool = str(
		_verification_pending_transactions.get(transaction_key, "")) == product_id
	var queued_revocation: bool = _deferred_revocation_matches(
		transaction_key, product_id)
	if not active_transaction \
			and not known_revocation \
			and not legacy_entitlement \
			and not verification_pending \
			and not queued_revocation:
		# Even if the iOS bridge or restore returns historical revocations for this app, there is nothing to
		# claw back when local entitlement/transaction/Vault sources are all absent. Isolate it as a harmless
		# historical event instead of touching a newer transaction's entitlement or putting the shop in ERROR.
		_forget_store_pending(transaction_key)
		return true
	_forget_store_pending(transaction_key)
	_set_processing(transaction_key, product_id, "revocation")

	var before_entitlements: Array[String] = entitlements.duplicate()
	var before_transactions: Dictionary = transactions.duplicate(true)
	var before_records: Dictionary = purchase_records.duplicate(true)
	var before_pending: Dictionary = pending_finishes.duplicate(true)
	var before_revoked: Array[String] = revoked_products.duplicate()
	var before_revoked_transactions: Dictionary = revoked_transactions.duplicate(true)
	var before_palette: String = selected_palette
	if not known_revocation:
		revoked_transactions[transaction_key] = product_id
		transactions.erase(transaction_key)
		purchase_records.erase(transaction_key)
		pending_finishes.erase(transaction_key)
		if _has_active_transaction(product_id):
			# A late revocation of an older transaction must not claw back an entitlement bought with a newer one.
			revoked_products.erase(product_id)
		else:
			entitlements.erase(product_id)
			if product_id not in revoked_products:
				revoked_products.append(product_id)
			if product_id == LANTERN_COLORS:
				selected_palette = DEFAULT_PALETTE
		if save_entitlements() != OK:
			entitlements = before_entitlements
			transactions = before_transactions
			purchase_records = before_records
			pending_finishes = before_pending
			revoked_products = before_revoked
			revoked_transactions = before_revoked_transactions
			selected_palette = before_palette
			_report_purchase_failure(
				product_id, "revocation-save-failed", transaction_key)
			return false

	# save_entitlements() committed the same revision to both replicas, so a later-corrupt primary can
	# be recovered from the backup's transaction tombstone. Vault clawback is idempotent, so the same
	# revocation callback or the next launch can safely repeat it.
	if not owns(product_id) and not _revoke_external_benefit(product_id):
		_report_purchase_failure(
			product_id,
			"revocation-benefit-failed",
			transaction_key,
			not known_revocation)
		return false
	if known_revocation:
		# Replaying an old already-tombstoned transaction is not the result of a new checkout for that SKU.
		_clear_processing(transaction_key)
		_verification_pending_transactions.erase(transaction_key)
	else:
		_finish_processing(transaction_key, product_id)
	if not owns(product_id) and not _announced_revocations.has(transaction_key):
		_announced_revocations[transaction_key] = true
		entitlement_changed.emit(product_id)
		if product_id == LANTERN_COLORS:
			lantern_changed.emit(selected_palette)
		purchase_revoked.emit(product_id)
	return true


func _sync_available_purchases() -> Dictionary:
	var pending_before: String = current_product_id \
		if state in [
			StoreState.PURCHASING,
			StoreState.PENDING,
			StoreState.LOADING,
		] else ""
	var pending_still_listed: bool = false
	var verification_failed: bool = false
	var processing_failed: bool = false
	var seen_transaction_keys: Dictionary = {}
	var pending_revision_before_query: int = _store_pending_mutation_revision
	var query: Dictionary = await _backend.available_purchases()
	if not bool(query.get("success", false)):
		return {
			"success": false,
		}
	var available_value: Variant = query.get("purchases", [])
	if available_value is not Array:
		return {
			"success": false,
		}
	var available: Array[Dictionary] = []
	for value in available_value:
		if value is not Dictionary:
			return {
				"success": false,
			}
		if not _available_purchase_row_is_well_formed(value):
			return {
				"success": false,
			}
		available.append(value)
	# Replace the pending set only from a successful snapshot. Apply it before the first async work so a
	# PURCHASED callback during the later await can still clear that transaction.
	var observed_pending_transactions: Dictionary = {}
	for purchase in available:
		var product_id: String = _product_id(purchase)
		var transaction_key: String = _transaction_key(purchase)
		if product_id in PRODUCT_IDS \
				and _pending_purchase_is_valid(
					purchase, product_id, transaction_key):
			observed_pending_transactions[transaction_key] = product_id
	var concurrent_pending_mutations: Dictionary = {}
	for raw_key in _store_pending_mutations.keys():
		var transaction_key: String = str(raw_key)
		var mutation_revision: int = int(
			_store_pending_mutations.get(transaction_key, 0))
		if mutation_revision <= pending_revision_before_query:
			continue
		concurrent_pending_mutations[transaction_key] = mutation_revision
		# The callback's pending/finished/revoked state is newer than that snapshot row.
		if _store_pending_transactions.has(transaction_key):
			observed_pending_transactions[transaction_key] = \
				_store_pending_transactions[transaction_key]
		else:
			observed_pending_transactions.erase(transaction_key)
	_store_pending_transactions = observed_pending_transactions
	_store_pending_mutations = concurrent_pending_mutations
	for purchase in available:
		var product_id: String = _product_id(purchase)
		# A SKU managed by another system in the same app is a valid row, but it is outside this ledger.
		if product_id not in PRODUCT_IDS:
			continue
		var transaction_key: String = _transaction_key(purchase)
		seen_transaction_keys[transaction_key] = true
		if concurrent_pending_mutations.has(transaction_key):
			# Do not roll a callback handled during the query back to a stale snapshot.
			continue
		if product_id == pending_before and _pending_purchase_is_valid(
				purchase, product_id, transaction_key):
			pending_still_listed = true
		var unrelated_to_pending_flow: bool = not pending_before.is_empty() \
			and product_id != pending_before
		if _purchase_is_explicitly_revoked(purchase):
			if not await process_revocation(purchase) \
					and not unrelated_to_pending_flow:
				processing_failed = true
		else:
			# Play Billing's owned snapshot can be briefly stale right after consume.
			# This row must use the same cooldown as the absent-record path, keyed off the consumable
			# finished-ledger verify timestamp, so it avoids IAPKit's 300-second
			# negative replay guard. Non-consumable owned rows must not skip, because the server may have
			# changed them to canceled and that must be detected immediately.
			# Explicit revocations were handled above; finish waits retry immediately.
			var recorded_purchase: Variant = purchase_records.get(transaction_key)
			if product_id in CONSUMABLE_PRODUCT_IDS \
					and transactions.has(transaction_key) \
					and not pending_finishes.has(transaction_key) \
					and recorded_purchase is Dictionary \
					and not _purchase_reverification_due(recorded_purchase):
				continue
			var result: Dictionary = await _process_purchase_result(purchase, true)
			if bool(result.get("retryable", false)) \
					and not unrelated_to_pending_flow:
				verification_failed = true
			elif bool(result.get("failed", false)) \
					and not unrelated_to_pending_flow:
				processing_failed = true
	# Android queryPurchasesAsync removes a refunded one-time product from current purchases.
	# Do not claw back from absence alone; resend the token stored after finish to IAPKit and check
	# whether it is now CANCELED. Transient errors keep the existing entitlement.
	for raw_key in purchase_records.keys():
		var transaction_key: String = str(raw_key)
		if seen_transaction_keys.has(transaction_key) \
				or not transactions.has(transaction_key):
			continue
		var purchase: Variant = purchase_records.get(transaction_key)
		var product_id: String = str(transactions.get(transaction_key, ""))
		var unrelated_to_pending_flow: bool = not pending_before.is_empty() \
			and product_id != pending_before
		if purchase is not Dictionary \
				or not _purchase_record_is_valid(
					purchase, transaction_key, product_id):
			_report_purchase_failure(
				product_id, "invalid-purchase-record", "", false)
			if not unrelated_to_pending_flow:
				processing_failed = true
			continue
		# A transaction that still needs finish must be recovered immediately, before the 3-day auto-refund,
		# so it is not on cooldown. Only delay a finished ledger that already granted and consume/acknowledge'd.
		if not pending_finishes.has(transaction_key) \
				and not _purchase_reverification_due(purchase):
			continue
		var result: Dictionary = await _process_purchase_result(purchase, true)
		if bool(result.get("retryable", false)) \
				and not unrelated_to_pending_flow:
			verification_failed = true
		elif bool(result.get("failed", false)) \
				and not unrelated_to_pending_flow:
			processing_failed = true
	if not pending_before.is_empty() and not pending_still_listed \
			and not _pending_without_store_transaction \
			and not verification_failed \
			and not _has_verification_pending_product(pending_before) \
			and state in [
				StoreState.PURCHASING,
				StoreState.PENDING,
				StoreState.LOADING,
			] \
			and current_product_id == pending_before:
		# If a successful store query after the app becomes active still has no requested or pending
		# transaction, treat the flow as canceled, expired, or callback-lost and unlock the shop globally.
		# If a real transaction remains, the native store blocks the next request and a later sync grants
		# the entitlement, so there is no double grant.
		_report_purchase_failure(pending_before, "pending-not-found")
	elif not pending_before.is_empty() \
			and _pending_without_store_transaction \
			and current_product_id == pending_before:
		_set_state(StoreState.PENDING)
	return {
		"success": not verification_failed \
			and not processing_failed \
			and not _has_verification_pending_product(pending_before),
	}


func _retry_pending_finishes() -> bool:
	var succeeded: bool = true
	var keys: Array = pending_finishes.keys()
	for raw_key in keys:
		var transaction_key: String = str(raw_key)
		if _processing.has(transaction_key):
			continue
		var purchase: Variant = pending_finishes.get(transaction_key)
		if purchase is not Dictionary:
			continue
		var product_id: String = str(transactions.get(transaction_key, ""))
		_set_processing(transaction_key, product_id, "finish")
		# Revive ledger rows that never received their coins here. If the app died between grant and
		# finish, this path is the only recovery point.
		# `_grant_consumable()` is idempotent by transaction key, so already-granted rows are skipped.
		if product_id not in PRODUCT_IDS \
				or (is_consumable(product_id)
					and not _grant_consumable(product_id, transaction_key)) \
				or not _grant_external_benefit(product_id):
			var unrelated: bool = _is_unrelated_to_active_flow(product_id)
			_report_purchase_failure(
				product_id, "benefit-save-failed", transaction_key)
			if not unrelated:
				succeeded = false
			continue
		if await _backend.finish(purchase, is_consumable(product_id)):
			pending_finishes.erase(transaction_key)
			save_entitlements()
			_clear_processing(transaction_key)
			await _drain_deferred_revocation(transaction_key)
			continue
		# The benefit and transaction ledger are already saved safely. Only finish/acknowledge failed, so
		# keep the entitlement, release the processing lock, and end connect/restore in ERROR so the user
		# can retry explicitly. Leaving the lock would make the next retry skip the same transaction and
		# hide Google's 3-day auto-refund risk.
		_clear_processing(transaction_key)
		if not _is_unrelated_to_active_flow(product_id):
			succeeded = false
	return succeeded


## Grant one consumable. Calling twice with the same transaction key still stacks only once.
##
## Vault atomically saves the balance and transaction key in one file, then this transaction ledger is written.
## If the app dies between those two, the next launch calls Vault again with the same transaction key,
## but Vault returns success without double-granting, so this ledger save can continue from there.
func _grant_consumable(product_id: String, transaction_key: String) -> bool:
	var count: int = int(CONSUMABLE_GRANTS.get(product_id, 0))
	if count <= 0:
		return true                              # consumable with nothing to grant

	var vault: Node = _vault_override
	if vault == null:
		vault = get_node_or_null("/root/Vault")
	if vault == null:
		return false
	if consumable_grants.has(transaction_key):
		# Older schemas remembered the transaction key only in the IAP ledger.
		# Do not grant a transaction already reflected in the balance; only migrate the key into Vault's
		# new idempotent ledger.
		return str(consumable_grants[transaction_key]) == product_id \
			and bool(vault.adopt_continue_coin_grant(count, transaction_key))
	if not bool(vault.grant_continue_coins(count, transaction_key)):
		return false

	consumable_grants[transaction_key] = product_id
	if save_entitlements() != OK:
		# Vault already stored the balance and transaction key together. Roll back only this ledger so the
		# next retry can save again without double-granting.
		consumable_grants.erase(transaction_key)
		return false
	return true


func _grant_external_benefit(product_id: String) -> bool:
	if product_id != HERO_BUNDLE and not is_hero_product(product_id):
		return true
	var vault: Node = _vault_override
	if vault == null:
		vault = get_node_or_null("/root/Vault")
	if vault == null:
		return false
	if product_id == HERO_BUNDLE:
		return bool(vault.grant_heroes(
			HERO_BUNDLE_PATHS, vault.HERO_SOURCE_IAP_BUNDLE))
	var path: String = hero_path_for_product(product_id)
	var paths: Array[String] = [path]
	return not path.is_empty() and bool(vault.grant_heroes(
		paths, vault.hero_iap_source(path)))


func _reapply_saved_entitlement_benefits() -> bool:
	var succeeded: bool = true
	for product_id in entitlements:
		if _grant_external_benefit(product_id):
			continue
		var unrelated: bool = _is_unrelated_to_active_flow(product_id)
		_report_purchase_failure(product_id, "benefit-save-failed")
		if not unrelated:
			succeeded = false
	return succeeded


func _revoke_external_benefit(product_id: String) -> bool:
	if product_id != HERO_BUNDLE and not is_hero_product(product_id):
		return true
	var vault: Node = _vault_override
	if vault == null:
		vault = get_node_or_null("/root/Vault")
	if vault == null:
		return false
	if product_id == HERO_BUNDLE:
		return bool(vault.revoke_heroes(
			HERO_BUNDLE_PATHS, vault.HERO_SOURCE_IAP_BUNDLE))
	var path: String = hero_path_for_product(product_id)
	var paths: Array[String] = [path]
	return not path.is_empty() and bool(vault.revoke_heroes(
		paths, vault.hero_iap_source(path)))


func _has_external_iap_benefit_source(product_id: String) -> bool:
	if product_id != HERO_BUNDLE and not is_hero_product(product_id):
		return false
	var vault: Node = _vault_override
	if vault == null:
		vault = get_node_or_null("/root/Vault")
	if vault == null or not vault.has_method("any_hero_has_source"):
		return false
	if product_id == HERO_BUNDLE:
		return bool(vault.any_hero_has_source(
			HERO_BUNDLE_PATHS, vault.HERO_SOURCE_IAP_BUNDLE))
	var path: String = hero_path_for_product(product_id)
	var paths: Array[String] = [path]
	return not path.is_empty() and bool(vault.any_hero_has_source(
		paths, vault.hero_iap_source(path)))


func _purchase_is_explicitly_revoked(purchase: Dictionary) -> bool:
	return bool(purchase.get("isSuspendedAndroid", false)) \
		or purchase.get("revocationDateIOS", null) != null


func _purchase_is_grantable(
		purchase: Dictionary, product_id: String, transaction_key: String) -> bool:
	if not _purchase_matches_app(purchase, product_id, transaction_key):
		return false
	if _purchase_state(purchase) != "purchased":
		return false
	return true


func _verification_decision(
		result: Dictionary,
		purchase: Dictionary,
		expected_product_id: String,
		allow_terminal_consumed: bool = false) -> Dictionary:
	var raw_success: Variant = result.get("success", null)
	if typeof(raw_success) != TYPE_BOOL:
		return {
			"accepted": false,
			"retryable": true,
			"error_code": "verification-unavailable",
		}
	if not raw_success:
		var raw_retryable: Variant = result.get("retryable", true)
		return {
			"accepted": false,
			"retryable": raw_retryable \
				if typeof(raw_retryable) == TYPE_BOOL else true,
			"error_code": str(
				result.get("error_code", "verification-unavailable")),
		}
	var raw_is_valid: Variant = result.get("is_valid", null)
	var raw_store: Variant = result.get("store", null)
	var raw_product_id: Variant = result.get("product_id", null)
	var raw_state: Variant = result.get("state", null)
	if typeof(raw_is_valid) != TYPE_BOOL \
			or typeof(raw_store) != TYPE_STRING \
			or typeof(raw_product_id) != TYPE_STRING \
			or typeof(raw_state) != TYPE_STRING:
		return {
			"accepted": false,
			"retryable": true,
			"error_code": "verification-unavailable",
		}
	var expected_store: String = _purchase_store(purchase)
	var verified_store: String = str(raw_store).strip_edges().to_lower()
	var verified_product_id: String = str(raw_product_id).strip_edges()
	var state: String = str(raw_state).strip_edges().to_lower() \
		.replace("_", "-")
	if expected_store.is_empty() \
			or verified_store != expected_store \
			or verified_product_id != expected_product_id:
		return {
			"accepted": false,
			"retryable": false,
		}
	if state == "canceled":
		return {
			"accepted": false,
			"retryable": false,
			"canceled": true,
		}
	if allow_terminal_consumed and state == "consumed":
		return {
			"accepted": true,
			"retryable": false,
		}
	if not raw_is_valid:
		return {
			"accepted": false,
			"retryable": false,
		}
	# IAPKit normalizes consumables on both platforms to `ready-to-consume`.
	# Google may return a valid `pending-acknowledgment` only for older transactions fetched before the
	# catalog type was read, or fetched incorrectly. The app can consume from the product type it owns,
	# so this transitional state is also allowed for consumables.
	var allowed_states: Array
	if is_consumable(expected_product_id):
		# Already-acknowledged but not-yet-consumed Google transactions, and older verification responses,
		# may be `entitled`. Product and app identity already matched, so it is safe to consume using the
		# consumable type from the app catalog.
		allowed_states = ["entitled", "ready-to-consume"]
		if expected_store == "google":
			allowed_states.append("pending-acknowledgment")
	else:
		allowed_states = ["entitled"]
		if expected_store == "google":
			allowed_states.append("pending-acknowledgment")
	return {
		"accepted": state in allowed_states,
		"retryable": false,
	}


func _purchase_store(purchase: Dictionary) -> String:
	var raw_store: String = str(purchase.get("store", "")).strip_edges().to_lower()
	var platform: String = str(purchase.get("platform", "")).strip_edges().to_lower()
	var is_apple: bool = raw_store in ["apple", "app-store", "ios"] \
		or platform == "ios" \
		or purchase.has("appBundleIdIOS") \
		or purchase.has("revocationDateIOS")
	var is_google: bool = raw_store in ["google", "google-play", "android"] \
		or platform == "android" \
		or purchase.has("packageNameAndroid") \
		or purchase.has("isSuspendedAndroid")
	if is_apple == is_google:
		return ""
	return "apple" if is_apple else "google"


func _hold_for_verification(
		transaction_key: String,
		product_id: String,
		unrelated_to_active_flow: bool) -> void:
	var first_failure: bool = not _verification_pending_transactions.has(
		transaction_key)
	_verification_pending_transactions[transaction_key] = product_id
	_clear_processing(transaction_key)
	if unrelated_to_active_flow:
		return
	current_product_id = product_id
	_pending_without_store_transaction = false
	_set_state(StoreState.ERROR)
	if first_failure:
		_emit_purchase_failure(product_id, "verification-unavailable")


func _has_verification_pending_product(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	for value in _verification_pending_transactions.values():
		if str(value) == product_id:
			return true
	return false


func _has_processing_product(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	for value in _processing_products.values():
		if str(value) == product_id:
			return true
	return false


func _has_store_pending_product(product_id: String) -> bool:
	if product_id.is_empty():
		return false
	for value in _store_pending_transactions.values():
		if str(value) == product_id:
			return true
	return false


func _remember_store_pending(transaction_key: String, product_id: String) -> void:
	_store_pending_transactions[transaction_key] = product_id
	_store_pending_mutation_revision += 1
	_store_pending_mutations[transaction_key] = _store_pending_mutation_revision


func _forget_store_pending(transaction_key: String) -> void:
	_store_pending_transactions.erase(transaction_key)
	_store_pending_mutation_revision += 1
	_store_pending_mutations[transaction_key] = _store_pending_mutation_revision


func _process_verified_cancellation(purchase: Dictionary) -> bool:
	var verified_revocation: Dictionary = purchase.duplicate(true)
	if _purchase_store(verified_revocation) == "apple":
		# Forward IAPKit's CANCELED verification of an App Store JWS into the existing durable-revocation
		# boundary. This value is a server-decision marker, not trusted local input.
		verified_revocation["revocationDateIOS"] = int(
			Time.get_unix_time_from_system() * 1000.0)
	else:
		verified_revocation["isSuspendedAndroid"] = true
	return await process_revocation(verified_revocation)


func _pending_purchase_is_valid(
		purchase: Dictionary, product_id: String, transaction_key: String) -> bool:
	return _purchase_state(purchase) == "pending" \
		and _purchase_matches_app(purchase, product_id, transaction_key) \
		and str(revoked_transactions.get(transaction_key, "")) != product_id


func _purchase_matches_app(
		purchase: Dictionary, product_id: String, transaction_key: String) -> bool:
	if product_id not in PRODUCT_IDS or transaction_key.is_empty():
		return false
	if bool(purchase.get("isSuspendedAndroid", false)) \
			or purchase.get("revocationDateIOS", null) != null:
		return false
	var package_name: String = str(purchase.get("packageNameAndroid", ""))
	if not package_name.is_empty() and package_name != APP_ID:
		return false
	var bundle_id: String = str(purchase.get("appBundleIdIOS", ""))
	if not bundle_id.is_empty() and bundle_id != APP_ID:
		return false
	return true


func _purchase_record_is_valid(
		purchase: Dictionary,
		transaction_key: String,
		product_id: String) -> bool:
	return _purchase_state(purchase) == "purchased" \
		and _transaction_key(purchase) == transaction_key \
		and _purchase_matches_app(purchase, product_id, transaction_key)


func _durable_purchase_record(
		purchase: Dictionary,
		product_id: String,
		transaction_key: String,
		verified_at_ms: int = 0) -> Dictionary:
	var store: String = _purchase_store(purchase)
	var token: String = str(purchase.get("purchaseToken", "")).strip_edges()
	if store.is_empty() or token.is_empty():
		return {}
	# Re-verifying a finished transaction only needs the receipt/JWS and a stable transaction identity.
	# The original Purchase may include unnecessary personal data such as an obfuscated account ID,
	# app account token, or Android payload, so those are not copied into the app ledger.
	var record: Dictionary = {
		"productId": product_id,
		"purchaseState": "purchased",
		"purchaseToken": token,
		"store": store,
	}
	var saved_verified_at_ms: int = maxi(
		verified_at_ms,
		int(purchase.get("lastVerifiedAtMs", 0)))
	if saved_verified_at_ms > 0:
		record["lastVerifiedAtMs"] = saved_verified_at_ms
	if store == "apple":
		var transaction_id: String = str(
			purchase.get("transactionId", "")).strip_edges()
		if not transaction_id.is_empty():
			record["transactionId"] = transaction_id
		record["appBundleIdIOS"] = APP_ID
	else:
		record["packageNameAndroid"] = APP_ID
	return record if _purchase_record_is_valid(
		record, transaction_key, product_id) else {}


func _purchase_reverification_due(purchase: Dictionary) -> bool:
	var last_verified_at_ms: int = int(purchase.get("lastVerifiedAtMs", 0))
	if last_verified_at_ms <= 0:
		return true
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var elapsed_ms: int = now_ms - last_verified_at_ms
	# If the device clock moved backwards, do not trust a future timestamp and skip audits forever.
	return elapsed_ms < 0 or elapsed_ms >= PURCHASE_REVERIFY_INTERVAL_MSEC


func _revocation_has_matching_app_identity(purchase: Dictionary) -> bool:
	var package_name: String = str(purchase.get("packageNameAndroid", ""))
	var bundle_id: String = str(purchase.get("appBundleIdIOS", ""))
	if package_name.is_empty() and bundle_id.is_empty():
		return false
	if not package_name.is_empty() and package_name != APP_ID:
		return false
	if not bundle_id.is_empty() and bundle_id != APP_ID:
		return false
	return true


func _purchase_state(purchase: Dictionary) -> String:
	var value: Variant = purchase.get("purchaseState", "unknown")
	if value is int:
		return "purchased" if int(value) == 1 else "pending" if int(value) == 0 else "unknown"
	return str(value).to_lower()


func _available_purchase_row_is_well_formed(purchase: Dictionary) -> bool:
	if _product_id(purchase).strip_edges().is_empty() \
			or _transaction_key(purchase).is_empty():
		return false
	return _purchase_state(purchase) in ["pending", "purchased"]


func _product_id(purchase: Dictionary) -> String:
	var raw_product_id: Variant = purchase.get("productId", null)
	var product_id: String = "" if raw_product_id == null \
		else str(raw_product_id).strip_edges()
	if not product_id.is_empty():
		return product_id
	var ids: Variant = purchase.get("ids", [])
	if ids is Array:
		for raw_id in ids:
			if raw_id != null and not str(raw_id).strip_edges().is_empty():
				return str(raw_id).strip_edges()
	return ""


func _transaction_key(purchase: Dictionary) -> String:
	var store: String = str(purchase.get("store", OS.get_name())).to_lower()
	var platform: String = str(purchase.get("platform", "")).to_lower()
	var is_apple: bool = store in ["apple", "app-store", "ios"] \
		or platform == "ios" \
		or purchase.has("appBundleIdIOS") \
		or purchase.has("revocationDateIOS")
	var is_google: bool = store in ["google", "google-play", "android"] \
		or platform == "android" \
		or purchase.has("packageNameAndroid")
	# Apple's purchaseToken is a signed JWS, so its contents can change on a revocation update.
	# transactionId is stable for the same transaction. On Google, purchaseToken is the ledger key.
	var identity_value: Variant = purchase.get(
		"transactionId" if is_apple else "purchaseToken", null)
	var identity: String = "" if identity_value == null \
		else str(identity_value).strip_edges()
	if identity.is_empty():
		identity_value = purchase.get(
			"purchaseToken" if is_apple else "transactionId", null)
		identity = "" if identity_value == null \
			else str(identity_value).strip_edges()
	if identity.is_empty():
		identity_value = purchase.get("id", null)
		identity = "" if identity_value == null \
			else str(identity_value).strip_edges()
	if identity.is_empty():
		return ""
	var store_namespace: String = "apple" if is_apple \
		else "google" if is_google else store
	return store_namespace.sha256_text().substr(0, 12) + ":" + identity.sha256_text()


func _plain_dictionary(value: Dictionary) -> Dictionary:
	var encoded: String = JSON.stringify(value)
	var parsed: Variant = JSON.parse_string(encoded)
	return parsed if parsed is Dictionary else {}


func _mark_purchase_pending(
		product_id: String, without_store_transaction: bool = false) -> void:
	if _is_unrelated_to_active_flow(product_id):
		return
	current_product_id = product_id
	_pending_without_store_transaction = without_store_transaction
	_set_state(StoreState.PENDING)
	purchase_pending.emit(product_id)


func _fail_current(code: String) -> void:
	var product_id: String = current_product_id
	current_product_id = ""
	_pending_without_store_transaction = false
	_set_state(_settled_store_state())
	purchase_failed.emit(product_id, code)


func _report_purchase_failure(
		product_id: String,
		code: String,
		transaction_key: String = "",
		settle_flow: bool = true) -> void:
	var had_active_flow: bool = _has_active_product_flow()
	var unrelated: bool = _is_unrelated_to_active_flow(product_id)
	if not transaction_key.is_empty():
		_clear_processing(transaction_key)
		_verification_pending_transactions.erase(transaction_key)
	if settle_flow:
		_settle_product_flow(product_id)
	# A background/old-transaction failure is not the result of the in-flight native checkout.
	# Isolate not only state but also user-visible failure copy to the current product.
	if unrelated or (had_active_flow and not settle_flow):
		return
	_emit_purchase_failure(product_id, code)


func _begin_purchase_failure_capture() -> void:
	_capture_purchase_failures = true
	_captured_purchase_failure.clear()


func _end_purchase_failure_capture() -> Dictionary:
	var captured: Dictionary = _captured_purchase_failure.duplicate(true)
	_capture_purchase_failures = false
	_captured_purchase_failure.clear()
	return captured


func _emit_purchase_failure(product_id: String, code: String) -> void:
	if _capture_purchase_failures:
		var captured_code: String = str(
			_captured_purchase_failure.get("code", ""))
		if _failure_capture_priority(code) >= _failure_capture_priority(captured_code):
			_captured_purchase_failure = {
				"product_id": product_id,
				"code": code,
			}
		return
	purchase_failed.emit(product_id, code)


func _replay_purchase_failure(
		captured: Dictionary, fallback_code: String = "") -> void:
	if not captured.is_empty():
		purchase_failed.emit(
			str(captured.get("product_id", "")),
			str(captured.get("code", fallback_code)))
	elif not fallback_code.is_empty():
		purchase_failed.emit("", fallback_code)


func _failure_capture_priority(code: String) -> int:
	if code.is_empty() or code == "revoked-transaction":
		return 0
	if code in [
			"pending-not-found",
			"user-cancelled",
			"user-canceled",
			"cancelled",
			"canceled",
	]:
		return 1
	return 2


func _captured_failure_requires_error(captured: Dictionary) -> bool:
	return _failure_capture_priority(str(captured.get("code", ""))) >= 2


func _captured_failure_is_success_notice(captured: Dictionary) -> bool:
	return _failure_capture_priority(str(captured.get("code", ""))) == 1


func _finish_purchase_callback() -> void:
	_active_purchase_callbacks = maxi(_active_purchase_callbacks - 1, 0)


func _wait_for_purchase_callbacks() -> void:
	while _active_purchase_callbacks > 0:
		# Resuming immediately from an internal signal would let a restore/resume caller close the screen or
		# free nodes on the purchase_updated signal call stack.
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree == null:
			return
		await tree.process_frame


func _set_processing(
		transaction_key: String, product_id: String, operation: String) -> void:
	_processing[transaction_key] = operation
	_processing_products[transaction_key] = product_id


func _clear_processing(transaction_key: String) -> void:
	_processing.erase(transaction_key)
	_processing_products.erase(transaction_key)


func _processing_product(transaction_key: String) -> String:
	if _processing_products.has(transaction_key):
		return str(_processing_products[transaction_key])
	return str(transactions.get(transaction_key, ""))


func _finish_processing(transaction_key: String, product_id: String) -> void:
	_clear_processing(transaction_key)
	_verification_pending_transactions.erase(transaction_key)
	_settle_product_flow(product_id)


func _settle_product_flow(product_id: String) -> void:
	if product_id.is_empty() or current_product_id != product_id:
		return
	current_product_id = ""
	_pending_without_store_transaction = false
	if state in [StoreState.PURCHASING, StoreState.PENDING, StoreState.ERROR]:
		_set_state(_settled_store_state())


func _settled_store_state() -> StoreState:
	if not _backend_initialized:
		return StoreState.UNAVAILABLE
	return StoreState.READY if _catalog_is_complete() else StoreState.ERROR


func _has_active_product_flow() -> bool:
	return not current_product_id.is_empty() \
		and state in [
			StoreState.LOADING,
			StoreState.PURCHASING,
			StoreState.PENDING,
			StoreState.ERROR,
		]


func _is_unrelated_to_active_flow(product_id: String) -> bool:
	return _has_active_product_flow() and current_product_id != product_id


func _queue_deferred_revocation(
		transaction_key: String,
		product_id: String,
		purchase: Dictionary) -> bool:
	var plain_revocation: Dictionary = _plain_dictionary(purchase)
	var had_deferred: bool = _deferred_revocations.has(transaction_key)
	var previous_deferred: Variant = _deferred_revocations.get(transaction_key)
	_deferred_revocations[transaction_key] = plain_revocation
	if save_entitlements() != OK:
		if had_deferred:
			_deferred_revocations[transaction_key] = previous_deferred
		# Keep the new entry in memory too so the same session must retry it right after the current
		# processing finishes. A disk save failure must not become a lost revocation callback.
		_report_purchase_failure(
			product_id, "revocation-queue-save-failed", "", false)
		return false
	# The callback is accepted because it will be applied as soon as the in-flight purchase ends.
	return true


func _deferred_revocation_matches(
		transaction_key: String, product_id: String) -> bool:
	var value: Variant = _deferred_revocations.get(transaction_key)
	return value is Dictionary \
		and _product_id(value) == product_id \
		and _transaction_key(value) == transaction_key \
		and _purchase_is_explicitly_revoked(value) \
		and _revocation_has_matching_app_identity(value)


func _drain_deferred_revocation(transaction_key: String) -> bool:
	if not _deferred_revocations.has(transaction_key):
		return false
	var purchase: Variant = _deferred_revocations[transaction_key]
	if purchase is not Dictionary:
		return false
	if not await process_revocation(purchase):
		return false
	_deferred_revocations.erase(transaction_key)
	if save_entitlements() != OK:
		_deferred_revocations[transaction_key] = purchase
		_report_purchase_failure(
			_product_id(purchase), "revocation-queue-save-failed")
		return false
	return true


func _drain_all_deferred_revocations() -> bool:
	var succeeded: bool = true
	for raw_key in _deferred_revocations.keys():
		var purchase: Variant = _deferred_revocations.get(raw_key)
		var product_id: String = _product_id(purchase) \
			if purchase is Dictionary else ""
		var unrelated: bool = _is_unrelated_to_active_flow(product_id)
		if not await _drain_deferred_revocation(str(raw_key)) and not unrelated:
			succeeded = false
	return succeeded


func _has_active_transaction(product_id: String) -> bool:
	for value in transactions.values():
		if str(value) == product_id:
			return true
	return false


func _set_state(value: StoreState) -> void:
	if state == value:
		return
	state = value
	state_changed.emit()


func load_entitlements() -> void:
	entitlements.clear()
	transactions.clear()
	purchase_records.clear()
	pending_finishes.clear()
	consumable_grants.clear()
	revoked_products.clear()
	revoked_transactions.clear()
	_deferred_revocations.clear()
	_announced_revocations.clear()
	_processing.clear()
	_processing_products.clear()
	_store_pending_transactions.clear()
	_store_pending_mutations.clear()
	_store_pending_mutation_revision = 0
	revision = 0
	selected_palette = DEFAULT_PALETTE
	var file: ConfigFile = _load_saved_config()
	if file == null:
		return
	revision = maxi(int(file.get_value(SECTION, "revision", 0)), 0)
	var saved_entitlements: Variant = file.get_value(SECTION, "entitlements", [])
	if saved_entitlements is Array:
		for value in saved_entitlements:
			var product_id: String = str(value)
			if product_id in PRODUCT_IDS and product_id not in entitlements:
				entitlements.append(product_id)
	var saved_transactions: Variant = file.get_value(SECTION, "transactions", {})
	if saved_transactions is Dictionary:
		for raw_key in saved_transactions:
			var product_id: String = str(saved_transactions[raw_key])
			var transaction_key: String = str(raw_key)
			if product_id in PRODUCT_IDS and not transaction_key.is_empty():
				transactions[transaction_key] = product_id
	var saved_records: Variant = file.get_value(SECTION, "purchase_records", {})
	if saved_records is Dictionary:
		for raw_key in saved_records:
			var transaction_key: String = str(raw_key)
			var purchase: Variant = saved_records[raw_key]
			var product_id: String = str(transactions.get(transaction_key, ""))
			if purchase is Dictionary \
					and _purchase_record_is_valid(
						purchase, transaction_key, product_id):
				var durable_record: Dictionary = _durable_purchase_record(
					purchase, product_id, transaction_key)
				if not durable_record.is_empty():
					purchase_records[transaction_key] = durable_record
	# Consumable grant ledger. Accept only transaction keys that exist in the actual transaction list,
	# so a tampered save file cannot wipe grant records and pay out coins twice.
	var saved_grants: Variant = file.get_value(SECTION, "consumable_grants", {})
	if saved_grants is Dictionary:
		for raw_key in saved_grants:
			var grant_key: String = str(raw_key)
			var granted_product: String = str(saved_grants[raw_key])
			if is_consumable(granted_product) \
					and str(transactions.get(grant_key, "")) == granted_product:
				consumable_grants[grant_key] = granted_product

	var saved_pending: Variant = file.get_value(SECTION, "pending_finishes", {})
	if saved_pending is Dictionary:
		for raw_key in saved_pending:
			var transaction_key: String = str(raw_key)
			var purchase: Variant = saved_pending[raw_key]
			var product_id: String = str(transactions.get(transaction_key, ""))
			if purchase is Dictionary \
					and _purchase_record_is_valid(
						purchase, transaction_key, product_id):
				var plain_purchase: Dictionary = _plain_dictionary(purchase)
				pending_finishes[transaction_key] = plain_purchase
				# Unfinished transactions from schema 4 or earlier already have a verified original, so promote them
				# on the next save into post-finish refund re-verification records.
				if not purchase_records.has(transaction_key):
					var durable_record: Dictionary = _durable_purchase_record(
						plain_purchase, product_id, transaction_key)
					if not durable_record.is_empty():
						purchase_records[transaction_key] = durable_record
	var saved_revoked_transactions: Variant = file.get_value(
		SECTION, "revoked_transactions", {})
	if saved_revoked_transactions is Dictionary:
		for raw_key in saved_revoked_transactions:
			var product_id: String = str(saved_revoked_transactions[raw_key])
			var transaction_key: String = str(raw_key)
			if product_id in PRODUCT_IDS and not transaction_key.is_empty():
				revoked_transactions[transaction_key] = product_id
				transactions.erase(transaction_key)
				purchase_records.erase(transaction_key)
				pending_finishes.erase(transaction_key)
	var saved_revoked: Variant = file.get_value(SECTION, "revoked_products", [])
	if saved_revoked is Array:
		for value in saved_revoked:
			var product_id: String = str(value)
			if product_id in PRODUCT_IDS and product_id not in revoked_products:
				revoked_products.append(product_id)
	var saved_deferred: Variant = file.get_value(SECTION, "deferred_revocations", {})
	if saved_deferred is Dictionary:
		for raw_key in saved_deferred:
			var transaction_key: String = str(raw_key)
			var purchase: Variant = saved_deferred[raw_key]
			if purchase is Dictionary \
					and _purchase_is_explicitly_revoked(purchase) \
					and _product_id(purchase) in PRODUCT_IDS \
					and _transaction_key(purchase) == transaction_key \
					and _revocation_has_matching_app_identity(purchase):
				_deferred_revocations[transaction_key] = \
					_plain_dictionary(purchase)
	for product_id in revoked_products.duplicate():
		if _has_active_transaction(str(product_id)):
			revoked_products.erase(product_id)
		else:
			entitlements.erase(product_id)
	var palette: String = str(file.get_value(SECTION, "selected_palette", DEFAULT_PALETTE))
	if palette in PALETTES and (palette == DEFAULT_PALETTE or owns(LANTERN_COLORS)):
		selected_palette = palette


func save_entitlements() -> Error:
	var next_revision: int = revision + 1
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION, "schema_version", SCHEMA_VERSION)
	file.set_value(SECTION, "revision", next_revision)
	file.set_value(SECTION, "entitlements", entitlements)
	file.set_value(SECTION, "transactions", transactions)
	file.set_value(SECTION, "purchase_records", purchase_records)
	file.set_value(SECTION, "pending_finishes", pending_finishes)
	file.set_value(SECTION, "revoked_products", revoked_products)
	file.set_value(SECTION, "consumable_grants", consumable_grants)
	file.set_value(SECTION, "revoked_transactions", revoked_transactions)
	file.set_value(SECTION, "deferred_revocations", _deferred_revocations)
	file.set_value(SECTION, "selected_palette", selected_palette)
	var encoded: String = file.encode_to_text()
	var write_error: Error = _write_verified_text(encoded, TEMP_SAVE_PATH)
	if write_error != OK:
		_discard_file(TEMP_SAVE_PATH)
		return write_error
	write_error = _write_verified_text(encoded, BACKUP_TEMP_SAVE_PATH)
	if write_error != OK:
		_discard_file(TEMP_SAVE_PATH)
		_discard_file(BACKUP_TEMP_SAVE_PATH)
		return write_error

	# Commit the backup first. Then even if replacing primary fails, the next launch can pick the
	# higher-revision backup and repair primary.
	var commit_error: Error = _replace_save(
		BACKUP_TEMP_SAVE_PATH, BACKUP_SAVE_PATH)
	if commit_error != OK:
		_discard_file(TEMP_SAVE_PATH)
		_discard_file(BACKUP_TEMP_SAVE_PATH)
		return commit_error
	revision = next_revision
	var mirror_error: Error = _replace_save(TEMP_SAVE_PATH, SAVE_PATH)
	if mirror_error != OK:
		_discard_file(TEMP_SAVE_PATH)
		# The new state is already fully committed on backup. The next load repairs primary.
		return OK
	return OK


func _load_saved_config() -> ConfigFile:
	var primary: ConfigFile = ConfigFile.new()
	var backup: ConfigFile = ConfigFile.new()
	var primary_usable: bool = primary.load(SAVE_PATH) == OK \
		and _config_is_usable(primary)
	var backup_usable: bool = backup.load(BACKUP_SAVE_PATH) == OK \
		and _config_is_usable(backup)
	if not primary_usable and not backup_usable:
		return null

	var selected: ConfigFile
	if primary_usable and backup_usable:
		var primary_revision: int = _replica_revision(primary)
		var backup_revision: int = _replica_revision(backup)
		if backup_revision > primary_revision:
			selected = backup
		elif primary_revision > backup_revision:
			selected = primary
		else:
			# Between revision-less legacy files, prefer the primary that has a real schema number.
			# A healthy backup is safer than an ambiguous primary that also lacks a version line.
			var primary_version: int = int(
				primary.get_value(SECTION, "schema_version", 0))
			var backup_version: int = int(
				backup.get_value(SECTION, "schema_version", 0))
			if primary_version != backup_version:
				selected = primary if primary_version > backup_version else backup
			elif primary_version == 0:
				# A version-less old ledger migrates missing keys to defaults. Parse success alone therefore cannot
				# tell a truncated primary from a complete backup.
				selected = primary if _known_key_count(primary) \
					>= _known_key_count(backup) else backup
			else:
				selected = primary
	elif primary_usable:
		selected = primary
	else:
		selected = backup

	var encoded: String = selected.encode_to_text()
	if not primary_usable or primary.encode_to_text() != encoded:
		_repair_replica(encoded, TEMP_SAVE_PATH, SAVE_PATH)
	if not backup_usable or backup.encode_to_text() != encoded:
		_repair_replica(encoded, BACKUP_TEMP_SAVE_PATH, BACKUP_SAVE_PATH)
	return selected


func _replica_revision(file: ConfigFile) -> int:
	# revision was introduced in schema 3 as the first atomic replica number. Trusting accidental or
	# partial fields from an older schema as freshness can overwrite a complete newer ledger.
	if int(file.get_value(SECTION, "schema_version", 0)) < 3:
		return 0
	return int(file.get_value(SECTION, "revision", 0))


func _config_is_current(file: ConfigFile) -> bool:
	return _config_is_usable(file) \
		and int(file.get_value(SECTION, "schema_version", 0)) == SCHEMA_VERSION


func _config_is_usable(file: ConfigFile) -> bool:
	if not file.has_section(SECTION):
		return false
	var version: Variant = file.get_value(SECTION, "schema_version", 0)
	if typeof(version) != TYPE_INT or int(version) < 0 or int(version) > SCHEMA_VERSION:
		return false
	var typed_keys: Dictionary = {
		"revision": TYPE_INT,
		"entitlements": TYPE_ARRAY,
		"transactions": TYPE_DICTIONARY,
		"purchase_records": TYPE_DICTIONARY,
		"pending_finishes": TYPE_DICTIONARY,
			"revoked_products": TYPE_ARRAY,
			"revoked_transactions": TYPE_DICTIONARY,
			"deferred_revocations": TYPE_DICTIONARY,
			"selected_palette": TYPE_STRING,
	}
	for key in typed_keys:
		if file.has_section_key(SECTION, key) \
				and typeof(file.get_value(SECTION, key)) != int(typed_keys[key]):
			return false
	if file.has_section_key(SECTION, "revision") \
			and int(file.get_value(SECTION, "revision", -1)) < 0:
		return false
	# A file that records schema_version must also have every core key that version promised.
	# ConfigFile can parse successfully from only the leading bytes of a truncated file, so
	# do not prefer an incomplete primary over a healthy backup just because it looks "old".
	var required_keys: Array[String] = []
	if int(version) >= 1:
		required_keys.assign([
			"entitlements", "transactions", "pending_finishes", "selected_palette"])
	if int(version) >= 2:
		required_keys.append("revoked_products")
	if int(version) >= 3:
		required_keys.append("revision")
		required_keys.append("revoked_transactions")
	if int(version) >= 4:
		required_keys.append("deferred_revocations")
	if int(version) >= 5:
		required_keys.append("purchase_records")
	for key in required_keys:
		if not file.has_section_key(SECTION, key):
			return false
	return true


func _known_key_count(file: ConfigFile) -> int:
	var count: int = 0
	for key in [
			"revision",
			"entitlements",
			"transactions",
			"purchase_records",
			"pending_finishes",
			"revoked_products",
			"revoked_transactions",
			"deferred_revocations",
			"selected_palette",
	]:
		if file.has_section_key(SECTION, key):
			count += 1
	return count


func _repair_replica(encoded: String, temp_path: String, target_path: String) -> void:
	var repair_error: Error = _write_verified_text(encoded, temp_path)
	if repair_error == OK:
		repair_error = _replace_save(temp_path, target_path)
	if repair_error != OK:
		_discard_file(temp_path)


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
