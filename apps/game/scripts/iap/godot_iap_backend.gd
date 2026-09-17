extends "res://scripts/iap/iap_backend.gd"

## Adapt godot-iap 3.5.1 to the game's small backend contract.
##
## `request_purchase()` is a command that opens the store sheet, not a function
## that returns the result. The terminal outcome always arrives on
## `purchase_updated` / `purchase_failed`.

const Types = preload("res://addons/godot-iap/types.gd")
const COMPAT_SCRIPT: Script = preload(
	"res://scripts/iap/godot_iap_3_compat.gd")
const IAPKIT_TRANSPORT_SCRIPT: Script = preload(
	"res://scripts/iap/iapkit_http_transport.gd")
const IAPKIT_CONFIG_PATH: String = "res://iapkit.cfg"
const IAPKIT_SECTION: String = "iapkit"
const IAPKIT_KEY_PREFIX: String = "openiap-kit_pk_"
## How long to wait when a product query never answers.
##
## Play Billing really does this. While a purchase that failed verification
## and was never finished stayed on the account, `fetchProducts` on Pixel 10
## never called back even after several minutes. If that await never returns,
## the connecting-attempt flag stays on forever so **even the retry button
## dies** — to the user the shop is simply broken. If there is no answer,
## fold it as failure so they can press retry.
const FETCH_TIMEOUT_SECONDS: float = 20.0
## Tests shrink this the same way they shrink `_apple_async_timeout_seconds`.
var _fetch_timeout_seconds: float = FETCH_TIMEOUT_SECONDS

var _plugin: Node
var _signals_connected: bool = false
var _iapkit_api_key: String = ""
var _iapkit_config_loaded: bool = false
var _iapkit_transport: Node
var _compat: RefCounted
var _purchase_dispatch_in_progress: bool = false
var _purchase_dispatch_failed: bool = false
var _purchase_request_generation: int = 0
var _terminal_error_generation: int = -1
var _purchase_request_product_id: String = ""
var _terminal_error_signatures: Dictionary = {}


func _init(
		plugin: Node = null,
		iapkit_api_key: String = "",
		iapkit_transport: Node = null) -> void:
	_plugin = plugin
	_iapkit_api_key = iapkit_api_key.strip_edges()
	_iapkit_config_loaded = not _iapkit_api_key.is_empty()
	_iapkit_transport = iapkit_transport
	if _plugin != null:
		_compat = COMPAT_SCRIPT.new(_plugin)


func initialize() -> bool:
	if not verification_ready():
		return false
	_ensure_iapkit_transport()
	if _plugin == null:
		_plugin = get_node_or_null("/root/GodotIapPlugin")
	if _plugin == null:
		return false
	_compat = COMPAT_SCRIPT.new(_plugin)
	_connect_plugin_signals()
	return bool(await _plugin.init_connection())


func _connect_plugin_signals() -> void:
	if _signals_connected:
		return
	_plugin.purchase_updated.connect(_on_purchase_updated)
	_plugin.purchase_error.connect(_on_purchase_error)
	_plugin.connected.connect(_on_connected)
	_plugin.disconnected.connect(_on_disconnected)
	_signals_connected = true


func fetch_products(product_ids: Array[String]) -> Array[Dictionary]:
	if _plugin == null:
		return []
	var request: RefCounted = Types.ProductRequest.new()
	request.skus = product_ids
	request.type = Types.ProductQueryType.IN_APP
	var answered: Array = [null, false]
	_fetch_products_into(request, answered)
	if not await _wait_until_answered(answered, _fetch_timeout_seconds):
		return []
	var raw: Variant = answered[0]
	if raw is not Array:
		return []
	var fetched: Array = raw as Array
	var result: Array[Dictionary] = []
	for product in fetched:
		if product != null and product.has_method("to_dict"):
			var value: Variant = product.to_dict()
			if value is Dictionary:
				result.append(value)
	return result


## Wait for the plugin query, but still box a late answer instead of dropping it.
func _fetch_products_into(request: RefCounted, answered: Array) -> void:
	var value: Variant = await _plugin.fetch_products(request)
	answered[0] = value
	answered[1] = true


## True if an answer arrives, false if time runs out. Waits by spinning frames
## so headless tests take the same path as a real coroutine.
func _wait_until_answered(answered: Array, seconds: float) -> bool:
	if bool(answered[1]):
		return true
	var tree: SceneTree = get_tree()
	if tree == null:
		return bool(answered[1])
	var deadline: SceneTreeTimer = tree.create_timer(seconds)
	while not bool(answered[1]):
		if deadline.time_left <= 0.0:
			return false
		await tree.process_frame
	return true


func request_purchase(product_id: String) -> bool:
	if _plugin == null \
			or product_id.is_empty() \
			or not _signals_connected \
			or not bool(_plugin.is_store_connected()):
		return false
	var platforms: RefCounted = Types.RequestPurchasePropsByPlatforms.new()
	var apple: RefCounted = Types.RequestPurchaseIosProps.new()
	apple.sku = product_id
	# Auto-finish can drop the transaction before the benefit is saved.
	apple.and_dangerously_finish_transaction_automatically = false
	platforms.apple = apple
	var google: RefCounted = Types.RequestPurchaseAndroidProps.new()
	var google_skus: Array[String] = [product_id]
	google.skus = google_skus
	platforms.google = google
	var props: RefCounted = Types.RequestPurchaseProps.in_app(platforms)
	# Use the 3.x canonical API. Even when StoreKit/Play Billing accepts the
	# request, an async pending result is null and the terminal outcome arrives
	# only on signals. So do not treat null as failure; only a synchronous
	# purchase_error during the call counts as dispatch failure.
	_purchase_request_generation += 1
	_terminal_error_generation = _purchase_request_generation
	_purchase_request_product_id = product_id
	_terminal_error_signatures.clear()
	_purchase_dispatch_failed = false
	_purchase_dispatch_in_progress = true
	var immediate: Variant = _plugin.request_purchase(props)
	_purchase_dispatch_in_progress = false
	return immediate != null or not _purchase_dispatch_failed


func restore() -> bool:
	if _plugin == null or _compat == null:
		return false
	var result: Dictionary = await _compat.restore_purchases()
	return bool(result.get("success", false))


func available_purchases() -> Dictionary:
	if _plugin == null or _compat == null:
		return {"success": false, "purchases": []}
	var options: RefCounted = Types.PurchaseOptions.new()
	# StoreKit's default Transaction.all also returns finished refund/revocation
	# history. Entitlement sync only wants active/pending; refunds for locally
	# finished ledger rows are re-verified separately through IAPKit with the
	# stored JWS.
	options.only_include_active_items_ios = true
	var query: Variant = await _compat.available_purchases(options)
	if query is not Dictionary or not bool(query.get("success", false)):
		return {"success": false, "purchases": []}
	var result: Array[Dictionary] = []
	var available: Variant = query.get("purchases", [])
	if available is not Array:
		return {"success": false, "purchases": []}
	for purchase in available:
		var value: Variant
		if purchase is Dictionary:
			value = purchase.duplicate(true)
		elif typeof(purchase) == TYPE_OBJECT \
				and is_instance_valid(purchase) \
				and purchase.has_method("to_dict"):
			value = purchase.to_dict()
		else:
			return {"success": false, "purchases": []}
		if value is not Dictionary or not _available_purchase_is_valid(value):
			return {"success": false, "purchases": []}
		result.append(value)
	return {
		"success": true,
		"purchases": result,
	}


func verification_ready() -> bool:
	_load_iapkit_config()
	return _iapkit_api_key.begins_with(IAPKIT_KEY_PREFIX) \
		and _iapkit_api_key.length() > IAPKIT_KEY_PREFIX.length()


func verify_purchase(
		purchase: Dictionary, expected_product_id: String) -> Dictionary:
	if _plugin == null or not verification_ready():
		return _verification_error("verification-configuration-error", false)
	if expected_product_id.strip_edges().is_empty():
		return _verification_error("verification-rejected", false)

	var store: String = _verification_store(purchase)
	var token: String = str(purchase.get("purchaseToken", "")).strip_edges()
	if store == "apple":
		if token.is_empty() or token.length() > 16_000:
			return _verification_error("verification-rejected", false)
	elif store == "google":
		if token.is_empty() or token.length() > 2_048:
			return _verification_error("verification-rejected", false)
	else:
		return _verification_error("verification-rejected", false)

	var body: Dictionary = {
		"store": store,
		"expectedProductId": expected_product_id,
	}
	if store == "apple":
		body["jws"] = token
	else:
		body["purchaseToken"] = token
	_ensure_iapkit_transport()
	if _iapkit_transport == null:
		return _verification_error("verification-unavailable")
	var response: Dictionary = await _iapkit_transport.post_verification(
		_iapkit_api_key, body)
	var raw_success: Variant = response.get("success", null)
	if typeof(raw_success) != TYPE_BOOL:
		return _verification_error("verification-unavailable", true)
	if not raw_success:
		var raw_error_code: Variant = response.get(
			"error_code", "verification-unavailable")
		var raw_retryable: Variant = response.get("retryable", true)
		if typeof(raw_error_code) != TYPE_STRING \
				or typeof(raw_retryable) != TYPE_BOOL:
			return _verification_error("verification-unavailable", true)
		return _verification_error(
			str(raw_error_code),
			raw_retryable)
	var value: Dictionary = _as_dictionary(response.get("body", {}))
	if value.is_empty():
		return _verification_error("verification-unavailable", true)
	var raw_is_valid: Variant = value.get("isValid", null)
	var raw_store: Variant = value.get("store", null)
	var raw_state: Variant = value.get("state", null)
	var raw_product_id: Variant = value.get("productId", null)
	if typeof(raw_is_valid) != TYPE_BOOL \
			or typeof(raw_store) != TYPE_STRING \
			or typeof(raw_state) != TYPE_STRING \
			or (raw_product_id != null and typeof(raw_product_id) != TYPE_STRING):
		return _verification_error("verification-unavailable", true)
	return {
		"success": true,
		"is_valid": raw_is_valid,
		"store": str(raw_store).strip_edges().to_lower(),
		"state": str(raw_state).strip_edges().to_lower(),
		"product_id": "" if raw_product_id == null \
			else str(raw_product_id).strip_edges(),
	}


func _ensure_iapkit_transport() -> void:
	if _iapkit_transport == null:
		_iapkit_transport = IAPKIT_TRANSPORT_SCRIPT.new()
	if _iapkit_transport.get_parent() == null:
		add_child(_iapkit_transport)


func _load_iapkit_config() -> void:
	if _iapkit_config_loaded:
		return
	_iapkit_config_loaded = true
	var config: ConfigFile = ConfigFile.new()
	if config.load(IAPKIT_CONFIG_PATH) != OK:
		return
	_iapkit_api_key = str(
		config.get_value(IAPKIT_SECTION, "api_key", "")).strip_edges()


func _verification_store(purchase: Dictionary) -> String:
	var raw_store: String = str(purchase.get("store", "")).strip_edges().to_lower()
	var platform: String = str(purchase.get("platform", "")).strip_edges().to_lower()
	var apple: bool = raw_store in ["apple", "app-store", "ios"] \
		or platform == "ios" \
		or purchase.has("appBundleIdIOS")
	var google: bool = raw_store in ["google", "google-play", "android"] \
		or platform == "android" \
		or purchase.has("packageNameAndroid")
	if apple == google:
		return ""
	return "apple" if apple else "google"


func _as_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	if typeof(value) == TYPE_OBJECT \
			and is_instance_valid(value) \
			and value.has_method("to_dict"):
		var converted: Variant = value.to_dict()
		if converted is Dictionary:
			return converted
	return {}


func _verification_error(code: String, retryable: bool = true) -> Dictionary:
	return {
		"success": false,
		"error_code": code,
		"retryable": retryable,
	}


func _available_purchase_is_valid(purchase: Dictionary) -> bool:
	var raw_product_id: Variant = purchase.get("productId", null)
	var product_id: String = "" if raw_product_id == null \
		else str(raw_product_id).strip_edges()
	if product_id.is_empty():
		var ids: Variant = purchase.get("ids", [])
		if ids is Array:
			for raw_id in ids:
				if raw_id != null and not str(raw_id).strip_edges().is_empty():
					product_id = str(raw_id).strip_edges()
					break
	if product_id.is_empty():
		return false
	var identity: String = ""
	for key in ["purchaseToken", "transactionId", "id"]:
		var value: Variant = purchase.get(key, null)
		if value != null and not str(value).strip_edges().is_empty():
			identity = str(value).strip_edges()
			break
	if identity.is_empty():
		return false
	var state: Variant = purchase.get("purchaseState", null)
	if state is int:
		return int(state) in [Types.PurchaseState.PENDING, Types.PurchaseState.PURCHASED]
	return str(state).to_lower() in ["pending", "purchased"]


## Finish the transaction. If `consumable`, the store consumes the purchase
## so it can be **bought again**. Consuming a non-consumable would release
## ownership, so pass true only for consumables.
func finish(purchase: Dictionary, consumable: bool = false) -> bool:
	if _plugin == null:
		return false
	var result: Variant = await _plugin.finish_transaction_dict(purchase, consumable)
	return result != null and bool(result.success)


func shutdown() -> void:
	if _plugin != null and _plugin.is_store_connected():
		_plugin.end_connection()


func _on_purchase_updated(purchase: Dictionary) -> void:
	purchase_updated.emit(purchase)


func _on_purchase_error(error: Dictionary) -> void:
	if _purchase_dispatch_in_progress:
		_purchase_dispatch_failed = true
	if _is_duplicate_request_terminal_error(error):
		return
	purchase_failed.emit(error)


func _is_duplicate_request_terminal_error(error: Dictionary) -> bool:
	if _purchase_request_generation <= 0 \
			or _terminal_error_generation != _purchase_request_generation:
		return false
	var raw_product_id: Variant = error.get(
		"productId", error.get("product_id", null))
	var product_id: String = "" if raw_product_id == null \
		else str(raw_product_id).strip_edges()
	if not product_id.is_empty() and product_id != _purchase_request_product_id:
		return false
	var code: String = str(error.get("code", "purchase-failed")) \
		.strip_edges().to_lower()
	if code.is_empty():
		code = "purchase-failed"
	var signature: String = _purchase_request_product_id + "\n" + code
	# OpenIAP #272: Android 3.0.1 can emit ServiceDisconnected twice, from the
	# Google layer and the Godot bridge. Suppress only the same request, product,
	# and terminal code; later request_purchase() generations and other-product
	# errors still pass through.
	if _terminal_error_signatures.has(signature):
		return true
	_terminal_error_signatures[signature] = true
	return false


func _on_connected() -> void:
	connected.emit()


func _on_disconnected() -> void:
	disconnected.emit()
